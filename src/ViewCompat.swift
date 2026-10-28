import SwiftUI

/// Shared compatibility shims for the two break overlays.
///
/// Both views shipped their own private copy of `onChangeCompat`, which meant a
/// fix (or a future macOS 14+ simplification) had to be made twice or the two
/// overlays silently diverged. They now share this one.
extension View {
    /// `onChange` gained a two-parameter closure in macOS 14; the deployment
    /// target is 13, so pick the right signature at runtime.
    @ViewBuilder
    func onChangeCompat<V: Equatable>(of value: V, perform action: @escaping () -> Void) -> some View {
        if #available(macOS 14.0, *) {
            self.onChange(of: value) { _, _ in action() }
        } else {
            self.onChange(of: value) { _ in action() }
        }
    }
}
