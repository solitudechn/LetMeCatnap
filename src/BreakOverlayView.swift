import AppKit
import SwiftUI
import ICHRCore

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
                                Color(red: 0.3, green: 0.4, blue: 0.9).opacity(0.15),
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
                                        Color(red: 0.4, green: 0.5, blue: 1.0).opacity(0.8),
                                        Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.6),
                                        Color(red: 0.4, green: 0.5, blue: 1.0).opacity(0.3),
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
                        Text(formatTime(timerManager.remainingSeconds))
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
                    .help(L10n.showRemaining)

                    VStack(spacing: 10) {
                        Text(timerManager.isLongBreak ? L10n.longBreakTitle : L10n.timeToRest)
                            .font(.system(size: 38, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 10)

                        Text(timerManager.breakTip.isEmpty ? L10n.restHint : timerManager.breakTip)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(.white.opacity(0.4))
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 8)
                            .animation(.easeInOut(duration: 0.4), value: timerManager.breakTip)

                        if !countdownVisible {
                            Text(L10n.showRemaining)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.white.opacity(0.18))
                                .opacity(appeared ? 1 : 0)
                        }
                    }

                    // A nudge after repeated skips — the break can still be
                    // skipped, this only makes the choice visible.
                    if timerManager.showsSkipHint {
                        Text(L10n.skipHint)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.white.opacity(0.3))
                            .opacity(appeared ? 1 : 0)
                    }

                    // Skip button
                    if timerManager.canSkipBreak {
                        Button(action: { timerManager.skipBreak() }) {
                            HStack(spacing: 10) {
                                Text(L10n.skip)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.5))
                                Text(L10n.skipKeys)
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
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
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

private extension View {
    @ViewBuilder
    func onChangeCompat<V: Equatable>(of value: V, perform action: @escaping () -> Void) -> some View {
        if #available(macOS 14.0, *) {
            self.onChange(of: value) { _, _ in action() }
        } else {
            self.onChange(of: value) { _ in action() }
        }
    }
}
