import AppKit
import Combine
import CoreGraphics
import Foundation
import ICHRCore

enum TimerState {
    case working
    case onBreak
    case paused
}

enum PauseReason {
    case manual
    case meeting
    case locked
    case idle
    case breakPending  // Work timer expired during meeting, waiting for meeting to end
}

@MainActor
class TimerManager: ObservableObject {
    @Published var state: TimerState = .working
    @Published var remainingSeconds: Int = 0

    private var timerCancellable: AnyCancellable?
    private var tickCount: Int = 0
    private var secondsBeforePause: Int = 0
    private var pauseReason: PauseReason = .manual
    private var breakStartTime: Date = .distantPast
    /// Wall-clock deadlines prevent a delayed timer tick from permanently
    /// lengthening a work session or break.
    private var workDeadline: Date?
    private var breakDeadline: Date?
    private var nextBreakTipDate: Date?
    private var activeBreakTotalSeconds = 0
    private var isEndingBreak = false
    private var graceAnimTask: Task<Void, Never>?
    private var wasInMeeting: Bool = false

    let settings: Settings
    let meetingDetector = MeetingDetector()
    let overlayManager = OverlayManager()
    private let postMeetingBreakDelay = 5
    let breakGracePeriod: TimeInterval = 1.5

    @Published var isInGracePeriod: Bool = false
    @Published var graceProgress: Double = 1

    /// Guidance shown on the break overlay; rotated on long breaks.
    @Published var breakTip: String = ""
    /// Whether the running break is the longer one from the pomodoro rhythm.
    @Published private(set) var isLongBreak: Bool = false
    /// True during the last minute of a work session (progressive reminders).
    @Published private(set) var isBreakImminent: Bool = false
    /// Consecutive breaks the user skipped without taking them. Only used for a
    /// gentle nudge — skipping is always allowed.
    @Published private(set) var skipStreak: Int = 0

    /// Finished work sessions since launch, used to place long breaks.
    private var workSessionsCompleted: Int = 0

    // Activity to prevent App Nap
    private var activity: NSObjectProtocol?

    var workDurationSeconds: Int { settings.workSeconds }
    var breakDurationSeconds: Int { settings.shortBreakSeconds }
    var pauseDuringMeetings: Bool { settings.pauseDuringMeetings }
    var muteSounds: Bool { settings.muteSounds }
    var longBreakEvery: Int { settings.longBreakEvery }
    var longBreakSeconds: Int { settings.longBreakTotalSeconds }
    var progressiveReminders: Bool { settings.progressiveReminders }

    /// Duration of the break in progress — the ring needs the real total,
    /// otherwise a 15-minute break would fill up in 20 seconds.
    var currentBreakTotalSeconds: Int {
        if state == .onBreak && activeBreakTotalSeconds > 0 {
            return activeBreakTotalSeconds
        }
        return isLongBreak ? longBreakSeconds : breakDurationSeconds
    }

    /// Skipping is always allowed while a break is on screen: a reminder must
    /// never be stronger than the work it interrupts.
    var canSkipBreak: Bool {
        state == .onBreak && settings.allowSkipBreak
    }

    /// After repeated skips the overlay shows a nudge instead of silently
    /// letting the break go — purely advisory, never blocking.
    var showsSkipHint: Bool {
        state == .onBreak
            && TimerRules.showsSkipHint(streak: skipStreak, enabled: progressiveReminders)
    }

    var menuBarText: String {
        switch state {
        case .working:
            return formatTime(remainingSeconds)
        case .onBreak:
            return L10n.t(.breakCountdown, formatTime(remainingSeconds))
        case .paused:
            switch pauseReason {
            case .meeting:
                return L10n.t(.meetingCountdown, formatTime(secondsBeforePause))
            case .breakPending:
                return L10n.t(.meetingInProgress)
            case .locked:
                return L10n.t(.locked)
            case .idle:
                return L10n.t(.idleCountdown, formatTime(secondsBeforePause))
            case .manual:
                return L10n.t(.pausedCountdown, formatTime(secondsBeforePause))
            }
        }
    }

    var pauseStatusText: String? {
        guard state == .paused else { return nil }
        switch pauseReason {
        case .meeting:
            return meetingDetector.meetingSource.map { L10n.t(.pausedWith, $0) } ?? L10n.t(.pausedInMeeting)
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

    var currentPauseReason: PauseReason? {
        state == .paused ? pauseReason : nil
    }

    var isInMeeting: Bool {
        meetingDetector.isInMeeting
    }

    init(settings: Settings) {
        self.settings = settings

        remainingSeconds = workDurationSeconds
        workDeadline = TimerRules.deadline(from: Date(), seconds: remainingSeconds)
        state = .working
        startTicking()
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

    /// Whether the session is locked. Overridable so tests do not depend on
    /// the machine's real lock state.
    var screenLockedProvider: () -> Bool = { TimerManager.sessionIsLocked() }

    static func sessionIsLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    private func handleScreenLocked() {
        guard settings.pauseTrigger.pausesOnLock, state == .working else { return }
        updateWorkingCountdown()
        secondsBeforePause = remainingSeconds
        workDeadline = nil
        isBreakImminent = false
        state = .paused
        pauseReason = .locked
        Log.info("Timer paused: screen locked (\(secondsBeforePause)s banked)")
    }

    private func handleScreenUnlocked() {
        guard state == .paused, pauseReason == .locked else { return }
        // Display wake fires before the unlock in most cases — stay paused
        // until the session really is unlocked.
        if settings.pauseTrigger.pausesOnLock && screenLockedProvider() { return }
        Log.info("Screen unlocked — starting a full work session")
        resumeFromAutomaticPause()
    }

    // MARK: - Idle (opt-in alternative to the lock screen)

    /// Seconds since the last keyboard or mouse event. Overridable so the idle
    /// rules can be verified without waiting for real input.
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

        if TimerRules.shouldPauseForIdle(
            secondsSinceInput: idle,
            trigger: settings.pauseTrigger,
            isWorking: state == .working
        ) {
            updateWorkingCountdown()
            secondsBeforePause = remainingSeconds
            workDeadline = nil
            isBreakImminent = false
            state = .paused
            pauseReason = .idle
            Log.info("Timer paused: idle for \(Int(idle))s (\(secondsBeforePause)s banked)")
        } else if state == .paused, pauseReason == .idle,
            TimerRules.isBackFromIdle(secondsSinceInput: idle, trigger: settings.pauseTrigger)
        {
            Log.info("User is back after an idle pause — starting a full work session")
            resumeFromAutomaticPause()
        }
    }

    /// Lifting a lock/idle pause is always a fresh cycle: the user was away,
    /// which is what the break was for.
    private func resumeFromAutomaticPause() {
        beginWorking(seconds: workDurationSeconds)
    }

    private func handleWake() {
        switch state {
        case .working:
            Log.info("Timer restarted after system wake")
            beginWorking(seconds: workDurationSeconds)
        case .onBreak:
            Log.info("Break dismissed after system wake, timer restarted")
            overlayManager.dismissOverlay()
            beginWorking(seconds: workDurationSeconds)
        case .paused:
            break
        }
    }

    func start() {
        guard state != .onBreak else {
            Log.info("Timer restart ignored while a break is in progress")
            return
        }
        Log.info("Timer started: work=\(workDurationSeconds / 60)min, break=\(breakDurationSeconds)s")
        beginWorking(seconds: workDurationSeconds)
    }

    /// User-requested short break. It does not consume a pomodoro work session
    /// and therefore does not move the next long break closer.
    func startBreakNow() {
        guard state != .onBreak else { return }
        Log.info("Manual break requested")
        startBreak(countWorkSession: false)
    }

    func pause() {
        guard state == .working else { return }
        Log.info("Timer paused by user")
        updateWorkingCountdown()
        secondsBeforePause = remainingSeconds
        workDeadline = nil
        isBreakImminent = false
        state = .paused
        pauseReason = .manual
    }

    func resume() {
        guard state == .paused else { return }
        Log.info("Timer resumed by user")
        beginWorking(seconds: secondsBeforePause, resetImminent: false)
        pauseReason = .manual
        updateImminentFlag()
    }

    func skipBreak() {
        guard state == .onBreak else { return }
        guard canSkipBreak else {
            Log.info("Break skip rejected: skipping is disabled in settings")
            return
        }
        Log.info("Break overlay closed: user cancelled")
        overlayManager.dismissOverlay()
        skipStreak += 1
        beginWorking(seconds: workDurationSeconds)
    }

    func workDurationSettingChanged() {
        guard state == .working else { return }
        if remainingSeconds > workDurationSeconds {
            remainingSeconds = workDurationSeconds
        }
        // Keep the remaining time, but move its deadline to match a setting
        // change made between timer ticks.
        workDeadline = TimerRules.deadline(from: Date(), seconds: remainingSeconds)
        updateImminentFlag()
    }

    func togglePause() {
        if state == .working {
            pause()
        } else if state == .paused && pauseReason != .meeting && pauseReason != .breakPending {
            resume()
        }
    }

    // Called when the user toggles "Pause During Meetings".
    func pauseDuringMeetingsSettingChanged(enabled: Bool) {
        guard !enabled else { return }
        wasInMeeting = false
        meetingDetector.reset()
        guard state == .paused else { return }
        switch pauseReason {
        case .meeting, .breakPending:
            Log.info("Pause During Meetings disabled while in meeting pause — resuming")
            beginWorking(seconds: workDurationSeconds)
            pauseReason = .manual
        default:
            break
        }
    }

    // Called when the user picks a different pause trigger in the menu.
    func pauseTriggerSettingChanged(_ trigger: PauseTrigger) {
        guard state == .paused else { return }
        switch pauseReason {
        case .locked where !trigger.pausesOnLock:
            Log.info("Lock pause disabled while paused — resuming")
            resumeFromAutomaticPause()
        case .idle where !trigger.pausesOnIdle:
            Log.info("Idle pause disabled while paused — resuming")
            resumeFromAutomaticPause()
        default:
            break
        }
    }

    // MARK: - Private

    /// Centralized transition out of breaks/pauses and into a running work
    /// session. Every caller gets a fresh wall-clock deadline and no stale
    /// overlay/animation state.
    private func beginWorking(seconds: Int, resetImminent: Bool = true) {
        let duration = max(0, seconds)
        graceAnimTask?.cancel()
        graceAnimTask = nil
        isInGracePeriod = false
        graceProgress = 1
        isEndingBreak = false
        isLongBreak = false
        activeBreakTotalSeconds = 0
        breakTip = ""
        breakDeadline = nil
        nextBreakTipDate = nil
        remainingSeconds = duration
        workDeadline = TimerRules.deadline(from: Date(), seconds: duration)
        if resetImminent {
            isBreakImminent = false
        }
        state = .working
    }

    private func updateWorkingCountdown(now: Date = Date()) {
        if workDeadline == nil {
            workDeadline = TimerRules.deadline(from: now, seconds: remainingSeconds)
        }
        guard let workDeadline else { return }
        remainingSeconds = TimerRules.remainingSeconds(deadline: workDeadline, now: now)
    }

    private func startTicking() {
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
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

        // Check for meetings every 5 seconds
        if tickCount % 5 == 0 {
            if pauseDuringMeetings { checkMeetingStatus() }
            checkIdleStatus()
        }

        switch state {
        case .paused:
            break

        case .working:
            let now = Date()
            updateWorkingCountdown(now: now)
            updateImminentFlag()
            if remainingSeconds <= 0 {
                startBreak(countWorkSession: true)
            }

        case .onBreak:
            let now = Date()
            let elapsed = now.timeIntervalSince(breakStartTime)
            if elapsed >= breakGracePeriod {
                if isInGracePeriod {
                    isInGracePeriod = false
                    graceAnimTask?.cancel()
                    graceAnimTask = nil
                }
                graceProgress = 1
                if breakDeadline == nil {
                    breakDeadline = TimerRules.deadline(from: now, seconds: remainingSeconds)
                }
                if let breakDeadline {
                    remainingSeconds = TimerRules.remainingSeconds(deadline: breakDeadline, now: now)
                }
                // Rotate by wall-clock time rather than an exact countdown
                // value, which a delayed tick could otherwise skip.
                if let nextBreakTipDate, now >= nextBreakTipDate, remainingSeconds > 0 {
                    breakTip = L10n.randomBreakTip(excluding: breakTip)
                    self.nextBreakTipDate = now.addingTimeInterval(20)
                }
                if remainingSeconds <= 0 {
                    endBreak()
                }
            }
        }
    }

    /// Progressive reminders: during the last minute, flag the menu-bar
    /// hourglass and play the soft chime once on entry (including after resume).
    private func updateImminentFlag() {
        let imminent = TimerRules.isImminent(
            remaining: remainingSeconds,
            enabled: progressiveReminders,
            isWorking: state == .working
        )
        if imminent && !isBreakImminent {
            Log.info("Break impending: \(remainingSeconds)s left")
            if !muteSounds { NSSound(named: "Tink")?.play() }
        }
        isBreakImminent = imminent
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

    private func startBreak(countWorkSession: Bool) {
        // Check for meeting immediately before showing break overlay
        if pauseDuringMeetings {
            meetingDetector.check()
            if meetingDetector.isInMeeting {
                Log.info("Break overlay suppressed: meeting in progress")
                secondsBeforePause = 0
                workDeadline = nil
                isBreakImminent = false
                state = .paused
                pauseReason = .breakPending
                return
            }
        }

        if countWorkSession {
            // Count only naturally completed work, not the manual "break now".
            workSessionsCompleted += 1
        }
        // Deliberately does NOT reset `skipStreak` here: clearing it when a
        // voluntary break starts would let the nudge be dodged and would also
        // lose the information that the user keeps skipping. It is cleared in
        // `endBreak()` only, i.e. once a break is actually taken.
        isLongBreak =
            countWorkSession
            && TimerRules.isLongBreak(
                sessionsCompleted: workSessionsCompleted,
                every: longBreakEvery
            )
        activeBreakTotalSeconds = TimerRules.breakTotalSeconds(
            isLong: isLongBreak,
            shortSeconds: settings.breakSeconds,
            longSeconds: settings.longBreakSeconds
        )

        let now = Date()
        remainingSeconds = activeBreakTotalSeconds
        state = .onBreak
        isEndingBreak = false
        isBreakImminent = false
        workDeadline = nil
        breakStartTime = now
        breakDeadline =
            now
            .addingTimeInterval(breakGracePeriod)
            .addingTimeInterval(TimeInterval(activeBreakTotalSeconds))
        nextBreakTipDate = now.addingTimeInterval(breakGracePeriod + 20)
        isInGracePeriod = true
        graceProgress = 0
        breakTip = L10n.randomBreakTip(excluding: breakTip)
        startGraceAnimation()

        if isFrontmostAppFullscreen() {
            overlayManager.showCompactBreakOverlay(timerManager: self)
            Log.info("Break overlay triggered: compact overlay (fullscreen app detected)")
        } else {
            overlayManager.showBreakOverlay(timerManager: self)
            Log.info("Break overlay triggered: full overlay (work timer expired)")
        }

        Log.info(
            "Break started: \(isLongBreak ? "long" : "short") \(activeBreakTotalSeconds)s (session #\(workSessionsCompleted), manual=\(!countWorkSession))"
        )
        if !muteSounds { NSSound(named: "Glass")?.play() }
    }

    private func endBreak() {
        guard !isEndingBreak else { return }
        isEndingBreak = true
        Log.info("Break overlay closed: timeout completed")
        graceAnimTask?.cancel()
        graceAnimTask = nil
        skipStreak = 0
        if !muteSounds { NSSound(named: "Blow")?.play() }
        overlayManager.dismissWithAnimation { [weak self] in
            guard let self else { return }
            // During the 0.45s fade-out something else may already have taken
            // over (a meeting interrupt paused the timer, the user skipped, or
            // the system woke) — only restart work if the break is still ours.
            guard self.state == .onBreak else { return }
            self.beginWorking(seconds: self.workDurationSeconds)
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

    private func checkMeetingStatus() {
        meetingDetector.check()

        if meetingDetector.isInMeeting {
            if !wasInMeeting {
                Log.info("Meeting mode entered (\(meetingDetector.meetingSource ?? "unknown"))")
                wasInMeeting = true
            }
            // Timer keeps running during meetings when working — no pause.
            // A meeting interrupts a break; the user can skip one themselves,
            // so this is only about getting out of the way.
            if state == .onBreak {
                Log.info("Break interrupted by meeting")
                overlayManager.dismissOverlay()
                beginWorking(seconds: workDurationSeconds)
                secondsBeforePause = remainingSeconds
                workDeadline = nil
                state = .paused
                pauseReason = .meeting
            }
        } else {
            if wasInMeeting {
                Log.info("Meeting mode left")
                wasInMeeting = false
            }
            if state == .paused && pauseReason == .breakPending {
                // Meeting ended with break pending — short countdown then break
                beginWorking(seconds: postMeetingBreakDelay)
            } else if state == .paused && pauseReason == .meeting {
                // Meeting ended (break was interrupted), resume
                resume()
            }
        }
    }
}

func formatTime(_ seconds: Int) -> String {
    TimerRules.formatTime(seconds)
}
