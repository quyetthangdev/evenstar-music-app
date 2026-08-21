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
    ///
    /// Năm và mười phút có mặt vì "tôi sắp ngủ rồi, cho nốt vài bài" là một ý
    /// định thật và không diễn đạt được bằng mười lăm. Trên sáu mươi thì dừng:
    /// ai còn muốn nghe lâu hơn một tiếng thì thật ra không muốn hẹn giờ.
    static let presetMinutes = [5, 10, 15, 30, 45, 60]

    /// Hai chế độ, thay thế nhau chứ không chồng nhau.
    ///
    /// Tách thành `enum` chứ không phải một `Bool` cạnh `endsAt`: hai trạng thái
    /// độc lập cho phép viết ra thứ vô nghĩa — vừa đếm ngược vừa chờ hết bài —
    /// và rồi phải nhớ tự tay loại trừ nó ở mọi chỗ đọc. Kiểu dữ liệu làm việc
    /// ấy thay, một lần.
    private enum Mode: Equatable {
        /// Đếm tới một mốc thời gian.
        case countdown(endsAt: Date)
        /// Chờ bài đang phát kết thúc. Không có đồng hồ nào ở đây, và đó là lý
        /// do người ta chọn nó: không ai biết bài còn bao lâu.
        case endOfTrack
    }

    private let now: () -> Date
    private var mode: Mode?
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

    var isRunning: Bool { mode != nil }

    /// Đang chờ bài hiện tại kết thúc. `PlaybackService.handleFinish` đọc cái này.
    var stopsAtTrackEnd: Bool { mode == .endOfTrack }

    /// Số giây còn lại, hoặc `nil` khi không có hẹn nào — **và cũng `nil` ở chế
    /// độ chờ hết bài**, vì ở đó không có mốc nào để đếm tới.
    var remaining: TimeInterval? {
        guard case let .countdown(endsAt) = mode else { return nil }
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
        mode = .countdown(endsAt: now().addingTimeInterval(seconds))
        hasStartedFade = false
        refreshMinutes()
    }

    /// Dừng khi bài đang phát kết thúc.
    ///
    /// Không mờ dần: bài tự đi hết chứ không bị ai cắt ngang, nên kéo âm lượng
    /// xuống ở mười lăm giây cuối sẽ làm hỏng đúng đoạn kết mà người dùng chọn
    /// chế độ này để được nghe trọn.
    func startAtEndOfTrack() {
        restoreVolumeIfFading()
        mode = .endOfTrack
        hasStartedFade = false
        refreshMinutes()
    }

    func cancel() {
        restoreVolumeIfFading()
        mode = nil
        refreshMinutes()
    }

    /// Bài vừa kết thúc, và đang có hẹn chờ đúng điều đó.
    ///
    /// `PlaybackService` gọi vào đây thay vì tự đọc `stopsAtTrackEnd` rồi tự
    /// dọn, để chỗ tắt hẹn nằm cùng chỗ với chỗ bật nó.
    func trackDidEnd() {
        guard mode == .endOfTrack else { return }
        mode = nil
        refreshMinutes()
        onExpire?()
    }

    /// Nhịp đếm, gọi từ ngoài vào.
    ///
    /// `SleepTimer` không tự nuôi `Timer` của riêng nó: `PlaybackService` đã có
    /// một nhịp nửa giây chạy sẵn trong lúc phát nhạc, và dựng thêm một nhịp thứ
    /// hai chỉ để đếm cùng một thứ là tốn mà không mua được gì.
    func tick() {
        // Chờ hết bài thì thời gian trôi không có nghĩa gì — chỉ `trackDidEnd()`
        // kết thúc được hẹn ấy.
        guard case let .countdown(endsAt) = mode else { return }
        let left = endsAt.timeIntervalSince(now())

        if left <= 0 {
            mode = nil
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
