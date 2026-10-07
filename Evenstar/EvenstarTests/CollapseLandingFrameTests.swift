import XCTest
import SwiftUI
@testable import Evenstar

/// **Cú thu vẽ ra thật, từng khung**: thẻ co đều vào viên kính — không nảy, không
/// lùi lại — không bao giờ nhỏ hơn hay thấp hơn viên kính, và dừng đúng trên
/// viên kính; mặt thẻ đặc lúc đầu và là kính lúc cuối (spec, Phần 1, chốt
/// 2026-10-07).
///
/// `CollapseHandoffTests` ghim đường cong; ở đây là việc SwiftUI có vẽ đúng
/// đường cong ấy không — thứ phép tính không trả lời được: hình học có thật sự
/// dừng ở đích dưới `CustomAnimation`, lớp kính có thật sự hiện ra.
///
/// ─────────────────────────────────────────────────────────────────────────
/// CÁCH ĐO
/// ─────────────────────────────────────────────────────────────────────────
/// **`drawHierarchy`, không phải `layer.render(in:)`.** Đo trước khi viết:
/// `layer.render(in:)` bỏ qua `.glassEffect` hoàn toàn — viên kính ra trong
/// suốt như không có gì, nên một thẻ kính và một thẻ đã biến mất cho cùng một
/// ảnh. `drawHierarchy(afterScreenUpdates: true)` đi qua render server và vẽ
/// kính thật.
///
/// **Ảnh của `drawHierarchy` có lúc lệch xuống, nên độ lệch được đo.** Với cửa
/// sổ 390×844 trên simulator 402×874, có lần chạy mọi thứ ra thấp hơn ~30pt —
/// đúng hiệu hai chiều cao — với một dải trắng trên cùng; có lần không lệch.
/// Dùng cửa sổ bằng màn hình để né thì tệ hơn: ảnh lẫn cả cửa sổ của chính app
/// chủ (thanh tab, viên kính accessory thật ở đúng chỗ thẻ nghỉ). Nên cửa sổ
/// giữ 390×844, và độ lệch đọc từ ảnh — hàng đầu tiên là sọc — rồi trừ đi.
///
/// Nền **sọc ngang 4pt đỏ/xanh**, đọc ở một cột giữa tên bài ngắn và cụm ▶ ⏭
/// — ở đoạn cuối cột ấy chỉ thấy mặt thẻ:
///
///   - **Mép thẻ:** hàng không còn là sọc trần (cách cả hai màu sọc > 60 theo
///     L1). Mặt đặc, nội dung thẻ và kính đều che hoặc đổi màu sọc.
///   - **Độ trong:** độ **đậm màu** (`max − min` của RGB). Thẻ bài không bìa
///     chỉ vẽ màu trung tính — mặt đặc ~[242, 242, 247], nền tối của player
///     ~[13…120] xám — nên dưới 10. Kính thì làm mờ sọc thành trung bình của
///     chúng rồi làm sáng lên: một mảng tím nhạt ~[220, 206, 253], đậm ~45.
///     Màu ấy chỉ có thể tới từ nền phía sau. (Sọc không còn thấy từng vạch:
///     đo được, lớp kính cỡ thẻ nhoè hẳn 4pt.)
@MainActor
final class CollapseLandingFrameTests: XCTestCase {

    private var window: UIWindow?
    private var savedReduceMotion = false

    override func setUp() async throws {
        try await super.setUp()
        savedReduceMotion = BottomBarStyle.reduceMotion
        BottomBarStyle.reduceMotion = false
    }

    override func tearDown() async throws {
        BottomBarStyle.reduceMotion = savedReduceMotion
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    private struct Rig {
        let playback: PlaybackService
        let expansion: PlayerExpansion
        let track: Track
        let host: UIViewController
        let screen: CGSize
        /// Ảnh của `drawHierarchy` thấp hơn nội dung bấy nhiêu hàng.
        var shift = 0
        /// Không có accessory trong test, nên thẻ bung từ khung dự phòng.
        var rest: CGRect { PlayerAnchor.fallbackFrame(screen: screen) }
        /// Giữa tên bài ngắn và cụm ▶ ⏭ của hàng mini.
        var column: Int { Int(rest.maxX) - 120 }
    }

    /// Vẽ bằng `Canvas` ở bội số nguyên của 4pt. Một `VStack` các dải 4pt bị
    /// nén cho vừa chiều cao — 844 / 212 — và mỗi ~12 hàng lại có một hàng
    /// pha trộn, đọc ra như "không phải sọc".
    private struct Stripes: View {
        var body: some View {
            Canvas { context, size in
                var row = 0
                while CGFloat(row * 4) < size.height {
                    context.fill(Path(CGRect(x: 0, y: CGFloat(row * 4), width: size.width, height: 4)),
                                 with: .color(row % 2 == 0 ? .red : .blue))
                    row += 1
                }
            }
            .ignoresSafeArea()
        }
    }

    private func mountRestingCard() throws -> Rig {
        let library = try InMemoryLibrary.make()
        let track = InMemoryLibrary.makeTrack()
        try library.insert(track)
        let playback = PlaybackService(player: MockAudioPlayer(),
                                       nowPlaying: MockNowPlayingPublisher(),
                                       library: library)
        // Chọn bài trước khi gắn view: thẻ nghỉ, cú mở sau đó là cú mở ấm.
        playback.play(track, in: [track])
        let expansion = PlayerExpansion()
        let card = PlayerCard(playback: playback, expansion: expansion)
            .environment(library)
            .environment(playback)
        let host = UIHostingController(rootView: ZStack { Stripes(); card })
        let screen = CGSize(width: 390, height: 844)
        host.view.frame = CGRect(origin: .zero, size: screen)
        host.overrideUserInterfaceStyle = .light
        let window = UIWindow(frame: host.view.frame)
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = host
        window.isHidden = false
        self.window = window
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        var rig = Rig(playback: playback, expansion: expansion, track: track, host: host, screen: screen)
        let raw = capture(rig).column
        rig.shift = try XCTUnwrap((0..<raw.pixels.count).first { raw.isBare($0) },
                                  "no stripes in the snapshot at all")
        XCTAssertLessThan(rig.shift, 60, "the snapshot is offset by \(rig.shift)pt; something else is drawn on top")
        return rig
    }

    // MARK: - Đọc một khung

    private struct Column {
        var pixels: [(r: Int, g: Int, b: Int)]

        func sum(_ row: Int) -> Int { pixels[row].r + pixels[row].g + pixels[row].b }

        /// Sọc trần: gần đỏ hoặc gần xanh của nền, đúng như `drawHierarchy`
        /// vẽ chúng.
        func isBare(_ row: Int) -> Bool {
            let p = pixels[row]
            let red = abs(p.r - 255) + abs(p.g - 55) + abs(p.b - 58)
            let blue = abs(p.r - 0) + abs(p.g - 137) + abs(p.b - 255)
            return min(red, blue) <= 60
        }

        /// Dải liền không-phải-sọc chứa `row`.
        func cover(around row: Int) -> ClosedRange<Int>? {
            guard !isBare(row) else { return nil }
            var top = row, bottom = row
            while top > 0, !isBare(top - 1) { top -= 1 }
            while bottom < pixels.count - 1, !isBare(bottom + 1) { bottom += 1 }
            return top...bottom
        }

        /// Trung vị độ đậm màu trên `rows` — xem doc của lớp.
        func tint(_ rows: ClosedRange<Int>) -> Double {
            let values = rows.filter { $0 < pixels.count }.map { row -> Int in
                let p = pixels[row]
                return max(p.r, p.g, p.b) - min(p.r, p.g, p.b)
            }.sorted()
            guard !values.isEmpty else { return 0 }
            return Double(values[values.count / 2])
        }
    }

    /// Một cột (dọc, ở `rig.column`) và một hàng (ngang, qua giữa viên kính
    /// lúc nghỉ) của cùng một khung.
    private func capture(_ rig: Rig) -> (column: Column, row: Column) {
        let width = Int(rig.screen.width), height = Int(rig.screen.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: rig.screen, format: format).image { _ in
            rig.host.view.drawHierarchy(in: CGRect(origin: .zero, size: rig.screen), afterScreenUpdates: true)
        }
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image.cgImage!, in: CGRect(origin: .zero, size: rig.screen))
        // Hàng nội dung `row` nằm ở hàng `row + shift` của ảnh; phần đáy bị
        // đẩy khỏi ảnh thì bỏ — thẻ nghỉ còn cách đáy cả trăm điểm.
        var pixels: [(r: Int, g: Int, b: Int)] = []
        pixels.reserveCapacity(height - rig.shift)
        for row in rig.shift..<height {
            let p = (row * width + rig.column) * 4
            pixels.append((Int(data[p]), Int(data[p + 1]), Int(data[p + 2])))
        }
        var across: [(r: Int, g: Int, b: Int)] = []
        let y = min(Int(rig.rest.midY) + rig.shift, height - 1)
        for x in 0..<width {
            let p = (y * width + x) * 4
            across.append((Int(data[p]), Int(data[p + 1]), Int(data[p + 2])))
        }
        return (Column(pixels: pixels), Column(pixels: across))
    }

    private struct Sample {
        let ms: Double
        let column: Column
        /// Bề ngang thẻ ở hàng giữa viên kính lúc nghỉ, nếu có.
        let across: ClosedRange<Int>?
        /// Thẻ quanh giữa viên kính lúc nghỉ, nếu có.
        let cover: ClosedRange<Int>?
        /// …và chỉ khi thẻ đã đủ nhỏ để cả dải nằm gọn trong vùng đo.
        let landedCover: ClosedRange<Int>?
    }

    /// Chụp liên tục trong `seconds`, mốc thời gian tính từ lúc gọi.
    private func film(_ rig: Rig, for seconds: Double) -> [Sample] {
        var out: [Sample] = []
        let start = CACurrentMediaTime()
        let middle = Int(rig.rest.midY)
        let zoneTop = Int(rig.rest.minY) - 120
        while CACurrentMediaTime() - start < seconds {
            RunLoop.main.run(until: Date().addingTimeInterval(0.004))
            let ms = (CACurrentMediaTime() - start) * 1000
            let (column, row) = capture(rig)
            let cover = column.cover(around: middle)
            out.append(Sample(ms: ms, column: column,
                              across: row.cover(around: Int(rig.rest.midX)), cover: cover,
                              landedCover: cover.flatMap { $0.lowerBound > zoneTop ? $0 : nil }))
        }
        return out
    }

    /// Độ đậm màu trên phần thẻ nằm dưới hàng 400 — vùng mà thẻ đang mở hoặc
    /// đang thu nào cũng phủ — bỏ 6pt sát mép.
    private func surfaceTint(_ sample: Sample) -> Double? {
        guard let cover = sample.cover else { return nil }
        let top = max(cover.lowerBound, 400) + 6, bottom = cover.upperBound - 6
        guard bottom > top + 8 else { return nil }
        return sample.column.tint(top...bottom)
    }

    // MARK: - Cú thu

    private func openFully(_ rig: Rig) {
        // Một cú chạm hàng thư viện: `explicitSelections` → `expand()`.
        rig.playback.play(rig.track, in: [rig.track])
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))
        XCTAssertEqual(rig.expansion.progress, 1)
    }

    /// Cú thu thường ngày: kéo thẻ đang mở xuống một đoạn rồi buông theo đà.
    /// Đi qua accessory chỉ vì đó là cú kéo test lái được — cú thả rơi vào
    /// đúng `handle(.release)` → `morph(to: 0…)` với `releaseCurves`, như cú
    /// kéo trên thẻ.
    private func dragDownAndRelease(_ rig: Rig, to start: Double, velocity: CGFloat) {
        let travel = PlayerAnchor.dragTravel(for: rig.rest)
        let translation = CGFloat(1 - start) * travel + AccessoryDragAxis.lockDistance
        rig.expansion.accessoryDragChanged(translationHeight: translation)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        rig.expansion.accessoryDragEnded(predictedTranslationHeight: translation + 500,
                                         verticalVelocity: velocity)
    }

    private typealias Landed = (ms: Double, cover: ClosedRange<Int>, column: Column, across: ClosedRange<Int>?)

    /// Những khung từ lúc thẻ đã gần bằng viên kính (cao không quá viên kính +
    /// 4pt) tới lúc thẻ bắt đầu mờ đi trao chỗ.
    ///
    /// Mờ đi là khung đầu tiên màu sọc lọt qua đậm hơn hẳn ~35–45 của kính:
    /// từ đó thẻ nửa trong suốt và không còn mép nào để đo. Đọc mốc từ ảnh chứ
    /// không từ `settlingTime`: đồng hồ của animation bắt đầu ở lượt cập nhật
    /// xử lý cú thả, trễ hơn mốc 0 của cuộn phim vài chục mili giây.
    private func landedFrames(_ frames: [Sample], rest: CGRect) -> [Landed] {
        let fading = frames.firstIndex { ($0.landedCover != nil) && (surfaceTint($0) ?? 999) > 60 }
            ?? frames.endIndex
        let measured: [Landed] = frames[..<fading]
            .compactMap { s in s.landedCover.map { (ms: s.ms, cover: $0, column: s.column, across: s.across) } }
        guard let arrival = measured.firstIndex(where: { $0.cover.count <= Int(rest.height) + 4 }) else {
            return []
        }
        return Array(measured[arrival...])
    }

    func testTheCardShrinksSteadilyIntoThePillAndSettlesExactlyOnIt() throws {
        let rig = try mountRestingCard()
        openFully(rig)

        let start = 0.9
        let velocity: CGFloat = 1900
        dragDownAndRelease(rig, to: start, velocity: velocity)
        let frames = film(rig, for: 1.0)

        let restTop = Int(rig.rest.minY), restBottom = Int(rig.rest.maxY) - 1
        let geometry = CollapseSpring(
            spring: BottomBarStyle.collapseSpring,
            initialVelocity: PlayerCard.settleVelocity(verticalVelocity: velocity,
                                                       travel: PlayerAnchor.dragTravel(for: rig.rest),
                                                       from: start, to: 0)
        )
        print("[landing] snapshot shift \(rig.shift)pt, rest rows \(restTop)–\(restBottom), column \(rig.column),"
              + " handoff at \(String(format: "%.0f", geometry.settlingTime * 1000))ms, \(frames.count) frames")
        for sample in frames {
            let tint = surfaceTint(sample).map { String(format: "%5.1f", $0) } ?? "    —"
            if let cover = sample.cover {
                let across = sample.across.map { "left=\($0.lowerBound) right=\($0.upperBound)" } ?? "left/right —"
                print(String(format: "[landing] t=%6.1fms top=%4d bottom=%4d height=%3d tint=%@ ",
                             sample.ms, cover.lowerBound, cover.upperBound, cover.count, tint) + across)
            } else {
                print(String(format: "[landing] t=%6.1fms no card at the capsule", sample.ms))
            }
        }

        let fading = frames.firstIndex { ($0.landedCover != nil) && (surfaceTint($0) ?? 999) > 60 }
            ?? frames.endIndex
        let moving = frames[..<fading].compactMap { s in s.cover.map { (ms: s.ms, cover: $0, across: s.across) } }
        let landed = landedFrames(frames, rest: rig.rest)
        XCTAssertGreaterThanOrEqual(moving.count, 6, "too few frames caught the collapse")
        XCTAssertGreaterThanOrEqual(landed.count, 2, "too few frames caught the card at the capsule")

        // 1. Co đều, không nảy: mép trên chỉ đi xuống, đáy chỉ đi lên, chiều
        // cao chỉ giảm — từng khung, sai số 1pt cho hàng pha trộn ở mép.
        for (earlier, later) in zip(moving, moving.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later.cover.lowerBound, earlier.cover.lowerBound - 1,
                                        "the top went back up at t=\(later.ms)ms")
            XCTAssertLessThanOrEqual(later.cover.upperBound, earlier.cover.upperBound + 1,
                                     "the bottom went back down at t=\(later.ms)ms")
            XCTAssertLessThanOrEqual(later.cover.count, earlier.cover.count + 1,
                                     "the card grew again at t=\(later.ms)ms")
        }

        // 2. Không bao giờ nhỏ hơn hay thấp hơn viên kính, và viên kính hệ thống
        // luôn nằm trọn trong thẻ.
        let restLeft = Int(rig.rest.minX), restRight = Int(rig.rest.maxX) - 1
        for frame in moving {
            XCTAssertLessThanOrEqual(frame.cover.lowerBound, restTop, "top inside the capsule at t=\(frame.ms)ms")
            XCTAssertGreaterThanOrEqual(frame.cover.upperBound, restBottom,
                                        "bottom inside the capsule at t=\(frame.ms)ms")
            XCTAssertGreaterThanOrEqual(frame.cover.count, Int(rig.rest.height) - 1,
                                        "the card shrank to \(frame.cover.count)pt at t=\(frame.ms)ms")
            if let across = frame.across {
                XCTAssertLessThanOrEqual(across.lowerBound, restLeft, "left edge inside at t=\(frame.ms)ms")
                XCTAssertGreaterThanOrEqual(across.upperBound, restRight, "right edge inside at t=\(frame.ms)ms")
            }
        }

        // 3. Dừng đúng trên viên kính. Mép trên cho phép 2pt viền kính phía
        // trên (đo được: 703 cho mép 705).
        let settled = try XCTUnwrap(landed.last)
        let settledAcross = try XCTUnwrap(settled.across)
        XCTAssertTrue((restTop - 3)...restTop ~= settled.cover.lowerBound, "settled top \(settled.cover.lowerBound)")
        XCTAssertEqual(settled.cover.upperBound, restBottom, accuracy: 1, "settled bottom")
        XCTAssertEqual(settledAcross.lowerBound, restLeft, accuracy: 1, "settled left")
        XCTAssertEqual(settledAcross.upperBound, restRight, accuracy: 1, "settled right")
        print("[landing] arrived (within 4pt) at \(String(format: "%.0f", landed.first?.ms ?? 0))ms,"
              + " handoff fade from \(fading < frames.count ? String(format: "%.0f", frames[fading].ms) : "—")ms")

        // 4. Kính ở cuối: màu của nền lọt qua mặt thẻ — mọi khung đã gần viên kính.
        for frame in landed {
            let rows = (frame.cover.lowerBound + 6)...(frame.cover.upperBound - 6)
            XCTAssertGreaterThan(frame.column.tint(rows), 20,
                                 "opaque at t=\(frame.ms)ms — the landed card should be glass")
        }

        // 5. Đặc lúc đầu: thẻ còn lớn, không chút màu nền nào lọt qua.
        let early = frames.filter { $0.ms < 90 }
        XCTAssertFalse(early.isEmpty)
        for frame in early {
            let tint = try XCTUnwrap(surfaceTint(frame), "no card at t=\(frame.ms)ms")
            XCTAssertLessThan(tint, 10, "translucent at t=\(frame.ms)ms while the card is still large")
        }

        // 6. Tới hết cú mờ trao tay: không có mảng tối nào quanh viên kính — kính
        // dưới `.opacity` của cả thẻ vẫn là kính.
        let firstNear = try XCTUnwrap(frames.firstIndex { $0.landedCover != nil })
        for frame in frames[firstNear...] {
            let darkest = ((restTop - 4)...(restBottom + 20)).map { frame.column.sum($0) }.min() ?? 0
            XCTAssertGreaterThan(darkest, 250, "something dark was drawn at t=\(frame.ms)ms")
        }
        // …và cú mờ có thật sự kết thúc: thẻ đã nhường chỗ.
        XCTAssertNil(frames.last?.cover, "the card was still drawn \(frames.last?.ms ?? 0)ms after release")
        let deadline = Date().addingTimeInterval(1.5)
        while !rig.expansion.isCardResting, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(rig.expansion.isCardResting)
    }

    // MARK: - Cú trao tay, với accessory thật

    /// Thẻ trong một `TabView` có `tabViewBottomAccessory` thật — như
    /// `RootView` — trên nền trắng: cú trao tay là chuyện giữa hàng của thẻ và
    /// hàng của accessory, nên phải có accessory thật, với môi trường chữ mà
    /// hệ thống đặt cho nó.
    private struct Shell: View {
        let playback: PlaybackService
        let expansion: PlayerExpansion

        var body: some View {
            ZStack {
                TabView {
                    Tab("A", systemImage: "music.note") { Color.white.ignoresSafeArea() }
                    Tab("B", systemImage: "square.stack") { Color.white }
                }
                .tabViewBottomAccessory {
                    MiniPlayerAccessory(playback: playback, expansion: expansion)
                }
                .recedesBehindPlayer(expansion)
                PlayerCard(playback: playback, expansion: expansion)
            }
        }
    }

    /// Một khung của dải quanh viên kính, ở 2×, và trạng thái lúc chụp.
    private struct HandoffShot {
        let ms: Double
        let surfaceHandedOver: Bool
        let resting: Bool
        /// Độ sáng từng điểm ảnh bên trong viên kính (bỏ 4pt sát mép).
        let pill: [UInt8]
    }

    /// Chênh lệch trung bình từng điểm ảnh giữa hai khung, theo độ sáng 0…255.
    private static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        Double(zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / Double(a.count)
    }

    private static func luminance(_ image: CGImage, in rect: CGRect, scale: CGFloat) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let context = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var out: [UInt8] = []
        for y in Int(rect.minY * scale)..<min(h, Int(rect.maxY * scale)) {
            for x in Int(rect.minX * scale)..<min(w, Int(rect.maxX * scale)) {
                let p = (y * w + x) * 4
                out.append(UInt8((299 * Int(data[p]) + 587 * Int(data[p + 1]) + 114 * Int(data[p + 2])) / 1000))
            }
        }
        return out
    }

    /// **Cú trao tay không chớp** (vòng sửa 8): từ lúc thẻ đã nằm trên viên kính
    /// tới khi accessory thế chỗ, vùng viên kính chỉ tiến **một chiều** về
    /// khung cuối, và hàng của thẻ là hàng của accessory.
    ///
    /// Đo được trước khi sửa, cùng test này: khung cuối trước khi về nghỉ lệch
    /// khung cuối 11,3 (hai hàng khác cỡ — `AccessoryTextStyle`), rồi cú mờ
    /// **đẩy lên** 13,0 trước khi giảm (hai hàng lệch chồng nhau sau một lớp
    /// kính nửa trong). Sửa môi trường chữ thôi: 3,9 → 6,3 → 0 — vẫn nảy lên,
    /// vì kính của thẻ vẫn nằm giữa hai hàng. Sau cả hai: 3,9 → 2,9 → 2,0 →
    /// 1,1 → 0,2 → 0.
    func testTheHandoffMovesOneWayAndTheTwoRowsAreTheSame() throws {
        let library = try InMemoryLibrary.make()
        let track = InMemoryLibrary.makeTrack()
        try library.insert(track)
        let playback = PlaybackService(player: MockAudioPlayer(), nowPlaying: MockNowPlayingPublisher(),
                                       library: library)
        playback.play(track, in: [track])
        let expansion = PlayerExpansion()
        let host = UIHostingController(rootView: Shell(playback: playback, expansion: expansion)
            .environment(library).environment(playback))
        let screen = CGSize(width: 390, height: 844)
        host.view.frame = CGRect(origin: .zero, size: screen)
        host.overrideUserInterfaceStyle = .light
        let window = UIWindow(frame: host.view.frame)
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = host
        // `makeKeyAndVisible`, rồi một lượt `drawHierarchy`: đo được, thiếu
        // lượt chụp ấy thì 2s sau accessory của hệ thống vẫn chưa có khung.
        window.makeKeyAndVisible()
        self.window = window
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        _ = UIGraphicsImageRenderer(size: screen).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let pill = expansion.accessoryFrame
        XCTAssertGreaterThan(pill.width, 100, "the system accessory was never laid out")

        playback.play(track, in: [track])
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))
        XCTAssertEqual(expansion.progress, 1)

        // Thả không vận tốc: cùng lò xo với cú chạm thu.
        let travel = PlayerAnchor.dragTravel(for: expansion.anchorFrame)
        let translation = 0.02 * travel + AccessoryDragAxis.lockDistance
        expansion.accessoryDragChanged(translationHeight: translation)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        expansion.accessoryDragEnded(predictedTranslationHeight: translation + 900, verticalVelocity: 0)

        let band = CGRect(x: 0, y: pill.minY - 30, width: screen.width, height: pill.height + 60)
        let inner = CGRect(x: pill.minX + 4, y: 34, width: pill.width - 8, height: pill.height - 8)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        var shots: [HandoffShot] = []
        var restedAt: Double?
        let start = CACurrentMediaTime()
        while CACurrentMediaTime() - start < 3 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.002))
            let ms = (CACurrentMediaTime() - start) * 1000
            let image = UIGraphicsImageRenderer(size: band.size, format: format).image { _ in
                host.view.drawHierarchy(in: CGRect(x: 0, y: -band.minY, width: screen.width, height: screen.height),
                                        afterScreenUpdates: true)
            }
            shots.append(HandoffShot(ms: ms, surfaceHandedOver: expansion.cardSurfaceHandedOver,
                                     resting: expansion.isCardResting,
                                     pill: Self.luminance(image.cgImage!, in: inner, scale: 2)))
            if expansion.isCardResting, restedAt == nil { restedAt = ms }
            if let restedAt, ms - restedAt > 150 { break }
        }
        let final = try XCTUnwrap(shots.last).pill
        let differences = shots.map { Self.difference($0.pill, final) }
        for (shot, difference) in zip(shots, differences) {
            print(String(format: "[handoff] t=%6.1fms surface=%@ resting=%d diffFinal=%6.2f", shot.ms,
                         shot.surfaceHandedOver ? "gone" : "kept", shot.resting ? 1 : 0, difference))
        }

        let firstRest = try XCTUnwrap(shots.firstIndex(where: \.resting), "the card never rested")
        XCTAssertGreaterThan(firstRest, 0)
        // Khung đầu của cú trao tay, bước nào trước cũng vậy.
        let handoff = try XCTUnwrap(shots.firstIndex { $0.surfaceHandedOver || $0.resting })

        // 1. Hai hàng là một: ngay trước cú đổi chỗ, vùng viên kính đã là khung
        // cuối — mặt thẻ đã tan, và hàng của thẻ là hàng của accessory.
        XCTAssertLessThan(differences[firstRest - 1], 1,
                          "just before the swap the pill still differs from its final look by "
                          + "\(differences[firstRest - 1]) — the surface is still there, or the rows differ")

        // 2. Một chiều: từ khung cuối trước cú trao tay tới hết, không khung nào
        // xa khung cuối hơn khung trước nó (0,3 cho nhiễu của kính).
        for index in max(handoff - 1, 0)..<(shots.count - 1) {
            XCTAssertLessThanOrEqual(differences[index + 1], differences[index] + 0.3,
                                     "the pill moved away from its final look at t=\(shots[index + 1].ms)ms")
        }

        // 3. Mặt thẻ tan trước, rồi hai hàng mới đổi chỗ.
        XCTAssertTrue(shots[..<firstRest].contains(where: \.surfaceHandedOver),
                      "the rows swapped while the card's surface was still there")
    }

    // MARK: - Cú bung

    /// Chiều mở không đổi: đặc ngay từ khung đầu, không có kính.
    func testTheCardIsOpaqueFromTheFirstFrameOfAnExpand() throws {
        let rig = try mountRestingCard()
        rig.playback.play(rig.track, in: [rig.track])
        let frames = film(rig, for: 0.35)

        var checked = 0
        var checkedWhereGlassCouldShow = 0
        let glassWindow = Int(rig.rest.height * PlayerCard.collapseGlassStartRatio)
        for frame in frames {
            guard let tint = surfaceTint(frame), let cover = frame.cover else { continue }
            print(String(format: "[expand] t=%6.1fms top=%4d height=%3d tint=%5.1f",
                         frame.ms, cover.lowerBound, cover.count, tint))
            XCTAssertLessThan(tint, 10, "translucent at t=\(frame.ms)ms")
            checked += 1
            if cover.count < glassWindow { checkedWhereGlassCouldShow += 1 }
        }
        XCTAssertGreaterThan(checked, 3)
        // Kính chỉ có thể hiện khi thẻ dưới 2× viên kính: phải bắt được ít nhất
        // một khung ở đó, không thì "đặc" ở trên chỉ nói về những cỡ vốn không
        // bao giờ là kính.
        XCTAssertGreaterThan(checkedWhereGlassCouldShow, 0,
                             "no expand frame was caught while the card was under 2× the capsule")
    }
}
