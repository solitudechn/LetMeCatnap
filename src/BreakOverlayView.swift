import AppKit
import CatnapCore
import SwiftUI

struct BreakOverlayView: View {
    @ObservedObject var timerManager: TimerManager
    let isPrimary: Bool
    @State private var breathe = false
    @State private var appeared = false
    @State private var ringProgress: CGFloat = 0
    /// The countdown is only shown for a few seconds: a break screen whose
    /// centrepiece is a ticking number invites you to stare at the screen,
    /// which is the opposite of what a break is for.
    @State private var countdownVisible = true
    @State private var revealTick = 0

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Long breaks get a different accent, so the screen reads differently
    /// before you have focused on any text. A 30 second break and a 15 minute
    /// one used to look identical apart from one word in the headline, which is
    /// exactly the word you cannot read when you are half awake.
    private var accent: (primary: Color, secondary: Color) {
        timerManager.isLongBreak
            ? (
                primary: Color(red: 0.32, green: 0.82, blue: 0.70),
                secondary: Color(red: 0.55, green: 0.90, blue: 0.62)
            )
            : (
                primary: Color(red: 0.40, green: 0.50, blue: 1.00),
                secondary: Color(red: 0.60, green: 0.40, blue: 1.00)
            )
    }

    /// "Long break · 15 分钟" — the type and the length, in one glance.
    private var typeLabel: String {
        L10n.breakTypeLabel(
            isLong: timerManager.isLongBreak,
            seconds: timerManager.currentBreakTotalSeconds
        )
    }

    var body: some View {
        ZStack {
            // Blurred dark background — semi-transparent
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)

            if isPrimary {
                // Ambient glow behind the content
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                accent.primary.opacity(0.15),
                                Color.clear,
                            ],
                            center: .center,
                            startRadius: 40,
                            endRadius: 350
                        )
                    )
                    .frame(width: 700, height: 700)
                    .scaleEffect(breathe ? 1.1 : 0.9)
                    .blur(radius: 60)

                VStack(spacing: 40) {
                    Spacer()

                    // Progress ring with breathing animation
                    ZStack {
                        // Outer breathing ring
                        Circle()
                            .stroke(.white.opacity(0.06), lineWidth: 2)
                            .frame(width: 180, height: 180)
                            .scaleEffect(breathe ? 1.12 : 0.92)

                        // Progress ring
                        Circle()
                            .trim(from: 0, to: ringProgress)
                            .stroke(
                                AngularGradient(
                                    colors: [
                                        accent.primary.opacity(0.8),
                                        accent.secondary.opacity(0.6),
                                        accent.primary.opacity(0.3),
                                    ],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .frame(width: 150, height: 150)
                            .rotationEffect(.degrees(-90))

                        // Inner circle
                        Circle()
                            .fill(.white.opacity(0.04))
                            .frame(width: 130, height: 130)
                            .scaleEffect(breathe ? 1.05 : 0.97)

                        // Timer inside the ring
                        Text(TimerRules.formatTime(timerManager.remainingSeconds))
                            .font(.system(size: 38, weight: .light, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                            .contentTransition(.numericText())
                            .opacity(reduceMotion ? 1 : timerManager.graceProgress)
                            .animation(.easeOut(duration: 1), value: timerManager.graceProgress)
                    }
                    .opacity(countdownVisible ? 1 : 0.16)
                    .scaleEffect(countdownVisible ? 1 : 0.9)
                    .animation(.easeInOut(duration: 0.7), value: countdownVisible)
                    .contentShape(Circle())
                    .onTapGesture { revealTick += 1 }
                    .help(L10n.t(.showRemaining))
                    // The ring is a progress arc: VoiceOver gets the remaining
                    // time as a value instead of trying to describe the shape.
                    // It stays readable after the digits fade out visually.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(typeLabel)
                    .accessibilityValue(
                        L10n.t(.timeRemaining, TimerRules.formatTime(timerManager.remainingSeconds))
                    )
                    .accessibilityHint(L10n.t(.showRemaining))
                    .accessibilityAddTraits(.isButton)

                    VStack(spacing: 10) {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(accent.primary)
                                .frame(width: 6, height: 6)
                            Text(typeLabel)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.white.opacity(0.07)))
                        .overlay(Capsule().stroke(accent.primary.opacity(0.45), lineWidth: 0.5))
                        .opacity(appeared ? 1 : 0)
                        .padding(.bottom, 2)
                        // The ring already announces the type and the time left;
                        // reading the same words twice makes VoiceOver chatter.
                        .accessibilityHidden(true)

                        Text(timerManager.isLongBreak ? L10n.t(.longBreakTitle) : L10n.t(.timeToRest))
                            .font(.system(size: 38, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 10)

                        Text(timerManager.breakTip.isEmpty ? L10n.t(.restHint) : timerManager.breakTip)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(.white.opacity(0.4))
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 8)
                            .animation(.easeInOut(duration: 0.4), value: timerManager.breakTip)

                        if !countdownVisible {
                            Text(L10n.t(.showRemaining))
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.white.opacity(0.18))
                                .opacity(appeared ? 1 : 0)
                        }
                    }

                    // A nudge after repeated skips — the break can still be
                    // skipped, this only makes the choice visible.
                    if timerManager.showsSkipHint {
                        Text(L10n.t(.skipHint))
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.white.opacity(0.3))
                            .opacity(appeared ? 1 : 0)
                    }

                    // Skip button
                    if timerManager.showsSkipButton {
                        Button(action: { timerManager.skipBreak() }) {
                            HStack(spacing: 10) {
                                Text(L10n.t(.skip))
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.5))
                                Text(L10n.t(.skipKeys))
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.25))
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 10)
                            .background(.white.opacity(0.08), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .opacity(appeared ? 1 : 0)
                        .accessibilityLabel(L10n.t(.skip))
                        .accessibilityHint(L10n.t(.skipKeys))
                        .onHover { hovering in
                            // `set` rather than `push`/`pop`: the panel can be
                            // dismissed while the pointer is still over the
                            // button, in which case `onHover(false)` never runs
                            // and a pushed cursor would stick for the whole
                            // system.
                            (hovering ? NSCursor.pointingHand : NSCursor.arrow).set()
                        }
                    } else {
                        // The button can be hidden, but Escape always ends the
                        // break — without this the full-screen overlay would
                        // look like a dead end.
                        Text(L10n.t(.escapeToDismiss))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.white.opacity(0.3))
                            .opacity(appeared ? 1 : 0)
                    }

                    Spacer()
                }
            }
        }
        .onAppear {
            if reduceMotion {
                breathe = true
            } else {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    breathe = true
                }
            }
            withAnimation(.easeOut(duration: 0.8)) {
                appeared = true
            }
            updateRingProgress()
        }
        .onChangeCompat(of: timerManager.remainingSeconds) {
            updateRingProgress()
        }
        // Show the countdown briefly on entry (and whenever the user taps the
        // ring), then let it recede so the guidance line is what you look at.
        .task(id: revealTick) {
            countdownVisible = true
            try? await Task.sleep(
                nanoseconds: UInt64(TimerRules.countdownVisibleSeconds * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.7)) {
                countdownVisible = false
            }
        }
    }

    private func updateRingProgress() {
        let total = CGFloat(timerManager.currentBreakTotalSeconds)
        let remaining = CGFloat(timerManager.remainingSeconds)
        let progress = total > 0 ? (total - remaining) / total : 0
        if reduceMotion {
            ringProgress = progress
        } else {
            withAnimation(.linear(duration: 1)) {
                ringProgress = progress
            }
        }
    }
}
