import SwiftUI

/// The app's prominent action button: an accent-filled capsule with a **black**
/// label.
///
/// The accent is light enough that white on it fails to read. Measured against
/// WCAG's 4.5:1 for body text:
///
/// | Accent | white label | black label |
/// |---|---|---|
/// | `#C64BD1` (light) | 3.94:1 | 5.33:1 |
/// | `#E48CF0` (dark) | 2.26:1 | 9.31:1 |
///
/// Black wins in both appearances, and in dark mode it is not close — 2.26 is
/// roughly half the threshold, which is why the label looked washed out on the
/// filled button before this.
///
/// Literal `.black`, not `Color(.systemBackground)`: the button is filled with
/// the accent in *both* appearances, so the label's job is to contrast with the
/// accent, not with the page behind it. `.systemBackground` would hand back
/// white in dark mode and reinstate exactly the problem above.
///
/// A whole `ButtonStyle` rather than `.borderedProminent` plus a colour, which
/// was the first attempt and does not work: `.borderedProminent` takes its
/// *fill* from the tint, and a `.foregroundStyle` applied to the button sets
/// that tint — so asking for a black label produced a black button with a black
/// label on it. The label colour is only reachable from inside the style.
struct ProminentActionButtonStyle: ButtonStyle {
    /// These give a 33pt-tall button against the 28pt `.borderedProminent`
    /// measured before it was replaced, so the three buttons using it grew
    /// slightly. Left that way deliberately: 28pt was already well under
    /// Apple's 44pt minimum touch target, and nothing around these buttons is
    /// tight enough for 5pt to matter.
    private static let verticalPadding: CGFloat = 5
    private static let horizontalPadding: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black)
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .background(Capsule().fill(Color.accentColor))
            // The system style dims on press; without this the button would be
            // the one control in the app that does not answer a finger.
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == ProminentActionButtonStyle {
    static var prominentAction: Self { ProminentActionButtonStyle() }
}
