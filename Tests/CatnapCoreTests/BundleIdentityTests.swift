import XCTest

@testable import CatnapCore

/// Guards the values that break the app silently when they drift apart.
///
/// The bundle identifier decides the code-signing requirement and the
/// `UserDefaults` domain; the feed URL decides where updates come from. A
/// typo in either is not a compile error — it is an app that never updates or
/// an app whose settings vanish.
final class BundleIdentityTests: XCTestCase {
    /// `Info.plist` lives at the repository root, three directories up from this
    /// file (`Tests/CatnapCoreTests/`).
    private static let infoPlistURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Info.plist")

    private func plistString(_ key: String) -> String? {
        guard let data = try? Data(contentsOf: Self.infoPlistURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        else { return nil }
        return plist[key] as? String
    }

    func testBundleIdentifierMatchesCode() {
        XCTAssertEqual(
            plistString("CFBundleIdentifier"),
            BundleIdentity.identifier,
            "Info.plist and core/BundleIdentity.swift disagree about the bundle id"
        )
    }

    func testUpdateFeedMatchesCode() {
        XCTAssertEqual(
            plistString("SUFeedURL"),
            BundleIdentity.updateFeedURL,
            "Info.plist points the updater somewhere else than this build expects"
        )
    }

    func testSigningKeyIsPresent() {
        let key = plistString("SUPublicEDKey")
        XCTAssertNotNil(key, "SUPublicEDKey is missing — Sparkle would reject every update")
        XCTAssertFalse(key?.isEmpty ?? true)
    }

    func testVersionIsConsistent() {
        let version = plistString("CFBundleVersion")
        let short = plistString("CFBundleShortVersionString")
        XCTAssertNotNil(version)
        XCTAssertEqual(version, short, "the two version keys disagree")
        // Three components, matching the tag: `v2.0.0` must not become "2.0",
        // because the release workflow copies the tag into both keys and
        // Sparkle compares whatever ends up there.
        XCTAssertNotNil(
            version?.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression),
            "version \(version ?? "?") is not of the form x.y.z"
        )
    }

    /// Every identifier this app has ever shipped under must stay in the
    /// migration list, otherwise renaming the app silently resets the settings
    /// of everyone who installed a previous build.
    func testEveryPreviousIdentifierIsStillMigrated() {
        XCTAssertTrue(
            BundleIdentity.legacyIdentifiers.contains("io.github.solitudechn.icanhazrepose"),
            "the pre-rename identifier was dropped from the migration list"
        )
        XCTAssertTrue(
            BundleIdentity.legacyIdentifiers.contains("wtf.d7.icanhazrepose"),
            "the upstream identifier was dropped from the migration list"
        )
        XCTAssertFalse(
            BundleIdentity.legacyIdentifiers.contains(BundleIdentity.identifier),
            "the current identifier is not a legacy one"
        )
    }
}
