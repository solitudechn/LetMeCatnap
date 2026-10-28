import Foundation

/// Pure timing rules shared by the app and its tests.
///
/// Everything here is deterministic and free of AppKit, timers and
/// `UserDefaults`, so the behaviour can be verified without launching the app.
public enum TimerRules {

    // MARK: - Settings bounds

    public static let workMinutesRange = 1...120
    public static let breakSecondsRange = 5...599
    public static let longBreakEveryRange = 0...12
    public static let longBreakSecondsRange = 60...3600

    /// One minute before the break, progressive reminders kick in.
    public static let imminentThreshold = 60
    /// Fade the break overlay's countdown after this many seconds.
    public static let countdownVisibleSeconds: TimeInterval = 3
    /// No input for this long counts as having left the desk. Only consulted
    /// when `PauseTrigger.pausesOnIdle` is selected; five minutes is long
    /// enough that reading a document does not look like an absence.
    public static let idleThresholdSeconds: TimeInterval = 300
    /// How long the user must be back (seconds since last input) before an
    /// idle pause is lifted.
    public static let idleReturnSeconds: TimeInterval = 5

    public static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
    }

    // MARK: - Derived durations

    public static func workSeconds(minutes: Int) -> Int {
        clamp(minutes, to: workMinutesRange) * 60
    }

    public static func shortBreakSeconds(_ raw: Int) -> Int {
        clamp(raw, to: breakSecondsRange)
    }

    public static func longBreakSeconds(_ raw: Int) -> Int {
        clamp(raw, to: longBreakSecondsRange)
    }

    /// `every == 0` disables the rhythm. Long breaks are placed after every
    /// N fully completed work sessions.
    public static func isLongBreak(sessionsCompleted: Int, every: Int) -> Bool {
        guard every > 0, sessionsCompleted > 0 else { return false }
        return sessionsCompleted % every == 0
    }

    public static func breakTotalSeconds(
        isLong: Bool,
        shortSeconds: Int,
        longSeconds: Int
    ) -> Int {
        isLong ? longBreakSeconds(longSeconds) : shortBreakSeconds(shortSeconds)
    }

    // MARK: - Countdown

    /// Remaining whole seconds for a wall-clock deadline, never negative.
    public static func remainingSeconds(deadline: Date, now: Date) -> Int {
        max(0, Int(ceil(deadline.timeIntervalSince(now))))
    }

    public static func deadline(from now: Date, seconds: Int) -> Date {
        now.addingTimeInterval(TimeInterval(max(0, seconds)))
    }

    /// Progressive reminder: only during the final minute of a running work
    /// session, and only when the feature is enabled.
    public static func isImminent(
        remaining: Int,
        enabled: Bool,
        isWorking: Bool,
        threshold: Int = imminentThreshold
    ) -> Bool {
        enabled && isWorking && remaining > 0 && remaining <= threshold
    }

    // MARK: - Away detection

    /// Whether an idle pause should start now. Only consulted when the user
    /// picked an idle-aware trigger.
    public static func shouldPauseForIdle(
        secondsSinceInput: TimeInterval,
        trigger: PauseTrigger,
        isWorking: Bool
    ) -> Bool {
        trigger.pausesOnIdle && isWorking && secondsSinceInput >= idleThresholdSeconds
    }

    /// Whether the user is demonstrably back at the keyboard.
    public static func isBackFromIdle(
        secondsSinceInput: TimeInterval,
        trigger: PauseTrigger
    ) -> Bool {
        trigger.pausesOnIdle && secondsSinceInput < idleReturnSeconds
    }

    // MARK: - Skip streak

    /// After this many consecutive skips the overlay nudges the user to stay —
    /// as a hint only, never as a lock.
    public static let skipHintThreshold = 2

    public static func showsSkipHint(streak: Int, enabled: Bool) -> Bool {
        enabled && streak >= skipHintThreshold
    }

    // MARK: - Formatting

    public static func formatTime(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }
}
