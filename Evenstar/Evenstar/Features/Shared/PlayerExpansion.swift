import SwiftUI

/// How far the player card has opened, 0 collapsed to 1 full screen.
///
/// A reference type rather than a `Binding` back to `RootView`, and that is the
/// whole point of the file.
///
/// The first version published this through a `@Binding` written from an
/// `onChange`. That cost two update passes per frame of a drag: the card's own
/// body ran, then `onChange` fired, then the write invalidated `RootView`, whose
/// body rebuilds the `TabView` and its five tabs for SwiftUI to diff. The recede
/// was visibly rough, and no amount of making the *effect* cheaper could fix it,
/// because the cost was not in the effect.
///
/// `@Observable` scopes the invalidation to whoever actually reads `progress` in
/// a body — here, one `ViewModifier` that applies a transform. `RootView`'s body
/// does not read it and so does not re-run, and the tab hierarchy is built once.
@Observable
final class PlayerExpansion {
    var progress: Double = 0 {
        didSet {
            let wanted = progress > Self.darkChromeThreshold
            // Compared before assigning. `@Observable` notifies on every write,
            // equal or not, so an unguarded assignment here would invalidate
            // whoever reads `prefersDarkChrome` on every frame of a drag —
            // which is the exact cost `progress` was made a reference type to
            // avoid, reintroduced one property along.
            if wanted != prefersDarkChrome { prefersDarkChrome = wanted }
        }
    }

    /// Whether the card covers enough of the screen that the whole window
    /// should be styled dark.
    ///
    /// A separate stored flag rather than a computed `progress > 0.5`, and the
    /// difference is not stylistic: a computed property would make its reader
    /// observe `progress` itself, and `progress` changes every frame.
    private(set) var prefersDarkChrome = false

    /// 0.5, and not the point the card actually reaches the status bar (~0.92).
    ///
    /// Later is where the status bar wants it, but the card's own colours change
    /// with the same switch, and at 0.92 the title and artist are at 83% opacity
    /// — the text would visibly change colour just before the card settled. At
    /// 0.5 `expandedContent`'s opacity is exactly 0, so nothing of the card's is
    /// on screen to be seen changing. The cost is the reverse: for the back half
    /// of the animation the white clock sits over the still-visible library. In
    /// dark mode that is invisible; in light mode it is about two tenths of a
    /// second, against a text colour change landing on a settled screen. The
    /// brief one wins.
    private static let darkChromeThreshold: Double = 0.5
}

/// Forces the whole window dark while the player is open, and applies the
/// user's own appearance choice the rest of the time.
///
/// **Both halves have to live in the same modifier, because
/// `preferredColorScheme` does not compose.** The first attempt set the app's
/// theme on `RootView` and the player's dark override inside `PlayerCard`,
/// assuming the deeper view would win. It does not: with an override at the
/// root, the expanded player rendered in light mode — black title and black
/// transport glyphs over the artwork, with the darkening gradient behind them.
/// Checked on screen, which is the only way that was ever going to be settled.
///
/// A `ViewModifier` rather than the modifier applied at the call site, for the
/// same reason `RecedeBehindPlayer` is one: only this body re-runs when the flag
/// flips, so `RootView` does not rebuild the `TabView` and its five tabs in the
/// middle of the expand animation.
private struct PlayerChromeScheme: ViewModifier {
    let expansion: PlayerExpansion
    let theme: AppTheme

    func body(content: Content) -> some View {
        content.preferredColorScheme(
            expansion.prefersDarkChrome ? .dark : theme.colorScheme
        )
    }
}

extension View {
    /// See `PlayerChromeScheme`. Applied once, at the root — a second
    /// `preferredColorScheme` anywhere inside will be ignored.
    func playerChromeScheme(_ expansion: PlayerExpansion, theme: AppTheme) -> some View {
        modifier(PlayerChromeScheme(expansion: expansion, theme: theme))
    }
}

/// Recedes content as the player opens, the way a sheet pushes its presenting
/// screen back.
///
/// The transform lives in a modifier rather than at the call site so that its
/// `body` — and nothing else — is what re-runs when `progress` changes.
///
/// Scale only. An earlier version also clipped to a rounded rectangle, which is
/// a mask and forces an offscreen pass over the whole screen every frame. If
/// the corners are wanted, round a static backdrop *behind* the content; do not
/// mask the content itself.
private struct RecedeBehindPlayer: ViewModifier {
    let expansion: PlayerExpansion

    func body(content: Content) -> some View {
        content.scaleEffect(
            1 - (1 - BottomBarStyle.recedeScale) * expansion.progress
        )
    }
}

extension View {
    func recedesBehindPlayer(_ expansion: PlayerExpansion) -> some View {
        modifier(RecedeBehindPlayer(expansion: expansion))
    }
}
