/// Identity of the app bundle, in one place.
///
/// The app went through two identifiers: the upstream one
/// (`wtf.d7.icanhazrepose`, shared with the original build) and
/// `io.github.solitudechn.icanhazrepose`. Renaming the app to LetMeCatnap moved
/// it once more, so preferences are migrated from *both* older domains on first
/// launch (see `Settings.migratePreferences`). Keep the list append-only: every
/// identifier this app has ever written to belongs in it.
///
/// `build.sh` and `Info.plist` must agree with `identifier`, and the code-signing
/// requirement for ad-hoc builds is pinned to it.
public enum BundleIdentity {
    public static let identifier = "io.github.solitudechn.letmecatnap"

    /// Identifiers this app previously stored preferences under, newest first.
    public static let legacyIdentifiers = [
        "io.github.solitudechn.icanhazrepose",
        "wtf.d7.icanhazrepose",
    ]

    /// GitHub repository that publishes the releases and the update feed.
    public static let repository = "solitudechn/iCanHazRepose"

    public static let repositoryURL = "https://github.com/\(repository)"

    /// The feed Sparkle polls. Also written into `Info.plist` as `SUFeedURL`;
    /// a unit test keeps the two in sync.
    public static let updateFeedURL =
        "https://github.com/\(repository)/releases/latest/download/appcast.xml"
}
