import XCTest

@testable import ICHRCore

final class TimerRulesTests: XCTestCase {

    func testClampKeepsValuesInsideRange() {
        XCTAssertEqual(TimerRules.clamp(0, to: 1...120), 1)
        XCTAssertEqual(TimerRules.clamp(500, to: 1...120), 120)
        XCTAssertEqual(TimerRules.clamp(20, to: 1...120), 20)
    }

    func testWorkSecondsHonoursBounds() {
        XCTAssertEqual(TimerRules.workSeconds(minutes: 20), 20 * 60)
        XCTAssertEqual(TimerRules.workSeconds(minutes: 0), 60)
        XCTAssertEqual(TimerRules.workSeconds(minutes: 9999), 120 * 60)
    }

    func testShortAndLongBreakBounds() {
        XCTAssertEqual(TimerRules.shortBreakSeconds(1), 5)
        XCTAssertEqual(TimerRules.shortBreakSeconds(20), 20)
        XCTAssertEqual(TimerRules.shortBreakSeconds(9999), 600)
        XCTAssertEqual(TimerRules.longBreakSeconds(1), 60)
        XCTAssertEqual(TimerRules.longBreakSeconds(900), 900)
        XCTAssertEqual(TimerRules.longBreakSeconds(99999), 3600)
    }

    func testLongBreakPlacement() {
        XCTAssertFalse(TimerRules.isLongBreak(sessionsCompleted: 4, every: 0))
        XCTAssertFalse(TimerRules.isLongBreak(sessionsCompleted: 0, every: 4))
        XCTAssertFalse(TimerRules.isLongBreak(sessionsCompleted: 3, every: 4))
        XCTAssertTrue(TimerRules.isLongBreak(sessionsCompleted: 4, every: 4))
        XCTAssertTrue(TimerRules.isLongBreak(sessionsCompleted: 8, every: 4))
        XCTAssertTrue(TimerRules.isLongBreak(sessionsCompleted: 2, every: 2))
    }

    func testBreakTotalSeconds() {
        XCTAssertEqual(
            TimerRules.breakTotalSeconds(isLong: false, shortSeconds: 20, longSeconds: 900),
            20
        )
        XCTAssertEqual(
            TimerRules.breakTotalSeconds(isLong: true, shortSeconds: 20, longSeconds: 900),
            900
        )
    }

    func testRemainingSecondsRoundsUpAndClampsAtZero() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(
            TimerRules.remainingSeconds(deadline: now.addingTimeInterval(10), now: now),
            10
        )
        XCTAssertEqual(
            TimerRules.remainingSeconds(deadline: now.addingTimeInterval(9.2), now: now),
            10
        )
        XCTAssertEqual(
            TimerRules.remainingSeconds(deadline: now.addingTimeInterval(-30), now: now),
            0
        )
    }

    func testImminentOnlyDuringFinalMinuteOfWork() {
        XCTAssertTrue(TimerRules.isImminent(remaining: 60, enabled: true, isWorking: true))
        XCTAssertTrue(TimerRules.isImminent(remaining: 1, enabled: true, isWorking: true))
        XCTAssertFalse(TimerRules.isImminent(remaining: 61, enabled: true, isWorking: true))
        XCTAssertFalse(TimerRules.isImminent(remaining: 0, enabled: true, isWorking: true))
        XCTAssertFalse(TimerRules.isImminent(remaining: 30, enabled: false, isWorking: true))
        XCTAssertFalse(TimerRules.isImminent(remaining: 30, enabled: true, isWorking: false))
    }

    func testSkipHintIsAdvisoryOnly() {
        XCTAssertFalse(TimerRules.showsSkipHint(streak: 1, enabled: true))
        XCTAssertTrue(TimerRules.showsSkipHint(streak: 2, enabled: true))
        XCTAssertTrue(TimerRules.showsSkipHint(streak: 9, enabled: true))
        XCTAssertFalse(TimerRules.showsSkipHint(streak: 9, enabled: false))
    }

    func testIdlePauseOnlyWhenTriggerAllowsIt() {
        let threshold = TimerRules.idleThresholdSeconds
        // Lock-screen trigger: idle time is irrelevant.
        XCTAssertFalse(
            TimerRules.shouldPauseForIdle(
                secondsSinceInput: threshold * 10, trigger: .lockScreen, isWorking: true
            ))
        // Idle triggers: only while working, only past the threshold.
        XCTAssertFalse(
            TimerRules.shouldPauseForIdle(
                secondsSinceInput: threshold - 1, trigger: .idle, isWorking: true
            ))
        XCTAssertTrue(
            TimerRules.shouldPauseForIdle(
                secondsSinceInput: threshold, trigger: .idle, isWorking: true
            ))
        XCTAssertTrue(
            TimerRules.shouldPauseForIdle(
                secondsSinceInput: threshold + 1, trigger: .lockScreenOrIdle, isWorking: true
            ))
        XCTAssertFalse(
            TimerRules.shouldPauseForIdle(
                secondsSinceInput: threshold + 1, trigger: .idle, isWorking: false
            ))
        XCTAssertFalse(
            TimerRules.shouldPauseForIdle(
                secondsSinceInput: threshold + 1, trigger: .never, isWorking: true
            ))
    }

    func testIdleReturnRequiresRecentInput() {
        XCTAssertTrue(TimerRules.isBackFromIdle(secondsSinceInput: 0, trigger: .idle))
        XCTAssertTrue(TimerRules.isBackFromIdle(secondsSinceInput: 4, trigger: .lockScreenOrIdle))
        XCTAssertFalse(TimerRules.isBackFromIdle(secondsSinceInput: 30, trigger: .idle))
        XCTAssertFalse(TimerRules.isBackFromIdle(secondsSinceInput: 0, trigger: .lockScreen))
        XCTAssertFalse(TimerRules.isBackFromIdle(secondsSinceInput: 0, trigger: .never))
    }

    func testFormatTime() {
        XCTAssertEqual(TimerRules.formatTime(0), "0:00")
        XCTAssertEqual(TimerRules.formatTime(59), "0:59")
        XCTAssertEqual(TimerRules.formatTime(60), "1:00")
        XCTAssertEqual(TimerRules.formatTime(3599), "59:59")
        XCTAssertEqual(TimerRules.formatTime(-5), "0:00")
    }

    func testDeadlineUsesNonNegativeOffset() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        XCTAssertEqual(
            TimerRules.deadline(from: now, seconds: 30).timeIntervalSince(now),
            30,
            accuracy: 0.001
        )
        XCTAssertEqual(
            TimerRules.deadline(from: now, seconds: -10).timeIntervalSince(now),
            0,
            accuracy: 0.001
        )
    }

    func testPollThrottle() {
        // Tick 0 never happens (the counter is incremented before the check),
        // and a zero tick must not poll anyway.
        XCTAssertFalse(TimerRules.shouldPoll(tickCount: 0))
        XCTAssertFalse(TimerRules.shouldPoll(tickCount: 1))
        XCTAssertFalse(TimerRules.shouldPoll(tickCount: 4))
        XCTAssertTrue(TimerRules.shouldPoll(tickCount: 5))
        XCTAssertFalse(TimerRules.shouldPoll(tickCount: 6))
        XCTAssertTrue(TimerRules.shouldPoll(tickCount: 10))
        XCTAssertTrue(TimerRules.shouldPoll(tickCount: 55))
    }

    func testPollIntervalIsFiveSeconds() {
        // The idle query and the meeting check are system calls; pinning the
        // interval keeps a future "make it cheaper" edit from quietly turning
        // idle detection into a once-a-minute affair.
        XCTAssertEqual(TimerRules.pollIntervalSeconds, 5)
    }
}
