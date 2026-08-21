import Foundation

/// Hẹn giờ ngủ: đếm ngược, báo lúc cần mờ dần, rồi báo lúc hết giờ.
///
/// **Nó không biết gì về audio.** Hai closure `onFadeOut` và `onExpire` là toàn
/// bộ chỗ nó chạm ra ngoài, và `PlaybackService` là chỗ nối chúng vào thứ phát
/// ra tiếng. Tách như vậy vì phần khó của tính năng này không nằm ở chỗ gọi
/// `pause()` — nó nằm ở đếm ngược, ở việc mờ đúng một lần, ở huỷ giữa chừng, và
/// ở đặt đè lên một hẹn đang chạy. Tất cả những thứ ấy kiểm được bằng một đồng
/// hồ giả trong vài mili giây, thay vì chờ ba mươi phút thật.
///
/// **Không lưu qua lần mở app, và đó là chủ ý.** Hẹn giờ ngủ gắn với phiên nghe
/// đang diễn ra. Mở app hôm sau mà nhạc tự tắt sau ba mươi phút thì người dùng
/// đọc ra là lỗi, không phải tính năng.
///
/// Đồng hồ tường, không phải bộ đếm: `endsAt` là một mốc thời gian, nên nếu tiến
/// trình bị treo hay `tick()` tới muộn, thời điểm dừng vẫn đúng chỗ đã hẹn.
@Observable
@MainActor
final class SleepTimer {
    /// Quãng mờ dần trước khi tắt hẳn.
    ///
    /// Mười lăm giây là đủ dài để tai không nhận ra chỗ bắt đầu, và đủ ngắn để
    /// người còn thức không phải ngồi nghe nhạc nhỏ dần suốt một phút.
    static let fadeDuration: TimeInterval = 15

    /// Các mốc bày ra trong menu.
    static let presetMinutes = [15, 30, 45, 60]

    private let now: () -> Date
    private var endsAt: Date?
    private var hasStartedFade = false

    /// Gọi khi tới lúc mờ dần, kèm số giây nên mờ trong đó.
    ///
    /// Tham số là quãng thời gian chứ không phải hằng số `fadeDuration`, vì một
    /// hẹn ngắn hơn quãng mờ phải mờ trong đúng thời gian còn lại — xem `start`.
    var onFadeOut: ((TimeInterval) -> Void)?

    /// Gọi đúng một lần khi hết giờ.
    var onExpire: (() -> Void)?

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    var isRunning: Bool { endsAt != nil }

    /// Số giây còn lại, hoặc `nil` khi không có hẹn nào.
    var remaining: TimeInterval? {
        guard let endsAt else { return nil }
        return max(0, endsAt.timeIntervalSince(now()))
    }

    /// Số phút bày ra trên nút, **làm tròn lên**.
    ///
    /// Làm tròn xuống thì còn chín mươi giây sẽ hiện "1 phút", và người đọc nghĩ
    /// mình còn ít hơn thực tế. Tệ hơn: ở giây cuối cùng nút sẽ hiện "0" trong
    /// lúc nhạc vẫn đang kêu.
    ///
    /// **Lưu trữ chứ không tính toán, và đó là chỗ dễ làm sai.** Một thuộc tính
    /// tính từ `now()` không đánh thức `@Observable` — không có gì thay đổi để
    /// nó nhận ra — nên số trên nút sẽ đứng im suốt ba mươi phút. Gán ở đây, và
    /// chỉ gán khi con số thật sự khác, nên player card vẽ lại **ba mươi lần**
    /// thay vì một nghìn tám trăm lần. Card ấy đang chạy sát ngân sách một
    /// khung hình, nên khoảng cách đó không phải chuyện làm đẹp.
    private(set) var minutesRemaining: Int?

    private func refreshMinutes() {
        let next = remaining.map { Int(ceil($0 / 60)) }
        if next != minutesRemaining { minutesRemaining = next }
    }

    func start(minutes: Int) {
        start(seconds: TimeInterval(minutes) * 60)
    }

    func start(seconds: TimeInterval) {
        // Đặt đè lên một hẹn đang mờ phải trả âm lượng về trước, nếu không nhạc
        // sẽ tiếp tục ở mức đã tụt và không có đường nào chỉnh lại trong app.
        restoreVolumeIfFading()
        endsAt = now().addingTimeInterval(seconds)
        hasStartedFade = false
        refreshMinutes()
    }

    func cancel() {
        restoreVolumeIfFading()
        endsAt = nil
        refreshMinutes()
    }

    /// Nhịp đếm, gọi từ ngoài vào.
    ///
    /// `SleepTimer` không tự nuôi `Timer` của riêng nó: `PlaybackService` đã có
    /// một nhịp nửa giây chạy sẵn trong lúc phát nhạc, và dựng thêm một nhịp thứ
    /// hai chỉ để đếm cùng một thứ là tốn mà không mua được gì.
    func tick() {
        guard let endsAt else { return }
        let left = endsAt.timeIntervalSince(now())

        if left <= 0 {
            self.endsAt = nil
            hasStartedFade = false
            refreshMinutes()
            onExpire?()
            return
        }

        refreshMinutes()

        if !hasStartedFade, left <= Self.fadeDuration {
            hasStartedFade = true
            // Mờ trong đúng thời gian còn lại, không phải lúc nào cũng mười lăm
            // giây: một hẹn ngắn hơn quãng mờ mà vẫn mờ mười lăm giây thì âm
            // lượng chưa xuống tới nơi nhạc đã tắt, và cú tắt ấy nghe như bị cắt.
            onFadeOut?(left)
        }
    }

    private func restoreVolumeIfFading() {
        guard hasStartedFade else { return }
        hasStartedFade = false
        onFadeOut?(0)
    }
}
