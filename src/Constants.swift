import Foundation

/// Central place for app-wide constants.
enum AppConstants {
    static let appName = "LetMeCatnap"

    // MARK: - URLs
    //
    // The repository this build updates from lives in `BundleIdentity`
    // (core/BundleIdentity.swift) together with the bundle identifier, so the
    // updater, the About window and the Info.plist cannot drift apart.

    /// Where the code this app is based on lives.
    static let upstreamRepoURL = "https://github.com/deseven/iCanHazRepose"
    static let originalRepoURL = "https://github.com/fikrikarim/repose"
    static let boxiconsURL = "https://boxicons.com"
}
