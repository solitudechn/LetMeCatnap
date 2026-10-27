import Foundation

/// Central place for app-wide constants.
enum AppConstants {
    static let appName = "iCanHazRepose"
    static let appShortName = "iCHR"

    // MARK: - Repository identity

    /// GitHub owner of the repository whose releases this build updates from.
    ///
    /// Upstream is `deseven/iCanHazRepose`, but a localized fork must point at
    /// its own releases: the updater replaces the whole `.app` bundle, so
    /// following upstream would silently throw the localized UI away.
    static let githubOwner = "solitudechn"
    static let githubRepo = "iCanHazRepose"

    // MARK: - URLs

    static let websiteURL = "https://icanhazapps.d7.wtf"
    static let githubRepoURL = "https://github.com/\(githubOwner)/\(githubRepo)"
    static let upstreamRepoURL = "https://github.com/deseven/iCanHazRepose"
    static let originalRepoURL = "https://github.com/fikrikarim/repose"
    static let kofiURL = "https://ko-fi.com/deseven"
    static let redditURL = "https://www.reddit.com/r/iCanHazApps"
    static let discordURL = "https://discord.gg/YE9KyTXRPt"
    static let boxiconsURL = "https://boxicons.com"
}
