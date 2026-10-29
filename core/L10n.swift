import Foundation

/// One translatable string, in every language the app ships with.
///
/// Keeping both sides next to each other (instead of two parallel files) makes a
/// half-finished translation impossible to merge by accident, and lets a unit
/// test check the pair without parsing source code.
public struct Translation: Equatable, Sendable {
    public let en: String
    public let zh: String

    public init(_ en: String, _ zh: String) {
        self.en = en
        self.zh = zh
    }

    public func value(for language: AppLanguage) -> String {
        language == .chinese ? zh : en
    }

    /// Placeholders as they appear in the format string (`%@`, `%ld`, …).
    ///
    /// Counted by hand rather than with a regex literal: bare `/…/` literals are
    /// opt-in in Swift 5 language mode, which is what this package builds with.
    public var placeholderCount: Int {
        zip(en, en.dropFirst()).reduce(into: 0) { count, pair in
            if pair.0 == "%", "@ld".contains(pair.1) { count += 1 }
        }
    }
}

/// Languages the UI can be rendered in.
public enum AppLanguage: String, CaseIterable, Sendable {
    case system = "system"
    case english = "en"
    case chinese = "zh"

    /// Label shown in the Language menu. "English" and "简体中文" are proper
    /// names and stay untranslated on purpose.
    public var displayName: String {
        switch self {
        case .system: return L10n.t(.systemLanguage)
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }
}

/// Every user-visible string the app can show, as a type.
///
/// Referencing a key that does not exist is a compile error, and
/// `StringTableTests` fails when a key has no entry or a translation lost a
/// placeholder — the two ways a string table rots.
public enum LocKey: String, CaseIterable, Sendable {
    // Menu bar
    case systemLanguage
    case pauseTimer
    case resumeTimer
    case restartTimer
    case takeBreakNow
    case workInterval
    case breakDuration
    case pauseDuringMeetings
    case pauseTrigger
    case triggerLockScreen
    case triggerIdle
    case triggerBoth
    case triggerNever
    case showSkipButton
    case escapeToDismiss
    case muteSounds
    case hideMenuBarTimer
    case launchAtLogin
    case languageLabel
    case timerSettings
    case reminderSettings
    case welcome
    case minutesFormat
    case secondsFormat
    case aboutFormat
    case quitFormat
    case ok

    // Menu bar countdown
    case breakCountdown
    case meetingCountdown
    case pausedCountdown
    case meetingInProgress
    case inMeeting
    case locked
    case idleCountdown
    case onBreak
    case nextBreakIn

    // Status line
    case pausedWith
    case pausedInMeeting
    case breakPending
    case inMeetingBreakPending
    case pausedLocked
    case pausedIdle
    case paused

    // Meeting detection
    case cameraInUse
    case microphoneInUse

    // Break overlay
    case timeToRest
    case restHint
    case timeRemaining
    case skip
    case skipKeys
    case showRemaining
    case skipHint
    case breakTypeShort
    case breakTypeLong

    // Pomodoro rhythm
    case pomodoroRhythm
    case off
    case longBreakTitle
    case longBreakPreset
    case progressiveReminders

    // About window
    case checkForUpdates
    case checkForUpdatesMenu
    case createdBy
    case upstreamBy
    case originalCodeBy
    case appIconBy
    case appIconCredit
    case iconsBy
    case licenseUnavailable

    // Main menu — only visible while the About window is open, because the
    // app is an accessory (menu bar only) the rest of the time.
    case menuEdit
    case menuWindow
    case hideAppFormat
    case hideOthers
    case showAll
    case undo
    case redo
    case cut
    case copy
    case paste
    case selectAll
    case minimize
    case close
}

/// Bilingual string lookup.
///
/// Language resolution order:
///   1. explicit choice from the Language menu (persisted in `UserDefaults`)
///   2. otherwise the system preferred language (`zh*` -> Chinese)
///
/// Strings live in code rather than `.lproj` files because the app bundle is
/// assembled by `build.sh` from a fixed file list; a `.strings` bundle would add
/// plumbing for no gain at two languages. `StringTable` is the only place a
/// string is written, and `script/check-l10n.py` plus `StringTableTests` keep it
/// honest.
public enum L10n {
    public typealias Language = AppLanguage

    public static let languageDefaultsKey = "uiLanguage"

    /// Explicit user preference. `.system` until the user picks a language.
    public static var preference: Language {
        get {
            guard let raw = UserDefaults.standard.string(forKey: languageDefaultsKey),
                let language = Language(rawValue: raw)
            else { return .system }
            return language
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: languageDefaultsKey)
        }
    }

    /// The language actually used to render strings right now (never `.system`).
    public static var current: Language {
        switch preference {
        case .english: return .english
        case .chinese: return .chinese
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("zh") ? .chinese : .english
        }
    }

    public static var isChinese: Bool { current == .chinese }

    /// Both sides of a key. A key missing from the table falls back to its own
    /// name so the gap is visible in the UI instead of crashing.
    public static func translation(_ key: LocKey) -> Translation {
        StringTable.table[key] ?? Translation(key.rawValue, key.rawValue)
    }

    /// Localized string for `key` in the active language, with format arguments
    /// applied when the translation declares placeholders.
    public static func t(_ key: LocKey, _ arguments: CVarArg...) -> String {
        format(translation(key).value(for: current), arguments)
    }

    /// Localized string for an explicit language. Used by tests and by anything
    /// that has to render a second language without changing the UI language.
    public static func text(_ key: LocKey, for language: Language) -> String {
        translation(key).value(for: language)
    }

    static func format(_ format: String, _ arguments: [CVarArg]) -> String {
        arguments.isEmpty ? format : String(format: format, arguments: arguments)
    }

    // MARK: - Break guidance

    /// A break length the way a person would say it: "15 分钟", "30 秒".
    ///
    /// Only whole minutes become minutes; a 90 second break stays "90 秒"
    /// rather than turning into "1.5 分钟", because the overlay has room for
    /// one short phrase and no room for arithmetic.
    public static func duration(seconds: Int) -> String {
        duration(seconds: seconds, for: current)
    }

    /// The same, for an explicit language. Used by tests, which need both
    /// sides without changing the user's UI language.
    public static func duration(seconds: Int, for language: Language) -> String {
        if seconds >= 60, seconds % 60 == 0 {
            return format(text(.minutesFormat, for: language), [seconds / 60])
        }
        return format(text(.secondsFormat, for: language), [seconds])
    }

    /// "Long break · 15 分钟" — the badge above the overlay headline.
    public static func breakTypeLabel(isLong: Bool, seconds: Int) -> String {
        let name = isLong ? t(.breakTypeLong) : t(.breakTypeShort)
        return "\(name) · \(duration(seconds: seconds))"
    }

    /// Shown instead of the static hint while the break overlay is up.
    public static var breakTips: [String] {
        StringTable.breakTips.map { isChinese ? $0.zh : $0.en }
    }

    /// A tip that differs from `current` so consecutive rotations never repeat.
    public static func randomBreakTip(excluding current: String? = nil) -> String {
        let all = breakTips
        let candidates = all.filter { $0 != current }
        return candidates.randomElement() ?? all.first ?? ""
    }
}
