import Foundation

/// Lightweight bilingual (English / Simplified Chinese) UI string table.
///
/// Strings live in code on purpose: the app bundle is assembled by `build.sh`,
/// which copies a fixed file list into `Contents/Resources`, so a `.lproj`
/// based `Localizable.strings` would need extra plumbing for very little gain.
/// Keeping everything here means the dev, dev-release and release builds all
/// behave identically.
///
/// Language resolution order:
///   1. explicit user choice from the "Language" menu (persisted in UserDefaults)
///   2. otherwise follow the system preferred language (`zh*` -> Chinese)
enum L10n {

    // MARK: - Language selection

    enum Language: String, CaseIterable {
        case system = "system"
        case english = "en"
        case chinese = "zh"

        /// Label shown in the Language menu.
        var displayName: String {
            switch self {
            case .system:  return L10n.t("System", "跟随系统")
            case .english: return "English"
            case .chinese: return "简体中文"
            }
        }
    }

    static let languageDefaultsKey = "uiLanguage"

    /// Explicit user preference. `.system` until the user picks a language.
    static var preference: Language {
        get {
            guard let raw = UserDefaults.standard.string(forKey: languageDefaultsKey),
                  let lang = Language(rawValue: raw) else { return .system }
            return lang
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: languageDefaultsKey)
        }
    }

    /// Language actually used to render strings right now.
    static var current: Language {
        switch preference {
        case .english: return .english
        case .chinese: return .chinese
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("zh") ? .chinese : .english
        }
    }

    static var isChinese: Bool { current == .chinese }

    /// Pick the localized variant of a pair of literals.
    static func t(_ en: String, _ zh: String) -> String {
        isChinese ? zh : en
    }
}

// MARK: - String table

extension L10n {

    // ── Menu bar ────────────────────────────────────────────────

    static var pauseTimer: String          { t("Pause Timer", "暂停计时") }
    static var resumeTimer: String         { t("Resume Timer", "继续计时") }
    static var restartTimer: String        { t("Restart Timer", "重新开始计时") }
    static var takeBreakNow: String        { t("Take a Break Now", "立即休息") }
    static var workInterval: String        { t("Work Interval", "工作时长") }
    static var breakDuration: String       { t("Break Duration", "休息时长") }
    static var pauseDuringMeetings: String { t("Pause During Meetings", "会议中自动暂停") }
    /// Submenu title: what makes the timer pause automatically.
    static var pauseTrigger: String        { t("Pause When", "暂停时机") }
    static var triggerLockScreen: String   { t("Screen Locks", "锁屏时") }
    static var triggerIdle: String         { t("Idle for 5 Minutes", "空闲 5 分钟时") }
    static var triggerBoth: String         { t("Screen Locks or Idle", "锁屏或空闲时") }
    static var triggerNever: String        { t("Never", "从不") }
    static var allowSkipBreak: String      { t("Allow Skip Break", "允许跳过休息") }
    static var muteSounds: String          { t("Mute Sounds", "静音") }
    static var hideMenuBarTimer: String    { t("Hide Timer in Menu Bar", "隐藏菜单栏倒计时") }
    static var launchAtLogin: String       { t("Launch at Login", "开机启动") }
    static var languageLabel: String     { t("Language", "语言") }
    static var timerSettings: String      { t("Timer", "计时") }
    static var reminderSettings: String   { t("Reminders", "提醒") }
    /// Shown once, in the menu, on the very first launch.
    static var welcome: String {
        t("Running in your menu bar — pick an action below",
          "已驻留在菜单栏，点下面的操作即可开始")
    }

    static func minutes(_ n: Int) -> String { t("\(n) min", "\(n) 分钟") }
    static func seconds(_ n: Int) -> String { t("\(n) sec", "\(n) 秒") }

    static func about(_ name: String) -> String { t("About \(name)", "关于 \(name)") }
    static func quit(_ name: String) -> String { t("Quit \(name)", "退出 \(name)") }

    // ── Menu bar countdown (TimerManager.menuBarText) ───────────

    static func breakCountdown(_ time: String) -> String { t("Break \(time)", "休息 \(time)") }
    static func meetingCountdown(_ time: String) -> String { t("Meeting \(time)", "会议 \(time)") }
    static func pausedCountdown(_ time: String) -> String { t("Paused \(time)", "已暂停 \(time)") }
    static var meetingInProgress: String { t("Meeting", "会议中") }
    static var inMeeting: String         { t("In meeting", "会议中") }
    static var locked: String            { t("Locked", "锁屏") }
    static func idleCountdown(_ time: String) -> String { t("Idle \(time)", "空闲 \(time)") }
    static var onBreak: String            { t("On a break", "休息中") }
    static func nextBreakIn(_ time: String) -> String {
        t("Next break in \(time)", "下次休息 \(time)")
    }

    // ── Status line (TimerManager.pauseStatusText) ──────────────

    static func pausedWith(_ reason: String) -> String { t("Paused — \(reason)", "已暂停 — \(reason)") }
    static var pausedInMeeting: String { t("Paused — Meeting", "已暂停 — 会议中") }
    static func breakPending(_ source: String) -> String { t("\(source) — Break pending", "\(source) — 待休息") }
    static var inMeetingBreakPending: String { t("In meeting — Break pending", "会议中 — 待休息") }
    static var pausedLocked: String { t("Paused — Screen locked", "已暂停 — 锁屏") }
    static var pausedIdle: String { t("Paused — Idle", "已暂停 — 空闲") }
    static var paused: String     { t("Paused", "已暂停") }

    // ── Meeting detection (MeetingDetector.meetingSource) ───────

    static var cameraInUse: String      { t("Camera in use", "摄像头使用中") }
    static var microphoneInUse: String  { t("Microphone in use", "麦克风使用中") }

    // ── Break overlays ──────────────────────────────────────────

    static var timeToRest: String {
        t("Time to Rest", "该休息了")
    }
    static var restHint: String {
        t("Look away from the screen, stretch, and re-pose",
          "把视线移开屏幕，伸个懒腰，重新调整姿势")
    }
    static var skip: String { t("Skip", "跳过") }
    /// Keyboard hint — key names are not translated.
    static var skipKeys: String { "Esc / ⌃Esc" }
    static var showRemaining: String { t("Tap the ring to see the time left", "点一下圆环可查看剩余时间") }

    // ── Break guidance ──────────────────────────────────────────

    /// Shown instead of the static hint while the break overlay is up.
    static var breakTips: [String] { isChinese ? zhBreakTips : enBreakTips }

    /// A tip that differs from `current` so consecutive rotations never repeat.
    static func randomBreakTip(excluding current: String? = nil) -> String {
        let all = breakTips
        let candidates = all.filter { $0 != current }
        return candidates.randomElement() ?? all.first ?? ""
    }

    static var breakSoon: String { t("Break in 1 minute", "1 分钟后休息") }
    /// Advisory only — the break can still be skipped with Esc.
    static var skipHint: String {
        t("Skipped a few times — this one is worth taking",
          "连跳几次了，这次休息一下会更好")
    }

    private static var enBreakTips: [String] {
        [
            "Look 20 feet away for 20 seconds",
            "Stand up and roll your shoulders",
            "Take three slow, deep breaths",
            "Drink a glass of water",
            "Blink slowly and let your eyes relax",
            "Look out of the window for a while",
            "Stretch your neck to both sides",
            "Unclench your jaw and soften your forehead",
            "Shake out your hands and wrists",
            "Walk a few steps",
        ]
    }

    private static var zhBreakTips: [String] {
        [
            "看向约 6 米（20 英尺）外，持续 20 秒",
            "站起来转一转肩膀",
            "慢慢深呼吸三次",
            "去喝一杯水",
            "缓慢眨眼，让眼睛放松",
            "看看窗外",
            "左右活动一下脖子",
            "松开下巴，舒展眉心",
            "甩甩手腕和手指",
            "起身走几步",
        ]
    }

    // ── Pomodoro rhythm ─────────────────────────────────────────

    static var pomodoroRhythm: String { t("Pomodoro Rhythm", "番茄节奏") }
    static var off: String            { t("Off", "关闭") }
    static var longBreakTitle: String { t("Time for a Longer Break", "该长休息了") }
    static var longBreakStarted: String { t("Long break", "长休息") }
    static func longBreakPreset(every: Int, minutes: Int) -> String {
        t("Every \(every) sessions · \(minutes) min", "每 \(every) 轮 · \(minutes) 分钟")
    }

    static var progressiveReminders: String { t("Progressive Reminders", "渐进式提醒") }


    // ── Update dialog ───────────────────────────────────────────

    static func newVersionFound(_ name: String) -> String {
        t("A new version of \(name) was found.", "发现 \(name) 的新版本。")
    }
    static var wantToUpdate: String     { t("Would you like to update?", "要现在更新吗？") }
    static var skipThisVersion: String  { t("Skip this version", "跳过此版本") }
    static var later: String            { t("Later", "稍后") }
    static var update: String           { t("Update", "更新") }
    static var softwareUpdate: String   { t("Software Update", "软件更新") }
    static var noChangelog: String      { t("No changelog available.", "暂无更新日志。") }

    // ── About window ────────────────────────────────────────────

    static var checkForUpdates: String      { t("check for updates", "检查更新") }
    static var checkingForUpdates: String   { t("checking for updates...", "正在检查更新…") }
    static var createdBy: String            { t("created by", "作者") }
    static var originalCodeBy: String       { t("original code by", "原作者") }
    static var iconsBy: String              { t("icons by", "图标来源") }
    static var alreadyLatestVersion: String { t("You have the latest available version!", "已经是最新版本！") }
    static var failedToCheckUpdates: String { t("Failed to check for updates", "检查更新失败") }
    static var updateFailed: String         { t("Update failed", "更新失败") }
    static var licenseUnavailable: String   { t("License text not available.", "许可证文本不可用。") }

    // ── Shared ──────────────────────────────────────────────────

    static var ok: String { t("OK", "好") }

    // ── Update errors (UpdateError.errorDescription) ────────────

    static var errInvalidGitHubResponse: String {
        t("GitHub returned an invalid response.", "GitHub 返回了无效响应。")
    }
    static var errInvalidDownloadedBundle: String {
        t("The downloaded update does not contain a valid app bundle.",
          "下载的更新包中没有有效的应用程序。")
    }
    static func errUnsafeArchiveEntry(_ entry: String) -> String {
        t("The downloaded archive contains an unsafe entry: \(entry)",
          "下载的压缩包包含不安全的条目：\(entry)")
    }
    static var errMissingCodeSigning: String {
        t("A bundle is missing required code-signing information.",
          "应用包缺少必要的代码签名信息。")
    }
    static var errMismatchedCodeSigning: String {
        t("The downloaded app was signed by a different identity.",
          "下载的应用由不同的签名身份签发。")
    }
    static func errProcessFailed(_ path: String, _ status: Int32) -> String {
        t("\(path) failed with status \(status)", "\(path) 执行失败，状态码 \(status)")
    }
}
