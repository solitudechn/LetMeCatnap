import AppKit
import CatnapCore
import Combine
import CoreGraphics
import Foundation

/// The timer's phase, as far as the rest of the app is concerned.
typealias TimerState = SessionPhase
/// Why the timer is paused.
typealias PauseReason = PauseCause

/// Drives `SessionState` and performs the effects it asks for.
///
/// All of the *decisions* — when a lock pauses, when a meeting eats a break,
/// whether resuming continues or restarts — live in `CatnapCore.SessionState`,
/// where they can be tested without a screen. What is left here is the part
/// that genuinely needs AppKit: the ticking clock, the system notifications,
/// the overlay panels, the sounds and the log.
///
/// The split exists for a concrete reason. This class used to hold the
/// decisions itself, and a decision living in an executable target cannot be
/// imported by the test bundle — which is how it grew a private copy of
/// `TimerRules.showsSkipHint` while the test kept passing against the copy
/// nobody ran.
@MainActor
class TimerManager: ObservableObject {
    /// The whole state machine. Publishing the value (rather than a handful of
    /// mirrored `@Published` fields) keeps one source of truth; the accessors
    /// below exist so the views did not have to change.
    @Published private(set) var session: SessionState

    /// Progress of the overlay's fade-in, only used for the countdown's opacity.
    ///
    /// Not published: nobody outside this class reads it (the views use
    /// `graceProgress`), and publishing it only made every observer re-diff on
    /// the two transitions per break.
    private(set) var isInGracePeriod = false
    @Published var graceProgress: Double = 1
    /// Guidance shown on the break overlay; rotated while the break runs.
    @Published var breakTip: String = ""

    let settings: Settings
    let meetingDetector = MeetingDetector()
    let overlayManager = OverlayManager()
    let breakGracePeriod = TimerRules.breakGracePeriod

    private var timerCancellable: AnyCancellable?
    private var settingsCancellable: AnyCancellable?
    private var tickCount = 0
    private var graceAnimTask: Task<Void, Never>?
    private var nextBreakTipDate: Date?
    private var wasInMeeting = false

    // Activity to prevent App Nap
    private var activity: NSObjectProtocol?

    // MARK: - Derived values

    var state: TimerState { session.phase }
    var remainingSeconds: Int { session.remaining }
    var isLongBreak: Bool { session.isLongBreak }
    var isBreakImminent: Bool { session.isImminent }
    var skipStreak: Int { session.skipStreak }
    var showsSkipButton: Bool { session.showsSkipButton }
    var showsSkipHint: Bool { session.showsSkipHint }
    var currentPauseReason: PauseReason? { session.currentPauseCause }
    var currentBreakTotalSeconds: Int { session.breakTotalSeconds }

    var workDurationSeconds: Int { settings.workSeconds }
    var breakDurationSeconds: Int { settings.shortBreakSeconds }
    var pauseDuringMeetings: Bool { settings.pauseDuringMeetings }
    var muteSounds: Bool { settings.muteSounds }

    var menuBarText: String {
        switch session.phase {
        case .working:
            return TimerRules.formatTime(session.remaining)
        case .onBreak:
            return L10n.t(.breakCountdown, TimerRules.formatTime(session.remaining))
        case .paused:
            switch session.pauseCause {
            case .meeting:
                return L10n.t(.meetingCountdown, TimerRules.formatTime(session.banked))
            case .breakPending:
                return L10n.t(.meetingInProgress)
            case .locked:
                return L10n.t(.locked)
            case .idle:
                return L10n.t(.idleCountdown, TimerRules.formatTime(session.banked))
            case .manual:
                return L10n.t(.pausedCountdown, TimerRules.formatTime(session.banked))
            }
        }
    }

    var pauseStatusText: String? {
        guard session.phase == .paused else { return nil }
        switch session.pauseCause {
        case .meeting:
            return meetingDetector.meetingSource.map { L10n.t(.pausedWith, $0) }
                ?? L10n.t(.pausedInMeeting)
        case .breakPending:
            return meetingDetector.meetingSource.map { L10n.t(.breakPending, $0) }
                ?? L10n.t(.inMeetingBreakPending)
        case .locked:
            return L10n.t(.pausedLocked)
        case .idle:
            return L10n.t(.pausedIdle)
        case .manual:
            return L10n.t(.paused)
        }
    }

    var isInMeeting: Bool {
        meetingDetector.isInMeeting
    }

    // MARK: - Init

    init(settings: Settings) {
        self.settings = settings
        session = SessionState(config: SessionConfig(settings: settings), now: Date())

        startTicking()
        observeSettings()
        observeScreenLock()

        // A Lock Screen or display sleep while the app was still launching
        // should not leave the timer running behind it.
        if settings.pauseTrigger.pausesOnLock && screenLockedProvider() {
            handleScreenLocked()
        }

        // Reset work timer on wake — sleep time isn't work time
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWake()
            }
        }
    }

    // MARK: - User actions

    func start() {
        guard session.phase != .onBreak else {
            Log.info("Timer restart ignored while a break is in progress")
            return
        }
        Log.info("Timer started: work=\(workDurationSeconds / 60)min, break=\(breakDurationSeconds)s")
        apply { $0.restartTimer(now: Date()) }
    }

    /// User-requested short break. It does not consume a pomodoro work session
    /// and therefore does not move the next long break closer.
    func startBreakNow() {
        guard session.phase != .onBreak else { return }
        Log.info("Manual break requested")
        apply { $0.takeBreakNow(now: Date()) }
    }

    func pause() {
        guard session.phase == .working else { return }
        Log.info("Timer paused by user")
        apply { $0.pauseManually(now: Date()) }
    }

    func resume() {
        guard session.phase == .paused else { return }
        Log.info("Timer resumed by user")
        apply { $0.resumeManually(now: Date()) }
    }

    func togglePause() {
        switch session.phase {
        case .working:
            pause()
        case .paused:
            let cause = session.pauseCause
            guard cause != .meeting && cause != .breakPending else { return }
            resume()
        case .onBreak:
            break
        }
    }

    /// Dismisses the break.
    ///
    /// `viaKeyboard` is the Escape shortcut, which always works. The on-screen
    /// button only exists when the preference is on, so the button path has to
    /// respect it.
    func skipBreak(viaKeyboard: Bool = false) {
        guard session.phase == .onBreak else { return }
        let effects = apply { $0.skipBreak(viaKeyboard: viaKeyboard, now: Date()) }
        if effects.isEmpty {
            Log.info("Break skip ignored: the skip button is hidden")
        } else {
            Log.info("Break overlay closed: user cancelled")
        }
    }

    // MARK: - Settings changes

    /// Called when the user toggles "Pause During Meetings".
    ///
    /// Only the side effect that is not a configuration change lives here; the
    /// snapshot itself is pushed by `observeSettings()`.
    func pauseDuringMeetingsSettingChanged(enabled: Bool) {
        if !enabled {
            wasInMeeting = false
            meetingDetector.reset()
        }
    }

    /// Keeps the session's configuration snapshot in step with `Settings`.
    ///
    /// Every setting used to need its own "tell the timer" call, and two of them
    /// (break duration, pomodoro rhythm) simply never got one — the value was
    /// stored and then ignored until the next unrelated change. Subscribing
    /// removes the whole class of bug: whatever writes a preference, the session
    /// hears about it.
    private func observeSettings() {
        settingsCancellable = settings.objectWillChange.sink { [weak self] _ in
            // `objectWillChange` fires *before* the new value is stored, so the
            // snapshot has to be taken on the next run loop turn.
            DispatchQueue.main.async {
                self?.applyConfigurationChange()
            }
        }
    }

    /// One path for every preference change: `SessionState` decides which of
    /// them can strand the timer, and does it in one place.
    private func applyConfigurationChange() {
        let next = SessionConfig(settings: settings)
        let changed = next != session.config
        apply { $0.configChanged(next, now: Date()) }
        if changed {
            // Worth a line: "I changed a setting and nothing happened" is the
            // kind of report that is impossible to diagnose from the outside.
            Log.info(
                "Settings applied: work=\(next.workSeconds / 60)min, "
                    + "break=\(next.shortBreakSeconds)s, "
                    + "longEvery=\(next.longBreakEvery), "
                    + "pauseTrigger=\(next.pauseTrigger)"
            )
        }
    }

    // MARK: - Transitions

    /// Applies a transition and performs whatever it asks for, in order.
    @discardableResult
    private func apply(
        _ transition: (inout SessionState) -> [SessionEffect]
    ) -> [SessionEffect] {
        // Write back only when something actually changed. An inout call always
        // writes back, and `@Published` fires `objectWillChange` on any write —
        // without this guard, every no-op second (the whole paused phase, for
        // instance) made every observing view re-diff itself for nothing.
        var next = session
        let effects = transition(&next)
        if next != session {
            session = next
        }
        for effect in effects {
            perform(effect)
        }
        return effects
    }

    private func perform(_ effect: SessionEffect) {
        switch effect {
        case .workSessionStarted:
            // Fresh session: no overlay state may leak into it.
            graceAnimTask?.cancel()
            graceAnimTask = nil
            isInGracePeriod = false
            graceProgress = 1
            breakTip = ""
            nextBreakTipDate = nil

        case .breakStarted(let isLong, let seconds, let manual):
            isInGracePeriod = true
            graceProgress = 0
            startGraceAnimation()
            breakTip = L10n.randomBreakTip(excluding: breakTip)
            nextBreakTipDate = Date().addingTimeInterval(breakGracePeriod + 20)

            if isFrontmostAppFullscreen() {
                overlayManager.showCompactBreakOverlay(timerManager: self)
                Log.info("Break overlay triggered: compact overlay (fullscreen app detected)")
            } else {
                overlayManager.showBreakOverlay(timerManager: self)
                Log.info("Break overlay triggered: full overlay (work timer expired)")
            }
            Log.info(
                "Break started: \(isLong ? "long" : "short") \(seconds)s "
                    + "(session #\(session.sessionsCompleted), manual=\(manual))"
            )
            if !muteSounds { NSSound(named: "Glass")?.play() }

        case .breakFinished:
            Log.info("Break overlay closed: timeout completed")
            graceAnimTask?.cancel()
            graceAnimTask = nil
            if !muteSounds { NSSound(named: "Blow")?.play() }
            overlayManager.dismissWithAnimation { [weak self] in
                self?.finishBreak()
            }

        case .breakInterrupted(let reason):
            switch reason {
            case .meeting: Log.info("Break interrupted by meeting")
            case .wake: Log.info("Break dismissed after system wake, timer restarted")
            }
            graceAnimTask?.cancel()
            graceAnimTask = nil
            overlayManager.dismissOverlay()

        case .breakDismissed:
            graceAnimTask?.cancel()
            graceAnimTask = nil
            overlayManager.dismissOverlay()

        case .breakDeferredToMeeting:
            Log.info("Break overlay suppressed: meeting in progress")

        case .imminentReminder:
            Log.info("Break impending: \(session.remaining)s left")
            if !muteSounds { NSSound(named: "Tink")?.play() }

        case .automaticPauseLifted(let cause):
            Log.info("Automatic pause lifted (\(cause)) — resuming")
        }
    }

    /// Called when the fade-out after `.breakFinished` completes.
    private func finishBreak() {
        apply { $0.finishBreak(now: Date()) }
    }

    // MARK: - Tick

    private func startTicking() {
        // Keeps the one-second tick honest under App Nap without pinning the
        // machine awake: plain `.userInitiated` would also disable idle system
        // sleep, which is the opposite of what the lock/idle pause flow assumes
        // — a machine nobody is touching ought to be allowed to sleep.
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Break timer running"
        )

        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func tick() {
        tickCount += 1

        if TimerRules.shouldPoll(tickCount: tickCount) {
            if pauseDuringMeetings { checkMeetingStatus() }
            checkIdleStatus()
        }

        apply { $0.tick(now: Date()) }
        updateBreakPresentation()
    }

    /// Fade-in bookkeeping and tip rotation — presentation only, so it stays
    /// out of the state machine.
    private func updateBreakPresentation() {
        guard session.phase == .onBreak,
            let started = session.breakStartedAt,
            Date().timeIntervalSince(started) >= breakGracePeriod
        else { return }

        if isInGracePeriod {
            isInGracePeriod = false
            graceAnimTask?.cancel()
            graceAnimTask = nil
        }
        graceProgress = 1

        // Rotate by wall-clock time rather than an exact countdown value, which
        // a delayed tick could otherwise skip.
        let now = Date()
        if let next = nextBreakTipDate, now >= next, session.remaining > 0 {
            breakTip = L10n.randomBreakTip(excluding: breakTip)
            nextBreakTipDate = now.addingTimeInterval(20)
        }
    }

    private func startGraceAnimation() {
        graceAnimTask?.cancel()
        graceAnimTask = Task { [weak self] in
            guard let self else { return }
            let start = Date()
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                if elapsed >= self.breakGracePeriod { break }
                let progress = min(1.0, elapsed / self.breakGracePeriod)
                await MainActor.run { [weak self] in
                    self?.graceProgress = progress
                }
                try? await Task.sleep(nanoseconds: 50_000_000)  // 50 ms
            }
            if !Task.isCancelled {
                await MainActor.run { [weak self] in
                    self?.graceProgress = 1
                }
            }
        }
    }

    // MARK: - Screen lock (the only "user is away" signal we trust)

    /// Locking is deliberate; idle time is not. Reading a long document leaves
    /// the keyboard untouched for minutes, and pausing on that would suppress
    /// the break exactly when it is most useful.
    private func observeScreenLock() {
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(
            forName: .init("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleScreenLocked() }
        }
        distributed.addObserver(
            forName: .init("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleScreenUnlocked() }
        }

        // Display sleep usually comes with the lock, and also means nobody is
        // looking at the screen any more.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleScreenLocked() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleScreenUnlocked() }
        }
    }

    /// Whether the session is locked. Injectable so the lock path can be
    /// exercised without really locking the screen; the decision it feeds lives
    /// in `SessionState` and is covered by `SessionStateTests`.
    var screenLockedProvider: () -> Bool = { TimerManager.sessionIsLocked() }

    static func sessionIsLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    private func handleScreenLocked() {
        guard session.phase == .working else { return }
        apply { $0.screenLocked(now: Date()) }
        if session.phase == .paused, session.pauseCause == .locked {
            Log.info("Timer paused: screen locked (\(session.banked)s banked)")
        }
    }

    private func handleScreenUnlocked() {
        let wasLockedPaused = session.phase == .paused && session.pauseCause == .locked
        // Display wake fires before the unlock in most cases, so pass the real
        // lock state and let the state machine decide.
        apply { $0.screenUnlocked(isScreenLocked: screenLockedProvider(), now: Date()) }
        if wasLockedPaused && session.phase == .working {
            Log.info("Screen unlocked — starting a full work session")
        }
    }

    // MARK: - Idle (opt-in alternative to the lock screen)

    /// Seconds since the last keyboard or mouse event. Same idea as
    /// `screenLockedProvider`: the threshold rules live in `TimerRules`, this
    /// hook only feeds them.
    var secondsSinceInputProvider: () -> TimeInterval = {
        // `~0` is the documented way to ask for "any event type" here; the
        // initializer only fails for values that fit in the raw type, so the
        // fallback is unreachable.
        let anyEvent = CGEventType(rawValue: ~0) ?? .null
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
    }

    private func checkIdleStatus() {
        guard settings.pauseTrigger.pausesOnIdle else { return }
        let idle = secondsSinceInputProvider()
        let wasWorking = session.phase == .working
        let wasIdlePaused = session.phase == .paused && session.pauseCause == .idle

        apply { $0.inputActivity(secondsSinceInput: idle, now: Date()) }

        if wasWorking && session.phase == .paused {
            Log.info("Timer paused: idle for \(Int(idle))s (\(session.banked)s banked)")
        } else if wasIdlePaused && session.phase == .working {
            Log.info("User is back after an idle pause — starting a full work session")
        }
    }

    private func handleWake() {
        let wasWorking = session.phase == .working
        apply { $0.systemWake(now: Date()) }
        if wasWorking && session.phase == .working {
            Log.info("Timer restarted after system wake")
        }
    }

    // MARK: - Meetings

    private func checkMeetingStatus() {
        meetingDetector.check()

        if meetingDetector.isInMeeting {
            if !wasInMeeting {
                Log.info("Meeting mode entered (\(meetingDetector.meetingSource ?? "unknown"))")
                wasInMeeting = true
            }
        } else if wasInMeeting {
            Log.info("Meeting mode left")
            wasInMeeting = false
        }

        // The timer keeps running during a meeting while working — no pause.
        // A meeting only gets out of the way of a break.
        apply {
            $0.meetingStatusChanged(isInMeeting: meetingDetector.isInMeeting, now: Date())
        }
    }

    // MARK: - Fullscreen Detection

    func isFrontmostAppFullscreen() -> Bool {
        guard
            let windowList = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else { return false }

        for window in windowList {
            let layer = window[kCGWindowLayer as String] as? Int64 ?? -1
            let alpha = window[kCGWindowAlpha as String] as? Double ?? 0
            guard layer == 0, alpha > 0.5 else { continue }

            let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
            let w = bounds["Width"] ?? 0
            let h = bounds["Height"] ?? 0
            let x = bounds["X"] ?? 0
            let y = bounds["Y"] ?? 0

            for screen in NSScreen.screens {
                let sf = screen.frame
                if abs(w - sf.width) < 2 && abs(h - sf.height) < 2 && abs(x - sf.minX) < 2
                    && abs(y - sf.minY) < 2
                {
                    return true
                }
            }
        }
        return false
    }
}
