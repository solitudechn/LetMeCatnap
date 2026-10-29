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
        // Badge above the headline. The two breaks looked identical apart from
        // a word in the title, which is easy to misread half awake.
        .breakTypeShort: Translation("Short break", "短休息"),
        .breakTypeLong: Translation("Long break", "长休息"),

        // ── Pomodoro rhythm ─────────────────────────────────────────
        .pomodoroRhythm: Translation("Pomodoro Rhythm", "番茄节奏"),
        .off: Translation("Off", "关闭"),
        .longBreakTitle: Translation("Time for a Longer Break", "该长休息了"),
        .longBreakPreset: Translation("Every %ld sessions · %ld min", "每 %ld 轮 · %ld 分钟"),
        .progressiveReminders: Translation("Progressive Reminders", "渐进式提醒"),

        // ── About window ────────────────────────────────────────────
        .checkForUpdates: Translation("check for updates", "检查更新"),
        .checkForUpdatesMenu: Translation("Check for Updates…", "检查更新…"),
        .createdBy: Translation("Author", "作者"),
        .upstreamBy: Translation("Upstream author", "上游作者"),
        .originalCodeBy: Translation("Original code", "原始代码"),
        // The app icon is the artwork this project ships; the boxicons line
        // below covers the small glyphs inside the UI, and saying just "Icons"
        // read as if the app icon were boxicons' work too.
        .appIconBy: Translation("App icon", "应用图标"),
        .appIconCredit: Translation("solitudechn (AI-generated)", "solitudechn（AI 生成）"),
        .iconsBy: Translation("Interface icons", "界面图标"),
        .licenseUnavailable: Translation("License text not available.", "许可证文本不可用。"),

        // ── Main menu (only visible while the About window is open) ──
        .menuEdit: Translation("Edit", "编辑"),
        .menuWindow: Translation("Window", "窗口"),
        .hideAppFormat: Translation("Hide %@", "隐藏 %@"),
        .hideOthers: Translation("Hide Others", "隐藏其他"),
        .showAll: Translation("Show All", "显示全部"),
        .undo: Translation("Undo", "撤销"),
        .redo: Translation("Redo", "重做"),
        .cut: Translation("Cut", "剪切"),
        .copy: Translation("Copy", "拷贝"),
        .paste: Translation("Paste", "粘贴"),
        .selectAll: Translation("Select All", "全选"),
        .minimize: Translation("Minimize", "最小化"),
        .close: Translation("Close", "关闭"),
    ]

    /// Rotated one per break. Same order in both arrays.
    ///
    /// Written as things a physiotherapist or optometrist would actually say,
    /// and kept to advice that holds up: no detox, no posture myths, and
    /// nothing that claims to prevent a disease. The 20-second eye rule, chin
    /// tucks, scapular squeezes and the warning against neck cracking are all
    /// standard; the phrasing stays descriptive ("eases the load") rather than
    /// promising an outcome.
    static let breakTips: [(en: String, zh: String)] = [
        ("Look 20 feet away for 20 seconds", "看向 6 米外，持续 20 秒"),
        (
            "Chin tuck: slide your chin straight back, hold 5 seconds, repeat 5 times",
            "收下巴：下巴水平后移做出双下巴，保持 5 秒，重复 5 次"
        ),
        (
            "Squeeze your shoulder blades together, hold 5 seconds, release",
            "两侧肩胛骨往中间夹，保持 5 秒再放松"
        ),
        ("Roll your shoulders back and down, five times", "肩膀向后向下绕环，做 5 次"),
        (
            "Don't crack your neck — that sound is joint gas, not a tight muscle letting go",
            "别掰脖子听响——那是关节里的气体，不是肌肉松开了"
        ),
        (
            "Turn your head slowly left and right, stopping before it hurts",
            "慢慢左右转头，到不舒服之前就停"
        ),
        ("Stand up and walk to the window", "站起来走到窗边"),
        (
            "Stand and do 10 heel raises to get the blood moving",
            "站起来做 10 次提踵，帮血液回流"
        ),
        (
            "Stretch your forearms: extend an arm, pull the fingers down, 15 seconds a side",
            "前臂拉伸：伸直手臂，另一只手把手指往下压，每侧 15 秒"
        ),
        ("Open your chest in a doorway for 20 seconds", "站在门框里打开胸口，保持 20 秒"),
        (
            "Unclench your hands: open and close your fists 10 times",
            "松开拳头，握紧再张开，做 10 次"
        ),
        (
            "Shrug your shoulders to your ears, hold 3 seconds, then drop them",
            "耸肩到耳朵，停 3 秒，然后一下放下来"
        ),
        ("Breathe in for 4 seconds, out for 6, five times", "吸气 4 秒、呼气 6 秒，重复 5 次"),
        (
            "Let your jaw hang loose, tongue resting behind your lower teeth",
            "松开牙关，舌尖轻抵下牙后方"
        ),
        (
            "Close your eyes for 20 seconds and let the tear film spread again",
            "闭眼 20 秒，让泪膜重新铺满眼球"
        ),
        (
            "Blink fully a few times — screen work cuts your blink rate roughly in half",
            "完整地眨几次眼——盯着屏幕时眨眼频率大约减半"
        ),
        (
            "Stand, hands on your lower back, lean back gently for 5 seconds",
            "站起来手扶后腰，轻轻后仰 5 秒"
        ),
        (
            "Screen an arm's length away, top edge level with your eyes",
            "屏幕放在一臂远，上沿与视线齐平"
        ),
        ("Keep your feet flat and stop crossing your legs", "双脚踩平，别跷二郎腿"),
        ("Drink a glass of water", "去喝一杯水"),
        (
            "Look out of the window until your eyes stop straining",
            "看看窗外，直到眼睛不再发紧"
        ),
        (
            "Stand up for a moment — sitting is what stiffens hips and lower back",
            "起身站一会儿——久坐才是髋和腰发僵的原因"
        ),
    ]
}
