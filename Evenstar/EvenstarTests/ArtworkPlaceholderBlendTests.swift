import XCTest
import SwiftUI
@testable import Evenstar

/// **Ô bìa của bài không bìa đổi màu dần theo cú thu, không nhảy lúc trao chỗ.**
///
/// QA trên máy (vòng sửa 4): ô bìa nhỏ của thẻ thu tối (`placeholderTile` trên
/// nền đen), ô của accessory (`ArtworkThumbnail`) sáng — nên lúc thẻ trao chỗ
/// cho accessory, ô bìa nhảy tối → sáng trong một khung, và sáng → tối khi bung.
/// Giờ ô của thẻ là ô của accessory phủ một lớp ô tối ở độ mờ
/// `placeholderExpandedWeight(progress:)`.
///
/// Test ghim hai đầu: hàm trọng số, và — vì "đúng bằng" là một câu về điểm ảnh
/// — ảnh dựng thật của ô bìa trong thẻ ở `progress` 0 so với ảnh dựng của một
/// `ArtworkThumbnail` trên cùng một nền, ở cả hai chế độ sáng/tối.
@MainActor
final class ArtworkPlaceholderBlendTests: XCTestCase {

    // MARK: - Trọng số

    func testTheCardsOwnColoursOnlyAtFullExpansion() {
        XCTAssertEqual(PlayerCard.placeholderExpandedWeight(progress: 1), 1)
        XCTAssertEqual(PlayerCard.placeholderExpandedWeight(progress: 0), 0)
    }

    /// Tuyến tính trên cả quãng — cùng nhịp với nền thẻ sau nó — và kẹp ở hai
    /// đầu, nên lò xo vọt qua không đẩy nó ra ngoài [0, 1].
    func testTheBlendFollowsTheWholeJourney() {
        XCTAssertEqual(PlayerCard.placeholderExpandedWeight(progress: 0.25), 0.25, accuracy: 1e-9)
        XCTAssertEqual(PlayerCard.placeholderExpandedWeight(progress: 0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(PlayerCard.placeholderExpandedWeight(progress: -0.02), 0)
        XCTAssertEqual(PlayerCard.placeholderExpandedWeight(progress: 1.03), 1)
    }

    // MARK: - Ảnh dựng: ở `progress` 0, ô của thẻ là ô của accessory

    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    private static let screen = CGSize(width: 390, height: 844)
    private static let scale: CGFloat = 2

    private func render<V: View>(_ view: V, style: UIUserInterfaceStyle,
                                 prepare: () -> Void = {}) throws -> [UInt8] {
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(origin: .zero, size: Self.screen)
        host.overrideUserInterfaceStyle = style
        let window = UIWindow(frame: host.view.frame)
        window.overrideUserInterfaceStyle = style
        window.rootViewController = host
        window.isHidden = false
        self.window = window
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        prepare()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let view = try XCTUnwrap(host.view)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let width = Int(Self.screen.width * Self.scale), height = Int(Self.screen.height * Self.scale)
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: Self.scale, y: -Self.scale)
        view.layer.render(in: context)
        window.isHidden = true
        return data
    }

    /// Trung bình và điểm tối nhất (nốt nhạc) của phần trong ô bìa — bỏ 3pt
    /// sát mép, nơi hai bán kính bo góc có thể lệch nhau nửa điểm ảnh.
    private func measure(_ data: [UInt8], tile: CGRect) -> (mean: [Double], darkest: Int, lightest: Int) {
        let width = Int(Self.screen.width * Self.scale)
        let inner = tile.insetBy(dx: 3, dy: 3)
        var sums = [0.0, 0.0, 0.0], count = 0.0, darkest = Int.max, lightest = 0
        for y in Int(inner.minY * Self.scale)..<Int(inner.maxY * Self.scale) {
            for x in Int(inner.minX * Self.scale)..<Int(inner.maxX * Self.scale) {
                let p = (y * width + x) * 4
                for c in 0..<3 { sums[c] += Double(data[p + c]) }
                count += 1
                let sum = Int(data[p]) + Int(data[p + 1]) + Int(data[p + 2])
                darkest = min(darkest, sum)
                lightest = max(lightest, sum)
            }
        }
        return (sums.map { $0 / count }, darkest, lightest)
    }

    func testAtRestTheCardsTileIsTheAccessorysTileInBothAppearances() throws {
        let screen = Self.screen
        let anchor = PlayerAnchor.fallbackFrame(screen: screen)
        // Ô bìa của hàng mini — cùng `MiniPlayerMetrics` mà cả hai nơi dùng.
        let tile = CGRect(x: anchor.minX + MiniPlayerMetrics.artworkLeadingInset,
                          y: anchor.midY - MiniPlayerMetrics.artworkSide / 2,
                          width: MiniPlayerMetrics.artworkSide, height: MiniPlayerMetrics.artworkSide)

        for style in [UIUserInterfaceStyle.light, .dark] {
            // Thẻ ở `progress` 0, rời nghỉ (đang kéo, chưa thu): mặt thẻ đặc,
            // `secondarySystemBackground` — không có kính để dựng.
            let library = try InMemoryLibrary.make()
            let track = InMemoryLibrary.makeTrack()
            try library.insert(track)
            let playback = PlaybackService(player: MockAudioPlayer(),
                                           nowPlaying: MockNowPlayingPublisher(), library: library)
            playback.play(track, in: [track])
            let expansion = PlayerExpansion()
            let card = try render(
                PlayerCard(playback: playback, expansion: expansion)
                    .environment(library)
                    .environment(playback),
                style: style
            ) {
                expansion.leaveRest()
                expansion.setAccessoryDragDelta(0)
            }

            // Accessory: một `ArtworkThumbnail` không bìa, trên cùng mặt nền.
            let accessory = try render(
                ZStack(alignment: .topLeading) {
                    Color(.secondarySystemBackground).ignoresSafeArea()
                    ArtworkThumbnail(relativePath: nil, size: MiniPlayerMetrics.artworkSide)
                        .position(x: tile.midX, y: tile.midY)
                }
                .ignoresSafeArea(),
                style: style
            )

            let a = measure(card, tile: tile), b = measure(accessory, tile: tile)
            let label = style == .light ? "light" : "dark"
            print("[placeholder] \(label): card mean \(a.mean.map { Int($0) }) darkest \(a.darkest) lightest \(a.lightest);"
                  + " accessory mean \(b.mean.map { Int($0) }) darkest \(b.darkest) lightest \(b.lightest)")
            for c in 0..<3 {
                XCTAssertEqual(a.mean[c], b.mean[c], accuracy: 3, "\(label): tile colour channel \(c)")
            }
            // Cực trị là nét nốt nhạc (tối nhất ở chế độ sáng, sáng nhất ở chế
            // độ tối), và nét ấy không trùng từng điểm ảnh: thẻ vẽ nốt ở 140pt
            // rồi thu nhỏ (`placeholderGlyphBase`, để cỡ nốt hoạt hoá được),
            // accessory vẽ thẳng ở 15pt — SF Symbols đổi độ dày nét theo cỡ
            // quang học. Đo được: lệch 15/12 trên tổng ba kênh. Độ trung bình
            // của cả ô — màu nền ô cộng nốt — thì trùng tới 1.
            XCTAssertEqual(Double(a.darkest), Double(b.darkest), accuracy: 24, "\(label): glyph ink")
            XCTAssertEqual(Double(a.lightest), Double(b.lightest), accuracy: 20, "\(label): tile ground / glyph")
        }
    }
}
