/// Identity of the app bundle, in one place.
///
/// The fork used to ship under the upstream identifier (`wtf.d7.icanhazrepose`),
/// which meant it could not be installed next to the original and could not be
/// told apart by LaunchServices. It now has its own identifier; preferences
/// written under the old one are migrated on first launch (see
/// `Settings.migratePreferences`).
///
/// `build.sh` and `Info.plist` must agree with `identifier`, and the code-signing
/// requirement for ad-hoc builds is pinned to it.
public enum BundleIdentity {
    public static let identifier = "io.github.solitudechn.icanhazrepose"

    /// Identifiers this app previously stored preferences under.
    public static let legacyIdentifiers = ["wtf.d7.icanhazrepose"]
}
