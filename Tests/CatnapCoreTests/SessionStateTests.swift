import XCTest

@testable import CatnapCore

/// The state machine, driven without a screen, a timer or `UserDefaults`.
///
/// Each test advances a fake clock, so a 20 minute session costs a couple of
/// `Date` operations instead of a wait. These cover the transitions that used
/// to live in `TimerManager` — and therefore could not be tested at all.
final class SessionStateTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Helpers

    private func makeState(
        workSeconds: Int = 20 * 60,
        shortBreak: Int = 20,
        longBreakEvery: Int = 4,
        longBreak: Int = 900,
        pauseDuringMeetings: Bool = true,
        progressiveReminders: Bool = true,
        showSkipButton: Bool = true,
        pauseTrigger: PauseTrigger = .lockScreen
    ) -> SessionState {
        SessionState(
            config: SessionConfig(
                workSeconds: workSeconds,
                shortBreakSeconds: shortBreak,
                longBreakEvery: longBreakEvery,
                longBreakSeconds: longBreak,
                progressiveReminders: progressiveReminders,
                showSkipButton: showSkipButton,
                pauseDuringMeetings: pauseDuringMeetings,
                pauseTrigger: pauseTrigger,
                postMeetingBreakDelay: 5
            ),
            now: start
        )
    }

    /// Advances to the instant the work session expires, asserts that a break
    /// started, and returns that instant.
    @discardableResult
    private func runToBreak(_ state: inout SessionState, from now: Date) -> Date {
        let expiry = now.addingTimeInterval(TimeInterval(state.remaining + 1))
        let effects = state.tick(now: expiry)
        XCTAssertTrue(
            effects.contains { if case .breakStarted = $0 { return true } else { return false } },
            "expected a break after the work session expired"
        )
        return expiry
    }

    /// The instant the overlay's countdown reaches zero.
    private func breakEnd(_ state: SessionState, from started: Date) -> Date {
        started.addingTimeInterval(
            TimerRules.breakGracePeriod + TimeInterval(state.breakTotalSeconds)
        )
    }

    /// Runs the break currently on screen to completion and returns the moment
    /// the next work session began.
    @discardableResult
    private func takeEntireBreak(_ state: inout SessionState, from started: Date) -> Date {
        let end = breakEnd(state, from: started)
        XCTAssertEqual(state.tick(now: end), [.breakFinished])
        let resumed = end.addingTimeInterval(0.5)
        _ = state.finishBreak(now: resumed)
        return resumed
    }

    // MARK: - Starting point

    func testFreshStateRunsAWorkSession() {
        let state = makeState()
        XCTAssertEqual(state.phase, .working)
        XCTAssertEqual(state.remaining, 20 * 60)
        XCTAssertNil(state.currentPauseCause)
        XCTAssertEqual(state.skipStreak, 0)
    }

    func testCountdownFollowsTheWallClock() {
        var state = makeState()
        _ = state.tick(now: start.addingTimeInterval(10))
        XCTAssertEqual(state.remaining, 20 * 60 - 10)
        // A late tick catches up instead of silently adding a second.
        _ = state.tick(now: start.addingTimeInterval(70))
        XCTAssertEqual(state.remaining, 20 * 60 - 70)
    }

    // MARK: - Breaks

    func testWorkExpiryStartsTheShortBreak() {
        var state = makeState(shortBreak: 30)
        runToBreak(&state, from: start)

        XCTAssertEqual(state.phase, .onBreak)
        XCTAssertFalse(state.isLongBreak)
        XCTAssertEqual(state.remaining, 30)
        XCTAssertNil(state.currentPauseCause)
        XCTAssertNotNil(state.breakStartedAt)
        XCTAssertEqual(state.sessionsCompleted, 1)
    }

    func testLongBreakArrivesOnTheConfiguredSession() {
        var state = makeState(shortBreak: 20, longBreakEvery: 2, longBreak: 600)

        let first = runToBreak(&state, from: start)
        XCTAssertFalse(state.isLongBreak, "the first session earns a short break")
        XCTAssertEqual(state.remaining, 20)

        let afterFirst = takeEntireBreak(&state, from: first)

        runToBreak(&state, from: afterFirst)
        XCTAssertTrue(state.isLongBreak, "the second session earns the long one")
        XCTAssertEqual(state.remaining, 600)
        XCTAssertEqual(state.sessionsCompleted, 2)
    }

    func testBreakCountdownWaitsForTheGracePeriod() {
        var state = makeState(shortBreak: 30)
        let started = runToBreak(&state, from: start)

        // Still fading in: the countdown must not have moved.
        _ = state.tick(now: started.addingTimeInterval(1))
        XCTAssertEqual(state.remaining, 30)

        // Past the grace period the ring starts moving.
        _ = state.tick(now: started.addingTimeInterval(TimerRules.breakGracePeriod + 5))
        XCTAssertEqual(state.remaining, 25)
    }

    func testCompletedBreakResetsTheSkipStreak() {
        var state = makeState(shortBreak: 20)
        let first = runToBreak(&state, from: start)
        _ = state.skipBreak(viaKeyboard: true, now: first.addingTimeInterval(2))
        XCTAssertEqual(state.skipStreak, 1)

        let second = runToBreak(&state, from: first.addingTimeInterval(2))
        let resumed = takeEntireBreak(&state, from: second)

        XCTAssertEqual(state.skipStreak, 0, "a break actually taken clears the nudge")
        XCTAssertEqual(state.phase, .working)
        XCTAssertEqual(state.remaining, state.config.workSeconds)
        XCTAssertEqual(resumed.timeIntervalSince(second), TimerRules.breakGracePeriod + 20.5)
    }

    func testBreakFinishedOnlyFiresOnce() {
        var state = makeState(shortBreak: 20)
        let started = runToBreak(&state, from: start)
        let finished = breakEnd(state, from: started)

        XCTAssertEqual(state.tick(now: finished), [.breakFinished])
        XCTAssertEqual(state.tick(now: finished.addingTimeInterval(1)), [])
    }

    /// The fade-out lasts 0.45s. Anything that happens inside that window wins.
    func testLateBreakCallbackDoesNotOverwriteAnInterruption() {
        var state = makeState(shortBreak: 20)
        let started = runToBreak(&state, from: start)
        let finished = breakEnd(state, from: started)
        _ = state.tick(now: finished)

        _ = state.meetingStatusChanged(isInMeeting: true, now: finished.addingTimeInterval(0.1))
        XCTAssertEqual(state.phase, .paused)
        XCTAssertEqual(state.pauseCause, .meeting)

        XCTAssertEqual(state.finishBreak(now: finished.addingTimeInterval(0.5)), [])
        XCTAssertEqual(state.phase, .paused, "a stale callback must not start work behind a meeting")
    }

    // MARK: - Skipping

    func testSkippingNeedsTheButtonOnlyWhenUsingTheButton() {
        var state = makeState(shortBreak: 20, showSkipButton: false)
        let started = runToBreak(&state, from: start)

        XCTAssertEqual(state.skipBreak(viaKeyboard: false, now: started.addingTimeInterval(2)), [])
        XCTAssertEqual(state.phase, .onBreak, "no button means the button path does nothing")

        let effects = state.skipBreak(viaKeyboard: true, now: started.addingTimeInterval(3))
        XCTAssertEqual(state.phase, .working, "Escape always works")
        XCTAssertTrue(effects.contains(.breakDismissed))
        XCTAssertEqual(state.skipStreak, 1)
    }

    func testSkipHintAppearsAfterTwoSkips() {
        var state = makeState(shortBreak: 20)
        var now = runToBreak(&state, from: start)

        _ = state.skipBreak(viaKeyboard: true, now: now.addingTimeInterval(2))
        now = now.addingTimeInterval(2)
        _ = state.takeBreakNow(now: now.addingTimeInterval(1))
        XCTAssertFalse(state.showsSkipHint, "one skip is not a pattern")

        _ = state.skipBreak(viaKeyboard: true, now: now.addingTimeInterval(2))
        now = now.addingTimeInterval(2)
        _ = state.takeBreakNow(now: now.addingTimeInterval(1))
        XCTAssertTrue(state.showsSkipHint)
    }

    func testManualBreakDoesNotCountAsAWorkSession() {
        var state = makeState(longBreakEvery: 1)
        _ = state.takeBreakNow(now: start.addingTimeInterval(5))

        XCTAssertEqual(state.phase, .onBreak)
        XCTAssertFalse(state.isLongBreak, "a manual break is never the long one")
        XCTAssertEqual(state.sessionsCompleted, 0)
    }

    // MARK: - Manual pause

    func testManualPauseKeepsTheRemainingTime() {
        var state = makeState(workSeconds: 1200)
        _ = state.pauseManually(now: start.addingTimeInterval(100))
        XCTAssertEqual(state.phase, .paused)
        XCTAssertEqual(state.pauseCause, .manual)
        XCTAssertEqual(state.banked, 1100)

        // A paused timer does not count down.
        _ = state.tick(now: start.addingTimeInterval(400))
        XCTAssertEqual(state.banked, 1100)

        _ = state.resumeManually(now: start.addingTimeInterval(400))
        XCTAssertEqual(state.phase, .working)
        XCTAssertEqual(state.remaining, 1100)
    }

    func testRestartIsIgnoredDuringABreak() {
        var state = makeState(shortBreak: 20)
        let started = runToBreak(&state, from: start)
        XCTAssertEqual(state.restartTimer(now: started.addingTimeInterval(2)), [])
        XCTAssertEqual(state.phase, .onBreak)
    }

    // MARK: - Lock screen

    func testLockPausesAndBanksTheRemainingTime() {
        var state = makeState(workSeconds: 1200)
        XCTAssertEqual(state.screenLocked(now: start.addingTimeInterval(300)), [])
        XCTAssertEqual(state.phase, .paused)
        XCTAssertEqual(state.pauseCause, .locked)
        XCTAssertEqual(state.banked, 900)
    }

    func testUnlockStartsAFreshSession() {
        var state = makeState(workSeconds: 1200)
        _ = state.screenLocked(now: start.addingTimeInterval(300))
        _ = state.screenUnlocked(isScreenLocked: false, now: start.addingTimeInterval(3600))
        XCTAssertEqual(state.phase, .working)
        XCTAssertEqual(state.remaining, 1200, "a locked screen is a real break")
    }

    func testDisplayWakeBeforeUnlockStaysPaused() {
        var state = makeState()
        _ = state.screenLocked(now: start.addingTimeInterval(30))
        _ = state.screenUnlocked(isScreenLocked: true, now: start.addingTimeInterval(60))
        XCTAssertEqual(state.phase, .paused)
        XCTAssertEqual(state.pauseCause, .locked)
    }

    func testLockIsIgnoredWhenTheTriggerDisablesIt() {
        var state = makeState(pauseTrigger: .never)
        XCTAssertEqual(state.screenLocked(now: start.addingTimeInterval(30)), [])
        XCTAssertEqual(state.phase, .working)
    }

    func testUnlockWithoutALockPauseIsIgnored() {
        var state = makeState(pauseTrigger: .idle)
        _ = state.screenLocked(now: start.addingTimeInterval(30))
        XCTAssertEqual(state.phase, .working)

        _ = state.screenUnlocked(isScreenLocked: false, now: start.addingTimeInterval(60))
        XCTAssertEqual(state.phase, .working, "nothing was paused, so there is nothing to resume")
    }

    // MARK: - Idle

    func testIdlePauseHonoursTheThresholdAndTheReturn() {
        var state = makeState(workSeconds: 1200, pauseTrigger: .idle)

        _ = state.inputActivity(secondsSinceInput: 299, now: start.addingTimeInterval(299))
        XCTAssertEqual(state.phase, .working, "under the threshold nothing happens")

        _ = state.inputActivity(secondsSinceInput: 300, now: start.addingTimeInterval(300))
        XCTAssertEqual(state.phase, .paused)
        XCTAssertEqual(state.pauseCause, .idle)
        XCTAssertEqual(state.banked, 900)

        _ = state.inputActivity(secondsSinceInput: 30, now: start.addingTimeInterval(330))
        XCTAssertEqual(state.phase, .paused, "still away until input resumes")

        _ = state.inputActivity(secondsSinceInput: 2, now: start.addingTimeInterval(400))
        XCTAssertEqual(state.phase, .working)
        XCTAssertEqual(state.remaining, 1200)
    }

    func testIdleIsIgnoredWhenTheTriggerDoesNotAllowIt() {
        var state = makeState(workSeconds: 1200, pauseTrigger: .lockScreen)
        _ = state.inputActivity(secondsSinceInput: 3600, now: start.addingTimeInterval(3600))
        XCTAssertEqual(state.phase, .working)
    }

    // MARK: - Settings

    func testSwitchingTheTriggerLiftsThePauseItCaused() {
        var state = makeState()
        _ = state.screenLocked(now: start.addingTimeInterval(30))

        var newConfig = state.config
        newConfig.pauseTrigger = .never
        let effects = state.configChanged(newConfig, now: start.addingTimeInterval(60))

        XCTAssertEqual(state.phase, .working)
        XCTAssertTrue(effects.contains(.automaticPauseLifted(.locked)))
    }

    func testWorkDurationChangeNeverExtendsTheCurrentSession() {
        var state = makeState(workSeconds: 1200)
        _ = state.tick(now: start.addingTimeInterval(200))
        XCTAssertEqual(state.remaining, 1000)

        var shorter = state.config
        shorter.workSeconds = 600
        _ = state.configChanged(shorter, now: start.addingTimeInterval(200))
        XCTAssertEqual(state.remaining, 600, "the old remaining time no longer fits")

        var longer = state.config
        longer.workSeconds = 900
        _ = state.configChanged(longer, now: start.addingTimeInterval(200))
        XCTAssertEqual(state.remaining, 600, "a longer limit must not hand out free time")
    }

    /// The same rule has to hold while the timer is paused, where the
    /// remaining time is banked instead of counted down.
    func testShorteningTheIntervalAlsoCapsTheBankedTime() {
        var state = makeState(workSeconds: 1200)
        _ = state.pauseManually(now: start.addingTimeInterval(100))
        XCTAssertEqual(state.banked, 1100)

        var shorter = state.config
        shorter.workSeconds = 600
        _ = state.configChanged(shorter, now: start.addingTimeInterval(120))
        XCTAssertEqual(state.banked, 600, "the banked time no longer fits the new interval")

        _ = state.resumeManually(now: start.addingTimeInterval(130))
        XCTAssertEqual(
            state.remaining,
            600,
            "resuming must not hand out more time than the configured interval"
        )
    }

    /// Lengthening the interval keeps the time that was already earned —
    /// a longer limit is not a gift.
    func testLengtheningTheIntervalKeepsTheBankedTime() {
        var state = makeState(workSeconds: 1200)
        _ = state.pauseManually(now: start.addingTimeInterval(100))

        var longer = state.config
        longer.workSeconds = 3600
        _ = state.configChanged(longer, now: start.addingTimeInterval(120))
        XCTAssertEqual(state.banked, 1100)

        _ = state.resumeManually(now: start.addingTimeInterval(130))
        XCTAssertEqual(state.remaining, 1100)
    }

    // MARK: - Meetings

    func testMeetingInterruptsABreak() {
        var state = makeState(shortBreak: 20)
        let started = runToBreak(&state, from: start)

        let effects = state.meetingStatusChanged(
            isInMeeting: true, now: started.addingTimeInterval(2))
        XCTAssertTrue(effects.contains(.breakInterrupted(.meeting)))
        XCTAssertEqual(state.phase, .paused)
        XCTAssertEqual(state.pauseCause, .meeting)
        XCTAssertEqual(state.banked, state.config.workSeconds)
    }

    func testBreakIsDeferredWhenWorkExpiresInAMeeting() {
        var state = makeState(workSeconds: 600)
        _ = state.meetingStatusChanged(isInMeeting: true, now: start.addingTimeInterval(10))

        let effects = state.tick(now: start.addingTimeInterval(700))
        XCTAssertTrue(effects.contains(.breakDeferredToMeeting))
        XCTAssertEqual(state.phase, .paused)
        XCTAssertEqual(state.pauseCause, .breakPending)
    }

    func testMeetingEndAfterADeferredBreakGivesAShortCountdown() {
        var state = makeState(workSeconds: 600)
        _ = state.meetingStatusChanged(isInMeeting: true, now: start.addingTimeInterval(10))
        _ = state.tick(now: start.addingTimeInterval(700))

        _ = state.meetingStatusChanged(isInMeeting: false, now: start.addingTimeInterval(800))
        XCTAssertEqual(state.phase, .working)
        XCTAssertEqual(state.remaining, 5, "the overlay must not appear the instant the call ends")
    }

    func testMeetingEndResumesAFullSessionAfterAnInterruptedBreak() {
        var state = makeState(workSeconds: 1200, shortBreak: 20)
        let started = runToBreak(&state, from: start)
        _ = state.meetingStatusChanged(isInMeeting: true, now: started.addingTimeInterval(2))

        _ = state.meetingStatusChanged(isInMeeting: false, now: started.addingTimeInterval(600))
        XCTAssertEqual(state.phase, .working)
        XCTAssertEqual(state.remaining, 1200)
    }

    func testTurningMeetingPausingOffReleasesThePause() {
        var state = makeState()
        let started = runToBreak(&state, from: start)
        _ = state.meetingStatusChanged(isInMeeting: true, now: started.addingTimeInterval(2))
        XCTAssertEqual(state.phase, .paused)
        XCTAssertEqual(state.pauseCause, .meeting)

        var newConfig = state.config
        newConfig.pauseDuringMeetings = false
        let effects = state.configChanged(newConfig, now: started.addingTimeInterval(10))

        XCTAssertEqual(state.phase, .working)
        XCTAssertTrue(effects.contains(.automaticPauseLifted(.meeting)))
    }

    func testMeetingsNeverPauseARunningWorkSession() {
        var state = makeState()
        _ = state.meetingStatusChanged(isInMeeting: true, now: start.addingTimeInterval(10))
        XCTAssertEqual(state.phase, .working, "the countdown keeps running during a call")
    }

    // MARK: - Wake

    func testWakeRestartsWorkAndDismissesABreak() {
        var state = makeState(workSeconds: 1200)
        _ = state.tick(now: start.addingTimeInterval(300))
        _ = state.systemWake(now: start.addingTimeInterval(400))
        XCTAssertEqual(state.remaining, 1200, "sleep time is not work time")

        let started = runToBreak(&state, from: start.addingTimeInterval(400))
        let effects = state.systemWake(now: started.addingTimeInterval(2))
        XCTAssertTrue(effects.contains(.breakInterrupted(.wake)))
        XCTAssertEqual(state.phase, .working)
    }

    func testWakeLeavesAManualPauseAlone() {
        var state = makeState()
        _ = state.pauseManually(now: start.addingTimeInterval(60))
        _ = state.systemWake(now: start.addingTimeInterval(600))
        XCTAssertEqual(state.phase, .paused)
        XCTAssertEqual(state.pauseCause, .manual)
    }

    // MARK: - Progressive reminder

    func testImminentReminderFiresOncePerSession() {
        var state = makeState(workSeconds: 100)

        XCTAssertEqual(state.tick(now: start.addingTimeInterval(39)), [])
        XCTAssertEqual(state.tick(now: start.addingTimeInterval(40)), [.imminentReminder])
        XCTAssertEqual(state.tick(now: start.addingTimeInterval(41)), [], "the chime is not a metronome")
        XCTAssertTrue(state.isImminent)
    }

    func testImminentReminderRespectsTheSwitch() {
        var state = makeState(workSeconds: 100, progressiveReminders: false)
        XCTAssertEqual(state.tick(now: start.addingTimeInterval(50)), [])
        XCTAssertFalse(state.isImminent)
    }

    // MARK: - Invariants

    /// The app's promise: no break can ever trap the user.
    func testEveryBreakCanBeDismissedWithTheKeyboard() {
        var state = makeState(shortBreak: 20, showSkipButton: false)
        let started = runToBreak(&state, from: start)
        _ = state.skipBreak(viaKeyboard: true, now: started.addingTimeInterval(1))
        XCTAssertEqual(state.phase, .working)
    }

    func testBreakTotalIsStableWhileOnScreen() {
        var state = makeState(shortBreak: 20, longBreakEvery: 1, longBreak: 900)
        runToBreak(&state, from: start)
        let total = state.breakTotalSeconds
        XCTAssertEqual(total, 900)

        // Changing the preference mid-break must not resize the ring.
        var newConfig = state.config
        newConfig.longBreakSeconds = 60
        _ = state.configChanged(newConfig, now: start.addingTimeInterval(100))
        XCTAssertEqual(state.breakTotalSeconds, total)
    }

    func testRestartClearsTheBreakTail() {
        var state = makeState(shortBreak: 20)
        let started = runToBreak(&state, from: start)
        _ = state.skipBreak(viaKeyboard: true, now: started.addingTimeInterval(2))

        XCTAssertEqual(state.phase, .working)
        XCTAssertFalse(state.isLongBreak)
        XCTAssertEqual(state.activeBreakTotal, 0)
        XCTAssertNil(state.breakStartedAt)
    }
}
