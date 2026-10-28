import Foundation

/// Central place for app-wide constants.
enum AppConstants {
    static let appName = "LetMeCatnap"

    /// The app's Chinese name, shown under the Latin one in the About window.
    ///
    /// Not translated: it is a name, so it reads the same whichever UI language
    /// is active — the same way the Latin name is not translated either.
    static let appNameChinese = "我要小喵一下"

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
