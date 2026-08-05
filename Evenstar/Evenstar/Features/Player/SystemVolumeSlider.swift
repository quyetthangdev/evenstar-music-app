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
        CGSize(
            width: proposal.width ?? uiView.intrinsicContentSize.width,
            height: ScrubberBar.touchHeight
        )
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
    /// A capsule as thick as `ScrubberBar`'s resting bar, so the two controls
    /// read as the same kind of thing rather than one being a hairline next to
    /// the other. `UISlider`'s own track is about 4pt and cannot be resized any
    /// other way.
    ///
    /// Rendered as a **template** image, deliberately. Painting `UIColor.label`
    /// into the bitmap would bake whichever appearance was current at launch
    /// and leave the bar the wrong colour after a switch to dark mode; a
    /// template takes `minimumTrackTintColor`/`maximumTrackTintColor` instead,
    /// which `TintedVolumeView` keeps dynamic.
    ///
    /// One image serves both ends: the caps make it stretch from the middle, so
    /// the same bitmap draws a short filled section and a long unfilled one.
    static let trackImage: UIImage = {
        let side = ScrubberBar.restingHeight
        let size = CGSize(width: side, height: side)
        let capsule = UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.black.setFill()
            UIBezierPath(
                roundedRect: CGRect(origin: .zero, size: size),
                cornerRadius: side / 2
            ).fill()
        }
        return capsule
            .resizableImage(
                withCapInsets: UIEdgeInsets(top: 0, left: side / 2, bottom: 0, right: side / 2),
                resizingMode: .stretch
            )
            .withRenderingMode(.alwaysTemplate)
    }()

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
/// Internal rather than private so `SystemVolumeSliderTests` can build one and
/// ask the slider what it ended up with. The alternative was leaving the track
/// thickness as an unverifiable claim: `MPVolumeView` draws nothing in the
/// simulator, so no screenshot can show it, and the first attempt at this —
/// through `MPVolumeView`'s own image setters — silently did nothing on device.
final class TintedVolumeView: MPVolumeView {
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let slider = Self.findSlider(in: self) else { return }
        slider.minimumTrackTintColor = .label
        slider.maximumTrackTintColor = UIColor.label.withAlphaComponent(0.25)
        // On the slider itself, not through
        // `MPVolumeView.setMinimum/MaximumVolumeSliderImage`. Those were tried
        // first and had no visible effect on device — which the simulator
        // could not have shown either way, since `MPVolumeView` draws nothing
        // there. `UISlider`'s own setters do land.
        slider.setMinimumTrackImage(SystemVolumeSlider.trackImage, for: .normal)
        slider.setMaximumTrackImage(SystemVolumeSlider.trackImage, for: .normal)
    }

    /// Searches the whole subtree, not just the direct children.
    ///
    /// The direct-children version silently found nothing. It was written when
    /// only the tint went through here, and the tint appeared to work anyway —
    /// `tintColor` on the outer view reaches the slider on its own, so the walk
    /// contributed nothing and no one noticed it was dead. The track image has
    /// no such fallback, which is what finally exposed it.
    ///
    /// A dump of `subviews` in a unit test shows `[UILabel, MPButton]` in the
    /// simulator, where there is no audio hardware and so no slider at all.
    /// Where a slider does exist, nothing documents how deep it sits, so this
    /// does not assume.
    private static func findSlider(in view: UIView) -> UISlider? {
        for subview in view.subviews {
            if let slider = subview as? UISlider { return slider }
            if let found = findSlider(in: subview) { return found }
        }
        return nil
    }
}
