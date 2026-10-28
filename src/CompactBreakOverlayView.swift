import AppKit
import ICHRCore
import SwiftUI

struct CompactBreakOverlayView: View {
    @ObservedObject var timerManager: TimerManager
    @State private var breathe = false
    @State private var appeared = false
    @State private var ringProgress: CGFloat = 0
    // The panel is click-through, so unlike the full overlay the countdown is
    // never hidden — there would be no way to bring it back.

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        ZStack {
            // Dark tint over the window's blur material (added in OverlayManager)
            Color.black.opacity(0.3)

            VStack(spacing: 28) {
                // Progress ring with breathing animation
                ZStack {
                    // Outer breathing ring
                    Circle()
                        .stroke(.white.opacity(0.08), lineWidth: 2)
                        .frame(width: 140, height: 140)
                        .scaleEffect(breathe ? 1.1 : 0.9)

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
                        .frame(width: 115, height: 115)
                        .rotationEffect(.degrees(-90))

                    // Inner circle
                    Circle()
                        .fill(.white.opacity(0.05))
                        .frame(width: 100, height: 100)
                        .scaleEffect(breathe ? 1.04 : 0.97)

                    // Timer inside the ring
                    Text(TimerRules.formatTime(timerManager.remainingSeconds))
                        .font(.system(size: 30, weight: .light, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                        .contentTransition(.numericText())
                        .opacity(reduceMotion ? 1 : timerManager.graceProgress)
                        .animation(.easeOut(duration: 1), value: timerManager.graceProgress)
                }
                // Same treatment as the full overlay: the arc is decorative, the
                // remaining time is the information.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    timerManager.isLongBreak ? L10n.t(.longBreakTitle) : L10n.t(.timeToRest)
                )
                .accessibilityValue(
                    L10n.t(.timeRemaining, TimerRules.formatTime(timerManager.remainingSeconds))
                )

                VStack(spacing: 8) {
                    Text(timerManager.isLongBreak ? L10n.t(.longBreakTitle) : L10n.t(.timeToRest))
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .opacity(appeared ? 1 : 0)

                    Text(timerManager.breakTip.isEmpty ? L10n.t(.restHint) : timerManager.breakTip)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeInOut(duration: 0.4), value: timerManager.breakTip)
                }

                // The panel is click-through, so nothing here can be clicked.
                // This used to draw the same capsule as the full overlay's Skip
                // button, which read as a button that did nothing when pressed.
                // Plain text, one line, always: Escape is the only way out.
                Text(L10n.t(.escapeToDismiss))
                    .font(.system(size: 12, weight: .regular))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.32))
                    .opacity(appeared ? 1 : 0)

                // A nudge after repeated skips — advisory only, Escape works too.
                if timerManager.showsSkipHint {
                    Text(L10n.t(.skipHint))
                        .font(.system(size: 11, weight: .regular))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.3))
                        .opacity(appeared ? 1 : 0)
                }
            }
            .padding(40)
        }
        .frame(width: 360, height: 420)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
        .onAppear {
            if reduceMotion {
                breathe = true
            } else {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    breathe = true
                }
            }
            withAnimation(.easeOut(duration: 0.6)) {
                appeared = true
            }
            updateRingProgress()
        }
        .onChangeCompat(of: timerManager.remainingSeconds) {
            updateRingProgress()
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
