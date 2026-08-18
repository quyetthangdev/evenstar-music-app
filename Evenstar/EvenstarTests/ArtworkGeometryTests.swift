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
/// `@MainActor` like every other test class here. The helpers under test are
/// statics on a `View`, which `InferIsolatedConformances` makes main-actor
/// isolated, so a nonisolated test cannot call them under Swift 6. Nothing
/// about how these run changes — `XCTestCase` already runs them on the main
/// thread; the annotation only writes that down.
@MainActor
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

    // MARK: - Bìa phủ hết bề rộng thẻ, và phủ sớm

    /// Bề rộng thẻ ở một `progress`, đúng như `card(size:insets:)` dựng nó:
    /// lề thu gọn mỗi bên, nhân `(1 - progress)`. Ở đây để cú quét dưới không
    /// kiểm một tình huống không có thật — trong app `cardSize.width` **đổi
    /// theo `progress`**, nó không phải hằng số.
    private func cardWidth(at progress: Double, sideMargin: CGFloat) -> CGFloat {
        cardSize.width - 2 * sideMargin * (1 - progress)
    }

    /// **Bất biến bản sửa này tồn tại để tạo ra.**
    ///
    /// Trước đó `width` bò từ 36pt trong khi thẻ đã rộng ~92% ngay ở
    /// `progress == 0`, nên suốt gần cả cú bung còn một dải hở bên phải và chữ
    /// của danh sách phía dưới đọc được xuyên qua đó. Đo trên video bản
    /// Release: ở `progress` 0,69 bìa mới phủ 72%.
    ///
    /// Hai nửa, và **cả hai đều cần**:
    ///
    ///   - Từ `artworkWidthCatchUp` trở đi, `centre.x ± width/2` phủ **trọn**
    ///     `[0, cardWidth]`. Đây là thứ dải hở không còn sống sót qua được.
    ///   - Trước đó, nó **không tràn** ra ngoài `[0, cardWidth]`. Đây là cái
    ///     bẫy: tăng tốc riêng `width` mà để `centre.x` tuyến tính thì ở
    ///     `progress` 0,3 dải phủ chạy từ −103,5 tới 264,1 — tràn trái và
    ///     **vẫn** hở phải. Nửa trên một mình sẽ cho bản sửa hỏng ấy đi qua.
    ///
    /// Quét dày (bước 0,02) chứ không lấy vài điểm: ngưỡng là một chỗ gãy của
    /// hàm, và lấy thưa thì đúng chỗ gãy là chỗ dễ nhảy qua nhất.
    ///
    /// Ba bề rộng lề: 21 là viên thuốc ở trạng thái nghỉ, 76 là lúc thu nhỏ
    /// (thẻ hẹp hơn nhiều), 0 là biên. Dạng đóng của hai mép không phụ thuộc
    /// `cardWidth`, và ba giá trị này là cách nói điều đó ra thành số.
    func testTheFullBleedCoverOwnsTheWholeCardWidthFromTheCatchUpOnward() {
        for sideMargin: CGFloat in [0, 21, 76] {
            for step in stride(from: 0, through: 50, by: 1) {
                let progress = Double(step) / 50
                let width = cardWidth(at: progress, sideMargin: sideMargin)
                let g = PlayerCard.artworkGeometry(
                    progress: progress,
                    queueFactor: 0,
                    cardSize: CGSize(width: width, height: cardSize.height),
                    fullBleed: true,
                    artworkSide: artworkSide,
                    artworkTop: artworkTop,
                    queueThumbCentre: thumbCentre,
                    queueThumbSide: thumbSide
                )
                let leading = g.centre.x - g.width / 2
                let trailing = g.centre.x + g.width / 2
                let where_ = "lề \(sideMargin), progress \(progress)"

                XCTAssertGreaterThanOrEqual(
                    leading, -0.001,
                    "tràn trái \(-leading)pt ra ngoài mép thẻ — \(where_)"
                )
                XCTAssertLessThanOrEqual(
                    trailing, width + 0.001,
                    "tràn phải \(trailing - width)pt ra ngoài mép thẻ — \(where_)"
                )

                guard progress >= PlayerCard.artworkWidthCatchUp else { continue }
                XCTAssertLessThanOrEqual(
                    leading, 0.001,
                    "hở \(leading)pt bên trái — \(where_)"
                )
                XCTAssertGreaterThanOrEqual(
                    trailing, width - 0.001,
                    "hở \(width - trailing)pt bên phải — \(where_)"
                )
            }
        }
    }

    /// Ngưỡng ⅓ không phải một con số gõ đại: nó là **cùng mốc** mà chrome mini
    /// tan trên (`1 - progress * 3`, hết ở ⅓) và nền thẻ đục trên
    /// (`min(1, progress * 3)`, đầy ở ⅓). Dải bên phải là chỗ ở của chrome mini
    /// tới ⅓ và của tấm bìa từ ⅓ — không lúc nào vô chủ.
    ///
    /// Ghim ở đây vì ba con số ấy nằm ở ba chỗ khác nhau trong `PlayerCard` và
    /// không có gì bắt chúng đồng ý với nhau. Nếu ai đó đổi cửa sổ `* 3` kia,
    /// dòng này là chỗ duy nhất nói rằng ngưỡng phải đi theo.
    func testTheCatchUpLandsOnTheSameThirdTheChromeFadeUses() {
        XCTAssertEqual(PlayerCard.artworkWidthCatchUp, 1.0 / 3, accuracy: 0.0001)
    }

    /// **Đường không-bìa không đổi một chút nào** — người dùng đã đo trên máy
    /// thật là nó mượt, và bản sửa trước bị revert vì đụng vào thứ đang chạy
    /// được.
    ///
    /// Chứng minh bằng số chứ không bằng lời: `width` và `centre.x` ở đường này
    /// phải khớp **dạng đóng tuyến tính trên `progress`** — đúng biểu thức có
    /// trước bản sửa — chứ không chỉ "vuông". Vuông một mình là chưa đủ: một
    /// `horizontalProgress` rò vào cả `width` lẫn `height` vẫn vuông mà đã đi
    /// sai đường.
    func testTheArtworklessPathStillRunsStraightOnProgress() {
        for step in stride(from: 0, through: 50, by: 1) {
            let progress = Double(step) / 50
            let g = geometry(progress: progress, queueFactor: 0, fullBleed: false)

            XCTAssertEqual(
                g.width, 36 + (artworkSide - 36) * progress,
                accuracy: 0.001, "width ở progress \(progress)"
            )
            XCTAssertEqual(g.height, g.width, accuracy: 0.001,
                           "vuông ở progress \(progress)")
            XCTAssertEqual(
                g.centre.x, 36 + (cardSize.width / 2 - 36) * progress,
                accuracy: 0.001, "centre.x ở progress \(progress)"
            )
        }
    }

    /// **Đường hàng đợi không đổi một chút nào**, kể cả ở những `progress` giữa
    /// chừng — và những `progress` ấy có thật.
    ///
    /// `showingQueue` chỉ tự tắt ở `progress < 0.05`, nên kéo thẻ xuống trong
    /// lúc hàng đợi đang mở là cả quãng 1 → 0,05 với `queueFactor == 1`. Đích ở
    /// đó là ô 44pt **vuông** trong header; để trục ngang chạy nhanh hơn trục
    /// dọc ở quãng ấy là bóp nó thành 44×40 giữa chừng.
    ///
    /// Ghim dạng đóng tuyến tính, cùng lý do như đường không-bìa ở trên.
    func testTheQueueSlotJourneyStillRunsStraightOnProgress() {
        for step in stride(from: 0, through: 50, by: 1) {
            let progress = Double(step) / 50
            let g = geometry(progress: progress, queueFactor: 1, fullBleed: true)

            XCTAssertEqual(
                g.width, 36 + (thumbSide - 36) * progress,
                accuracy: 0.001, "width ở progress \(progress)"
            )
            XCTAssertEqual(g.height, g.width, accuracy: 0.001,
                           "ô header vuông ở progress \(progress)")
            XCTAssertEqual(
                g.centre.x, 36 + (thumbCentre.x - 36) * progress,
                accuracy: 0.001, "centre.x ở progress \(progress)"
            )
        }
    }

    /// Hai đầu đã ship, trên đường tràn màn hình, ở **mọi** `queueFactor` — đây
    /// là đường duy nhất bản sửa chạm vào, nên nó phải chịu đúng cái ràng buộc
    /// mà `testTheCollapsedPillIsUnchangedByTheQueueFactor` đặt lên đường kia.
    func testTheFullBleedEndsAreWhereTheyAlwaysWere() {
        for factor in stride(from: 0.0, through: 1.0, by: 0.25) {
            let collapsed = geometry(progress: 0, queueFactor: factor, fullBleed: true)
            XCTAssertEqual(collapsed.width, 36, accuracy: 0.001, "queueFactor \(factor)")
            XCTAssertEqual(collapsed.height, 36, accuracy: 0.001, "queueFactor \(factor)")
            XCTAssertEqual(collapsed.centre.x, 36, accuracy: 0.001, "queueFactor \(factor)")
            XCTAssertEqual(collapsed.centre.y, 27, accuracy: 0.001, "queueFactor \(factor)")
        }

        let open = geometry(progress: 1, queueFactor: 0, fullBleed: true)
        XCTAssertEqual(open.width, cardSize.width, accuracy: 0.001)
        XCTAssertEqual(open.height, cardSize.height, accuracy: 0.001)
        XCTAssertEqual(open.centre.x, cardSize.width / 2, accuracy: 0.001)
        XCTAssertEqual(open.centre.y, cardSize.height / 2, accuracy: 0.001)
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
