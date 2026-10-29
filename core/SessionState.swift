import Foundation

/// Which phase the timer is in.
public enum SessionPhase: Equatable, Sendable {
    case working
    case onBreak
    case paused
}

/// Why the timer is paused. Only meaningful while `phase == .paused`.
public enum PauseCause: Equatable, Sendable {
    case manual
    /// A meeting started, or the break expired during one.
    case meeting
    case locked
    case idle
    /// The work session expired while a meeting was running; the break waits
    /// for the meeting to end plus a short countdown.
    case breakPending
}

/// Why a break that had already started went away.
public enum BreakInterruption: Equatable, Sendable {
    case meeting
    case wake
}

/// Something the caller has to do as a result of a transition.
///
/// `SessionState` never touches AppKit, timers, sounds or the log: it returns
/// what should happen and the app decides how. That is what makes the state
/// machine testable — a test can assert on these values without a screen.
public enum SessionEffect: Equatable, Sendable {
    case workSessionStarted(seconds: Int)
    case breakStarted(isLong: Bool, seconds: Int, manual: Bool)
    /// The break's countdown reached zero. The caller should fade the overlay
    /// out and then call `finishBreak()`, which is what actually resumes work.
    case breakFinished
    /// The break was closed before it ran out.
    case breakInterrupted(BreakInterruption)
    /// The user dismissed the break with the button or Escape.
    case breakDismissed
    /// The work session expired during a meeting, so no overlay was shown.
    case breakDeferredToMeeting
    /// Entered the last minute of a work session.
    case imminentReminder
    /// A settings change released a pause the user did not ask to end.
    case automaticPauseLifted(PauseCause)
}

/// Everything the state machine needs to know about the user's preferences.
///
/// A snapshot rather than a reference to `Settings`, so the tests can describe
/// a scenario without touching `UserDefaults`.
public struct SessionConfig: Equatable, Sendable {
    public var workSeconds: Int
    public var shortBreakSeconds: Int
    public var longBreakEvery: Int
    public var longBreakSeconds: Int
    public var progressiveReminders: Bool
    public var showSkipButton: Bool
    public var pauseDuringMeetings: Bool
    public var pauseTrigger: PauseTrigger
    /// Wait this long after a meeting ends before showing the deferred break.
    public var postMeetingBreakDelay: Int

    public init(
        workSeconds: Int = 20 * 60,
        shortBreakSeconds: Int = 20,
        longBreakEvery: Int = 4,
        longBreakSeconds: Int = 900,
        progressiveReminders: Bool = true,
        showSkipButton: Bool = true,
        pauseDuringMeetings: Bool = true,
        pauseTrigger: PauseTrigger = .lockScreen,
        postMeetingBreakDelay: Int = TimerRules.postMeetingBreakDelaySeconds
    ) {
        self.workSeconds = workSeconds
        self.shortBreakSeconds = shortBreakSeconds
        self.longBreakEvery = longBreakEvery
        self.longBreakSeconds = longBreakSeconds
        self.progressiveReminders = progressiveReminders
        self.showSkipButton = showSkipButton
        self.pauseDuringMeetings = pauseDuringMeetings
        self.pauseTrigger = pauseTrigger
        self.postMeetingBreakDelay = postMeetingBreakDelay
    }

    /// Snapshot of everything the state machine cares about in `Settings`.
    ///
    /// Lives next to `SessionConfig` rather than in `TimerManager` for the same
    /// reason the state machine does: a hand-written mapping in the app target
    /// cannot be tested, so a newly added preference silently fails to reach the
    /// machine. Here a test can assert the whole snapshot.
    /// - Note: `Settings` is main-actor isolated, so reading a snapshot of it
    ///   has to happen there too. The result is a plain value the machine can
    ///   carry anywhere.
    @MainActor
    public init(settings: Settings) {
        self.init(
            workSeconds: settings.workSeconds,
            shortBreakSeconds: settings.shortBreakSeconds,
            longBreakEvery: settings.longBreakEvery,
            longBreakSeconds: settings.longBreakTotalSeconds,
            progressiveReminders: settings.progressiveReminders,
            showSkipButton: settings.showSkipButton,
            pauseDuringMeetings: settings.pauseDuringMeetings,
            pauseTrigger: settings.pauseTrigger,
            postMeetingBreakDelay: TimerRules.postMeetingBreakDelaySeconds
        )
    }
}

/// The whole timer state machine, as a value.
///
/// Every transition takes the current time as a parameter and returns the
/// effects the app has to perform. There is deliberately no `Timer`, no
/// `Date()` call, no sound and no `NSPanel` in here: the app layer owns those,
/// so a test can drive months of behaviour in a millisecond.
///
/// This exists because `TimerManager` used to hold the decisions itself, and a
/// decision that lives in the AppKit target cannot be unit-tested — which is
/// how `TimerManager` once grew a private copy of `TimerRules.showsSkipHint`
/// and the test kept passing against code nobody ran.
public struct SessionState: Equatable {
    // MARK: - Observable state

    public private(set) var phase: SessionPhase = .working
    public private(set) var pauseCause: PauseCause = .manual
    /// Seconds left in the current phase.
    public private(set) var remaining: Int = 0
    /// Work seconds banked when an automatic pause started. Resuming a manual
    /// pause continues from here; an automatic one restarts a full session,
    /// because the user was away — which is what the break was for.
    public private(set) var banked: Int = 0
    public private(set) var isLongBreak = false
    public private(set) var activeBreakTotal = 0
    public private(set) var isImminent = false
    /// Fully completed work sessions, used to place long breaks.
    public private(set) var sessionsCompleted = 0
    /// Consecutive breaks the user dismissed without taking.
    public private(set) var skipStreak = 0
    public private(set) var isInMeeting = false
    /// When the current break's overlay appeared; drives the grace period.
    public private(set) var breakStartedAt: Date?
    /// Set once the countdown hits zero, so the fade-out cannot be triggered
    /// twice and a late callback cannot resume work behind a new state.
    public private(set) var isFinishingBreak = false

    public private(set) var config: SessionConfig

    private var workDeadline: Date?
    private var breakDeadline: Date?
    /// The last moment a work session started or ended. Used to tell "the user
    /// paused for a bit" from "the user went home" — see `resetRhythmIfStale`.
    private var lastActivityAt: Date?

    // MARK: - Init

    public init(config: SessionConfig = SessionConfig(), now: Date) {
        self.config = config
        self.lastActivityAt = now
        remaining = max(0, config.workSeconds)
        workDeadline = TimerRules.deadline(from: now, seconds: remaining)
    }

    // MARK: - Derived values

    /// `nil` unless actually paused, so callers cannot read a stale cause.
    public var currentPauseCause: PauseCause? {
        phase == .paused ? pauseCause : nil
    }

    /// Whether the overlay should offer an on-screen skip button. Escape always
    /// works regardless of this.
    public var showsSkipButton: Bool {
        phase == .onBreak && config.showSkipButton
    }

    /// Advisory nudge after repeated skips; never a lock.
    public var showsSkipHint: Bool {
        phase == .onBreak
            && TimerRules.showsSkipHint(streak: skipStreak, enabled: config.progressiveReminders)
    }

    /// Real total of the break in progress, so a 15 minute break does not fill
    /// the ring in 20 seconds.
    public var breakTotalSeconds: Int {
        if phase == .onBreak && activeBreakTotal > 0 {
            return activeBreakTotal
        }
        return isLongBreak ? config.longBreakSeconds : config.shortBreakSeconds
    }

    // MARK: - User actions

    /// Restart the work countdown from the top. Ignored during a break: the
    /// break is the thing the user is supposed to be taking.
    public mutating func restartTimer(now: Date) -> [SessionEffect] {
        guard phase != .onBreak else { return [] }
        return beginWork(seconds: config.workSeconds, now: now)
    }

    public mutating func pauseManually(now: Date) -> [SessionEffect] {
        guard phase == .working else { return [] }
        refreshWorkingRemaining(now: now)
        banked = remaining
        workDeadline = nil
        isImminent = false
        phase = .paused
        pauseCause = .manual
        return []
    }

    public mutating func resumeManually(now: Date) -> [SessionEffect] {
        guard phase == .paused else { return [] }
        var effects = beginWork(seconds: banked, now: now, resetImminent: false)
        pauseCause = .manual
        effects += updateImminent()
        return effects
    }

    /// A break the user asked for. It does not consume a pomodoro session and
    /// therefore does not move the next long break closer.
    public mutating func takeBreakNow(now: Date) -> [SessionEffect] {
        guard phase != .onBreak else { return [] }
        return beginBreak(countsAsSession: false, now: now)
    }

    /// - Parameter viaKeyboard: Escape, which always works.
    public mutating func skipBreak(viaKeyboard: Bool, now: Date) -> [SessionEffect] {
        guard phase == .onBreak else { return [] }
        guard viaKeyboard || config.showSkipButton else { return [] }
        skipStreak += 1
        return [.breakDismissed] + beginWork(seconds: config.workSeconds, now: now)
    }

    // MARK: - Clock

    /// One tick of the countdown. Returns the break effects when the work
    /// session or the break runs out.
    public mutating func tick(now: Date) -> [SessionEffect] {
        switch phase {
        case .paused:
            return []

        case .working:
            refreshWorkingRemaining(now: now)
            var effects = updateImminent()
            if remaining <= 0 {
                effects += beginBreak(countsAsSession: true, now: now)
            }
            return effects

        case .onBreak:
            guard !isFinishingBreak,
                let started = breakStartedAt,
                now.timeIntervalSince(started) >= TimerRules.breakGracePeriod
            else { return [] }

            // The countdown only starts once the overlay has faded in, so a 20
            // second break really is 20 seconds of visible time.
            if breakDeadline == nil {
                breakDeadline = TimerRules.deadline(from: now, seconds: remaining)
            }
            if let breakDeadline {
                remaining = TimerRules.remainingSeconds(deadline: breakDeadline, now: now)
            }
            guard remaining <= 0 else { return [] }
            isFinishingBreak = true
            skipStreak = 0
            return [.breakFinished]
        }
    }

    /// Called by the app once the fade-out after `.breakFinished` has finished.
    ///
    /// Guarded on `isFinishingBreak` *and* `phase`: during those 0.45 seconds a
    /// meeting can interrupt, the user can skip, or the machine can wake, and
    /// none of those should be overwritten by a stale callback.
    public mutating func finishBreak(now: Date) -> [SessionEffect] {
        guard isFinishingBreak else { return [] }
        isFinishingBreak = false
        guard phase == .onBreak else { return [] }
        return beginWork(seconds: config.workSeconds, now: now)
    }

    // MARK: - Away detection

    public mutating func screenLocked(now: Date) -> [SessionEffect] {
        guard config.pauseTrigger.pausesOnLock, phase == .working else { return [] }
        refreshWorkingRemaining(now: now)
        banked = remaining
        workDeadline = nil
        isImminent = false
        phase = .paused
        pauseCause = .locked
        return []
    }

    /// - Parameter isScreenLocked: the session's lock state *right now*.
    ///   Display wake fires before the unlock, so waking up is not enough.
    public mutating func screenUnlocked(isScreenLocked: Bool, now: Date) -> [SessionEffect] {
        guard phase == .paused, pauseCause == .locked else { return [] }
        if config.pauseTrigger.pausesOnLock && isScreenLocked { return [] }
        return beginWork(seconds: config.workSeconds, now: now)
    }

    public mutating func systemWake(now: Date) -> [SessionEffect] {
        switch phase {
        case .working:
            return beginWork(seconds: config.workSeconds, now: now)
        case .onBreak:
            return [.breakInterrupted(.wake)] + beginWork(seconds: config.workSeconds, now: now)
        case .paused:
            // A manual or lock pause survives sleep; the lock/unlock path owns
            // the decision to resume.
            return []
        }
    }

    public mutating func inputActivity(
        secondsSinceInput: TimeInterval,
        now: Date
    ) -> [SessionEffect] {
        guard config.pauseTrigger.pausesOnIdle else { return [] }

        if TimerRules.shouldPauseForIdle(
            secondsSinceInput: secondsSinceInput,
            trigger: config.pauseTrigger,
            isWorking: phase == .working
        ) {
            refreshWorkingRemaining(now: now)
            banked = remaining
            workDeadline = nil
            isImminent = false
            phase = .paused
            pauseCause = .idle
            return []
        }

        if phase == .paused, pauseCause == .idle,
            TimerRules.isBackFromIdle(secondsSinceInput: secondsSinceInput, trigger: config.pauseTrigger)
        {
            return beginWork(seconds: config.workSeconds, now: now)
        }
        return []
    }

    // MARK: - Meetings

    /// Meetings never pause a running work session (that is the point of the
    /// app: it stays out of the way), they only suppress or interrupt breaks.
    public mutating func meetingStatusChanged(
        isInMeeting: Bool,
        now: Date
    ) -> [SessionEffect] {
        self.isInMeeting = isInMeeting
        guard config.pauseDuringMeetings else { return [] }

        if isInMeeting {
            guard phase == .onBreak else { return [] }
            var effects = beginWork(seconds: config.workSeconds, now: now)
            banked = remaining
            workDeadline = nil
            phase = .paused
            pauseCause = .meeting
            effects.insert(.breakInterrupted(.meeting), at: 0)
            return effects
        }

        if phase == .paused, pauseCause == .breakPending {
            // The break was postponed; give the user a short countdown so the
            // overlay does not appear in the instant the call ends.
            return beginWork(seconds: config.postMeetingBreakDelay, now: now)
        }
        if phase == .paused, pauseCause == .meeting {
            return resumeManually(now: now)
        }
        return []
    }

    // MARK: - Settings

    /// Applies a new preference snapshot and reacts to the parts that change
    /// what is happening right now. One entry point on purpose: every setting
    /// that can strand the timer (pause trigger, meeting pausing, work length)
    /// has to be considered together, and splitting them into separate calls is
    /// how one of them gets forgotten.
    public mutating func configChanged(_ new: SessionConfig, now: Date) -> [SessionEffect] {
        let previous = config
        config = new
        var effects: [SessionEffect] = []

        if phase == .paused, previous.pauseTrigger != new.pauseTrigger {
            switch pauseCause {
            case .locked where !new.pauseTrigger.pausesOnLock:
                effects += beginWork(seconds: config.workSeconds, now: now)
                effects.append(.automaticPauseLifted(.locked))
            case .idle where !new.pauseTrigger.pausesOnIdle:
                effects += beginWork(seconds: config.workSeconds, now: now)
                effects.append(.automaticPauseLifted(.idle))
            default:
                break
            }
        }

        if previous.pauseDuringMeetings && !new.pauseDuringMeetings {
            isInMeeting = false
            if phase == .paused, pauseCause == .meeting || pauseCause == .breakPending {
                let lifted = pauseCause
                effects += beginWork(seconds: config.workSeconds, now: now)
                pauseCause = .manual
                effects.append(.automaticPauseLifted(lifted))
            }
        }

        if new.workSeconds != previous.workSeconds {
            if phase == .working {
                // Keep the remaining time but move its deadline to match, otherwise
                // the change would only take effect after the next full session.
                if remaining > new.workSeconds { remaining = new.workSeconds }
                workDeadline = TimerRules.deadline(from: now, seconds: remaining)
            } else if phase == .paused {
                // A paused session has banked its remaining time instead. The
                // cap has to apply there too: without it, pausing at 18:20 of
                // a 20 minute session and then shortening the interval to
                // 5 minutes would resume an 18 minute session — the free time
                // the running case explicitly refuses to hand out.
                if banked > new.workSeconds { banked = new.workSeconds }
            }
        }

        if phase == .working {
            effects += updateImminent()
        }
        return effects
    }

    // MARK: - Transitions

    /// A long absence is a reset, not a pause.
    ///
    /// `sessionsCompleted` used to only ever go up, so an app left running
    /// overnight — which is the normal case for a menu bar app with "launch at
    /// login" — carried yesterday's count into today: the long break could be
    /// due before the first short one. Time away starts a fresh cycle.
    ///
    /// `skipStreak` goes with it: the nudge is about someone skipping breaks
    /// *now*, and nobody wants to be told off for what they did before dinner.
    private mutating func resetRhythmIfStale(now: Date) {
        guard let lastActivityAt,
            now.timeIntervalSince(lastActivityAt) >= TimerRules.pomodoroResetAfterSeconds
        else { return }
        sessionsCompleted = 0
        skipStreak = 0
    }

    private mutating func beginWork(
        seconds: Int,
        now: Date,
        resetImminent: Bool = true
    ) -> [SessionEffect] {
        // Never longer than one full session: a resumed pause hands over its
        // banked time, and that time must not exceed the configured interval.
        let duration = min(max(0, seconds), config.workSeconds)
        resetRhythmIfStale(now: now)
        lastActivityAt = now
        isFinishingBreak = false
        isLongBreak = false
        activeBreakTotal = 0
        breakDeadline = nil
        breakStartedAt = nil
        remaining = duration
        workDeadline = TimerRules.deadline(from: now, seconds: duration)
        if resetImminent {
            isImminent = false
        }
        phase = .working
        return [.workSessionStarted(seconds: duration)]
    }

    private mutating func beginBreak(countsAsSession: Bool, now: Date) -> [SessionEffect] {
        lastActivityAt = now
        // The overlay would sit on top of the call; wait for it to end.
        if config.pauseDuringMeetings && isInMeeting {
            banked = 0
            workDeadline = nil
            isImminent = false
            phase = .paused
            pauseCause = .breakPending
            return [.breakDeferredToMeeting]
        }

        if countsAsSession {
            // Count only naturally completed work, not a manual "break now".
            sessionsCompleted += 1
        }
        // Deliberately does NOT reset `skipStreak`: clearing it when a break
        // starts would let the nudge be dodged and would lose the fact that the
        // user keeps skipping. It is cleared when a break is actually taken.
        isLongBreak =
            countsAsSession
            && TimerRules.isLongBreak(
                sessionsCompleted: sessionsCompleted,
                every: config.longBreakEvery
            )
        activeBreakTotal = TimerRules.breakTotalSeconds(
            isLong: isLongBreak,
            shortSeconds: config.shortBreakSeconds,
            longSeconds: config.longBreakSeconds
        )

        remaining = activeBreakTotal
        phase = .onBreak
        isFinishingBreak = false
        isImminent = false
        workDeadline = nil
        breakStartedAt = now
        breakDeadline =
            now
            .addingTimeInterval(TimerRules.breakGracePeriod)
            .addingTimeInterval(TimeInterval(activeBreakTotal))
        return [
            .breakStarted(
                isLong: isLongBreak,
                seconds: activeBreakTotal,
                manual: !countsAsSession
            )
        ]
    }

    private mutating func refreshWorkingRemaining(now: Date) {
        if workDeadline == nil {
            workDeadline = TimerRules.deadline(from: now, seconds: remaining)
        }
        guard let workDeadline else { return }
        remaining = TimerRules.remainingSeconds(deadline: workDeadline, now: now)
    }

    private mutating func updateImminent() -> [SessionEffect] {
        let imminent = TimerRules.isImminent(
            remaining: remaining,
            enabled: config.progressiveReminders,
            isWorking: phase == .working
        )
        var effects: [SessionEffect] = []
        if imminent && !isImminent {
            effects.append(.imminentReminder)
        }
        isImminent = imminent
        return effects
    }
}
