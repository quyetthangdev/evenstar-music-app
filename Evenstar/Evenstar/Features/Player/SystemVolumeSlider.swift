import MediaPlayer
import SwiftUI
import UIKit

/// The system volume control.
///
/// iOS gives no way to set system volume from SwiftUI —
/// `AVAudioSession.outputVolume` is read-only, and `MPVolumeView` is the only
/// sanctioned route. Using Apple's own control means it stays in sync with the
/// hardware buttons and with AirPlay routing for free.
///
/// Note: `MPVolumeView` renders **nothing in the simulator**. Empty space there
/// is expected, not a bug.
struct SystemVolumeSlider: UIViewRepresentable {

    /// `showsRouteButton` was deprecated by iOS 13 in favour of
    /// `AVRoutePickerView`, but it is still the only way to hide this
    /// button: `AVRoutePickerView` is a *separate control*, not a switch for
    /// this one's, and an AirPlay button here is out of scope.
    ///
    /// **The suppression below is function-wide, not line-specific.** Any
    /// other API deprecated in iOS 13 or earlier that gets called anywhere
    /// in this body will also be silenced, and will pass the project's
    /// zero-warnings bar without anyone noticing. Check deliberately before
    /// adding calls here, and remove the attribute if `showsRouteButton` is
    /// ever dropped.
    ///
    /// KVC (`view.setValue(false, forKey: "showsRouteButton")`) was
    /// considered as an alternative that avoids the attribute entirely, and
    /// rejected: it turns a compile-time-checked property access into an
    /// unchecked string key, so if Apple ever removes `showsRouteButton`
    /// this call would fail to compile today but would crash at runtime —
    /// `NSUnknownKeyException`, on a user's device, in the exact screen
    /// they opened to change the volume — under KVC. A silenced warning,
    /// caught by the human reviewing this file, is the safer failure mode
    /// than a crash caught by a user.
    @available(iOS, deprecated: 13.0, message: "showsRouteButton is the only way to hide MPVolumeView's route button; AVRoutePickerView is a separate control, not a switch for this one.")
    func makeUIView(context: Context) -> MPVolumeView {
        let view = TintedVolumeView(frame: .zero)
        view.showsRouteButton = false
        view.setVolumeThumbImage(Self.invisibleThumb, for: .normal)
        view.setVolumeThumbImage(Self.invisibleThumb, for: .highlighted)
        view.tintColor = .label
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}

    /// Takes the intrinsic size out of the width decision entirely.
    ///
    /// `.frame(maxWidth: .infinity)` at the call site cannot change a wrapped
    /// `UIView`'s width: the modifier absorbs whatever width is proposed to it
    /// into its own reported size and proposes that *same* width to its
    /// child, so the representable receives an identical proposal whether or
    /// not the modifier is present. If the representable then reports a
    /// narrow intrinsic size, the narrow view is simply centred inside a
    /// full-width slot instead of inside a full-width `VStack` — visually
    /// identical, and the width question stays unanswered either way.
    /// Implementing `sizeThatFits` sidesteps that: it hands back the proposed
    /// width directly, so no absorb-and-repropose step is involved.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MPVolumeView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: 44)
    }

    /// A 30x30 transparent image. An empty `UIImage()` is not reliably
    /// honoured by `setVolumeThumbImage` across iOS versions — if a knob is
    /// still visible on device, this is the first thing to check.
    ///
    /// It must not shrink back to 1x1: `UISlider` only begins tracking a
    /// touch that lands inside the thumb rect, and that rect derives from
    /// the thumb image's size. A 1x1 image gives a roughly 1pt grab target
    /// across a control this wide — nothing is drawn either way, since the
    /// image itself is invisible, so there is no size at which 1x1 is
    /// better and 30x30 costs nothing visually.
    private static let invisibleThumb: UIImage = {
        UIGraphicsImageRenderer(size: CGSize(width: 30, height: 30)).image { _ in }
    }()
}

/// Tints the track to match `ScrubberBar`, after layout instead of at
/// `makeUIView` time.
///
/// `MPVolumeView` builds its internal `UISlider` lazily, during layout — at
/// `makeUIView` time `subviews` is very likely still empty, so a walk done
/// there silently finds nothing. `layoutSubviews` runs after that slider
/// exists, and runs again any time the hierarchy changes, so the walk stays
/// correct even if Apple alters when or how the slider is built.
///
/// The walk itself is still undocumented — but only for colour. If Apple
/// changes the hierarchy the slider keeps working and simply falls back to
/// the system tint (`tintColor` on the outer view still reaches the minimum
/// track). That is deliberately different from driving the volume itself
/// through the same traversal, which would fail silently and is why this
/// design does not do it.
private final class TintedVolumeView: MPVolumeView {
    override func layoutSubviews() {
        super.layoutSubviews()
        for case let slider as UISlider in subviews {
            slider.minimumTrackTintColor = .label
            slider.maximumTrackTintColor = UIColor.label.withAlphaComponent(0.25)
        }
    }
}
