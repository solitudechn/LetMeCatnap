import AppKit

/// Entry point.
///
/// This is deliberately an AppKit entry point rather than a SwiftUI `App`.
/// The app is a status item plus a couple of panels; SwiftUI is only used
/// *inside* those panels (`NSHostingView`), so the only thing an `App` would
/// contribute is an empty `Settings` scene — which `App` requires but this app
/// has no use for. On current macOS that unused scene opens itself as a blank
/// 900×450 window on launch, which is exactly what a menu bar app must never
/// do. `AppDelegate.installMainMenu()` provides the menu an AppKit app would
/// otherwise be missing.
@main
enum CatnapMain {
    /// `NSApplication.delegate` is an unowned reference, so without this
    /// property the delegate would be deallocated right after `main()` starts.
    @MainActor private static let appDelegate = AppDelegate()

    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.run()
    }
}
