import SwiftUI

/// The app's prominent action button: a solid capsule with a label drawn in
/// the inverse of it.
///
/// **No longer tied to the accent colour.** It used to fill with
/// `Color.accentColor` and rely on a hardcoded `.black` label to stay
/// readable against the old purple-pink accent. The accent is white now
/// (design Part 2 item 5), and a white-filled capsule is invisible against
/// the light backgrounds this button actually sits on — `ContentUnavailableView`
/// actions, `.systemGroupedBackground` lists — whatever colour its label is.
///
/// `Color.primary`/`Color(.systemBackground)` sidesteps the whole class of
/// bug: the fill is always the *opposite* of the page behind it, in both
/// appearances, so the button can never colour-match its own background again.
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
            .foregroundStyle(Color(.systemBackground))
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .background(Capsule().fill(Color.primary))
            // The system style dims on press; without this the button would be
            // the one control in the app that does not answer a finger.
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == ProminentActionButtonStyle {
    static var prominentAction: Self { ProminentActionButtonStyle() }
}
