import AppKit
import ServiceManagement
import SwiftUI
import ICHRCore

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var timerManager: TimerManager!
    private var statusBarTimer: Timer?
    private var menuIsOpen = false
    private var aboutWindow: NSWindow?
    private let settings = Settings.shared
    /// First-run guidance is shown inside the menu itself, so the app never
    /// throws a window at someone who just installed it.
    private var showsWelcome = false

    /// Boolean preferences, encoded as menu tags so one action can toggle them.
    private enum BoolSetting: Int, CaseIterable {
        case pauseDuringMeetings
        case allowSkipBreak
        case progressiveReminders
        case muteSounds
        case hideMenuBarTimer

        var title: String {
            switch self {
            case .pauseDuringMeetings: return L10n.pauseDuringMeetings
            case .allowSkipBreak: return L10n.allowSkipBreak
            case .progressiveReminders: return L10n.progressiveReminders
            case .muteSounds: return L10n.muteSounds
            case .hideMenuBarTimer: return L10n.hideMenuBarTimer
            }
        }
    }

    // Menu items that need updating
    private var statusMenuItem: NSMenuItem!
    private var pauseResumeMenuItem: NSMenuItem!
    private var takeBreakNowMenuItem: NSMenuItem!
    private var restartMenuItem: NSMenuItem!
    private var workIntervalMenu: NSMenu!
    private var breakDurationMenu: NSMenu!
    private var pomodoroMenu: NSMenu!
    private var pauseTriggerMenu: NSMenu!
    private var boolSettingItems: [NSMenuItem] = []
    private var launchAtLoginMenuItem: NSMenuItem!
    private var languageMenu: NSMenu!

    #if DEBUG
    private let workIntervalOptions = [1, 5, 10, 15, 20, 25, 30, 45, 60, 90]
    private let breakDurationOptions = [10, 20, 30, 60, 120, 300, 600]
    #else
    private let workIntervalOptions = [5, 10, 15, 20, 25, 30, 45, 60, 90]
    private let breakDurationOptions = [20, 30, 60, 120, 300, 600]
    #endif

    /// `every == 0` turns the rhythm off. Encoded into the menu item tag as
    /// `every * 10_000 + seconds` so one checkmark can match both values.
    private let pomodoroPresets: [(every: Int, seconds: Int)] = [
        (0, 0),
        (2, 600),
        (3, 900),
        (4, 900),
        (4, 1500),
        (5, 1800),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        timerManager = TimerManager(settings: settings)

        Log.info("App started")
        Log.info("Log file: \(Log.fileURL.path)")
        Log.info("Config: work=\(settings.workMinutes)min, break=\(settings.breakSeconds)s, pauseDuringMeetings=\(settings.pauseDuringMeetings), pauseTrigger=\(settings.pauseTrigger), allowSkipBreak=\(settings.allowSkipBreak), muteSounds=\(settings.muteSounds), launchAtLogin=\(SMAppService.mainApp.status == .enabled)")
        Log.info("Rhythm: longBreakEvery=\(settings.longBreakEvery), longBreak=\(settings.longBreakSeconds)s, progressiveReminders=\(settings.progressiveReminders)")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "timer", accessibilityDescription: AppConstants.appName)
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        showsWelcome = !settings.hasCompletedWelcome
        buildMenu()
        startStatusBarTimer()
        setupUpdateSystem()

        // On the very first launch, open the menu once so the window-less app
        // announces itself. Everything else stays where every other menu bar
        // app puts it — no extra windows, no dialogs.
        if showsWelcome {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.statusItem.button?.performClick(nil)
            }
        }
    }

    // MARK: - Menu Construction

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // Status line (disabled, just for display)
        statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        // ── Actions: the only items pressed daily ──
        pauseResumeMenuItem = NSMenuItem(
            title: timerManager.state == .paused ? L10n.resumeTimer : L10n.pauseTimer,
            action: #selector(togglePause), keyEquivalent: "p"
        )
        pauseResumeMenuItem.target = self
        menu.addItem(pauseResumeMenuItem)

        takeBreakNowMenuItem = NSMenuItem(
            title: L10n.takeBreakNow,
            action: #selector(takeBreakNow),
            keyEquivalent: "b"
        )
        takeBreakNowMenuItem.target = self
        menu.addItem(takeBreakNowMenuItem)

        restartMenuItem = NSMenuItem(
            title: L10n.restartTimer,
            action: #selector(restartTimer),
            keyEquivalent: "r"
        )
        restartMenuItem.target = self
        menu.addItem(restartMenuItem)

        menu.addItem(.separator())

        // ── Timer settings ──
        let timerItem = NSMenuItem(title: L10n.timerSettings, action: nil, keyEquivalent: "")
        let timerMenu = NSMenu()
        timerMenu.addItem(makeWorkIntervalItem())
        timerMenu.addItem(makeBreakDurationItem())
        timerMenu.addItem(makePomodoroItem())
        timerItem.submenu = timerMenu
        menu.addItem(timerItem)

        // ── Reminder settings ──
        let reminderItem = NSMenuItem(title: L10n.reminderSettings, action: nil, keyEquivalent: "")
        let reminderMenu = NSMenu()
        boolSettingItems = []
        reminderMenu.addItem(makePauseTriggerItem())
        reminderMenu.addItem(.separator())
        for setting in BoolSetting.allCases {
            let item = NSMenuItem(
                title: setting.title,
                action: #selector(toggleBoolSetting(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = setting.rawValue
            boolSettingItems.append(item)
            reminderMenu.addItem(item)
        }
        reminderItem.submenu = reminderMenu
        menu.addItem(reminderItem)

        menu.addItem(.separator())

        launchAtLoginMenuItem = NSMenuItem(
            title: L10n.launchAtLogin,
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginMenuItem.target = self
        menu.addItem(launchAtLoginMenuItem)

        // Language submenu
        let languageItem = NSMenuItem(title: L10n.languageLabel, action: nil, keyEquivalent: "")
        languageMenu = NSMenu()
        for lang in L10n.Language.allCases {
            let item = NSMenuItem(
                title: lang.displayName,
                action: #selector(setLanguage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = lang.rawValue
            languageMenu.addItem(item)
        }
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(
            title: L10n.about(AppConstants.appName),
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(
            title: L10n.quit(AppConstants.appName),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Settings submenus

    /// Radio group: what counts as "the user left the desk".
    private func makePauseTriggerItem() -> NSMenuItem {
        let item = NSMenuItem(title: L10n.pauseTrigger, action: nil, keyEquivalent: "")
        pauseTriggerMenu = NSMenu()
        for trigger in PauseTrigger.allCases {
            let option = NSMenuItem(
                title: title(for: trigger),
                action: #selector(setPauseTrigger(_:)),
                keyEquivalent: ""
            )
            option.target = self
            option.tag = trigger.rawValue
            pauseTriggerMenu.addItem(option)
        }
        item.submenu = pauseTriggerMenu
        return item
    }

    private func title(for trigger: PauseTrigger) -> String {
        switch trigger {
        case .lockScreen: return L10n.triggerLockScreen
        case .idle: return L10n.triggerIdle
        case .lockScreenOrIdle: return L10n.triggerBoth
        case .never: return L10n.triggerNever
        }
    }

    private func makeWorkIntervalItem() -> NSMenuItem {
        let item = NSMenuItem(title: L10n.workInterval, action: nil, keyEquivalent: "")
        workIntervalMenu = NSMenu()
        for minutes in workIntervalOptions {
            let option = NSMenuItem(
                title: L10n.minutes(minutes),
                action: #selector(setWorkInterval(_:)),
                keyEquivalent: ""
            )
            option.target = self
            option.tag = minutes
            workIntervalMenu.addItem(option)
        }
        item.submenu = workIntervalMenu
        return item
    }

    private func makeBreakDurationItem() -> NSMenuItem {
        let item = NSMenuItem(title: L10n.breakDuration, action: nil, keyEquivalent: "")
        breakDurationMenu = NSMenu()
        for seconds in breakDurationOptions {
            let option = NSMenuItem(
                title: formatBreakDuration(seconds),
                action: #selector(setBreakDuration(_:)),
                keyEquivalent: ""
            )
            option.target = self
            option.tag = seconds
            breakDurationMenu.addItem(option)
        }
        item.submenu = breakDurationMenu
        return item
    }

    private func makePomodoroItem() -> NSMenuItem {
        let item = NSMenuItem(title: L10n.pomodoroRhythm, action: nil, keyEquivalent: "")
        pomodoroMenu = NSMenu()
        for preset in pomodoroPresets {
            let title = preset.every == 0
                ? L10n.off
                : L10n.longBreakPreset(every: preset.every, minutes: preset.seconds / 60)
            let option = NSMenuItem(
                title: title,
                action: #selector(setPomodoroPreset(_:)),
                keyEquivalent: ""
            )
            option.target = self
            option.tag = preset.every * 10_000 + preset.seconds
            pomodoroMenu.addItem(option)
        }
        item.submenu = pomodoroMenu
        return item
    }

    // MARK: - NSMenuDelegate — update items right before the menu opens

    nonisolated func menuWillOpen(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            menuIsOpen = true
            updateMenuItems()
        }
    }

    nonisolated func menuDidClose(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            menuIsOpen = false
            // The first open doubles as onboarding; dismiss it for good.
            if showsWelcome {
                showsWelcome = false
                settings.markWelcomeCompleted()
            }
        }
    }

    private func updateStatusText() {
        if showsWelcome {
            statusMenuItem.title = L10n.welcome
            return
        }
        switch timerManager.state {
        case .working:
            if timerManager.isInMeeting {
                statusMenuItem.title = L10n.inMeeting
            } else {
                statusMenuItem.title = L10n.nextBreakIn(formatTime(timerManager.remainingSeconds))
            }
        case .onBreak:
            statusMenuItem.title = L10n.onBreak
        case .paused:
            statusMenuItem.title = timerManager.pauseStatusText ?? L10n.paused
        }
    }

    private func updateMenuItems() {
        updateStatusText()

        // Pause / Resume
        switch timerManager.state {
        case .working:
            pauseResumeMenuItem.title = L10n.pauseTimer
            pauseResumeMenuItem.isEnabled = true
            pauseResumeMenuItem.isHidden = false
        case .paused:
            pauseResumeMenuItem.title = L10n.resumeTimer
            pauseResumeMenuItem.isEnabled = timerManager.currentPauseReason != .meeting && timerManager.currentPauseReason != .breakPending
            pauseResumeMenuItem.isHidden = false
        default:
            pauseResumeMenuItem.isHidden = true
        }
        takeBreakNowMenuItem.isEnabled = timerManager.state != .onBreak
        restartMenuItem.isEnabled = timerManager.state != .onBreak

        // Work interval checkmarks
        for item in workIntervalMenu.items {
            item.state = item.tag == settings.workMinutes ? .on : .off
        }

        // Break duration checkmarks
        for item in breakDurationMenu.items {
            item.state = item.tag == settings.breakSeconds ? .on : .off
        }

        // Pomodoro rhythm checkmark — both values must match a preset
        let rhythmTag = settings.longBreakEvery * 10_000 + settings.longBreakSeconds
        for item in pomodoroMenu.items {
            item.state = item.tag == rhythmTag ? .on : .off
        }

        // Pause trigger radio group
        for item in pauseTriggerMenu.items {
            item.state = item.tag == settings.pauseTrigger.rawValue ? .on : .off
        }

        // Boolean settings
        for item in boolSettingItems {
            guard let setting = BoolSetting(rawValue: item.tag) else { continue }
            item.state = boolValue(for: setting) ? .on : .off
        }
        launchAtLoginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off

        // Language checkmarks
        let currentLang = L10n.preference.rawValue
        for item in languageMenu.items {
            if let raw = item.representedObject as? String {
                item.state = raw == currentLang ? .on : .off
            }
        }
    }

    private func boolValue(for setting: BoolSetting) -> Bool {
        switch setting {
        case .pauseDuringMeetings: return settings.pauseDuringMeetings
        case .allowSkipBreak: return settings.allowSkipBreak
        case .progressiveReminders: return settings.progressiveReminders
        case .muteSounds: return settings.muteSounds
        case .hideMenuBarTimer: return settings.hideMenuBarTimer
        }
    }

    private func setBool(_ value: Bool, for setting: BoolSetting) {
        switch setting {
        case .pauseDuringMeetings:
            settings.setPauseDuringMeetings(value)
            timerManager.pauseDuringMeetingsSettingChanged(enabled: value)
        case .allowSkipBreak:
            settings.setAllowSkipBreak(value)
        case .progressiveReminders:
            settings.setProgressiveReminders(value)
        case .muteSounds:
            settings.setMuteSounds(value)
        case .hideMenuBarTimer:
            settings.setHideMenuBarTimer(value)
        }
    }

    // MARK: - Status bar title updates

    private func startStatusBarTimer() {
        updateStatusBarTitle()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.updateStatusBarTitle()
                if self.menuIsOpen {
                    self.updateStatusText()
                }
            }
        }
        // .common includes both default and eventTracking modes,
        // so updates work even while the menu is open.
        RunLoop.main.add(timer, forMode: .common)
        statusBarTimer = timer
    }

    private func updateStatusBarTitle() {
        let icon: String
        switch timerManager.state {
        case .working:
            if timerManager.isInMeeting {
                icon = "video.fill"
            } else if timerManager.isBreakImminent {
                // One minute left — progressive reminder.
                icon = "hourglass"
            } else {
                icon = "timer"
            }
        case .onBreak: icon = "cup.and.saucer.fill"
        case .paused:
            switch timerManager.currentPauseReason {
            case .meeting, .breakPending: icon = "video.fill"
            case .locked: icon = "lock.fill"
            case .idle: icon = "moon.zzz"
            default: icon = "pause.circle"
            }
        }

        statusItem.button?.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        if settings.hideMenuBarTimer {
            statusItem.button?.title = ""
        } else {
            statusItem.button?.title = " \(timerManager.menuBarText)"
        }
    }

    // MARK: - Actions

    @objc private func togglePause() {
        timerManager.togglePause()
    }

    @objc private func restartTimer() {
        Log.info("Timer restarted by user")
        timerManager.start()
    }

    @objc private func takeBreakNow() {
        timerManager.startBreakNow()
    }

    @objc private func setWorkInterval(_ sender: NSMenuItem) {
        Log.info("Work interval changed to \(sender.tag) min")
        settings.setWorkMinutes(sender.tag)
        timerManager.workDurationSettingChanged()
    }

    @objc private func setBreakDuration(_ sender: NSMenuItem) {
        Log.info("Break duration changed to \(sender.tag)s")
        settings.setBreakSeconds(sender.tag)
    }

    @objc private func setPomodoroPreset(_ sender: NSMenuItem) {
        let every = sender.tag / 10_000
        let seconds = sender.tag % 10_000
        settings.setLongBreak(every: every, seconds: seconds)
        Log.info("Pomodoro rhythm: every=\(every), longBreak=\(seconds)s")
    }

    @objc private func setPauseTrigger(_ sender: NSMenuItem) {
        guard let trigger = PauseTrigger(rawValue: sender.tag) else { return }
        settings.setPauseTrigger(trigger)
        timerManager.pauseTriggerSettingChanged(trigger)
        Log.info("Pause trigger changed to \(trigger)")
    }

    @objc private func toggleBoolSetting(_ sender: NSMenuItem) {
        guard let setting = BoolSetting(rawValue: sender.tag) else { return }
        let newValue = !boolValue(for: setting)
        setBool(newValue, for: setting)
        Log.info("Setting '\(setting)' changed to \(newValue)")
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let lang = L10n.Language(rawValue: raw) else { return }
        L10n.preference = lang
        Log.info("UI language changed to \(lang.rawValue)")
        // Rebuilding the menu swaps `statusItem.menu` while that very menu is
        // still being tracked by AppKit (this action fires from inside it), so
        // defer to the next run loop iteration and let it close first.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.buildMenu()
            self.updateMenuItems()
            // The About window builds its labels once, from L10n — repaint it
            // if it happens to be on screen while the language changes.
            if let window = self.aboutWindow, window.isVisible {
                window.title = L10n.about(AppConstants.appName)
                (window.contentViewController as? AboutViewController)?.reloadForLanguageChange()
            }
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let currentlyEnabled = SMAppService.mainApp.status == .enabled
        let newStatus = !currentlyEnabled
        try? currentlyEnabled ? SMAppService.mainApp.unregister() : SMAppService.mainApp.register()
        Log.info("Launch at login changed to \(newStatus)")
    }

    @objc private func showAbout() {
        // If already open, just bring to front
        if let existingWindow = aboutWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let aboutVC = AboutViewController()

        let window = NSWindow(contentViewController: aboutVC)
        window.styleMask = [.titled, .closable, .resizable]
        window.title = L10n.about(AppConstants.appName)
        window.setContentSize(NSSize(width: 700, height: 520))
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self

        // Switch from accessory to regular mode so the window appears in the Dock
        NSApp.setActivationPolicy(.regular)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        aboutWindow = window
    }

    // MARK: - Update System

    private func setupUpdateSystem() {
        let manager = UpdateManager.shared

        manager.onAutomaticUpdateFound = { [weak self] updateInfo in
            self?.presentUpdateDialog(for: updateInfo)
        }

        manager.startPeriodicChecks()
    }

    private func presentUpdateDialog(for updateInfo: UpdateInfo) {
        let vc = UpdateDialogViewController(
            updateInfo: updateInfo,
            onUpdate: {
                Task {
                    do {
                        try await UpdateManager.shared.downloadAndInstall(updateInfo)
                    } catch {
                        let alert = NSAlert()
                        alert.messageText = L10n.updateFailed
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = .critical
                        alert.addButton(withTitle: L10n.ok)
                        alert.runModal()
                    }
                }
            },
            onSkip: {
                UpdateManager.shared.skippedVersion = updateInfo.version
            }
        )

        let window = NSWindow(contentViewController: vc)
        window.styleMask = [.titled, .closable]
        window.title = L10n.softwareUpdate

        // Present as a sheet on the key window, or as a regular window if none
        if let keyWindow = NSApp.keyWindow {
            keyWindow.beginSheet(window) { _ in }
        } else {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == aboutWindow else { return }
        aboutWindow = nil
        // Return to accessory mode when the about window is closed
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func quitApp() {
        Log.info("App quitting")
        NSApplication.shared.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.info("App terminated")
        Log.flush()
    }

    // MARK: - Helpers

    private func formatBreakDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return L10n.seconds(seconds)
        } else {
            return L10n.minutes(seconds / 60)
        }
    }
}
