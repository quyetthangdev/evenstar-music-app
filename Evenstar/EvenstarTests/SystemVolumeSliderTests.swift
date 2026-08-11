import XCTest
import MediaPlayer
import UIKit
@testable import Evenstar

@MainActor
final class SystemVolumeSliderTests: XCTestCase {

    /// Builds the volume view the way SwiftUI would and drives it through a
    /// real layout pass, because `MPVolumeView` creates its slider lazily
    /// during layout — asking any earlier finds nothing.
    private func laidOut() -> (TintedVolumeView, UISlider?) {
        let view = TintedVolumeView(
            frame: CGRect(x: 0, y: 0, width: 300, height: ScrubberBar.touchHeight)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        window.addSubview(view)
        window.isHidden = false
        view.setNeedsLayout()
        view.layoutIfNeeded()
        return (view, Self.findSlider(in: view))
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
    /// where passing would be vacuous: these assertions are real, and they run
    /// on a device.
    private func requireSlider() throws -> (TintedVolumeView, UISlider) {
        let (view, slider) = laidOut()
        guard let slider else {
            throw XCTSkip("MPVolumeView builds no UISlider without audio hardware; run on a device")
        }
        return (view, slider)
    }

    /// The point of the whole exercise: the volume bar has to be as thick as
    /// the scrubber, and `UISlider`'s own track is about 4pt with no property
    /// to change it — only a track image can.
    func testTrackImagesAreAsThickAsTheScrubber() throws {
        let (_, slider) = try requireSlider()

        let minimum = try XCTUnwrap(slider.currentMinimumTrackImage, "no minimum track image")
        let maximum = try XCTUnwrap(slider.currentMaximumTrackImage, "no maximum track image")

        XCTAssertEqual(minimum.size.height, ScrubberBar.restingHeight, accuracy: 0.01)
        XCTAssertEqual(maximum.size.height, ScrubberBar.restingHeight, accuracy: 0.01)
    }

    /// Without this the bar is a solid block and the current volume cannot be
    /// read off it — which is what shipped once, because `UISlider` tints a
    /// track *image* with `tintColor` rather than with `minimumTrackTintColor`
    /// and `maximumTrackTintColor`, so a single template image came out the
    /// same colour at both ends.
    func testTheTwoEndsOfTheTrackAreDrawnDifferently() throws {
        let (_, slider) = try requireSlider()

        let minimum = try XCTUnwrap(slider.currentMinimumTrackImage)
        let maximum = try XCTUnwrap(slider.currentMaximumTrackImage)

        XCTAssertNotEqual(
            minimum.pngData(),
            maximum.pngData(),
            "the filled and unfilled halves must not be the same bitmap"
        )
    }

    /// `MPVolumeView` lays its slider out against its own idea of the row
    /// rather than the height this view reports, which left the bar sitting
    /// above the speaker glyphs either side of it.
    func testTheSliderIsCentredInTheRow() throws {
        let (view, slider) = try requireSlider()

        XCTAssertEqual(slider.frame.midY, view.bounds.midY, accuracy: 0.5)
    }

    /// One bitmap serves both ends of the bar by stretching from the middle.
    /// Without the caps it would squash the rounded ends into ellipses at one
    /// end and stretch them into a lozenge at the other.
    ///
    /// Runs everywhere — it asks the image directly and needs no slider.
    func testTrackImageStretchesFromItsMiddle() {
        let image = SystemVolumeSlider.trackImage(color: .label)

        XCTAssertEqual(image.size.height, ScrubberBar.restingHeight, accuracy: 0.01)
        XCTAssertEqual(image.capInsets.left, ScrubberBar.restingHeight / 2, accuracy: 0.01)
        XCTAssertEqual(image.capInsets.right, ScrubberBar.restingHeight / 2, accuracy: 0.01)
        XCTAssertEqual(image.resizingMode, UIImage.ResizingMode.stretch)
    }

    /// The colour is baked into the bitmap rather than taken from a tint, so
    /// two different colours have to produce two different images — which is
    /// what the dark-mode rebuild in `layoutSubviews` relies on.
    func testTrackImageColourReachesTheBitmap() {
        let opaque = SystemVolumeSlider.trackImage(color: UIColor.black)
        let faded = SystemVolumeSlider.trackImage(color: UIColor.black.withAlphaComponent(0.25))

        XCTAssertNotEqual(opaque.pngData(), faded.pngData())
    }

    // MARK: - Touch response (design Part 2 item 4)

    func testTrackImageAcceptsACustomHeight() {
        let image = SystemVolumeSlider.trackImage(color: .label, height: 12)

        XCTAssertEqual(image.size.height, 12, accuracy: 0.01)
        XCTAssertEqual(image.capInsets.left, 6, accuracy: 0.01)
        XCTAssertEqual(image.capInsets.right, 6, accuracy: 0.01)
    }

    func testTouchDownSwellsTheTrackToTheActiveHeight() throws {
        let (_, slider) = try requireSlider()

        slider.sendActions(for: .touchDown)

        let minimum = try XCTUnwrap(slider.currentMinimumTrackImage)
        XCTAssertEqual(minimum.size.height, ScrubberBar.activeHeight, accuracy: 0.01)
    }

    func testReleasingRestoresTheRestingHeight() throws {
        let (_, slider) = try requireSlider()
        slider.sendActions(for: .touchDown)

        slider.sendActions(for: .touchUpInside)

        let minimum = try XCTUnwrap(slider.currentMinimumTrackImage)
        XCTAssertEqual(minimum.size.height, ScrubberBar.restingHeight, accuracy: 0.01)
    }

    func testTouchDownFiresTheCallbackExactlyOnce() throws {
        let view = TintedVolumeView(
            frame: CGRect(x: 0, y: 0, width: 300, height: ScrubberBar.touchHeight)
        )
        var fireCount = 0
        view.onTouchDown = { fireCount += 1 }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        window.addSubview(view)
        window.isHidden = false
        view.setNeedsLayout()
        view.layoutIfNeeded()
        guard let slider = Self.findSlider(in: view) else {
            throw XCTSkip("MPVolumeView builds no UISlider without audio hardware; run on a device")
        }

        slider.sendActions(for: .touchDown)
        slider.sendActions(for: .touchDown) // a second down without a release in between

        XCTAssertEqual(fireCount, 1, "one press must fire the callback once, not once per event")
    }
}
