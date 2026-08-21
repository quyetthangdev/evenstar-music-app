import XCTest
@testable import Evenstar

/// Hẹn giờ ngủ, tách khỏi mọi thứ phát ra tiếng.
///
/// `SleepTimer` không biết gì về audio — nó chỉ biết "còn bao lâu" và gọi hai
/// closure đúng lúc. Nhờ vậy toàn bộ phần khó của tính năng (đếm ngược, mờ dần
/// trước khi hết, huỷ giữa chừng, đặt đè lên một hẹn đang chạy) kiểm được bằng
/// một đồng hồ giả, không cần phần cứng và không cần chờ ba mươi phút thật.
///
/// Đồng hồ tiêm vào là lý do duy nhất file này chạy trong vài mili giây.
@MainActor
final class SleepTimerTests: XCTestCase {
    /// Đồng hồ giả: thời gian chỉ nhích khi test bảo nó nhích.
    private final class FakeClock {
        var now: Date = Date(timeIntervalSince1970: 1_000_000)
        func advance(_ seconds: TimeInterval) { now += seconds }
    }

    private var clock: FakeClock!
    private var faded: [TimeInterval] = []
    private var expiredCount = 0

    override func setUp() {
        super.setUp()
        clock = FakeClock()
        faded = []
        expiredCount = 0
    }

    private func makeTimer() -> SleepTimer {
        let clock = self.clock!
        let timer = SleepTimer(now: { clock.now })
        timer.onFadeOut = { [weak self] duration in self?.faded.append(duration) }
        timer.onExpire = { [weak self] in self?.expiredCount += 1 }
        return timer
    }

    // MARK: - Trạng thái cơ bản

    func testATimerStartsOff() {
        let timer = makeTimer()
        XCTAssertFalse(timer.isRunning)
        XCTAssertNil(timer.remaining)
    }

    func testStartingSetsTheRemainingTime() {
        let timer = makeTimer()
        timer.start(minutes: 30)
        XCTAssertTrue(timer.isRunning)
        XCTAssertEqual(timer.remaining, 30 * 60)
    }

    func testCancellingClearsEverything() {
        let timer = makeTimer()
        timer.start(minutes: 30)
        timer.cancel()
        XCTAssertFalse(timer.isRunning)
        XCTAssertNil(timer.remaining)
    }

    // MARK: - Đếm ngược

    func testRemainingShrinksAsTimePasses() {
        let timer = makeTimer()
        timer.start(minutes: 30)
        clock.advance(10 * 60)
        timer.tick()
        XCTAssertEqual(timer.remaining, 20 * 60)
    }

    /// Số phút hiện trên nút, làm tròn LÊN.
    ///
    /// Còn 90 giây mà hiện "1 phút" thì người đọc nghĩ mình còn ít hơn thực tế;
    /// và ở giây cuối cùng nút phải còn hiện "1", không được nhảy về "0" trong
    /// lúc nhạc vẫn đang kêu.
    func testTheMinutesShownRoundUp() {
        let timer = makeTimer()
        timer.start(minutes: 30)

        clock.advance(28 * 60 + 30)   // còn 90 giây
        timer.tick()
        XCTAssertEqual(timer.minutesRemaining, 2)

        clock.advance(59)             // còn 31 giây
        timer.tick()
        XCTAssertEqual(timer.minutesRemaining, 1)
    }

    // MARK: - Mờ dần

    func testTheFadeStartsOnceAndOnlyOnce() {
        let timer = makeTimer()
        timer.start(minutes: 30)

        clock.advance(30 * 60 - SleepTimer.fadeDuration - 1)
        timer.tick()
        XCTAssertEqual(faded, [], "chưa tới lúc mờ")

        // Quãng mờ nhận được là thời gian còn lại THẬT (14 giây), không phải
        // hằng số 15. Nhịp gọi `tick()` rơi vào đâu thì mờ từ đó, nên con số
        // gần như không bao giờ đúng bằng `fadeDuration` — và phải như vậy, để
        // âm lượng chạm 0 đúng lúc nhạc tắt chứ không sớm hơn.
        clock.advance(2)
        timer.tick()
        XCTAssertEqual(faded, [14], "phải bắt đầu mờ, trong đúng 14 giây còn lại")

        timer.tick()
        timer.tick()
        XCTAssertEqual(faded, [14],
                       "tick tiếp không được gọi mờ lần nữa — âm lượng sẽ giật lại về đầu dốc")
    }

    /// Đặt hẹn ngắn hơn cả quãng mờ.
    ///
    /// Không có ca này thì `start(minutes:)` với một phút sẽ tính ra quãng mờ
    /// dài hơn thời gian còn lại, và âm lượng giảm chưa tới nơi thì nhạc đã tắt.
    func testAShortTimerFadesOverWhateverTimeIsLeft() {
        let timer = makeTimer()
        timer.start(seconds: 10)
        timer.tick()
        XCTAssertEqual(faded, [10], "quãng mờ phải co lại bằng thời gian còn lại")
    }

    // MARK: - Hết giờ

    func testExpiringFiresOnceAndStopsTheTimer() {
        let timer = makeTimer()
        timer.start(minutes: 30)

        clock.advance(30 * 60)
        timer.tick()
        XCTAssertEqual(expiredCount, 1)
        XCTAssertFalse(timer.isRunning, "hết giờ rồi thì không còn chạy nữa")

        timer.tick()
        XCTAssertEqual(expiredCount, 1, "tick sau khi hết giờ không được gọi lại")
    }

    func testCancellingBeforeTheEndNeverExpires() {
        let timer = makeTimer()
        timer.start(minutes: 30)
        clock.advance(29 * 60)
        timer.tick()
        timer.cancel()

        clock.advance(10 * 60)
        timer.tick()
        XCTAssertEqual(expiredCount, 0, "đã huỷ thì không bao giờ được nổ")
    }

    /// Huỷ sau khi đã bắt đầu mờ phải trả âm lượng về.
    ///
    /// Không có bước này thì người dùng huỷ hẹn ở giây thứ năm của quãng mờ sẽ
    /// nghe nhạc tiếp ở một nửa âm lượng, và không có cách nào chỉnh lại trong
    /// app ngoài việc tắt mở lại bài.
    func testCancellingMidFadeRestoresTheVolume() {
        let timer = makeTimer()
        timer.start(minutes: 30)
        clock.advance(30 * 60 - SleepTimer.fadeDuration + 1)
        timer.tick()
        XCTAssertEqual(faded, [14], "đang mờ, còn 14 giây")

        timer.cancel()
        XCTAssertEqual(faded, [14, 0],
                       "huỷ giữa lúc mờ phải trả âm lượng về ngay")
    }

    // MARK: - Đặt đè

    func testStartingAgainReplacesTheRunningTimer() {
        let timer = makeTimer()
        timer.start(minutes: 15)
        clock.advance(14 * 60)
        timer.tick()

        timer.start(minutes: 30)
        XCTAssertEqual(timer.remaining, 30 * 60, "hẹn mới tính lại từ đầu")

        clock.advance(2 * 60)
        timer.tick()
        XCTAssertEqual(expiredCount, 0, "hẹn cũ đã bị thay, không được nổ theo lịch cũ")
    }

    /// Đặt đè lúc đang mờ phải mở âm lượng trở lại.
    func testStartingAgainMidFadeRestoresTheVolume() {
        let timer = makeTimer()
        timer.start(seconds: 5)
        timer.tick()
        XCTAssertEqual(faded, [5], "đang mờ")

        timer.start(minutes: 30)
        XCTAssertEqual(faded, [5, 0], "hẹn mới phải trả âm lượng về trước khi đếm lại")
    }

    // MARK: - Hết bài hiện tại

    /// Chế độ này không có đồng hồ, và đó là điểm khác biệt cốt lõi.
    ///
    /// Người ta chọn nó chính vì **không** biết bài còn bao lâu — không diễn đạt
    /// được bằng phút. Nên `remaining` và `minutesRemaining` phải là `nil`, và
    /// nút không được hiện con số nào.
    func testEndOfTrackHasNoCountdown() {
        let timer = makeTimer()
        timer.startAtEndOfTrack()

        XCTAssertTrue(timer.isRunning)
        XCTAssertTrue(timer.stopsAtTrackEnd)
        XCTAssertNil(timer.remaining, "không có mốc thời gian nào để đếm tới")
        XCTAssertNil(timer.minutesRemaining, "nút không được hiện số phút")
    }

    /// Thời gian trôi không làm gì cả ở chế độ này.
    func testEndOfTrackNeverExpiresOnItsOwn() {
        let timer = makeTimer()
        timer.startAtEndOfTrack()

        clock.advance(3 * 60 * 60)
        timer.tick()
        timer.tick()

        XCTAssertEqual(expiredCount, 0, "chỉ bài kết thúc mới kết thúc hẹn này")
        XCTAssertEqual(faded, [], "không mờ dần — bài tự hết, không ai cắt nó")
        XCTAssertTrue(timer.isRunning)
    }

    func testCancellingEndOfTrackStopsIt() {
        let timer = makeTimer()
        timer.startAtEndOfTrack()
        timer.cancel()
        XCTAssertFalse(timer.isRunning)
        XCTAssertFalse(timer.stopsAtTrackEnd)
    }

    /// Hai chế độ thay thế nhau, không chồng lên nhau.
    func testTheTwoModesReplaceEachOther() {
        let timer = makeTimer()

        timer.start(minutes: 30)
        timer.startAtEndOfTrack()
        XCTAssertTrue(timer.stopsAtTrackEnd)
        XCTAssertNil(timer.remaining, "hẹn đếm ngược phải bị thay hẳn")

        timer.start(minutes: 30)
        XCTAssertFalse(timer.stopsAtTrackEnd, "và ngược lại")
        XCTAssertEqual(timer.remaining, 30 * 60)
    }

    /// Mốc bày ra trong menu, khớp thứ tự người dùng đọc.
    func testThePresetsAreTheOnesOffered() {
        XCTAssertEqual(SleepTimer.presetMinutes, [5, 10, 15, 30, 45, 60])
    }
}
