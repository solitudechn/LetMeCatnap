import Foundation
import Combine

/// Single source of truth for every user preference.
///
/// Before this existed each consumer read `UserDefaults` through its own
/// computed property, so a change never notified anything and bounds had to be
/// re-applied at every call site. Values are clamped in the setters, persisted
/// immediately, and published so SwiftUI can react.
///
/// Defaults are applied here instead of via `UserDefaults.register(defaults:)`
/// on purpose: the registration domain is process-wide, which makes
/// "has the user ever set this key?" unanswerable and silently breaks the
/// one-time migration below.
@MainActor
public final class Settings: ObservableObject {
    public static let shared = Settings()

    /// Keys stay as plain strings so existing installs keep their values.
    public enum Key {
        public static let workMinutes = "workDurationMinutes"
        public static let breakSeconds = "breakDurationSeconds"
        public static let pauseDuringMeetings = "pauseDuringMeetings"
        public static let pauseTrigger = "pauseTrigger"
        /// Legacy boolean, read once for migration.
        public static let legacyPauseWhenLocked = "pauseWhenLocked"
        public static let allowSkipBreak = "allowSkipBreak"
        public static let progressiveReminders = "progressiveReminders"
        public static let muteSounds = "muteSounds"
        public static let hideMenuBarTimer = "hideMenuBarTimer"
        public static let longBreakEvery = "longBreakEvery"
        public static let longBreakSeconds = "longBreakSeconds"
        public static let skippedUpdate = "skippedUpdate"
        public static let hasCompletedWelcome = "hasCompletedWelcome"
    }

    /// Factory values, used when a key has never been written.
    public enum Defaults {
        public static let workMinutes = 20
        public static let breakSeconds = 20
        public static let longBreakEvery = 4
        public static let longBreakSeconds = 900
        public static let pauseDuringMeetings = true
        public static let pauseTrigger: PauseTrigger = .lockScreen
        public static let allowSkipBreak = true
        public static let progressiveReminders = true
        public static let muteSounds = false
        public static let hideMenuBarTimer = false
        public static let hasCompletedWelcome = false
    }

    private let defaults: UserDefaults

    // MARK: - Published state

    @Published public private(set) var workMinutes: Int
    @Published public private(set) var breakSeconds: Int
    @Published public private(set) var longBreakEvery: Int
    @Published public private(set) var longBreakSeconds: Int

    @Published public private(set) var pauseDuringMeetings: Bool
    @Published public private(set) var pauseTrigger: PauseTrigger
    @Published public private(set) var allowSkipBreak: Bool
    @Published public private(set) var progressiveReminders: Bool
    @Published public private(set) var muteSounds: Bool
    @Published public private(set) var hideMenuBarTimer: Bool

    @Published public private(set) var skippedUpdateVersion: String?
    @Published public private(set) var hasCompletedWelcome: Bool

    // MARK: - Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        workMinutes = TimerRules.clamp(
            Self.integer(defaults, Key.workMinutes, fallback: Defaults.workMinutes),
            to: TimerRules.workMinutesRange
        )
        breakSeconds = TimerRules.clamp(
            Self.integer(defaults, Key.breakSeconds, fallback: Defaults.breakSeconds),
            to: TimerRules.breakSecondsRange
        )
        longBreakEvery = TimerRules.clamp(
            Self.integer(defaults, Key.longBreakEvery, fallback: Defaults.longBreakEvery),
            to: TimerRules.longBreakEveryRange
        )
        longBreakSeconds = TimerRules.clamp(
            Self.integer(defaults, Key.longBreakSeconds, fallback: Defaults.longBreakSeconds),
            to: TimerRules.longBreakSecondsRange
        )

        pauseDuringMeetings = Self.boolean(
            defaults, Key.pauseDuringMeetings, fallback: Defaults.pauseDuringMeetings
        )
        allowSkipBreak = Self.boolean(
            defaults, Key.allowSkipBreak, fallback: Defaults.allowSkipBreak
        )
        progressiveReminders = Self.boolean(
            defaults, Key.progressiveReminders, fallback: Defaults.progressiveReminders
        )
        muteSounds = Self.boolean(defaults, Key.muteSounds, fallback: Defaults.muteSounds)
        hideMenuBarTimer = Self.boolean(
            defaults, Key.hideMenuBarTimer, fallback: Defaults.hideMenuBarTimer
        )

        // One-time migration from the two booleans that predate `pauseTrigger`:
        //  - explicitly disabled automatic pausing  -> stay disabled (`.never`)
        //  - otherwise                             -> `.lockScreen`
        // Idle pausing, which used to be the default, is deliberately not
        // restored: it is what made reading look like an absence.
        if let raw = Self.optionalInteger(defaults, Key.pauseTrigger),
           let stored = PauseTrigger(rawValue: raw) {
            pauseTrigger = stored
        } else if Self.optionalBoolean(defaults, Key.legacyPauseWhenLocked) == false {
            pauseTrigger = .never
        } else {
            pauseTrigger = Defaults.pauseTrigger
        }

        skippedUpdateVersion = defaults.string(forKey: Key.skippedUpdate)
        hasCompletedWelcome = Self.boolean(
            defaults, Key.hasCompletedWelcome, fallback: Defaults.hasCompletedWelcome
        )
    }

    // MARK: - Derived values

    public var workSeconds: Int { TimerRules.workSeconds(minutes: workMinutes) }
    public var shortBreakSeconds: Int { TimerRules.shortBreakSeconds(breakSeconds) }
    public var longBreakTotalSeconds: Int { TimerRules.longBreakSeconds(longBreakSeconds) }

    // MARK: - Timers

    public func setWorkMinutes(_ value: Int) {
        let clamped = TimerRules.clamp(value, to: TimerRules.workMinutesRange)
        guard clamped != workMinutes else { return }
        workMinutes = clamped
        defaults.set(clamped, forKey: Key.workMinutes)
    }

    public func setBreakSeconds(_ value: Int) {
        let clamped = TimerRules.clamp(value, to: TimerRules.breakSecondsRange)
        guard clamped != breakSeconds else { return }
        breakSeconds = clamped
        defaults.set(clamped, forKey: Key.breakSeconds)
    }

    public func setLongBreak(every: Int, seconds: Int) {
        let clampedEvery = TimerRules.clamp(every, to: TimerRules.longBreakEveryRange)
        let clampedSeconds = TimerRules.clamp(seconds, to: TimerRules.longBreakSecondsRange)
        if clampedEvery != longBreakEvery {
            longBreakEvery = clampedEvery
            defaults.set(clampedEvery, forKey: Key.longBreakEvery)
        }
        if clampedSeconds != longBreakSeconds {
            longBreakSeconds = clampedSeconds
            defaults.set(clampedSeconds, forKey: Key.longBreakSeconds)
        }
    }

    // MARK: - Behaviour toggles

    public func setPauseDuringMeetings(_ value: Bool) {
        pauseDuringMeetings = persist(value, Key.pauseDuringMeetings)
    }

    public func setPauseTrigger(_ value: PauseTrigger) {
        guard value != pauseTrigger else { return }
        pauseTrigger = value
        defaults.set(value.rawValue, forKey: Key.pauseTrigger)
    }

    public func setAllowSkipBreak(_ value: Bool) {
        allowSkipBreak = persist(value, Key.allowSkipBreak)
    }

    public func setProgressiveReminders(_ value: Bool) {
        progressiveReminders = persist(value, Key.progressiveReminders)
    }

    public func setMuteSounds(_ value: Bool) {
        muteSounds = persist(value, Key.muteSounds)
    }

    public func setHideMenuBarTimer(_ value: Bool) {
        hideMenuBarTimer = persist(value, Key.hideMenuBarTimer)
    }

    // MARK: - State flags

    public func setSkippedUpdateVersion(_ value: String?) {
        skippedUpdateVersion = value
        if let value {
            defaults.set(value, forKey: Key.skippedUpdate)
        } else {
            defaults.removeObject(forKey: Key.skippedUpdate)
        }
    }

    public func markWelcomeCompleted() {
        guard !hasCompletedWelcome else { return }
        hasCompletedWelcome = true
        defaults.set(true, forKey: Key.hasCompletedWelcome)
    }

    // MARK: - Persistence helpers

    private func persist(_ value: Bool, _ key: String) -> Bool {
        defaults.set(value, forKey: key)
        return value
    }

    private static func integer(_ defaults: UserDefaults, _ key: String, fallback: Int) -> Int {
        defaults.object(forKey: key) == nil ? fallback : defaults.integer(forKey: key)
    }

    private static func boolean(_ defaults: UserDefaults, _ key: String, fallback: Bool) -> Bool {
        optionalBoolean(defaults, key) ?? fallback
    }

    private static func optionalBoolean(_ defaults: UserDefaults, _ key: String) -> Bool? {
        (defaults.object(forKey: key) as? NSNumber)?.boolValue
    }

    private static func optionalInteger(_ defaults: UserDefaults, _ key: String) -> Int? {
        (defaults.object(forKey: key) as? NSNumber)?.intValue
    }
}
