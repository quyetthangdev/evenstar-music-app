import XCTest
import SwiftUI
@testable import Evenstar

/// **Cú thu vẽ ra thật, từng khung**: thẻ **phồng đối xứng** quanh viên kính —
/// mép trên lên ~5pt, mép dưới xuống ~5pt, hai bên nở chút ít, rồi cùng về —
/// không mép nào lọt vào trong viên kính, chiều cao không bao giờ dưới viên
/// kính, mặt thẻ đặc lúc đầu và là kính lúc cuối.
///
/// Vì sao phồng chứ không dời hay giãn một phía: QA trên máy — dời xuống thì
/// viên kính hệ thống đứng yên lộ ra phía trên thẻ (IMG_2559,
/// `device3-bounce.png`); ghim mép trên thì "mép trên không đàn hồi như mép
/// dưới, nhìn như gãy". Xem `CollapseGlass` trong `PlayerCard.swift`.
///
/// `CollapseHandoffTests` ghim đường cong; ở đây là việc SwiftUI có vẽ đúng
/// đường cong ấy không — thứ phép tính không trả lời được: hình học có thật sự
/// dừng ở đích dưới `CustomAnimation`, cú phồng có thật sự chạy trên đường cong
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

    private typealias Landed = (ms: Double, cover: ClosedRange<Int>, column: Column, across: ClosedRange<Int>?)

    /// Những khung từ lúc hình học tới đích tới lúc thẻ bắt đầu mờ đi trao chỗ —
    /// dùng **cùng** một cách lọc cho cả hai cuộn phim.
    ///
    /// Tới đích là khung đầu tiên thẻ đã vào vùng phồng (xem dưới); từ đó mọi
    /// khung đều tính, kể cả đỉnh cú phồng cao ~63pt — lọc từng khung theo
    /// chiều cao thì chính các khung đỉnh rơi mất.
    /// Mờ đi là khung đầu tiên màu sọc lọt qua đậm hơn hẳn ~35–45 của kính:
    /// từ đó thẻ nửa trong suốt và không còn mép nào để đo. Đọc mốc từ ảnh chứ
    /// không từ `settlingTime`: đồng hồ của animation bắt đầu ở lượt cập nhật
    /// xử lý cú thả, trễ hơn mốc 0 của cuộn phim vài chục mili giây.
    private func landedFrames(_ frames: [Sample], rest: CGRect) -> [Landed] {
        let fading = frames.firstIndex { ($0.landedCover != nil) && (surfaceTint($0) ?? 999) > 60 }
            ?? frames.endIndex
        let measured: [Landed] = frames[..<fading]
            .compactMap { s in s.landedCover.map { (ms: s.ms, cover: $0, column: s.column, across: s.across) } }
        // Cú nén bắt đầu ngay khi chạm, nên có cuộn phim không có khung nào cao
        // đúng bằng viên kính trước khi cú nảy xong — mốc "tới đích" là thẻ đã
        // vào vùng chạm sàn: cao không quá viên kính + trần nén
        // (`squashCap`) + 4pt.
        let landingZone = Int(rest.height + BottomBarStyle.squashCap) + 4
        guard let arrival = measured.firstIndex(where: { $0.cover.count <= landingZone }) else { return [] }
        return Array(measured[arrival...])
    }

    /// Cú nén và cú giãn trong một cuộn phim, đo so với khung đã về chỗ: đáy
    /// võng sâu nhất (và lúc ấy), mép trên vươn cao nhất (và lúc ấy), cùng mép
    /// trên ở khung võng sâu nhất và đáy ở khung vươn cao nhất.
    private struct Bounce {
        var sag: Int, sagAt: Double, topAtSag: Int
        var rise: Int, riseAt: Double, bottomAtRise: Int
    }

    private func bounce(_ run: [Landed], settled: Landed) -> Bounce? {
        guard let deepest = run.max(by: { $0.cover.upperBound < $1.cover.upperBound }),
              let highest = run.min(by: { $0.cover.lowerBound < $1.cover.lowerBound }) else { return nil }
        return Bounce(sag: deepest.cover.upperBound - settled.cover.upperBound, sagAt: deepest.ms,
                      topAtSag: deepest.cover.lowerBound - settled.cover.lowerBound,
                      rise: settled.cover.lowerBound - highest.cover.lowerBound, riseAt: highest.ms,
                      bottomAtRise: highest.cover.upperBound - settled.cover.upperBound)
    }

    func testTheCardSquashesThenStretchesOnceAroundTheCapsule() throws {
        let rig = try mountRestingCard()
        openFully(rig)

        let start = 0.9
        let velocity: CGFloat = 1900
        dragDownAndRelease(rig, to: start, velocity: velocity)
        let frames = film(rig, for: 1.0)

        // Lịch mà thẻ chạy, để đặt cạnh thứ đo được.
        let travel = PlayerAnchor.dragTravel(for: rig.rest)
        let plan = LandingPlan(
            spring: BottomBarStyle.collapseSpring(afterDrag: true),
            initialVelocity: PlayerCard.settleVelocity(verticalVelocity: velocity, travel: travel,
                                                       from: start, to: 0),
            span: start, travel: travel
        )

        let restTop = Int(rig.rest.minY), restBottom = Int(rig.rest.maxY) - 1
        print("[landing] snapshot shift \(rig.shift)pt, rest rows \(restTop)–\(restBottom), column \(rig.column),"
              + " plan: impact \(String(format: "%.0f", plan.impact * 1000))ms, squash"
              + " \(String(format: "%.1f", plan.squashPeak))pt, done \(String(format: "%.0f", plan.duration * 1000))ms,"
              + " \(frames.count) frames")
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
        let measured = frames[..<fading]
            .compactMap { s in s.landedCover.map { (ms: s.ms, cover: $0, column: s.column, across: s.across) } }
        let landed = landedFrames(frames, rest: rig.rest)
        // Từ lúc chạm sàn tới lúc trao chỗ ~0,33s; một `drawHierarchy` tốn
        // ~30ms nên thường bắt được ~10 khung. Bốn là đủ cho các phép kiểm dưới.
        XCTAssertGreaterThanOrEqual(landed.count, 4, "too few frames caught the card at the capsule")

        // 1. Viên kính hệ thống luôn nằm trọn trong thẻ — suốt cú nén **và** cú
        // giãn: mép trên không bao giờ xuống dưới mép trên viên kính, đáy không
        // bao giờ lên trên đáy, hai bên không bao giờ lọt vào trong. Từng điểm
        // ảnh là 1pt: "≤ 0,5pt" là "không qua hàng".
        let restLeft = Int(rig.rest.minX), restRight = Int(rig.rest.maxX) - 1
        for frame in landed {
            XCTAssertLessThanOrEqual(frame.cover.lowerBound, restTop,
                                     "the top edge sank inside the capsule at t=\(frame.ms)ms")
            XCTAssertGreaterThanOrEqual(frame.cover.upperBound, restBottom,
                                        "the bottom edge rose inside the capsule at t=\(frame.ms)ms")
            let across = try XCTUnwrap(frame.across, "no card across the capsule at t=\(frame.ms)ms")
            XCTAssertLessThanOrEqual(across.lowerBound, restLeft, "left edge inside the capsule at t=\(frame.ms)ms")
            XCTAssertGreaterThanOrEqual(across.upperBound, restRight,
                                        "right edge inside the capsule at t=\(frame.ms)ms")
        }

        // 2. Khung cuối trước cú mờ là viên kính. Mép trên cho phép 2pt viền
        // kính phía trên (đo được: 703 cho mép 705).
        let settled = try XCTUnwrap(landed.last)
        let settledAcross = try XCTUnwrap(settled.across)
        XCTAssertTrue((restTop - 3)...restTop ~= settled.cover.lowerBound, "settled top \(settled.cover.lowerBound)")
        XCTAssertEqual(settled.cover.upperBound, restBottom, accuracy: 1, "settled bottom")
        XCTAssertEqual(settledAcross.lowerBound, restLeft, accuracy: 1, "settled left")
        XCTAssertEqual(settledAcross.upperBound, restRight, accuracy: 1, "settled right")

        // 3. Nén **rồi** giãn: đáy võng sâu nhất đến trước mép trên vươn cao
        // nhất; lúc võng mép trên ở yên, lúc vươn đáy ở yên.
        //
        // Hai cuộn phim giống hệt nhau, giữ cuộn đo rõ hơn: mỗi nửa chu kỳ chỉ
        // 80ms và một `drawHierarchy` tốn ~30ms, có khung ~60ms, nên một cuộn
        // có thể rơi hai bên đỉnh.
        openFully(rig)
        dragDownAndRelease(rig, to: start, velocity: velocity)
        let again = landedFrames(film(rig, for: 1.0), rest: rig.rest)
        let runs = [bounce(landed, settled: settled), again.last.flatMap { bounce(again, settled: $0) }]
            .compactMap { $0 }
        let best = try XCTUnwrap(runs.max(by: { min($0.sag, $0.rise) < min($1.sag, $1.rise) }))
        print("[landing] squash \(best.sag)pt at \(String(format: "%.0f", best.sagAt))ms (top moved \(best.topAtSag)pt),"
              + " stretch \(best.rise)pt at \(String(format: "%.0f", best.riseAt))ms (bottom moved \(best.bottomAtRise)pt);"
              + " runs \(runs.map { "\($0.sag)/\($0.rise)" }); handoff fade from"
              + " \(fading < frames.count ? String(format: "%.0f", frames[fading].ms) : "—")ms")
        XCTAssertGreaterThanOrEqual(best.sag, 3, "the bottom only sagged \(best.sag)pt")
        XCTAssertGreaterThanOrEqual(best.rise, 3, "the top only rose \(best.rise)pt")
        XCTAssertLessThan(best.sagAt, best.riseAt, "the stretch came before the squash")
        XCTAssertLessThanOrEqual(abs(best.topAtSag), 1, "the top moved during the squash")
        XCTAssertLessThanOrEqual(abs(best.bottomAtRise), 1, "the bottom moved during the stretch")
        XCTAssertLessThanOrEqual(best.sag, Int(BottomBarStyle.squashCap) + 1)

        // 4. Không bao giờ nhỏ hơn viên kính.
        let smallest = try XCTUnwrap(measured.map(\.cover.count).min())
        XCTAssertGreaterThanOrEqual(smallest, Int(rig.rest.height) - 1, "the card shrank to \(smallest)pt")

        // 5. Kính ở cuối: màu của nền lọt qua mặt thẻ — mọi khung từ lúc tới đích.
        for frame in landed {
            let rows = (frame.cover.lowerBound + 6)...(frame.cover.upperBound - 6)
            XCTAssertGreaterThan(frame.column.tint(rows), 20,
                                 "opaque at t=\(frame.ms)ms — the landed card should be glass")
        }

        // 6. Đặc lúc đầu: thẻ còn lớn, không chút màu nền nào lọt qua.
        let early = frames.filter { $0.ms < 90 }
        XCTAssertFalse(early.isEmpty)
        for frame in early {
            let tint = try XCTUnwrap(surfaceTint(frame), "no card at t=\(frame.ms)ms")
            XCTAssertLessThan(tint, 10, "translucent at t=\(frame.ms)ms while the card is still large")
        }

        // 7. Từ lúc thẻ đã nhỏ tới hết cú mờ trao tay: không có mảng tối nào
        // quanh viên kính — kính dưới `.opacity` của cả thẻ vẫn là kính.
        let firstLanded = try XCTUnwrap(frames.firstIndex { $0.landedCover != nil })
        for frame in frames[firstLanded...] {
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
