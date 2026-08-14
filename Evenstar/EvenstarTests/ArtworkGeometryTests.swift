import XCTest
@testable import Evenstar

/// The artwork's geometry across three states, as one pure function.
///
/// Bìa mở rộng giờ là **khối vuông ở giữa**, không còn tràn màn hình: cả ba
/// đích đều vuông, nên cú morph là một phép phóng to đều. Đó là thứ các
/// assertion dưới đây ghim. This change works by feeding an existing
/// expression a different number, and the whole claim is that the number is
/// unchanged at both ends. These assertions are what turn that claim into
/// something that fails out loud if it stops being true.
final class ArtworkGeometryTests: XCTestCase {

    /// An iPhone 17 at full expansion. `artworkSide` và `artworkTop` là fixture
    /// đứng thay đầu ra của công thức thật. `thumbCentre` is a *fixture*, not
    /// a measurement: it stands for wherever the header slot happens to be, and
    /// every assertion below is written against the value passed in rather than
    /// against a number this test claims to know. That is deliberate — pinning
    /// the real slot position here would make these tests fail every time the
    /// panel's padding changed, for a reason that has nothing to do with what
    /// they check.
    private let cardSize = CGSize(width: 402, height: 874)
    private let artworkSide: CGFloat = 354
    private let artworkTop: CGFloat = 96
    private let thumbCentre = CGPoint(x: 46, y: 81)
    private let thumbSide: CGFloat = 44


    private func geometry(progress: Double, queueFactor: Double,
                          fullBleed: Bool = false) -> PlayerCard.ArtworkGeometry {
        PlayerCard.artworkGeometry(
            progress: progress,
            queueFactor: queueFactor,
            cardSize: cardSize,
            fullBleed: fullBleed,
            artworkSide: artworkSide,
            artworkTop: artworkTop,
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

    func testTheExpandedCoverIsACentredSquare() {
        let g = geometry(progress: 1, queueFactor: 0)

        XCTAssertEqual(g.width, artworkSide, accuracy: 0.001)
        XCTAssertEqual(g.height, artworkSide, accuracy: 0.001, "vuông, không tràn")
        XCTAssertEqual(g.centre.x, cardSize.width / 2, accuracy: 0.001)
        XCTAssertEqual(g.centre.y, artworkTop + artworkSide / 2, accuracy: 0.001)
        XCTAssertEqual(g.shapeProgress, 1, accuracy: 0.001)
    }

    // MARK: - The path between the two ends

    /// **Vuông ở mọi điểm, và đó là toàn bộ bản sửa.**
    ///
    /// Bản trước nội suy bề rộng và chiều cao độc lập nhau, nên tỉ lệ khung
    /// trượt từ 1:1 sang ~0.78:1 suốt hành trình. Với `scaledToFill`, đổi tỉ lệ
    /// khung là đổi phần ảnh bị cắt — bức ảnh vừa lớn lên vừa tự zoom bên trong
    /// khung của nó. Hai chuyển động chồng nhau, và mắt đọc ra là bị kéo giãn.
    ///
    /// Vuông suốt thì chỉ còn một chuyển động: phóng to đều.
    func testTheCoverIsSquareAtEveryPointOfTheJourney() {
        for progress in stride(from: 0.0, through: 1.0, by: 0.1) {
            let g = geometry(progress: progress, queueFactor: 0)
            XCTAssertEqual(g.height, g.width, accuracy: 0.001,
                           "ở progress \(progress) bìa phải vuông")
        }
    }

    /// Bài **có** ảnh bìa thì đi đường kia: tràn ngang thẻ, cao 59%, tì vào
    /// mép trên. Hai chế độ, chọn theo `artworkRelativePath` của bài đang phát.
    func testACoverBearingTrackGoesFullBleedInstead() {
        let g = geometry(progress: 1, queueFactor: 0, fullBleed: true)

        XCTAssertEqual(g.width, cardSize.width, accuracy: 0.001)
        XCTAssertEqual(g.height, cardSize.height, accuracy: 0.001, "phủ cả chiều cao thẻ")
        XCTAssertEqual(g.centre.y, cardSize.height / 2, accuracy: 0.001)
    }

    /// Hai chế độ chỉ khác nhau ở đầu **mở**. Viên thuốc thu gọn là 36pt vuông
    /// ở cùng một chỗ, dù bài có bìa hay không — nếu không, đổi bài sẽ làm
    /// thumbnail nhảy.
    func testBothModesShareTheSameCollapsedThumbnail() {
        let square = geometry(progress: 0, queueFactor: 0, fullBleed: false)
        let bleed = geometry(progress: 0, queueFactor: 0, fullBleed: true)

        XCTAssertEqual(square.width, bleed.width, accuracy: 0.001)
        XCTAssertEqual(square.height, bleed.height, accuracy: 0.001)
        XCTAssertEqual(square.centre.x, bleed.centre.x, accuracy: 0.001)
        XCTAssertEqual(square.centre.y, bleed.centre.y, accuracy: 0.001)
    }

    /// Và vuông cả khi hàng đợi đang mở — ô trong header cũng là hình vuông.
    func testTheCoverStaysSquareWhileTheQueueOpens() {
        for factor in stride(from: 0.0, through: 1.0, by: 0.25) {
            let g = geometry(progress: 1, queueFactor: factor)
            XCTAssertEqual(g.height, g.width, accuracy: 0.001,
                           "ở queueFactor \(factor) bìa phải vuông")
        }
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

    // MARK: - The wiring between the destination point and the panel's own padding

    /// `queueThumbCentre(topInset:)` computes the point the artwork flies to;
    /// `queuePanelTop(topInset:)` computes the offset `QueuePanel`'s own
    /// `.padding(.top,)` actually applies. They must describe the same panel:
    /// the header sits at the very top of `QueuePanel`'s `VStack` with no
    /// further offset, so the point's y has to be exactly the panel's own
    /// top padding plus half the header artwork.
    ///
    /// This pins that *relationship*, not either side's value — pinning a
    /// value here would fail the moment the panel's padding changed, for
    /// reasons unrelated to what this checks (see the fixture note above).
    /// It is a different case from every other test in this file: those
    /// exercise the pure `artworkGeometry` arithmetic given an arbitrary
    /// fixture `thumbCentre`; this one exercises whether the two independent
    /// expressions that are supposed to produce that fixture in real life
    /// still agree with each other.
    func testQueueThumbCentreLandsOnThePanelsOwnTopPadding() {
        for topInset: CGFloat in [0, 47, 59] {
            let centre = PlayerCard.queueThumbCentre(topInset: topInset)
            let panelTop = PlayerCard.queuePanelTop(topInset: topInset)

            XCTAssertEqual(
                centre.y,
                panelTop + QueuePanel.headerArtwork / 2,
                accuracy: 0.001,
                "topInset \(topInset)"
            )
        }
    }
}
