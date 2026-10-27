import Foundation
import Combine
import AppKit
import CoreGraphics
import IOKit.pwr_mgt

enum TimerState {
    case working
    case onBreak
    case paused
}

enum PauseReason {
    case manual
    case meeting
    case idle
    case breakPending  // Work timer expired during meeting, waiting for meeting to end
}

enum SettingsKey {
    static let workDurationMinutes = "workDurationMinutes"
    static let breakDurationSeconds = "breakDurationSeconds"
    static let pauseDuringMeetings = "pauseDuringMeetings"
    static let allowSkipBreak = "allowSkipBreak"
    static let muteSounds = "muteSounds"
    static let pauseWhenIdle = "pauseWhenIdle"
    static let skippedUpdate = "skippedUpdate"
    static let hideMenuBarTimer = "hideMenuBarTimer"
    /// 0 disables the pomodoro rhythm; otherwise every N finished work sessions
    /// ends in a long break instead of a short one.
    static let longBreakEvery = "longBreakEvery"
    static let longBreakSeconds = "longBreakSeconds"
    /// Warn before the break, and stop the user from skipping forever.
    static let progressiveReminders = "progressiveReminders"
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
    private var wasIdle: Bool = false

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
    /// Consecutive breaks the user skipped without taking them.
    @Published private(set) var skipStreak: Int = 0

    /// Finished work sessions since launch, used to place long breaks.
    private var workSessionsCompleted: Int = 0
    /// After this many consecutive skips the next break is not skippable.
    private let mandatorySkipStreak = 2
    private let impendingBreakSeconds = 60

    // Activity to prevent App Nap
    private var activity: NSObjectProtocol?

    var workDurationSeconds: Int {
        UserDefaults.standard.integer(forKey: SettingsKey.workDurationMinutes).clamped(to: 1...120) * 60
    }

    var breakDurationSeconds: Int {
        let val = UserDefaults.standard.integer(forKey: SettingsKey.breakDurationSeconds)
        // FIXME: clamp to 9:59 due to UI issues
        return val.clamped(to: 5...599)
    }

    var pauseDuringMeetings: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.pauseDuringMeetings)
    }

    var muteSounds: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.muteSounds)
    }

    var pauseWhenIdle: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.pauseWhenIdle)
    }

    // MARK: - Pomodoro rhythm / progressive reminders

    /// 0 = rhythm disabled. Clamped so a hand-edited plist cannot break the timer.
    var longBreakEvery: Int {
        UserDefaults.standard.integer(forKey: SettingsKey.longBreakEvery).clamped(to: 0...12)
    }

    /// A long break may well exceed the short-break UI cap (9:59).
    var longBreakSeconds: Int {
        UserDefaults.standard.integer(forKey: SettingsKey.longBreakSeconds).clamped(to: 60...3600)
    }

    /// Duration of the break in progress — the ring needs the real total,
    /// otherwise a 15-minute break would fill up in 20 seconds.
    var currentBreakTotalSeconds: Int {
        if state == .onBreak && activeBreakTotalSeconds > 0 {
            return activeBreakTotalSeconds
        }
        return isLongBreak ? longBreakSeconds : breakDurationSeconds
    }

    var progressiveReminders: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.progressiveReminders)
    }

    /// Progressive reminders: after enough consecutive skips, the break is not
    /// skippable any more.
    var isBreakMandatory: Bool {
        progressiveReminders && state == .onBreak && skipStreak >= mandatorySkipStreak
    }

    /// The single source of truth for both the overlay button and Esc hotkey.
    var canSkipBreak: Bool {
        state == .onBreak
            && UserDefaults.standard.bool(forKey: SettingsKey.allowSkipBreak)
            && !isBreakMandatory
    }

    var menuBarText: String {
        switch state {
        case .working:
            return formatTime(remainingSeconds)
        case .onBreak:
            return L10n.breakCountdown(formatTime(remainingSeconds))
        case .paused:
            switch pauseReason {
            case .meeting:
                return L10n.meetingCountdown(formatTime(secondsBeforePause))
            case .breakPending:
                return L10n.meetingInProgress
            case .idle:
                return L10n.idle
            case .manual:
                return L10n.pausedCountdown(formatTime(secondsBeforePause))
            }
        }
    }

    var pauseStatusText: String? {
        guard state == .paused else { return nil }
        switch pauseReason {
        case .meeting:
            return meetingDetector.meetingSource.map { L10n.pausedWith($0) } ?? L10n.pausedInMeeting
        case .breakPending:
            return meetingDetector.meetingSource.map { L10n.breakPending($0) } ?? L10n.inMeetingBreakPending
        case .idle:
            return L10n.pausedIdle
        case .manual:
            return L10n.paused
        }
    }

    var currentPauseReason: PauseReason? {
        state == .paused ? pauseReason : nil
    }

    var isInMeeting: Bool {
        meetingDetector.isInMeeting
    }

    init() {
        // Register defaults
        UserDefaults.standard.register(defaults: [
            SettingsKey.workDurationMinutes: 20,
            SettingsKey.breakDurationSeconds: 20,
            SettingsKey.pauseDuringMeetings: true,
            SettingsKey.allowSkipBreak: true,
            SettingsKey.muteSounds: false,
            SettingsKey.pauseWhenIdle: true,
            SettingsKey.hideMenuBarTimer: false,
            SettingsKey.longBreakEvery: 4,
            SettingsKey.longBreakSeconds: 900,
            SettingsKey.progressiveReminders: true,
        ])
        // Start timer and ticker (ticker runs for app lifetime)
        remainingSeconds = workDurationSeconds
        workDeadline = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        state = .working
        startTicking()

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
            Log.info("Break skip blocked (allowed=\(UserDefaults.standard.bool(forKey: SettingsKey.allowSkipBreak)), mandatory=\(isBreakMandatory))")
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
        workDeadline = Date().addingTimeInterval(TimeInterval(remainingSeconds))
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

    // Called when the user toggles "Pause When Idle".
    func pauseWhenIdleSettingChanged(enabled: Bool) {
        guard !enabled, state == .paused, pauseReason == .idle else { return }
        Log.info("Pause When Idle disabled while idle — resuming")
        wasIdle = false
        resumeFromIdle()
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
        workDeadline = Date().addingTimeInterval(TimeInterval(duration))
        if resetImminent {
            isBreakImminent = false
        }
        state = .working
    }

    private func updateWorkingCountdown(now: Date = Date()) {
        if workDeadline == nil {
            workDeadline = now.addingTimeInterval(TimeInterval(remainingSeconds))
        }
        guard let workDeadline else { return }
        remainingSeconds = max(0, Int(ceil(workDeadline.timeIntervalSince(now))))
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

        // Check for meetings and idle every 5 seconds
        if tickCount % 5 == 0 {
            if pauseDuringMeetings { checkMeetingStatus() }
            if pauseWhenIdle { checkIdleStatus() }
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
                    breakDeadline = now.addingTimeInterval(TimeInterval(remainingSeconds))
                }
                if let breakDeadline {
                    remainingSeconds = max(0, Int(ceil(breakDeadline.timeIntervalSince(now))))
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
        let imminent = progressiveReminders
            && state == .working
            && remainingSeconds > 0
            && remainingSeconds <= impendingBreakSeconds
        if imminent && !isBreakImminent {
            Log.info("Break impending: \(remainingSeconds)s left")
            if !muteSounds { NSSound(named: "Tink")?.play() }
        }
        isBreakImminent = imminent
    }

    // MARK: - Fullscreen Detection

    func isFrontmostAppFullscreen() -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return false }

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
                if abs(w - sf.width) < 2 && abs(h - sf.height) < 2 &&
                   abs(x - sf.minX) < 2 && abs(y - sf.minY) < 2 {
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
        } else {
            // Voluntarily taking a break satisfies the progressive reminder.
            skipStreak = 0
        }
        let every = longBreakEvery
        isLongBreak = countWorkSession && every > 0 && workSessionsCompleted % every == 0
        activeBreakTotalSeconds = isLongBreak ? longBreakSeconds : breakDurationSeconds

        remainingSeconds = activeBreakTotalSeconds
        state = .onBreak
        isEndingBreak = false
        isBreakImminent = false
        workDeadline = nil
        breakStartTime = Date()
        breakDeadline = breakStartTime
            .addingTimeInterval(breakGracePeriod)
            .addingTimeInterval(TimeInterval(activeBreakTotalSeconds))
        nextBreakTipDate = breakStartTime.addingTimeInterval(breakGracePeriod + 20)
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

        Log.info("Break started: \(isLongBreak ? "long" : "short") \(activeBreakTotalSeconds)s (session #\(workSessionsCompleted), manual=\(!countWorkSession))")
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
                try? await Task.sleep(nanoseconds: 50_000_000) // 50 ms
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
            // A meeting may interrupt a normal break, but must not bypass a
            // mandatory break or count as a user-initiated skip.
            if state == .onBreak && !isBreakMandatory {
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
                // Meeting ended (break was skipped), resume
                resume()
            }
        }
    }

    // MARK: - Idle Detection

    #if DEBUG
    private let idleThreshold: TimeInterval = 30 // 30 seconds for testing
    #else
    private var idleThreshold: TimeInterval { 60 + TimeInterval(breakDurationSeconds) }
    #endif

    private func checkIdleStatus() {
        // kCGAnyInputEventType (~0) checks all input event types
        let idleTime = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)

        if idleTime >= idleThreshold && !hasActiveDisplaySleepAssertion() {
            if state == .working {
                if !wasIdle {
                    Log.info("Idle mode entered (idle for \(Int(idleTime))s)")
                    wasIdle = true
                }
                secondsBeforePause = remainingSeconds
                state = .paused
                pauseReason = .idle
            }
        } else {
            if wasIdle {
                Log.info("Idle mode left")
                wasIdle = false
            }
            if state == .paused && pauseReason == .idle {
                resumeFromIdle()
            }
        }
    }

    private func resumeFromIdle() {
        guard state == .paused && pauseReason == .idle else { return }

        // Check for active meeting before resuming to avoid a gap
        if pauseDuringMeetings {
            meetingDetector.check()
            if meetingDetector.isInMeeting {
                secondsBeforePause = workDurationSeconds
                pauseReason = .meeting
                return
            }
        }

        beginWorking(seconds: workDurationSeconds)
    }

    private func hasActiveDisplaySleepAssertion() -> Bool {
        var assertions: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&assertions) == kIOReturnSuccess,
              let dict = assertions?.takeRetainedValue() as? [String: [[String: Any]]] else {
            return false
        }

        for (_, processAssertions) in dict {
            for assertion in processAssertions {
                if let type = assertion["AssertType"] as? String,
                   type == "PreventUserIdleDisplaySleep" || type == "NoDisplaySleep" {
                    return true
                }
            }
        }
        return false
    }

}

func formatTime(_ seconds: Int) -> String {
    let m = seconds / 60
    let s = seconds % 60
    return String(format: "%d:%02d", m, s)
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
