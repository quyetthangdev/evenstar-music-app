import SwiftUI

/// The window's bottom safe-area inset — 34 on a phone with a home indicator,
/// 0 on one without.
///
/// Published by `RootView`, which measures it once, and read only by
/// `BottomBarClearanceModifier` below. It is in the environment rather than
/// passed as a parameter because two of the seven screens that need it —
/// `AlbumDetailView` and `ArtistDetailView` — are pushed destinations declared
/// inside `navigationDestination` closures, and a third, `SearchView`, takes no
/// bindings at all. The environment reaches all of them, and reaches the next
/// screen someone adds without that screen's author having to be told; a
/// parameter would have to be threaded through every closure by hand, and Đợt A
/// has already shipped a Critical defect from exactly that kind of omission.
///
/// The default is 0, not "unknown": that is the correct value for a device with
/// no home indicator, and it is the *safe* wrong answer everywhere else — it
/// yields the largest clearance, so a screen that somehow never receives the
/// real measurement leaves too much room rather than hiding its last row under
/// the bar.
private struct BottomSafeAreaInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var bottomSafeAreaInset: CGFloat {
        get { self[BottomSafeAreaInsetKey.self] }
        set { self[BottomSafeAreaInsetKey.self] = newValue }
    }
}

/// Keeps a scrolling screen's last row clear of the floating bottom stack.
///
/// One modifier rather than the same `safeAreaInset` block copied into seven
/// screens, for the same reason `minimisesBottomBar` is one modifier: the rule
/// is device-dependent now (see `BottomBarMetrics.clearanceTabBarOnly`), and
/// seven copies of a rule is seven places for it to be updated in six.
///
/// The height is measured from the safe area, because that is what
/// `.safeAreaInset(edge: .bottom)` measures from, while the bar it clears is
/// measured from the screen. `BottomBarMetrics` owns that conversion; nothing
/// here restates it.
private struct BottomBarClearanceModifier: ViewModifier {
    @Environment(PlaybackService.self) private var playback
    @Environment(\.bottomSafeAreaInset) private var bottomSafeAreaInset

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            Color.clear
                // Never 0 on a device with no home indicator, and never the
                // same number on two different devices: the floating tab bar is
                // always present, so the last row must clear it whether or not
                // a track is loaded. With a track the pill sits above the bar
                // and the clearance grows by the pill and its gap.
                .frame(
                    height: playback.currentTrack == nil
                        ? BottomBarMetrics.clearanceTabBarOnly(
                            bottomSafeAreaInset: bottomSafeAreaInset
                        )
                        : BottomBarMetrics.clearanceWithPlayer(
                            bottomSafeAreaInset: bottomSafeAreaInset
                        )
                )
                // The third piece of chrome that moves on this one event, and
                // the third that was moving on its own clock. A track starting
                // grows this by the pill plus its gap; the pill fades in over
                // `settle` and the blur band now does too, while this stepped
                // the whole list on a single frame.
                //
                // On the spacer, not on `content`: this is the only thing that
                // should animate. Putting it on the modified view would hand the
                // same curve to every row in the list for a change that is not
                // about them.
                .animation(BottomBarStyle.settle, value: playback.currentTrack == nil)
        }
    }
}

extension View {
    /// Leaves room at the bottom of this screen for the floating tab bar, and
    /// for the collapsed player above it whenever a track is loaded.
    ///
    /// Every screen that scrolls under the bottom bar needs this — the four tab
    /// roots, both pushed detail screens, and `SearchView`. Applying it is the
    /// whole obligation: the amount is not the screen's business, and a screen
    /// that computes its own would be wrong on half the devices in the lineup.
    func clearsBottomBar() -> some View {
        modifier(BottomBarClearanceModifier())
    }
}
