import XCTest
import SwiftUI
@testable import Evenstar

/// **Cú thu vẽ ra thật, từng khung**: thẻ **giãn** trùm lên viên kính — mép
/// trên đứng yên ở mép trên viên kính, mép dưới võng ~10pt rồi về, hai mép bên
/// không bao giờ lọt vào trong — chiều cao không bao giờ dưới viên kính, mặt
/// thẻ đặc lúc đầu và là kính lúc cuối.
///
/// Vì sao giãn chứ không dời: QA trên máy (IMG_2559, `device3-bounce.png`) —
/// viên kính hệ thống đứng yên lộ ra phía trên một tấm thẻ dời xuống. Xem
/// `CollapseGlass` trong `PlayerCard.swift`.
///
/// `CollapseHandoffTests` ghim đường cong; ở đây là việc SwiftUI có vẽ đúng
/// đường cong ấy không — thứ phép tính không trả lời được: hình học có thật sự
/// dừng ở đích dưới `CustomAnimation`, cú giãn có thật sự chạy trên đường cong
/// của riêng nó, lớp kính có thật sự hiện ra.
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

    func testTheCollapseStretchesOverTheCapsuleWithoutShrinkingAndEndsInGlass() throws {
        let rig = try mountRestingCard()
        openFully(rig)

        let start = 0.9
        let velocity: CGFloat = 1900
        dragDownAndRelease(rig, to: start, velocity: velocity)
        let frames = film(rig, for: 1.1)

        // Cú lún mà phép tính đoán, để đặt cạnh cú lún đo được.
        let travel = PlayerAnchor.dragTravel(for: rig.rest)
        let relative = PlayerCard.settleVelocity(verticalVelocity: velocity, travel: travel,
                                                 from: start, to: 0)
        let spring = CollapseSpring(spring: BottomBarStyle.collapseSpring(afterDrag: true),
                                    initialVelocity: relative, stopsAtTarget: false)
        var deepest = 0.0
        var time = 0.0
        while let f = spring.fraction(at: time) { deepest = max(deepest, f - 1); time += 0.001 }
        let predicted = PlayerCard.landingSag(overshoot: deepest * start, travel: travel)

        let restTop = Int(rig.rest.minY), restBottom = Int(rig.rest.maxY) - 1
        print("[landing] snapshot shift \(rig.shift)pt, rest rows \(restTop)–\(restBottom), column \(rig.column),"
              + " predicted sag \(String(format: "%.1f", predicted))pt,"
              + " handoff at \(String(format: "%.0f", spring.settlingTime * 1000))ms, \(frames.count) frames")
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

        // Thẻ bắt đầu mờ đi — trao chỗ — khi cú đáp lắng. Từ đó nó nửa trong
        // suốt, màu sọc lọt qua đậm dần (độ đậm vượt ~45 của kính), và không
        // còn mép nào để đo; chỉ phép kiểm 5 nhìn qua mốc ấy. Đọc mốc từ ảnh
        // chứ không từ `settlingTime`: đồng hồ của animation bắt đầu ở lượt
        // cập nhật xử lý cú thả, trễ hơn mốc 0 của cuộn phim vài chục mili giây.
        let fading = frames.firstIndex { ($0.landedCover != nil) && (surfaceTint($0) ?? 999) > 60 }
            ?? frames.endIndex
        let measured = frames[..<fading]
            .compactMap { s in s.landedCover.map { (ms: s.ms, cover: $0, column: s.column, across: s.across) } }
        // Hình học đã tới đích: thẻ chỉ còn cỡ viên kính. Trước đó mép dưới
        // vốn nằm dưới viên kính — nó đi **lên** 91pt suốt cú thu — nên "lún"
        // chỉ có nghĩa từ đây.
        let landed = measured.filter { $0.cover.count <= Int(rig.rest.height * 1.25) }
        // Quãng đáp kéo dài ~0,34s (từ lúc chạm đích tới lúc trao chỗ); một
        // `drawHierarchy` tốn ~30ms ở đây nên thường bắt được ~11 khung. Bốn là
        // đủ cho các phép kiểm dưới — đỉnh lún phẳng trong ±40ms — và chừa chỗ
        // cho một máy chậm gấp đôi.
        XCTAssertGreaterThanOrEqual(landed.count, 4, "too few frames caught the card at the capsule's size")

        // 1. Mép dưới võng quá viên kính ~10pt, rồi về.
        //
        // Độ sâu đo bằng khung sâu nhất của **hai** cú thu giống hệt nhau. Một
        // `drawHierarchy` tốn ~30ms, có khung tới ~60ms, nên một cuộn phim có
        // lúc rơi hai bên đỉnh võng và đọc ra 8pt cho một đỉnh 10,7pt (đo được,
        // hai trong sáu lần chạy). Lần thứ hai lệch pha lấy mẫu với lần đầu;
        // lấy cái sâu hơn là đo đỉnh, không phải nới biên.
        openFully(rig)
        dragDownAndRelease(rig, to: start, velocity: velocity)
        let again = film(rig, for: 0.8)
        let againDeepest = again.compactMap { s -> Int? in
            guard let cover = s.landedCover, cover.count <= Int(rig.rest.height * 1.4) else { return nil }
            return cover.upperBound
        }.max() ?? 0
        let deepestBottom = try XCTUnwrap(landed.map(\.cover.upperBound).max())
        let dip = max(deepestBottom, againDeepest) - restBottom
        print("[landing] deepest bottom: first run \(deepestBottom), second run \(againDeepest)")
        XCTAssertGreaterThanOrEqual(dip, 8, "the card's bottom edge went only \(dip)pt below the capsule")
        XCTAssertLessThanOrEqual(dip, 12, "the card's bottom edge went \(dip)pt below the capsule")
        XCTAssertEqual(CGFloat(dip), predicted, accuracy: 2.5, "drawn \(dip)pt against \(predicted)pt computed")
        let peak = try XCTUnwrap(landed.firstIndex { $0.cover.upperBound == deepestBottom })
        XCTAssertGreaterThanOrEqual(deepestBottom - restBottom, 6, "the first run barely sagged")
        XCTAssertTrue(landed[peak...].contains { abs($0.cover.upperBound - restBottom) <= 1 },
                      "the card never came back up to the capsule's bottom edge")
        // …còn mép trên **đứng yên** ở mép trên viên kính: không có khung nào
        // viên kính hệ thống lộ ra phía trên thẻ (QA IMG_2559). Từng điểm ảnh
        // ở đây là 1pt, nên "≤ 0,5pt" là "không qua hàng của mép trên".
        for frame in landed {
            XCTAssertLessThanOrEqual(frame.cover.lowerBound, restTop,
                                     "the top edge sank to \(frame.cover.lowerBound) at t=\(frame.ms)ms")
        }
        // …và hai mép bên không bao giờ lọt vào trong hai mép viên kính.
        let restLeft = Int(rig.rest.minX), restRight = Int(rig.rest.maxX) - 1
        var widest = 0
        for frame in landed {
            let across = try XCTUnwrap(frame.across, "no card across the capsule at t=\(frame.ms)ms")
            XCTAssertLessThanOrEqual(across.lowerBound, restLeft, "left edge inside the capsule at t=\(frame.ms)ms")
            XCTAssertGreaterThanOrEqual(across.upperBound, restRight,
                                        "right edge inside the capsule at t=\(frame.ms)ms")
            widest = max(widest, across.count)
        }
        // Và nở ra thật: ở đỉnh cú võng rộng hơn lúc đã về chỗ.
        let settledWidth = try XCTUnwrap(landed.last?.across?.count)
        XCTAssertGreaterThanOrEqual(widest - settledWidth, 2,
                                    "the card did not widen: \(widest)pt at most against \(settledWidth)pt settled")

        // 2. Không bao giờ nhỏ hơn viên kính.
        let smallest = try XCTUnwrap(measured.map(\.cover.count).min())
        XCTAssertGreaterThanOrEqual(smallest, Int(rig.rest.height) - 1, "the card shrank to \(smallest)pt")

        // 3. Kính ở cuối: màu của nền lọt qua mặt thẻ.
        let glassy = landed.filter { $0.cover.count <= Int(rig.rest.height * 1.2) }
        XCTAssertGreaterThan(glassy.count, 3)
        for frame in glassy {
            let rows = (frame.cover.lowerBound + 6)...(frame.cover.upperBound - 6)
            XCTAssertGreaterThan(frame.column.tint(rows), 20,
                                 "opaque at t=\(frame.ms)ms — the landed card should be glass")
        }

        // 4. Đặc lúc đầu: thẻ còn lớn, không chút màu nền nào lọt qua.
        let early = frames.filter { $0.ms < 90 }
        XCTAssertFalse(early.isEmpty)
        for frame in early {
            let tint = try XCTUnwrap(surfaceTint(frame), "no card at t=\(frame.ms)ms")
            XCTAssertLessThan(tint, 10, "translucent at t=\(frame.ms)ms while the card is still large")
        }

        // 5. Từ lúc thẻ đã nhỏ tới hết cú mờ trao tay: không có mảng tối nào
        // quanh viên kính — kính dưới `.opacity` của cả thẻ vẫn là kính.
        let firstLanded = try XCTUnwrap(frames.firstIndex { $0.landedCover != nil })
        for frame in frames[firstLanded...] {
            let darkest = ((restTop - 4)...(restBottom + 20)).map { frame.column.sum($0) }.min() ?? 0
            XCTAssertGreaterThan(darkest, 250, "something dark was drawn at t=\(frame.ms)ms")
        }
        // …và cú mờ có thật sự kết thúc: thẻ đã nhường chỗ.
        XCTAssertNil(frames.last?.cover, "the card was still drawn \(frames.last?.ms ?? 0)ms after release")
        XCTAssertTrue(rig.expansion.isCardResting)
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
