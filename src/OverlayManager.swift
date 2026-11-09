import AppKit
import Carbon
import CatnapCore
import SwiftUI

private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
class OverlayManager {
    private var overlayWindows: [NSPanel] = []
    private var compactPanel: NSPanel?
    private var isCompactMode: Bool = false
    /// A break that is currently on screen, so the panels can be rebuilt when
    /// the display set changes underneath them.
    private weak var presentedTimerManager: TimerManager?
    private var isPresentingBreak = false
    private var screenObservers: [NSObjectProtocol] = []
    /// What the current panels were built for (display id + wake state + frame).
    private var lastLayoutSignature: [String] = []
    private var relayoutScheduled = false

    init() {
        // A lid closing can emit a display-sleep notification, a display
        // reconfiguration, or both, in either order — and sometimes before
        // `NSScreen.screens` has been updated. Listen to all of them, then
        // check the actual screen set once things have settled.
        let handleChange: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleRelayout()
            }
        }
        let appCenter = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        screenObservers = [
            appCenter.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main,
                using: handleChange
            ),
            workspaceCenter.addObserver(
                forName: NSWorkspace.screensDidSleepNotification,
                object: nil,
                queue: .main,
                using: handleChange
            ),
            workspaceCenter.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: .main,
                using: handleChange
            ),
        ]
    }

    deinit {
        for observer in screenObservers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    // Carbon global hotkey refs for escape (used by both full and compact overlays)
    private var escapeHotKeyRef: EventHotKeyRef?
    private var ctrlEscapeHotKeyRef: EventHotKeyRef?
    private var escapeEventHandlerRef: EventHandlerRef?
    private var escapeHandlerContext: UnsafeMutableRawPointer?

    // MARK: - Full overlay (all screens)

    /// The screen the break content is drawn on.
    ///
    /// `NSScreen.main` is the screen that holds the keyboard focus. A menu bar
    /// app has no window of its own, so that value can be `nil` — the frontmost
    /// app may have no key window either. It used to be used directly, and with
    /// `nil` *no* panel was flagged as primary, which meant the overlay showed
    /// as a black screen with no message and no countdown on it. Falling back
    /// to the first screen keeps the promise that a break always says
    /// something.
    ///
    /// It can also go stale: after a lid closes, `main` may still name the
    /// built-in panel that is no longer in the display set. Only believe it
    /// while that screen is both present and awake, otherwise the one panel
    /// carrying the text is the one nobody can see.
    private static func isActive(_ screen: NSScreen) -> Bool {
        guard
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? CGDirectDisplayID
        else { return true }
        return CGDisplayIsActive(id) != 0
    }

    private static var primaryScreen: NSScreen? {
        let screens = NSScreen.screens
        let awake = screens.filter(isActive)
        let candidates = awake.isEmpty ? screens : awake
        guard !candidates.isEmpty else { return nil }
        // Return an object from `screens`: the caller compares with `==`, and
        // AppKit can hand out a freshly wrapped `NSScreen.main` during a
        // reconfiguration. Matching by frame survives that object churn.
        if let main = NSScreen.main,
            let match = candidates.first(where: { $0.frame == main.frame })
        {
            return match
        }
        return candidates.first
    }

    func showBreakOverlay(timerManager: TimerManager) {
        dismissOverlay()

        let primary = OverlayManager.primaryScreen
        for screen in NSScreen.screens {
            let isPrimary = screen == primary
            let view = BreakOverlayView(timerManager: timerManager, isPrimary: isPrimary)

            let panel = KeyablePanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.contentView = NSHostingView(rootView: view)

            if isPrimary {
                panel.makeKeyAndOrderFront(nil)
            } else {
                panel.orderFrontRegardless()
            }
            overlayWindows.append(panel)
        }

        isCompactMode = false
        isPresentingBreak = true
        presentedTimerManager = timerManager
        lastLayoutSignature = Self.screenSignature()
        installKeyMonitor(timerManager: timerManager)
    }

    // MARK: - Compact overlay (single centered panel for fullscreen apps)

    func showCompactBreakOverlay(timerManager: TimerManager) {
        dismissOverlay()

        // Keep the break marked as presented even if no screen is available
        // right now — a display may come back a moment after a lid opens.
        isPresentingBreak = true
        presentedTimerManager = timerManager
        guard let screen = OverlayManager.primaryScreen else {
            // Keep the chosen mode, so the rebuild when a display returns uses
            // the compact panel rather than silently switching to full screen.
            isCompactMode = true
            lastLayoutSignature = Self.screenSignature()
            return
        }

        let panelWidth: CGFloat = 360
        let panelHeight: CGFloat = 420
        let cornerRadius: CGFloat = 24
        let panelX = screen.frame.midX - panelWidth / 2
        let panelY = screen.frame.midY - panelHeight / 2
        let panelRect = NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)

        let panel = NSPanel(
            contentRect: panelRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true

        // The blur material must be the window's root view for the mask to
        // clip it. Nested inside an NSHostingView (or clipped by SwiftUI),
        // the backdrop layer drawn by the window server stays rectangular.
        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = cornerRadius
        effectView.layer?.masksToBounds = true
        effectView.maskImage = Self.roundedMaskImage(size: panelRect.size, cornerRadius: cornerRadius)

        let hostingView = NSHostingView(
            rootView: CompactBreakOverlayView(timerManager: timerManager)
        )
        hostingView.frame = effectView.bounds
        hostingView.autoresizingMask = [.width, .height]
        effectView.addSubview(hostingView)

        panel.contentView = effectView

        panel.orderFrontRegardless()
        compactPanel = panel
        isCompactMode = true
        lastLayoutSignature = Self.screenSignature()
        installKeyMonitor(timerManager: timerManager)
    }

    // MARK: - Dismiss

    func dismissWithAnimation(completion: @escaping () -> Void = {}) {
        // The break is over; a display change during the fade-out must not
        // bring the panels back.
        isPresentingBreak = false
        let windows = isCompactMode ? (compactPanel.map { [$0] } ?? []) : overlayWindows
        for window in windows {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                window.animator().alphaValue = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.dismissOverlay()
            completion()
        }
    }

    func dismissOverlay() {
        uninstallKeyMonitor()
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        compactPanel?.orderOut(nil)
        compactPanel = nil
        isCompactMode = false
        isPresentingBreak = false
        presentedTimerManager = nil
    }

    /// Frames alone miss a display that stays in `NSScreen.screens` but falls
    /// asleep (a closed lid), so the id and wake state are part of it too.
    private static func screenSignature() -> [String] {
        NSScreen.screens.map { screen in
            let id =
                screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? CGDirectDisplayID ?? 0
            return "\(id)-\(isActive(screen))-\(NSStringFromRect(screen.frame))"
        }
    }

    private func scheduleRelayout() {
        guard isPresentingBreak, !relayoutScheduled else { return }
        relayoutScheduled = true
        // AppKit may still be reporting the old display set when the first
        // notification arrives. One short wait, then compare against what the
        // panels were built for — several notifications collapse into one
        // rebuild.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.relayoutScheduled = false
            self?.relayoutForScreenChange()
        }
    }

    /// Panels are built for a fixed screen frame, and exactly one of them draws
    /// the message and countdown. If that screen is the laptop lid that just
    /// closed, the remaining screens would show a black panel with nothing on
    /// it for the rest of the break. Rebuilding puts the content back on a
    /// display that is actually lit.
    private func relayoutForScreenChange() {
        guard isPresentingBreak, let timerManager = presentedTimerManager else { return }
        guard Self.screenSignature() != lastLayoutSignature else { return }
        let wasCompact = isCompactMode
        if wasCompact {
            showCompactBreakOverlay(timerManager: timerManager)
        } else {
            showBreakOverlay(timerManager: timerManager)
        }
    }

    // MARK: - Private

    private static func roundedMaskImage(size: CGSize, cornerRadius: CGFloat) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
    }

    private func installKeyMonitor(timerManager: TimerManager) {
        // Escape is always registered: a break must never be able to trap the
        // user, so the shortcut works even when the on-screen skip button is
        // hidden by the "Show Skip Button" preference.
        registerEscapeHotkey { [weak timerManager] in
            DispatchQueue.main.async {
                timerManager?.skipBreak(viaKeyboard: true)
            }
        }
    }

    private func uninstallKeyMonitor() {
        unregisterEscapeHotkey()
    }

    // MARK: - Carbon global hotkey (escape, with/without control)

    private func registerEscapeHotkey(handler: @escaping () -> Void) {
        unregisterEscapeHotkey()

        let signature = fourCharCode("reps")

        // Hotkey 1: Escape (no modifiers)
        var hotKeyRef1: EventHotKeyRef?
        let status1 = RegisterEventHotKey(
            0x35,  // kVK_Escape
            0,  // no modifiers
            EventHotKeyID(signature: signature, id: 1),
            GetApplicationEventTarget(),
            0,
            &hotKeyRef1
        )
        if status1 == noErr, let ref = hotKeyRef1 {
            escapeHotKeyRef = ref
        }

        // Hotkey 2: Ctrl+Escape
        var hotKeyRef2: EventHotKeyRef?
        let status2 = RegisterEventHotKey(
            0x35,  // kVK_Escape
            UInt32(controlKey),  // ctrl modifier
            EventHotKeyID(signature: signature, id: 2),
            GetApplicationEventTarget(),
            0,
            &hotKeyRef2
        )
        if status2 == noErr, let ref = hotKeyRef2 {
            ctrlEscapeHotKeyRef = ref
        }

        guard escapeHotKeyRef != nil || ctrlEscapeHotKeyRef != nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Use the handler directly via a heap-allocated context to avoid
        // Unmanaged pointer complexity with a closure capture.
        let ctx = EscapeHandlerContext(handler: handler)
        let ctxPtr = Unmanaged.passRetained(ctx).toOpaque()

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, theEvent, userData) -> OSStatus in
                guard let theEvent = theEvent, let userData = userData else {
                    return OSStatus(eventNotHandledErr)
                }
                var hkCom = EventHotKeyID()
                guard
                    GetEventParameter(
                        theEvent,
                        EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil, MemoryLayout<EventHotKeyID>.size, nil,
                        &hkCom
                    ) == noErr, hkCom.id == 1 || hkCom.id == 2
                else { return OSStatus(eventNotHandledErr) }

                let ctx = Unmanaged<EscapeHandlerContext>.fromOpaque(userData).takeUnretainedValue()
                ctx.handler()
                return noErr
            },
            1,
            &eventType,
            ctxPtr,
            &escapeEventHandlerRef
        )

        if installStatus != noErr {
            Unmanaged<EscapeHandlerContext>.fromOpaque(ctxPtr).release()
            unregisterEscapeHotkey()
        } else {
            escapeHandlerContext = ctxPtr
        }
    }

    private func unregisterEscapeHotkey() {
        if let ref = escapeHotKeyRef {
            UnregisterEventHotKey(ref)
            escapeHotKeyRef = nil
        }
        if let ref = ctrlEscapeHotKeyRef {
            UnregisterEventHotKey(ref)
            ctrlEscapeHotKeyRef = nil
        }
        if let handlerRef = escapeEventHandlerRef {
            RemoveEventHandler(handlerRef)
            escapeEventHandlerRef = nil
        }
        if let context = escapeHandlerContext {
            Unmanaged<EscapeHandlerContext>.fromOpaque(context).release()
            escapeHandlerContext = nil
        }
    }
}

/// A simple heap-allocated object to hold the escape handler closure
/// for the Carbon event callback.
private class EscapeHandlerContext {
    let handler: () -> Void
    init(handler: @escaping () -> Void) { self.handler = handler }
}

/// Convert a 4-character ASCII string to a FourCharCode (OSType).
private func fourCharCode(_ string: String) -> FourCharCode {
    var result: FourCharCode = 0
    for char in string.utf8 {
        result = (result << 8) | FourCharCode(char)
    }
    return result
}
