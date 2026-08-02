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

    /// Marked deprecated to silence the deprecation on `showsRouteButton`,
    /// which iOS 13 retired in favour of `AVRoutePickerView`.
    /// `AVRoutePickerView` is a *separate control*, not a switch for this one's
    /// button, so the deprecated property is still the only way to hide it —
    /// and an AirPlay button here is out of scope. SwiftUI reaches this method
    /// through the protocol witness, so no call site inherits the deprecation.
    ///
    /// **The suppression is function-wide, not line-specific.** Any API
    /// deprecated in iOS 13 or earlier that is called anywhere in this body
    /// will also be silenced, and will pass the project's zero-warnings bar
    /// without anyone noticing. Check deliberately before adding calls here,
    /// and remove the attribute if `showsRouteButton` is ever dropped.
    @available(iOS, deprecated: 13.0, message: "See the note on this method.")
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        view.setVolumeThumbImage(Self.invisibleThumb, for: .normal)
        view.setVolumeThumbImage(Self.invisibleThumb, for: .highlighted)
        view.tintColor = .label
        Self.matchTrackColours(in: view)
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}

    /// A genuinely 1x1 transparent image. An empty `UIImage()` is not reliably
    /// honoured by `setVolumeThumbImage` across iOS versions — if a knob is
    /// still visible on device, this is the first thing to check.
    private static let invisibleThumb: UIImage = {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
    }()

    /// Tints the track to match `ScrubberBar`.
    ///
    /// This walks `MPVolumeView`'s subviews, which is undocumented — but only
    /// for colour. If Apple changes the hierarchy the slider keeps working and
    /// simply falls back to the system tint. That is deliberately different
    /// from driving the volume itself through the same traversal, which would
    /// fail silently and is why this design does not do it.
    private static func matchTrackColours(in view: MPVolumeView) {
        for subview in view.subviews {
            guard let slider = subview as? UISlider else { continue }
            slider.minimumTrackTintColor = .label
            slider.maximumTrackTintColor = UIColor.label.withAlphaComponent(0.25)
        }
    }
}
