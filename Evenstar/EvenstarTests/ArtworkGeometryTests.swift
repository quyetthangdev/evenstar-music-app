import XCTest
@testable import Evenstar

/// The artwork's geometry across three states, as one pure function.
///
/// The two that already shipped — the collapsed pill and the full-bleed cover —
/// matter more here than the new one. This change works by feeding an existing
/// expression a different number, and the whole claim is that the number is
/// unchanged at both ends. These assertions are what turn that claim into
/// something that fails out loud if it stops being true.
final class ArtworkGeometryTests: XCTestCase {

    /// An iPhone 17 at full expansion. `artworkHeight` is the real formula's
    /// output — `min(0.59 * 874, 874 - 120)`. `thumbCentre` is a *fixture*, not
    /// a measurement: it stands for wherever the header slot happens to be, and
    /// every assertion below is written against the value passed in rather than
    /// against a number this test claims to know. That is deliberate — pinning
    /// the real slot position here would make these tests fail every time the
    /// panel's padding changed, for a reason that has nothing to do with what
    /// they check.
    private let cardSize = CGSize(width: 402, height: 874)
    private let artworkHeight: CGFloat = 515.66
    private let thumbCentre = CGPoint(x: 46, y: 81)
    private let thumbSide: CGFloat = 44

    private func geometry(progress: Double, queueFactor: Double) -> PlayerCard.ArtworkGeometry {
        PlayerCard.artworkGeometry(
            progress: progress,
            queueFactor: queueFactor,
            cardSize: cardSize,
            artworkHeight: artworkHeight,
            queueThumbCentre: thumbCentre,
            queueThumbSide: thumbSide
        )
    }

    // MARK: - The two ends that already shipped

    func testTheCollapsedPillIsUnchangedByTheQueueFactor() {
        let withoutQueue = geometry(progress: 0, queueFactor: 0)
        let withQueue = geometry(progress: 0, queueFactor: 1)

        // The pill is not on screen while the queue is open, but the factor
        // must not reach it even so — an expression that changes the collapsed
        // state is an expression that will change it the day the two overlap.
        XCTAssertEqual(withoutQueue.width, withQueue.width, accuracy: 0.001)
        XCTAssertEqual(withoutQueue.height, withQueue.height, accuracy: 0.001)
        XCTAssertEqual(withoutQueue.centre.x, withQueue.centre.x, accuracy: 0.001)
        XCTAssertEqual(withoutQueue.centre.y, withQueue.centre.y, accuracy: 0.001)
        XCTAssertEqual(withoutQueue.shapeProgress, withQueue.shapeProgress, accuracy: 0.001)
    }

    func testTheCollapsedPillKeepsItsOwnSizeAndPlace() {
        let g = geometry(progress: 0, queueFactor: 0)

        XCTAssertEqual(g.width, 36, accuracy: 0.001, "collapsedArtwork")
        XCTAssertEqual(g.height, 36, accuracy: 0.001)
        XCTAssertEqual(g.centre.x, 36, accuracy: 0.001, "inset 18 + half of 36")
        XCTAssertEqual(g.centre.y, 27, accuracy: 0.001, "half of collapsedHeight 54")
        XCTAssertEqual(g.shapeProgress, 0, accuracy: 0.001, "rounded, no dissolve")
    }

    func testTheExpandedCoverIsFullBleedAndSquareCornered() {
        let g = geometry(progress: 1, queueFactor: 0)

        XCTAssertEqual(g.width, cardSize.width, accuracy: 0.001)
        XCTAssertEqual(g.height, artworkHeight, accuracy: 0.001)
        XCTAssertEqual(g.centre.x, cardSize.width / 2, accuracy: 0.001)
        XCTAssertEqual(g.centre.y, artworkHeight / 2, accuracy: 0.001)
        XCTAssertEqual(g.shapeProgress, 1, accuracy: 0.001, "square, dissolving")
    }

    // MARK: - The new end

    func testQueueOpenLandsExactlyOnTheHeaderSlot() {
        let g = geometry(progress: 1, queueFactor: 1)

        XCTAssertEqual(g.width, thumbSide, accuracy: 0.001)
        XCTAssertEqual(g.height, thumbSide, accuracy: 0.001)
        XCTAssertEqual(g.centre.x, thumbCentre.x, accuracy: 0.001)
        XCTAssertEqual(g.centre.y, thumbCentre.y, accuracy: 0.001)
    }

    /// The observation the whole design rests on: at queue-open the artwork
    /// must look like a thumbnail, and `shapeProgress == 0` is how the existing
    /// mask and corner-radius expressions already say that.
    func testQueueOpenLooksLikeAThumbnailNotLikeACover() {
        XCTAssertEqual(geometry(progress: 1, queueFactor: 1).shapeProgress, 0, accuracy: 0.001)
    }

    // MARK: - In between

    func testTheTransitionIsMonotonicInTheQueueFactor() {
        // Half-open must sit strictly between the two ends on every term, or
        // the artwork would double back on itself mid-animation.
        let open = geometry(progress: 1, queueFactor: 0)
        let half = geometry(progress: 1, queueFactor: 0.5)
        let queued = geometry(progress: 1, queueFactor: 1)

        XCTAssertTrue(queued.width < half.width && half.width < open.width)
        XCTAssertTrue(queued.height < half.height && half.height < open.height)
        XCTAssertTrue(queued.centre.y < half.centre.y && half.centre.y < open.centre.y)
        XCTAssertTrue(queued.shapeProgress < half.shapeProgress && half.shapeProgress < open.shapeProgress)
    }
}
