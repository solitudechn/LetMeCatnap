/// The bilingual string table.
///
/// Rules enforced by `StringTableTests` and `scripts/check-l10n.py`:
///   - every `LocKey` has an entry here;
///   - neither side is empty, the Chinese side contains Chinese, the English
///     side does not;
///   - both sides carry the same number of placeholders.
///
/// Keep the tables in the same order as `LocKey` so a diff is easy to read.
enum StringTable {
    static let table: [LocKey: Translation] = [
        // ── Menu bar ────────────────────────────────────────────────
        .systemLanguage: Translation("System", "跟随系统"),
        .pauseTimer: Translation("Pause Timer", "暂停计时"),
        .resumeTimer: Translation("Resume Timer", "继续计时"),
        .restartTimer: Translation("Restart Timer", "重新开始计时"),
        .takeBreakNow: Translation("Take a Break Now", "立即休息"),
        .workInterval: Translation("Work Interval", "工作时长"),
        .breakDuration: Translation("Break Duration", "休息时长"),
        // The switch does not pause the work countdown — a running session keeps
        // running. What it holds back is the break overlay itself.
        .pauseDuringMeetings: Translation("Hold Breaks in Meetings", "会议中不弹休息"),
        .pauseTrigger: Translation("Pause When", "暂停时机"),
        .triggerLockScreen: Translation("Screen Locks", "锁屏时"),
        .triggerIdle: Translation("Idle for 5 Minutes", "空闲 5 分钟时"),
        .triggerBoth: Translation("Screen Locks or Idle", "锁屏或空闲时"),
        .triggerNever: Translation("Never", "从不"),
        .showSkipButton: Translation("Show Skip Button", "显示跳过按钮"),
        .muteSounds: Translation("Mute Sounds", "静音"),
        .hideMenuBarTimer: Translation("Hide Timer in Menu Bar", "隐藏菜单栏倒计时"),
        .launchAtLogin: Translation("Launch at Login", "开机启动"),
        .languageLabel: Translation("Language", "语言"),
        .timerSettings: Translation("Timer", "计时"),
        .reminderSettings: Translation("Reminders", "提醒"),
        .welcome: Translation(
            "Running in your menu bar — pick an action below",
            "已驻留在菜单栏，点下面的操作即可开始"
        ),
        .minutesFormat: Translation("%ld min", "%ld 分钟"),
        .secondsFormat: Translation("%ld sec", "%ld 秒"),
        .aboutFormat: Translation("About %@", "关于 %@"),
        .quitFormat: Translation("Quit %@", "退出 %@"),
        .ok: Translation("OK", "好"),

        // ── Menu bar countdown ──────────────────────────────────────
        .breakCountdown: Translation("Break %@", "休息 %@"),
        .meetingCountdown: Translation("Meeting %@", "会议 %@"),
        .pausedCountdown: Translation("Paused %@", "已暂停 %@"),
        .meetingInProgress: Translation("Meeting", "会议中"),
        .inMeeting: Translation("In meeting", "会议中"),
        .locked: Translation("Locked", "锁屏"),
        .idleCountdown: Translation("Idle %@", "空闲 %@"),
        .onBreak: Translation("On a break", "休息中"),
        .nextBreakIn: Translation("Next break in %@", "下次休息 %@"),

        // ── Status line ─────────────────────────────────────────────
        .pausedWith: Translation("Paused — %@", "已暂停 — %@"),
        .pausedInMeeting: Translation("Paused — Meeting", "已暂停 — 会议中"),
        .breakPending: Translation("%@ — Break pending", "%@ — 待休息"),
        .inMeetingBreakPending: Translation("In meeting — Break pending", "会议中 — 待休息"),
        .pausedLocked: Translation("Paused — Screen locked", "已暂停 — 锁屏"),
        .pausedIdle: Translation("Paused — Idle", "已暂停 — 空闲"),
        .paused: Translation("Paused", "已暂停"),

        // ── Meeting detection ───────────────────────────────────────
        .cameraInUse: Translation("Camera in use", "摄像头使用中"),
        .microphoneInUse: Translation("Microphone in use", "麦克风使用中"),

        // ── Break overlay ───────────────────────────────────────────
        .timeToRest: Translation("Time to Rest", "该休息了"),
        .restHint: Translation(
            "Look away from the screen, stretch, and re-pose",
            "把视线移开屏幕，伸个懒腰，重新调整姿势"
        ),
        // Spoken by VoiceOver for the countdown ring, where the visual value is
        // a progress arc that a screen reader cannot describe.
        .timeRemaining: Translation("%@ remaining", "剩余 %@"),
        .skip: Translation("Skip", "跳过"),
        // Key names are not translated; both sides are identical on purpose.
        .skipKeys: Translation("Esc / ⌃Esc", "Esc / ⌃Esc"),
        // Shown when the on-screen skip button is hidden: Escape always works.
        .escapeToDismiss: Translation("Press Esc to dismiss", "按 Esc 退出"),
        .showRemaining: Translation("Tap the ring to see the time left", "点一下圆环可查看剩余时间"),
        // Advisory only — the break can still be skipped with Esc.
        .skipHint: Translation(
            "Skipped a few times — this one is worth taking",
            "连跳几次了，这次休息一下会更好"
        ),

        // ── Pomodoro rhythm ─────────────────────────────────────────
        .pomodoroRhythm: Translation("Pomodoro Rhythm", "番茄节奏"),
        .off: Translation("Off", "关闭"),
        .longBreakTitle: Translation("Time for a Longer Break", "该长休息了"),
        .longBreakPreset: Translation("Every %ld sessions · %ld min", "每 %ld 轮 · %ld 分钟"),
        .progressiveReminders: Translation("Progressive Reminders", "渐进式提醒"),

        // ── About window ────────────────────────────────────────────
        .checkForUpdates: Translation("check for updates", "检查更新"),
        .checkForUpdatesMenu: Translation("Check for Updates…", "检查更新…"),
        .createdBy: Translation("created by", "作者"),
        .originalCodeBy: Translation("original code by", "原作者"),
        .iconsBy: Translation("icons by", "图标来源"),
        .localizedBy: Translation("Chinese localization by", "简体中文汉化"),
        .licenseUnavailable: Translation("License text not available.", "许可证文本不可用。"),
    ]

    /// Rotated one per break. Same order in both arrays.
    static let breakTips: [(en: String, zh: String)] = [
        ("Look 20 feet away for 20 seconds", "看向约 6 米（20 英尺）外，持续 20 秒"),
        ("Stand up and roll your shoulders", "站起来转一转肩膀"),
        ("Take three slow, deep breaths", "慢慢深呼吸三次"),
        ("Drink a glass of water", "去喝一杯水"),
        ("Blink slowly and let your eyes relax", "缓慢眨眼，让眼睛放松"),
        ("Look out of the window for a while", "看看窗外"),
        ("Stretch your neck to both sides", "左右活动一下脖子"),
        ("Unclench your jaw and soften your forehead", "松开下巴，舒展眉心"),
        ("Shake out your hands and wrists", "甩甩手腕和手指"),
        ("Walk a few steps", "起身走几步"),
    ]
}
