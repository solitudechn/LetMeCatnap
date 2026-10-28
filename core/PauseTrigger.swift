import Foundation

/// What the timer treats as "the user has left".
///
/// The lock screen is the signal we trust by default: locking is deliberate,
/// while a keyboard that has been quiet for a while may simply mean the user is
/// reading. Idle detection is still available for people who never lock their
/// screen, but it is now an explicit choice rather than the default.
public enum PauseTrigger: Int, CaseIterable, Sendable {
    /// Pause when the screen locks or the display sleeps. Default.
    case lockScreen = 0
    /// Pause after a stretch of no keyboard or mouse input.
    case idle = 1
    /// Either signal pauses the timer.
    case lockScreenOrIdle = 2
    /// Never pause automatically.
    case never = 3

    public var pausesOnLock: Bool {
        self == .lockScreen || self == .lockScreenOrIdle
    }

    public var pausesOnIdle: Bool {
        self == .idle || self == .lockScreenOrIdle
    }

    /// Title used in the menu. Localization lives in the app bundle, so the
    /// enum deliberately carries no display string of its own.
    public var isEnabled: Bool { self != .never }
}
