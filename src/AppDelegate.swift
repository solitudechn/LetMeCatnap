import AppKit
import ServiceManagement
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var timerManager: TimerManager!
    private var statusBarTimer: Timer?
    private var menuIsOpen = false
    private var aboutWindow: NSWindow?

    // Menu items that need updating
    private var statusMenuItem: NSMenuItem!
    private var pauseResumeMenuItem: NSMenuItem!
    private var takeBreakNowMenuItem: NSMenuItem!
    private var restartMenuItem: NSMenuItem!
    private var workIntervalMenu: NSMenu!
    private var breakDurationMenu: NSMenu!
    private var pomodoroMenu: NSMenu!
    private var pauseDuringMeetingsMenuItem: NSMenuItem!
    private var allowSkipMenuItem: NSMenuItem!
    private var progressiveMenuItem: NSMenuItem!
    private var pauseWhenIdleMenuItem: NSMenuItem!
    private var muteSoundsMenuItem: NSMenuItem!
    private var hideMenuBarTimerMenuItem: NSMenuItem!
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
        timerManager = TimerManager()

        Log.info("App started")
        Log.info("Log file: \(Log.fileURL.path)")
        let ud = UserDefaults.standard
        Log.info("Config: work=\(timerManager.workDurationSeconds / 60)min, break=\(timerManager.breakDurationSeconds)s, pauseDuringMeetings=\(timerManager.pauseDuringMeetings), allowSkipBreak=\(ud.bool(forKey: SettingsKey.allowSkipBreak)), muteSounds=\(timerManager.muteSounds), pauseWhenIdle=\(timerManager.pauseWhenIdle), launchAtLogin=\(SMAppService.mainApp.status == .enabled)")
        Log.info("Rhythm: longBreakEvery=\(timerManager.longBreakEvery), longBreak=\(timerManager.longBreakSeconds)s, progressiveReminders=\(timerManager.progressiveReminders)")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "timer", accessibilityDescription: AppConstants.appName)
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        buildMenu()
        startStatusBarTimer()
        setupUpdateSystem()
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

        // Pause / Resume
        pauseResumeMenuItem = NSMenuItem(
            title: timerManager.state == .paused ? L10n.resumeTimer : L10n.pauseTimer,
            action: #selector(togglePause), keyEquivalent: "p"
        )
        pauseResumeMenuItem.target = self
        menu.addItem(pauseResumeMenuItem)

        takeBreakNowMenuItem = NSMenuItem(title: L10n.takeBreakNow, action: #selector(takeBreakNow), keyEquivalent: "b")
        takeBreakNowMenuItem.target = self
        menu.addItem(takeBreakNowMenuItem)

        restartMenuItem = NSMenuItem(title: L10n.restartTimer, action: #selector(restartTimer), keyEquivalent: "r")
        restartMenuItem.target = self
        menu.addItem(restartMenuItem)

        menu.addItem(.separator())

        // Work Interval submenu
        let workItem = NSMenuItem(title: L10n.workInterval, action: nil, keyEquivalent: "")
        workIntervalMenu = NSMenu()
        for minutes in workIntervalOptions {
            let item = NSMenuItem(title: L10n.minutes(minutes), action: #selector(setWorkInterval(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            workIntervalMenu.addItem(item)
        }
        workItem.submenu = workIntervalMenu
        menu.addItem(workItem)

        // Break Duration submenu
        let breakItem = NSMenuItem(title: L10n.breakDuration, action: nil, keyEquivalent: "")
        breakDurationMenu = NSMenu()
        for seconds in breakDurationOptions {
            let item = NSMenuItem(title: formatBreakDuration(seconds), action: #selector(setBreakDuration(_:)), keyEquivalent: "")
            item.target = self
            item.tag = seconds
            breakDurationMenu.addItem(item)
        }
        breakItem.submenu = breakDurationMenu
        menu.addItem(breakItem)

        // Pomodoro rhythm submenu — every N work sessions ends in a long break
        let pomodoroItem = NSMenuItem(title: L10n.pomodoroRhythm, action: nil, keyEquivalent: "")
        pomodoroMenu = NSMenu()
        for preset in pomodoroPresets {
            let title = preset.every == 0
                ? L10n.off
                : L10n.longBreakPreset(every: preset.every, minutes: preset.seconds / 60)
            let item = NSMenuItem(title: title, action: #selector(setPomodoroPreset(_:)), keyEquivalent: "")
            item.target = self
            item.tag = preset.every * 10000 + preset.seconds
            pomodoroMenu.addItem(item)
        }
        pomodoroItem.submenu = pomodoroMenu
        menu.addItem(pomodoroItem)

        menu.addItem(.separator())

        // Toggles
        pauseDuringMeetingsMenuItem = NSMenuItem(title: L10n.pauseDuringMeetings, action: #selector(toggleBoolSetting(_:)), keyEquivalent: "")
        pauseDuringMeetingsMenuItem.target = self
        pauseDuringMeetingsMenuItem.representedObject = SettingsKey.pauseDuringMeetings
        menu.addItem(pauseDuringMeetingsMenuItem)

        pauseWhenIdleMenuItem = NSMenuItem(title: L10n.pauseWhenIdle, action: #selector(toggleBoolSetting(_:)), keyEquivalent: "")
        pauseWhenIdleMenuItem.target = self
        pauseWhenIdleMenuItem.representedObject = SettingsKey.pauseWhenIdle
        menu.addItem(pauseWhenIdleMenuItem)

        allowSkipMenuItem = NSMenuItem(title: L10n.allowSkipBreak, action: #selector(toggleBoolSetting(_:)), keyEquivalent: "")
        allowSkipMenuItem.target = self
        allowSkipMenuItem.representedObject = SettingsKey.allowSkipBreak
        menu.addItem(allowSkipMenuItem)

        progressiveMenuItem = NSMenuItem(title: L10n.progressiveReminders, action: #selector(toggleBoolSetting(_:)), keyEquivalent: "")
        progressiveMenuItem.target = self
        progressiveMenuItem.representedObject = SettingsKey.progressiveReminders
        menu.addItem(progressiveMenuItem)

        muteSoundsMenuItem = NSMenuItem(title: L10n.muteSounds, action: #selector(toggleBoolSetting(_:)), keyEquivalent: "")
        muteSoundsMenuItem.target = self
        muteSoundsMenuItem.representedObject = SettingsKey.muteSounds
        menu.addItem(muteSoundsMenuItem)

        hideMenuBarTimerMenuItem = NSMenuItem(title: L10n.hideMenuBarTimer, action: #selector(toggleBoolSetting(_:)), keyEquivalent: "")
        hideMenuBarTimerMenuItem.target = self
        hideMenuBarTimerMenuItem.representedObject = SettingsKey.hideMenuBarTimer
        menu.addItem(hideMenuBarTimerMenuItem)

        menu.addItem(.separator())

        launchAtLoginMenuItem = NSMenuItem(title: L10n.launchAtLogin, action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginMenuItem.target = self
        menu.addItem(launchAtLoginMenuItem)

        // Language submenu
        let languageItem = NSMenuItem(title: L10n.languageLabel, action: nil, keyEquivalent: "")
        languageMenu = NSMenu()
        for lang in L10n.Language.allCases {
            let item = NSMenuItem(title: lang.displayName, action: #selector(setLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = lang.rawValue
            languageMenu.addItem(item)
        }
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: L10n.about(AppConstants.appName), action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: L10n.quit(AppConstants.appName), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
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
        }
    }

    private func updateStatusText() {
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
        let currentWork = UserDefaults.standard.integer(forKey: SettingsKey.workDurationMinutes)
        for item in workIntervalMenu.items {
            item.state = item.tag == currentWork ? .on : .off
        }

        // Break duration checkmarks
        let currentBreak = UserDefaults.standard.integer(forKey: SettingsKey.breakDurationSeconds)
        for item in breakDurationMenu.items {
            item.state = item.tag == currentBreak ? .on : .off
        }

        // Pomodoro rhythm checkmark — both values must match a preset
        let rhythmTag = UserDefaults.standard.integer(forKey: SettingsKey.longBreakEvery) * 10000
            + UserDefaults.standard.integer(forKey: SettingsKey.longBreakSeconds)
        for item in pomodoroMenu.items {
            item.state = item.tag == rhythmTag ? .on : .off
        }

        // Toggle states
        pauseDuringMeetingsMenuItem.state = UserDefaults.standard.bool(forKey: SettingsKey.pauseDuringMeetings) ? .on : .off
        pauseWhenIdleMenuItem.state = UserDefaults.standard.bool(forKey: SettingsKey.pauseWhenIdle) ? .on : .off
        allowSkipMenuItem.state = UserDefaults.standard.bool(forKey: SettingsKey.allowSkipBreak) ? .on : .off
        progressiveMenuItem.state = UserDefaults.standard.bool(forKey: SettingsKey.progressiveReminders) ? .on : .off
        muteSoundsMenuItem.state = UserDefaults.standard.bool(forKey: SettingsKey.muteSounds) ? .on : .off
        hideMenuBarTimerMenuItem.state = UserDefaults.standard.bool(forKey: SettingsKey.hideMenuBarTimer) ? .on : .off
        launchAtLoginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off

        // Language checkmarks
        let currentLang = L10n.preference.rawValue
        for item in languageMenu.items {
            if let raw = item.representedObject as? String {
                item.state = raw == currentLang ? .on : .off
            }
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
            case .idle: icon = "moon.zzz"
            default: icon = "pause.circle"
            }
        }

        statusItem.button?.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        if UserDefaults.standard.bool(forKey: SettingsKey.hideMenuBarTimer) {
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
        UserDefaults.standard.set(sender.tag, forKey: SettingsKey.workDurationMinutes)
        timerManager.workDurationSettingChanged()
    }

    @objc private func setBreakDuration(_ sender: NSMenuItem) {
        Log.info("Break duration changed to \(sender.tag)s")
        UserDefaults.standard.set(sender.tag, forKey: SettingsKey.breakDurationSeconds)
    }

    @objc private func setPomodoroPreset(_ sender: NSMenuItem) {
        let every = sender.tag / 10000
        let seconds = sender.tag % 10000
        UserDefaults.standard.set(every, forKey: SettingsKey.longBreakEvery)
        UserDefaults.standard.set(seconds, forKey: SettingsKey.longBreakSeconds)
        Log.info("Pomodoro rhythm: every=\(every), longBreak=\(seconds)s")
    }

    @objc private func toggleBoolSetting(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        let newValue = !UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(newValue, forKey: key)
        Log.info("Setting '\(key)' changed to \(newValue)")

        // Some toggles need to reconcile the current timer state, otherwise
        // disabling the feature while it's actively pausing the timer would
        // leave the timer stranded (the resume path lives inside the gated
        // periodic check).
        switch key {
        case SettingsKey.pauseDuringMeetings:
            timerManager.pauseDuringMeetingsSettingChanged(enabled: newValue)
        case SettingsKey.pauseWhenIdle:
            timerManager.pauseWhenIdleSettingChanged(enabled: newValue)
        default:
            break
        }
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
