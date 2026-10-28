import Combine
import XCTest

@testable import ICHRCore

final class SettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ICHRCoreTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    @MainActor
    func testDefaultsWhenNothingStored() {
        let settings = Settings(defaults: defaults)
        XCTAssertEqual(settings.workMinutes, 20)
        XCTAssertEqual(settings.breakSeconds, 20)
        XCTAssertEqual(settings.longBreakEvery, 4)
        XCTAssertEqual(settings.longBreakSeconds, 900)
        XCTAssertTrue(settings.pauseDuringMeetings)
        XCTAssertEqual(settings.pauseTrigger, .lockScreen)
        XCTAssertTrue(settings.allowSkipBreak)
        XCTAssertTrue(settings.progressiveReminders)
        XCTAssertFalse(settings.muteSounds)
        XCTAssertFalse(settings.hideMenuBarTimer)
        XCTAssertFalse(settings.hasCompletedWelcome)
    }

    @MainActor
    func testOutOfRangeStoredValuesAreClampedOnLoad() {
        defaults.set(0, forKey: Settings.Key.workMinutes)
        defaults.set(99_999, forKey: Settings.Key.breakSeconds)
        defaults.set(42, forKey: Settings.Key.longBreakEvery)
        defaults.set(5, forKey: Settings.Key.longBreakSeconds)
        let settings = Settings(defaults: defaults)
        XCTAssertEqual(settings.workMinutes, 1)
        XCTAssertEqual(settings.breakSeconds, 599)
        XCTAssertEqual(settings.longBreakEvery, 12)
        XCTAssertEqual(settings.longBreakSeconds, 60)
    }

    @MainActor
    func testSettersClampAndPersist() {
        let settings = Settings(defaults: defaults)
        settings.setBreakSeconds(9_999)
        XCTAssertEqual(settings.breakSeconds, 599)
        XCTAssertEqual(defaults.integer(forKey: Settings.Key.breakSeconds), 599)

        settings.setWorkMinutes(0)
        XCTAssertEqual(settings.workMinutes, 1)
        XCTAssertEqual(defaults.integer(forKey: Settings.Key.workMinutes), 1)

        settings.setLongBreak(every: 99, seconds: 10)
        XCTAssertEqual(settings.longBreakEvery, 12)
        XCTAssertEqual(settings.longBreakSeconds, 60)
        XCTAssertEqual(defaults.integer(forKey: Settings.Key.longBreakEvery), 12)
    }

    @MainActor
    func testDerivedDurations() {
        let settings = Settings(defaults: defaults)
        settings.setWorkMinutes(25)
        settings.setBreakSeconds(30)
        settings.setLongBreak(every: 4, seconds: 1200)
        XCTAssertEqual(settings.workSeconds, 1500)
        XCTAssertEqual(settings.shortBreakSeconds, 30)
        XCTAssertEqual(settings.longBreakTotalSeconds, 1200)
    }

    @MainActor
    func testLegacyDisabledPauseMigratesToNever() {
        defaults.set(false, forKey: Settings.Key.legacyPauseWhenLocked)
        let settings = Settings(defaults: defaults)
        XCTAssertEqual(settings.pauseTrigger, .never)
    }

    @MainActor
    func testLegacyEnabledPauseMigratesToLockScreen() {
        defaults.set(true, forKey: Settings.Key.legacyPauseWhenLocked)
        let settings = Settings(defaults: defaults)
        XCTAssertEqual(settings.pauseTrigger, .lockScreen)
    }

    @MainActor
    func testExplicitTriggerWinsOverLegacyValue() {
        defaults.set(false, forKey: Settings.Key.legacyPauseWhenLocked)
        defaults.set(PauseTrigger.idle.rawValue, forKey: Settings.Key.pauseTrigger)
        let settings = Settings(defaults: defaults)
        XCTAssertEqual(settings.pauseTrigger, .idle)
    }

    @MainActor
    func testPauseTriggerPersistsAndClampsToKnownValues() {
        let settings = Settings(defaults: defaults)
        settings.setPauseTrigger(.lockScreenOrIdle)
        XCTAssertEqual(
            defaults.integer(forKey: Settings.Key.pauseTrigger),
            PauseTrigger.lockScreenOrIdle.rawValue)
        XCTAssertEqual(Settings(defaults: defaults).pauseTrigger, .lockScreenOrIdle)

        settings.setPauseTrigger(.never)
        XCTAssertEqual(Settings(defaults: defaults).pauseTrigger, .never)

        // Unknown stored values fall back to the safe default instead of
        // trapping on an invalid raw value.
        defaults.set(99, forKey: Settings.Key.pauseTrigger)
        XCTAssertEqual(Settings(defaults: defaults).pauseTrigger, .lockScreen)
    }

    func testTriggerPredicates() {
        XCTAssertTrue(PauseTrigger.lockScreen.pausesOnLock)
        XCTAssertFalse(PauseTrigger.lockScreen.pausesOnIdle)
        XCTAssertFalse(PauseTrigger.idle.pausesOnLock)
        XCTAssertTrue(PauseTrigger.idle.pausesOnIdle)
        XCTAssertTrue(PauseTrigger.lockScreenOrIdle.pausesOnLock)
        XCTAssertTrue(PauseTrigger.lockScreenOrIdle.pausesOnIdle)
        XCTAssertFalse(PauseTrigger.never.pausesOnLock)
        XCTAssertFalse(PauseTrigger.never.pausesOnIdle)
        XCTAssertEqual(PauseTrigger.allCases.count, 4)
    }

    @MainActor
    func testWelcomeFlagPersists() {
        let settings = Settings(defaults: defaults)
        settings.markWelcomeCompleted()

        XCTAssertTrue(Settings(defaults: defaults).hasCompletedWelcome)
    }

    @MainActor
    func testPreferencesMigrateFromLegacyBundleIdentifier() {
        let legacySuite = "ICHRCoreTests.legacy." + UUID().uuidString
        let legacy = UserDefaults(suiteName: legacySuite)!
        legacy.removePersistentDomain(forName: legacySuite)
        defer { legacy.removePersistentDomain(forName: legacySuite) }

        legacy.set(45, forKey: Settings.Key.workMinutes)
        legacy.set(false, forKey: Settings.Key.allowSkipBreak)
        legacy.set(AppLanguage.chinese.rawValue, forKey: L10n.languageDefaultsKey)

        XCTAssertTrue(
            Settings.migratePreferences(into: defaults, from: [legacySuite]),
            "values stored under the old bundle id should be copied"
        )
        XCTAssertEqual(defaults.integer(forKey: Settings.Key.workMinutes), 45)
        XCTAssertEqual(defaults.object(forKey: Settings.Key.allowSkipBreak) as? Bool, false)
        XCTAssertEqual(defaults.string(forKey: L10n.languageDefaultsKey), "zh")

        // The migrated values must survive into a live Settings instance.
        let settings = Settings(defaults: defaults)
        XCTAssertEqual(settings.workMinutes, 45)
        XCTAssertFalse(settings.allowSkipBreak)

        // Running it again must not overwrite anything.
        defaults.set(25, forKey: Settings.Key.workMinutes)
        XCTAssertFalse(Settings.migratePreferences(into: defaults, from: [legacySuite]))
        XCTAssertEqual(defaults.integer(forKey: Settings.Key.workMinutes), 25)
    }

    @MainActor
    func testPublishingNotifiesObservers() {
        let settings = Settings(defaults: defaults)
        let expectation = expectation(description: "objectWillChange")
        let cancellable = settings.objectWillChange.sink { expectation.fulfill() }
        settings.setMuteSounds(true)
        wait(for: [expectation], timeout: 1)
        cancellable.cancel()
        XCTAssertTrue(settings.muteSounds)
    }
}
