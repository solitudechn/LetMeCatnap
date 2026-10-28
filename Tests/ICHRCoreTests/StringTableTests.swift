import XCTest

@testable import ICHRCore

/// Guards the string table itself. Every failure here would otherwise reach the
/// user as a missing, half-translated or `%ld`-mangled label.
final class StringTableTests: XCTestCase {

    /// Keys whose two sides are identical on purpose (key names are not
    /// translated), so the "Chinese side must contain Chinese" rule cannot apply.
    private let intentionallyUntranslated: Set<LocKey> = [.skipKeys]

    func testEveryKeyHasAnEntry() {
        let missing = LocKey.allCases.filter { StringTable.table[$0] == nil }
        XCTAssertTrue(
            missing.isEmpty,
            "no translation for: \(missing.map(\.rawValue).joined(separator: ", "))"
        )
    }

    func testNoEmptySides() {
        for (key, translation) in StringTable.table {
            XCTAssertFalse(
                translation.en.trimmingCharacters(in: .whitespaces).isEmpty,
                "empty English side for \(key.rawValue)"
            )
            XCTAssertFalse(
                translation.zh.trimmingCharacters(in: .whitespaces).isEmpty,
                "empty Chinese side for \(key.rawValue)"
            )
        }
    }

    func testChineseSideIsChinese() {
        for (key, translation) in StringTable.table where !intentionallyUntranslated.contains(key) {
            XCTAssertTrue(
                translation.zh.containsCJK,
                "\(key.rawValue): Chinese side has no Chinese text (\(translation.zh))"
            )
        }
    }

    func testEnglishSideIsNotChinese() {
        for (key, translation) in StringTable.table {
            XCTAssertFalse(
                translation.en.containsCJK,
                "\(key.rawValue): English side contains Chinese (\(translation.en))"
            )
        }
    }

    func testPlaceholdersMatch() {
        for (key, translation) in StringTable.table {
            XCTAssertEqual(
                translation.placeholderCount,
                Translation(translation.zh, translation.en).placeholderCount,
                "\(key.rawValue): placeholder count differs"
            )
        }
    }

    func testTableHasNoOrphanEntries() {
        // The table is keyed by LocKey already, so this only guards against a key
        // that exists in the type but was never listed by `allCases`.
        XCTAssertEqual(Set(StringTable.table.keys), Set(LocKey.allCases))
    }

    func testBreakTipsAreComplete() {
        XCTAssertFalse(StringTable.breakTips.isEmpty)
        for tip in StringTable.breakTips {
            XCTAssertFalse(tip.en.isEmpty)
            XCTAssertTrue(tip.zh.containsCJK, "untranslated tip: \(tip.en)")
            XCTAssertFalse(tip.en.containsCJK, "English tip contains Chinese: \(tip.en)")
        }
    }

    func testFormattingAppliesArguments() {
        let english = L10n.format(L10n.text(.minutesFormat, for: .english), [25])
        XCTAssertEqual(english, "25 min")

        let chinese = L10n.format(L10n.text(.minutesFormat, for: .chinese), [25])
        XCTAssertEqual(chinese, "25 分钟")

        let preset = L10n.format(L10n.text(.longBreakPreset, for: .chinese), [4, 15])
        XCTAssertEqual(preset, "每 4 轮 · 15 分钟")
    }

    func testTranslationPicksTheRequestedLanguage() {
        let pair = Translation("Skip", "跳过")
        XCTAssertEqual(pair.value(for: .english), "Skip")
        XCTAssertEqual(pair.value(for: .chinese), "跳过")
        // `L10n.current` resolves `.system` before anyone asks for a string, so
        // this is only a safety net — it must fall back to English, not trap.
        XCTAssertEqual(pair.value(for: .system), "Skip")
    }

    func testPlaceholderCountingHandlesEverySpecifierInUse() {
        XCTAssertEqual(Translation("%ld min", "%ld 分钟").placeholderCount, 1)
        XCTAssertEqual(Translation("%d min", "%d 分钟").placeholderCount, 1)
        XCTAssertEqual(Translation("%@ of %@", "%@ / %@").placeholderCount, 2)
        XCTAssertEqual(Translation("%@ — %@", "%@ — %@").placeholderCount, 2)
        XCTAssertEqual(Translation("no slots", "无占位符").placeholderCount, 0)
        // A literal percent followed by a letter must not count as a placeholder,
        // otherwise a translation may look mismatched when it is fine.
        XCTAssertEqual(Translation("100% sure", "100% 确定").placeholderCount, 0)
    }
}

extension String {
    fileprivate var containsCJK: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }
    }
}
