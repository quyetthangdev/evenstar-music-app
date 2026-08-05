import XCTest
import MediaPlayer
import UIKit
@testable import Evenstar

@MainActor
final class SystemVolumeSliderTests: XCTestCase {

    /// Builds the volume view the way SwiftUI would and drives it through a
    /// real layout pass, because `MPVolumeView` creates its `UISlider` lazily
    /// during layout — asking for it any earlier finds nothing.
    /// Builds the volume view the way SwiftUI would and drives it through a
    /// real layout pass, because `MPVolumeView` creates its slider lazily
    /// during layout — asking any earlier finds nothing.
    private func laidOutSlider() -> UISlider? {
        let view = TintedVolumeView(frame: CGRect(x: 0, y: 0, width: 300, height: 28))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        window.addSubview(view)
        window.isHidden = false
        view.setNeedsLayout()
        view.layoutIfNeeded()
        return Self.findSlider(in: view)
    }

    private static func findSlider(in view: UIView) -> UISlider? {
        for subview in view.subviews {
            if let slider = subview as? UISlider { return slider }
            if let found = findSlider(in: subview) { return found }
        }
        return nil
    }

    /// The simulator has no audio hardware, so `MPVolumeView` builds no slider
    /// there at all — its subtree is `[UILabel, MPButton]`. Skipping is honest
    /// where passing would be vacuous: these two assertions are real, and they
    /// run on a device.
    private func requireSlider() throws -> UISlider {
        guard let slider = laidOutSlider() else {
            throw XCTSkip("MPVolumeView builds no UISlider without audio hardware; run on a device")
        }
        return slider
    }

    /// The point of the whole exercise: the volume bar has to be as thick as
    /// the scrubber, and `UISlider`'s own track is about 4pt with no property
    /// to change it — only a track image can.
    func testTrackImageIsAsThickAsTheScrubber() throws {
        let slider = try requireSlider()

        let minimum = try XCTUnwrap(slider.currentMinimumTrackImage, "no minimum track image")
        let maximum = try XCTUnwrap(slider.currentMaximumTrackImage, "no maximum track image")

        XCTAssertEqual(minimum.size.height, ScrubberBar.restingHeight, accuracy: 0.01)
        XCTAssertEqual(maximum.size.height, ScrubberBar.restingHeight, accuracy: 0.01)
    }

    /// Painting `UIColor.label` into the bitmap would bake whichever appearance
    /// was current when the image was first built, leaving the bar the wrong
    /// colour after a switch to dark mode. A template image takes the slider's
    /// tint colours instead, which is what keeps it dynamic.
    func testTrackImageIsATemplateSoItFollowsTheAppearance() throws {
        let slider = try requireSlider()
        let minimum = try XCTUnwrap(slider.currentMinimumTrackImage)

        XCTAssertEqual(minimum.renderingMode, .alwaysTemplate)
    }

    /// One bitmap serves both ends of the bar by stretching from the middle.
    /// Without the caps it would squash the rounded ends into ellipses at one
    /// end and stretch them into a lozenge at the other.
    func testTrackImageStretchesFromItsMiddle() {
        let image = SystemVolumeSlider.trackImage
        XCTAssertEqual(image.capInsets.left, ScrubberBar.restingHeight / 2, accuracy: 0.01)
        XCTAssertEqual(image.capInsets.right, ScrubberBar.restingHeight / 2, accuracy: 0.01)
        XCTAssertEqual(image.resizingMode, UIImage.ResizingMode.stretch)
    }
}
