import XCTest
import SwiftUI
@testable import Evenstar

final class TrackSwipeTests: XCTestCase {
    private let width: CGFloat = 234

    func testPastThirtyPercentLeftIsNext() {
        XCTAssertEqual(TrackSwipe.outcome(translation: -80, predictedTranslation: -80, width: width,
                                          canGoNext: true, canGoPrevious: true), .next)
    }

    func testPastThirtyPercentRightIsPrevious() {
        XCTAssertEqual(TrackSwipe.outcome(translation: 80, predictedTranslation: 80, width: width,
                                          canGoNext: true, canGoPrevious: true), .previous)
    }

    func testAShortSlowSwipeCancels() {
        XCTAssertEqual(TrackSwipe.outcome(translation: -30, predictedTranslation: -40, width: width,
                                          canGoNext: true, canGoPrevious: true), .cancel)
    }

    /// Một cú búng ngắn nhưng nhanh: dự đoán quá ngưỡng thì vẫn đổi bài.
    func testAShortFastFlickCommits() {
        XCTAssertEqual(TrackSwipe.outcome(translation: -30, predictedTranslation: -200, width: width,
                                          canGoNext: true, canGoPrevious: true), .next)
    }

    /// Review Focus 4: ở cuối hàng đợi không bao giờ gọi `next()`, vì khi tắt
    /// repeat nó dừng phát.
    func testNoNextNeverCommitsNext() {
        XCTAssertEqual(TrackSwipe.outcome(translation: -200, predictedTranslation: -400, width: width,
                                          canGoNext: false, canGoPrevious: true), .cancel)
    }

    /// Vùng thông tin bài chưa được đo (`infoWidth` bắt đầu ở 0): ngưỡng 30%
    /// của 0 là 0, và chỉ một cú nhích cũng đổi bài. Chưa đo thì không đổi.
    func testBeforeTheWidthIsMeasuredNothingCommits() {
        XCTAssertEqual(TrackSwipe.outcome(translation: -12, predictedTranslation: -12, width: 0,
                                          canGoNext: true, canGoPrevious: true), .cancel)
        XCTAssertEqual(TrackSwipe.outcome(translation: 12, predictedTranslation: 300, width: 0,
                                          canGoNext: true, canGoPrevious: true), .cancel)
    }

    func testNoPreviousNeverCommitsPrevious() {
        XCTAssertEqual(TrackSwipe.outcome(translation: 200, predictedTranslation: 400, width: width,
                                          canGoNext: true, canGoPrevious: false), .cancel)
    }

    func testTheContentFollowsTheFingerWhenThereIsSomewhereToGo() {
        XCTAssertEqual(TrackSwipe.displayedOffset(translation: -60, canGoNext: true, canGoPrevious: true), -60)
        XCTAssertEqual(TrackSwipe.displayedOffset(translation: 60, canGoNext: true, canGoPrevious: true), 60)
    }

    func testTheContentRubberBandsWhenThereIsNowhereToGo() {
        XCTAssertEqual(TrackSwipe.displayedOffset(translation: -60, canGoNext: false, canGoPrevious: true),
                       -60 * TrackSwipe.rubberBandFactor)
        XCTAssertEqual(TrackSwipe.displayedOffset(translation: 60, canGoNext: true, canGoPrevious: false),
                       60 * TrackSwipe.rubberBandFactor)
    }

    // MARK: - Presentation

    func testTheContentSlidesWithTheFinger() {
        XCTAssertEqual(TrackSwipe.slide(travel: -60, reduceMotion: false), -60)
    }

    /// Giảm chuyển động: không trượt, chỉ mờ.
    func testReduceMotionNeverSlides() {
        XCTAssertEqual(TrackSwipe.slide(travel: -60, reduceMotion: true), 0)
        XCTAssertEqual(TrackSwipe.slide(travel: 200, reduceMotion: true), 0)
    }

    func testTheContentFadesWithDistance() {
        XCTAssertEqual(TrackSwipe.opacity(travel: 0, width: width), 1)
        XCTAssertEqual(TrackSwipe.opacity(travel: -width / 2, width: width), 1 - TrackSwipe.maxFade / 2, accuracy: 1e-9)
        XCTAssertEqual(TrackSwipe.opacity(travel: width / 2, width: width), 1 - TrackSwipe.maxFade / 2, accuracy: 1e-9)
    }

    func testTheFadeStopsAtOneWidth() {
        XCTAssertEqual(TrackSwipe.opacity(travel: -3 * width, width: width), 1 - TrackSwipe.maxFade, accuracy: 1e-9)
    }

    /// Trước lần đo đầu tiên `width` là 0 — hàng đứng yên không được mờ.
    func testAtRestTheContentIsFullyOpaqueEvenBeforeItIsMeasured() {
        XCTAssertEqual(TrackSwipe.opacity(travel: 0, width: 0), 1)
    }

    func testAZeroWidthDoesNotDivideByZero() {
        XCTAssertEqual(TrackSwipe.opacity(travel: 10, width: 0), 1 - TrackSwipe.maxFade, accuracy: 1e-9)
    }
}

// MARK: - Cú trượt vào của bài mới

/// Bài mới vào **từ phía đối diện** bài cũ vừa ra, ở mọi khung — một lần ghi
/// có animation, không có cú nhảy nào để SwiftUI gộp mất (xem
/// `TrackSwipe.Entry`).
@MainActor
final class TrackSwipeEntryTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    /// Phép tính: bài cũ ra tới `exit`, rồi cùng một đường cong `s` đưa
    /// `travel` từ `exit` về 0 và `phase` từ `count − 1` về `count`. Tổng là
    /// `−exit·(1 − s)`: đúng phía đối diện ở đầu, đúng 0 ở cuối, kể cả lúc lò
    /// xo vượt đích.
    func testTheNewTrackStartsOppositeTheExitAndLandsAtZero() {
        for exit: CGFloat in [-234, 234] {
            var entry = TrackSwipe.Entry()
            entry.begin(after: exit)
            for s in stride(from: 0.0, through: 1.1, by: 0.05) {
                let travel = exit * CGFloat(1 - s)
                let shown = TrackSwipe.slide(travel: travel,
                                             entry: entry.offset(phase: Double(entry.count - 1) + s),
                                             reduceMotion: false)
                XCTAssertEqual(shown, -exit * CGFloat(1 - s), accuracy: 1e-6, "exit \(exit), s \(s)")
            }
        }
    }

    func testAtRestTheEntryAddsNothing() {
        var entry = TrackSwipe.Entry()
        XCTAssertEqual(entry.offset(phase: 0), 0)
        entry.begin(after: -200)
        XCTAssertEqual(entry.offset(phase: Double(entry.count)), 0)
        XCTAssertEqual(TrackSwipe.slide(travel: -80, entry: 50, reduceMotion: true), 0, "Reduce Motion: no slide")
    }

    /// Thật, trên màn hình: một khối trong một khung cắt, đã trượt ra hẳn bên
    /// phải. Một lần ghi có animation — như `MiniPlayerAccessory.finishSwipe`
    /// — và ở **mọi** khung khối ấy nằm bên trái chỗ nghỉ, tiến dần về đó.
    /// Đường cũ (nhảy ngoài animation, rồi animate ở lượt sau) mà bị gộp thì
    /// khối vào từ bên phải.
    private struct Probe: View {
        @MainActor static var begin: (() -> Void)?
        @State private var travel: CGFloat = 300
        @State private var entry = TrackSwipe.Entry()

        var body: some View {
            Color.red
                .frame(width: 100, height: 40)
                .modifier(TrackSwipeSlide(travel: travel, entry: entry, reduceMotion: false))
                .frame(width: 300, height: 40, alignment: .leading)
                .clipped()
                .background(Color.white)
                .onAppear {
                    Probe.begin = {
                        withAnimation(.linear(duration: 0.5)) {
                            travel = 0
                            entry.begin(after: 300)
                        }
                    }
                }
        }
    }

    /// Cột đầu và cột sau cột cuối của khối đỏ, hay `nil` khi khối khuất hẳn.
    ///
    /// Cùng cách `LivePixels` trong `ReduceMotionSurfacesTests`: ép bố cục rồi
    /// `CALayer.render(in:)` vào một ngữ cảnh lật trục, neo ở góc trên trái.
    private func blockEdges(_ view: UIView) -> (left: Int, right: Int)? {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let width = 300, height = 40
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        view.layer.render(in: context)
        let red = (0..<width).filter { column in
            let p = (20 * width + column) * 4
            return data[p] > 200 && data[p + 1] < 80 && data[p + 2] < 80
        }
        guard let first = red.first, let last = red.last else { return nil }
        return (first, last + 1)
    }

    func testOnScreenTheNewTrackComesInFromTheOppositeSide() throws {
        let root = Probe()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()
        let host = UIHostingController(rootView: root)
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let window = UIWindow(frame: host.view.frame)
        window.rootViewController = host
        window.isHidden = false
        self.window = window
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertNil(blockEdges(host.view), "the block should start fully slid out to the right")

        try XCTUnwrap(Probe.begin)()
        var rights: [Int] = []
        let start = Date()
        while Date().timeIntervalSince(start) < 0.7 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            guard let edges = blockEdges(host.view) else {
                rights.append(0)
                continue
            }
            // Bên phải chỗ nghỉ (cạnh trái > 0): đang vào từ phía bài cũ ra.
            XCTAssertEqual(edges.left, 0, "came in from the right, edges \(edges)")
            rights.append(edges.right)
        }
        print("[entry] right edges \(rights)")
        for (earlier, later) in zip(rights, rights.dropFirst()) {
            XCTAssertLessThanOrEqual(earlier, later, "moved back the way it came: \(rights)")
        }
        XCTAssertTrue(rights.contains { $0 < 90 }, "never caught on its way in: \(rights)")
        XCTAssertEqual(try XCTUnwrap(rights.last), 100, "did not land at rest")
        Probe.begin = nil
    }
}
