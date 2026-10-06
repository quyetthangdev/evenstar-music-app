import XCTest
import SwiftUI
@testable import Evenstar

/// Cú trao tay từ thẻ sang accessory ở **cuối cú thu**.
///
/// Lỗi đo trên máy thật (iPhone 12, Release, `device2-end_collapse.png`): thẻ
/// đã đáp đúng lên viên kính mà vẫn là tấm thẻ đặc màu xám tím, ô bìa tối,
/// suốt ~300ms đuôi lò xo; rồi trong **một** khung nhảy sang viên kính hệ thống
/// với ô bìa sáng. Hai độ mờ cùng nhị phân trên `isCardResting`, và nó chỉ lật
/// trong `completion` của `withAnimation` — tức sau đuôi dài của lò xo.
///
/// Cách chữa có hai nửa, mỗi nửa một nhóm test ở đây:
///   - thẻ tự mờ đi ở vài phần trăm cuối của `progress` khi đang thu;
///   - accessory hiện nội dung ngay khi cú thu được quyết, nằm sẵn dưới thẻ.
@MainActor
final class CollapseHandoffTests: XCTestCase {

    // MARK: - Đường cong độ mờ

    func testTheCardIsOpaqueUntilTheLastFewPercentOfACollapse() {
        let window = PlayerCard.collapseHandoffWindow
        XCTAssertEqual(PlayerCard.collapseHandoffOpacity(progress: 1, isCollapsing: true), 1)
        XCTAssertEqual(PlayerCard.collapseHandoffOpacity(progress: 0.5, isCollapsing: true), 1)
        XCTAssertEqual(PlayerCard.collapseHandoffOpacity(progress: window, isCollapsing: true), 1)
        XCTAssertEqual(PlayerCard.collapseHandoffOpacity(progress: window / 2, isCollapsing: true),
                       0.5, accuracy: 0.0001)
        XCTAssertEqual(PlayerCard.collapseHandoffOpacity(progress: 0, isCollapsing: true), 0)
    }

    /// Lò xo `settle` vọt qua 0 khoảng 0,5% rồi quay về. Phần âm ấy phải là
    /// trong suốt chứ không phải một độ mờ âm.
    func testTheSpringsOvershootBelowZeroStaysTransparent() {
        XCTAssertEqual(PlayerCard.collapseHandoffOpacity(progress: -0.005, isCollapsing: true), 0)
    }

    /// Chiều mở và lúc kéo: thẻ đặc từ khung đầu (spec, như Apple Music), dù
    /// `progress` còn nằm trong cửa sổ mờ.
    func testTheCardStaysOpaqueWhenNotCollapsing() {
        for progress in [0, 0.005, PlayerCard.collapseHandoffWindow / 2, 0.5, 1] {
            XCTAssertEqual(PlayerCard.collapseHandoffOpacity(progress: progress, isCollapsing: false), 1,
                           "progress \(progress)")
        }
    }

    /// Cửa sổ là quãng đường, và nó phải nhỏ: thẻ mờ đi khi còn gần bằng
    /// viên kính. Trên iPhone 12 (`dragTravel` ~710pt) 0.02 là ~14pt.
    func testTheWindowIsASmallFractionOfTheTravel() {
        XCTAssertGreaterThan(PlayerCard.collapseHandoffWindow, 0)
        XCTAssertLessThanOrEqual(PlayerCard.collapseHandoffWindow, 0.03)
    }

    // MARK: - Accessory hiện nội dung lúc nào

    private func make() -> PlayerExpansion {
        let e = PlayerExpansion()
        e.screenSize = CGSize(width: 390, height: 844)
        return e
    }

    func testAtRestTheAccessoryShowsItsContent() {
        XCTAssertTrue(make().showsAccessoryContent)
    }

    func testLeavingRestHidesTheAccessorysContent() {
        let e = make()
        e.leaveRest()
        XCTAssertFalse(e.showsAccessoryContent)
    }

    /// Đúng nửa thứ hai của cách chữa: nội dung có mặt **trước** khi thẻ về
    /// nghỉ, nằm dưới tấm thẻ đang mờ.
    func testCommittingACollapseShowsTheAccessorysContentBeforeTheCardRests() {
        let e = make()
        e.leaveRest()
        e.commitCollapse()
        XCTAssertTrue(e.isCollapsing)
        XCTAssertFalse(e.isCardResting, "isCardResting giữ nguyên nghĩa cũ — cho hit test và báo khung")
        XCTAssertTrue(e.showsAccessoryContent)
    }

    func testArrivingAtRestEndsTheCollapse() {
        let e = make()
        e.leaveRest()
        e.commitCollapse()
        e.arriveAtRest()
        XCTAssertFalse(e.isCollapsing)
        XCTAssertTrue(e.isCardResting)
        XCTAssertTrue(e.showsAccessoryContent)
    }

    /// Chạm accessory giữa đuôi cú thu: thẻ chưa về nghỉ nên `leaveRest()` bỏ
    /// qua phần chụp khung, nhưng cú thu phải bị huỷ — thẻ lại đè lên.
    func testExpandingAgainMidCollapseHidesTheAccessorysContent() {
        let e = make()
        e.leaveRest()
        e.commitCollapse()
        e.leaveRest()
        XCTAssertFalse(e.isCollapsing)
        XCTAssertFalse(e.showsAccessoryContent)
    }

    func testADragOnTheAccessoryMidCollapseHidesItsContent() {
        let e = make()
        e.leaveRest()
        e.commitCollapse()
        e.accessoryDragChanged(translationHeight: -100)
        XCTAssertFalse(e.isCollapsing)
        XCTAssertFalse(e.showsAccessoryContent)
    }

    // MARK: - Nối dây: `PlayerCard.morph(to: 0…)` quyết cú thu

    private var window: UIWindow?
    private var savedReduceMotion = false

    override func setUp() async throws {
        try await super.setUp()
        savedReduceMotion = BottomBarStyle.reduceMotion
    }

    override func tearDown() async throws {
        BottomBarStyle.reduceMotion = savedReduceMotion
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    /// Thẻ nghỉ, có bài sẵn (khôi phục phiên trước: chọn bài **trước** khi
    /// gắn view, nên `explicitSelections` không mở thẻ).
    private func mountRestingCard(reduceMotion: Bool) throws -> PlayerExpansion {
        BottomBarStyle.reduceMotion = reduceMotion
        let library = try InMemoryLibrary.make()
        let track = InMemoryLibrary.makeTrack()
        try library.insert(track)
        let playback = PlaybackService(
            player: MockAudioPlayer(),
            nowPlaying: MockNowPlayingPublisher(),
            library: library
        )
        playback.play(track, in: [track])
        let expansion = PlayerExpansion()
        let host = UIHostingController(
            rootView: PlayerCard(playback: playback, expansion: expansion)
                .environment(library)
                .environment(playback)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        self.window = window
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(expansion.isCardResting)
        return expansion
    }

    /// Kéo accessory lên một chút rồi thả: cú thả rơi về 0, `PlayerCard.handle`
    /// gọi `morph(to: 0…)`. Accessory phải hiện nội dung **ngay**, trong khi
    /// lò xo còn chạy và thẻ chưa về nghỉ.
    func testAReleaseThatFallsBackShowsTheAccessoryWhileTheSpringIsStillRunning() throws {
        let expansion = try mountRestingCard(reduceMotion: false)

        expansion.accessoryDragChanged(translationHeight: -120)
        XCTAssertFalse(expansion.showsAccessoryContent)
        expansion.accessoryDragEnded(predictedTranslationHeight: -120, verticalVelocity: 0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))

        XCTAssertEqual(expansion.progress, 0, "the card settled on the collapse target")
        XCTAssertFalse(expansion.isCardResting, "the spring has not finished yet")
        XCTAssertTrue(expansion.isCollapsing)
        XCTAssertTrue(expansion.showsAccessoryContent)

        let deadline = Date().addingTimeInterval(3)
        while !expansion.isCardResting, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertTrue(expansion.isCardResting)
        XCTAssertFalse(expansion.isCollapsing)
        XCTAssertTrue(expansion.showsAccessoryContent)
    }

    /// Giảm chuyển động: nhánh ấy về nghỉ ngay, nên accessory hiện và thẻ ẩn
    /// trong cùng lượt — không có trạng thái "đang thu" nào treo lại.
    func testWithReduceMotionTheReleaseArrivesAtRestImmediately() throws {
        let expansion = try mountRestingCard(reduceMotion: true)

        expansion.accessoryDragChanged(translationHeight: -120)
        expansion.accessoryDragEnded(predictedTranslationHeight: -120, verticalVelocity: 0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))

        XCTAssertTrue(expansion.isCardResting)
        XCTAssertFalse(expansion.isCollapsing)
        XCTAssertTrue(expansion.showsAccessoryContent)
    }
}
