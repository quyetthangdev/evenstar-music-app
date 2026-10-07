import XCTest
import SwiftUI
@testable import Evenstar

/// **Player mở hết trên màn 4,7" (iPhone SE thế hệ 2/3, 375×667) còn trọn
/// hàng cuối** — hàng hẹn giờ ngủ / hàng đợi, dưới thanh âm lượng — ở cỡ chữ
/// mặc định và một bậc lớn hơn.
///
/// Hàng nút transport đã lớn lên khi chuyển sang kính native (nút ▶ khung
/// 58,8pt cộng phần đệm của `.glass`), trong khi `PlayerCard.contentBudget` ghi
/// chỉ còn ~16pt dư. Nên đo chứ không cộng tay: dựng đúng `NowPlayingContent`
/// ở bề rộng nó có trên SE, hỏi chiều cao nó cần, so với vùng thẻ dành cho nó
/// (`PlayerCard.contentRegionHeight`, neo ở đáy thẻ). Và chụp cả thẻ thật trong
/// một cửa sổ 375×667 để nhìn.
@MainActor
final class PlayerCardSmallScreenTests: XCTestCase {
    private static let screen = CGSize(width: 375, height: 667)
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    private func makePlayback() throws -> (LibraryService, PlaybackService, Track) {
        let library = try InMemoryLibrary.make()
        let track = InMemoryLibrary.makeTrack(title: "A title long enough to need both of its two reserved lines here",
                                              artistName: "An artist with a long name",
                                              albumTitle: "And an album to go with it")
        try library.insert(track)
        let playback = PlaybackService(player: MockAudioPlayer(), nowPlaying: MockNowPlayingPublisher(),
                                       library: library)
        playback.play(track, in: [track])
        return (library, playback, track)
    }

    /// Chiều cao chồng nội dung cần ở bề rộng của SE: thẻ dựng nó ở bề rộng
    /// thẻ mở hết trừ hai lề 24pt.
    private func stackHeight(_ typeSize: DynamicTypeSize) throws -> CGFloat {
        let (library, playback, _) = try makePlayback()
        let width = Self.screen.width - 48
        let content = NowPlayingContent(playback: playback, showingQueue: .constant(false))
            .environment(\.dynamicTypeSize, typeSize)
            .environment(\.colorScheme, .dark)
            .environment(library)
            .environment(playback)
        let host = UIHostingController(rootView: content)
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    func testTheWholeStackFitsOnA47InchScreenAtTheDefaultTextSize() throws {
        let needed = try stackHeight(.large)
        print("[se] stack \(needed)pt at .large, region \(PlayerCard.contentRegionHeight)pt")
        XCTAssertLessThanOrEqual(needed, PlayerCard.contentRegionHeight,
                                 "the bottom \(needed - PlayerCard.contentRegionHeight)pt fall below the card")
        try snapshot(.large, name: "se-375x667-player-large.png")
    }

    func testTheWholeStackFitsOnA47InchScreenOneTextSizeUp() throws {
        let needed = try stackHeight(.xLarge)
        print("[se] stack \(needed)pt at .xLarge, region \(PlayerCard.contentRegionHeight)pt")
        XCTAssertLessThanOrEqual(needed, PlayerCard.contentRegionHeight,
                                 "the bottom \(needed - PlayerCard.contentRegionHeight)pt fall below the card")
        try snapshot(.xLarge, name: "se-375x667-player-xlarge.png")
    }

    /// Thẻ thật, mở hết, trong một cửa sổ 375×667, lưu ra ảnh cho người xem.
    /// Không có đường dẫn ghi được thì bỏ qua phần lưu, không đánh trượt.
    private func snapshot(_ typeSize: DynamicTypeSize, name: String) throws {
        let (library, playback, track) = try makePlayback()
        let expansion = PlayerExpansion()
        let card = PlayerCard(playback: playback, expansion: expansion)
            .environment(\.dynamicTypeSize, typeSize)
            .environment(library)
            .environment(playback)
        let host = UIHostingController(rootView: ZStack { Color.white.ignoresSafeArea(); card })
        host.view.frame = CGRect(origin: .zero, size: Self.screen)
        host.overrideUserInterfaceStyle = .light
        let window = UIWindow(frame: host.view.frame)
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = host
        window.isHidden = false
        self.window = window
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        playback.play(track, in: [track])
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        XCTAssertEqual(expansion.progress, 1)
        let image = UIGraphicsImageRenderer(size: Self.screen).image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: Self.screen), afterScreenUpdates: true)
        }
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".superpowers/sdd/2026-10-06-native-liquid-glass")
        guard FileManager.default.fileExists(atPath: directory.path), let data = image.pngData() else { return }
        try? data.write(to: directory.appendingPathComponent(name))
    }
}
