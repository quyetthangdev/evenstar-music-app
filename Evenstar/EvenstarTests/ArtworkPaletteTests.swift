import XCTest
import UIKit
@testable import Evenstar

/// `ArtworkStore.grid3x3` — the nine cell colours behind the expanded player's
/// animated background.
///
/// **These exist for the row order and almost nothing else.** A `CGBitmapContext`
/// puts its coordinate origin at the bottom left, which makes "row 0 is the
/// bottom of the picture" a very reasonable thing to believe; the first version
/// of `grid3x3` believed it, reversed the rows, and produced every cover upside
/// down. Nothing caught it. A colour field taken from an abstract cover looks
/// plausible either way up, the build was clean, and the rest of the suite was
/// green — it took a screenshot of a cover with a blue sky, and noticing the
/// blue had come out along the bottom of the screen.
///
/// So the fixtures below have a deliberate top and a deliberate bottom, and the
/// assertions name which is which.
final class ArtworkPaletteTests: XCTestCase {

    /// A square image whose top half is `top` and bottom half is `bottom`, built
    /// through `UIGraphicsImageRenderer` — i.e. in UIKit's top-down coordinates,
    /// the same way every real cover arrives.
    private func halved(top: UIColor, bottom: UIColor, side: CGFloat = 48) -> CGImage? {
        let size = CGSize(width: side, height: side)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            top.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side / 2))
            bottom.setFill()
            context.fill(CGRect(x: 0, y: side / 2, width: side, height: side / 2))
        }
        return image.cgImage
    }

    private func components(_ colour: UIColor) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        colour.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    func testReturnsNineColours() throws {
        let image = try XCTUnwrap(halved(top: .red, bottom: .blue))

        let palette = try XCTUnwrap(ArtworkStore.grid3x3(of: image))

        XCTAssertEqual(palette.count, 9)
    }

    /// The one that matters. Top of the picture must land in the first three
    /// entries, because that is the row `MeshGradient` draws at the top.
    func testTheTopOfThePictureComesFirst() throws {
        let image = try XCTUnwrap(halved(top: .red, bottom: .blue))

        let palette = try XCTUnwrap(ArtworkStore.grid3x3(of: image))

        for (index, colour) in palette.prefix(3).enumerated() {
            let rgb = components(colour)
            XCTAssertGreaterThan(
                rgb.r, rgb.b,
                "cell \(index) is in the top row and the top of the picture is red"
            )
        }
    }

    func testTheBottomOfThePictureComesLast() throws {
        let image = try XCTUnwrap(halved(top: .red, bottom: .blue))

        let palette = try XCTUnwrap(ArtworkStore.grid3x3(of: image))

        for (index, colour) in palette.suffix(3).enumerated() {
            let rgb = components(colour)
            XCTAssertGreaterThan(
                rgb.b, rgb.r,
                "cell \(index + 6) is in the bottom row and the bottom of the picture is blue"
            )
        }
    }

    /// Left-to-right has the same trap as top-to-bottom and is cheaper to rule
    /// out than to argue about.
    func testColumnsRunLeftToRight() throws {
        let side: CGFloat = 48
        let image = try XCTUnwrap(
            UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: side / 2, height: side))
                UIColor.blue.setFill()
                context.fill(CGRect(x: side / 2, y: 0, width: side / 2, height: side))
            }.cgImage
        )

        let palette = try XCTUnwrap(ArtworkStore.grid3x3(of: image))

        let leftmost = components(palette[3])
        let rightmost = components(palette[5])
        XCTAssertGreaterThan(leftmost.r, leftmost.b, "the left of the picture is red")
        XCTAssertGreaterThan(rightmost.b, rightmost.r, "the right of the picture is blue")
    }

    /// The saturation lift must not turn a grey cover coloured — a monochrome
    /// sleeve should stay monochrome rather than acquiring a hue out of
    /// rounding noise.
    func testAGreyCoverStaysGrey() throws {
        let image = try XCTUnwrap(halved(top: .darkGray, bottom: .lightGray))

        let palette = try XCTUnwrap(ArtworkStore.grid3x3(of: image))

        for colour in palette {
            let rgb = components(colour)
            XCTAssertEqual(rgb.r, rgb.g, accuracy: 0.02)
            XCTAssertEqual(rgb.g, rgb.b, accuracy: 0.02)
        }
    }

    /// White text is drawn over this field. A cover that averages to near-white
    /// must be pulled down before it gets there.
    func testAWhiteCoverIsCappedBelowFullBrightness() throws {
        let image = try XCTUnwrap(halved(top: .white, bottom: .white))

        let palette = try XCTUnwrap(ArtworkStore.grid3x3(of: image))

        for colour in palette {
            var brightness: CGFloat = 0
            var hue: CGFloat = 0, saturation: CGFloat = 0, alpha: CGFloat = 0
            colour.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            XCTAssertLessThanOrEqual(brightness, 0.9)
        }
    }
}
