import SwiftUI

/// How far the player card has opened, 0 collapsed to 1 full screen.
///
/// A reference type rather than a `Binding` back to `RootView`, and that is the
/// whole point of the file.
///
/// The first version published this through a `@Binding` written from an
/// `onChange`. That cost two update passes per frame of a drag: the card's own
/// body ran, then `onChange` fired, then the write invalidated `RootView`, whose
/// body rebuilds the `TabView` and its five tabs for SwiftUI to diff. The recede
/// was visibly rough, and no amount of making the *effect* cheaper could fix it,
/// because the cost was not in the effect.
///
/// `@Observable` scopes the invalidation to whoever actually reads `progress` in
/// a body — here, one `ViewModifier` that applies a transform. `RootView`'s body
/// does not read it and so does not re-run, and the tab hierarchy is built once.
@MainActor
@Observable
final class PlayerExpansion {
    /// Không còn `didSet`, và đó là kết luận của cả một buổi đo.
    ///
    /// Ở đây từng có một cờ `prefersDarkChrome` lật ở 0.5, nuôi một
    /// `preferredColorScheme` ở gốc để ép cả cửa sổ sang tối trong lúc player
    /// mở. Nó hỏng theo hai cách:
    ///
    ///   - **Thấy được:** ở chế độ sáng, mở player làm cả phần UI còn lại đen
    ///     theo — trong lúc morph và cả sau khi đã thu.
    ///   - **Đo được:** đổi color scheme ở gốc bắt mọi view trong cửa sổ tính
    ///     lại màu và vẽ lại. Quay màn hình 30fps trên máy thật rồi phân tích
    ///     từng khung: hai khung ĐỨNG IM (66ms) rồi độ sáng trung bình toàn màn
    ///     nhảy 21 → 197 trong một khung, đúng lúc ngón tay rời màn hình.
    ///
    /// Cách chữa không phải dời cú lật đi chỗ khác mà là **bỏ hẳn**: chrome mở
    /// rộng tự tô tối bằng `\.colorScheme` trong environment, thứ đi xuôi
    /// xuống và không chạm tới cửa sổ. Xem `expandedContent` trong `PlayerCard`.
    var progress: Double = 0

    /// Đường cong cho **lần đổi `progress` kế tiếp**. `nil` nghĩa là bám ngón
    /// tay, không nội suy.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// VÌ SAO KHÔNG DỰA VÀO `withAnimation` Ở CHỖ GÁN
    /// ─────────────────────────────────────────────────────────────────────
    /// `PlayerCard` gán `progress` bên trong `withAnimation`, và với một
    /// `@Observable` thì transaction ấy *thường* đi theo tới view đọc nó. Ở đây
    /// nó không tới: view duy nhất đọc `progress` là `RecedeBehindPlayer`, và
    /// nó bọc một `TabView` — thứ do UIKit dựng bên dưới.
    ///
    /// Đo trên máy thật, 30fps, một cú vuốt thu nhỏ: mép dưới nội dung đứng ở
    /// y 797 suốt **chín khung** rồi nhảy xuống 828 trong một khung. Đúng 31
    /// điểm, và `(1 − recedeScale) × chiều cao / 2 = 33.8`. Tức cú thu nhỏ giữ
    /// nguyên mức đầy suốt cú đáp của thẻ rồi tắt phụt — trong khi chính cái
    /// thẻ đã về hình viên thuốc từ trước đó.
    ///
    /// Trong lúc kéo thì không lộ, vì mỗi khung là một giá trị mới và không cần
    /// nội suy gì cả. Chỉ đúng cú nội suy một-lần lúc thả là mất.
    ///
    /// Nên đường cong được nói ra ở đây, và `RecedeBehindPlayer` tự
    /// `.animation(_:value:)` lấy — một đường đi không phụ thuộc transaction
    /// nào băng qua ranh giới UIKit.
    ///
    /// `@ObservationIgnored`: đặt nó không được phép tự kích hoạt vẽ lại. Người
    /// gán luôn đặt nó **trước** `progress`, nên khi thân view chạy lại vì
    /// `progress` đổi thì giá trị ở đây đã đúng.
    @ObservationIgnored var animation: Animation?

    /// Đặt đường cong rồi đặt đích, đúng thứ tự ấy.
    func set(progress newValue: Double, animation: Animation?) {
        self.animation = animation
        self.progress = newValue
    }

    // MARK: - Accessory

    /// Khung accessory mới nhất đo được **lúc thẻ đang nghỉ**, toạ độ global.
    ///
    /// Không quan sát: hệ thống dời accessory mỗi lần thanh tab thu nhỏ, và
    /// không view nào cần dựng lại vì chuyện đó. Chỉ `leaveRest()` đọc nó.
    @ObservationIgnored private(set) var accessoryFrame: CGRect = .zero
    @ObservationIgnored private(set) var accessoryIsInline = false

    /// Cỡ màn hình vật lý, do `PlayerCard` ghi từ `GeometryReader` của nó.
    ///
    /// Đổi trong lúc thẻ không nghỉ — xoay máy khi player đang mở — thì neo
    /// phải đi theo: xem `reanchor()`.
    @ObservationIgnored var screenSize: CGSize = .zero {
        didSet {
            guard screenSize != oldValue, !isCardResting else { return }
            reanchor()
        }
    }

    /// Khung thẻ bung ra từ đó, chụp **lúc thẻ rời trạng thái nghỉ** và giữ
    /// nguyên tới khi thẻ về nghỉ — trừ khi màn hình xoay trong lúc ấy, xem
    /// `reanchor()`. Không đọc thẳng `accessoryFrame` trong lúc bung: khung
    /// đo được lúc thẻ mở không phải khung của chỗ nghỉ (thời còn
    /// `recedeScale` < 1, nội dung lùi lại làm nó co theo).
    private(set) var anchorFrame: CGRect = .zero
    /// Accessory có đang ở `.inline` lúc thẻ rời nghỉ không. Hàng mini player
    /// trong thẻ đọc nó để ẩn ⏭ giống hệt accessory ở khung đầu.
    private(set) var anchorIsInline = false

    /// Cỡ biểu tượng và cỡ chữ mà hệ thống đặt cho nội dung accessory, đo được
    /// mới nhất. Không quan sát, cùng lẽ với `accessoryFrame`.
    @ObservationIgnored private(set) var accessoryTextStyle = AccessoryTextStyle.systemDefault
    /// …và bản chụp lúc thẻ rời nghỉ. Hàng mini của thẻ vẽ theo nó, để trùng
    /// khít hàng của accessory — xem `AccessoryTextStyle`.
    private(set) var anchorTextStyle = AccessoryTextStyle.systemDefault

    /// Thẻ đang nằm yên ở 0 và vô hình, còn accessory đang hiện nội dung của nó.
    private(set) var isCardResting = true

    /// Viên kính của hệ thống, ẩn tạm trong lúc thẻ hạ cánh — xem
    /// `AccessoryCapsule`. Mọi lối ra khỏi cú hạ cánh đi qua đây đều hiện nó
    /// lại: `leaveRest()` và `arriveAtRest()`.
    @ObservationIgnored let capsule = AccessoryCapsule()

    init() {
        // Viên kính đang ẩn thì một lớp trong suốt nhận chạm thay nó — chạm
        // vào viên thuốc giữa cú hạ cánh vẫn mở lại thẻ, như trước.
        capsule.onTap = { [weak self] in self?.requestExpand() }
    }

    /// Một cú thu đã được quyết (`PlayerCard.morph(to: 0…)`) và thẻ chưa về
    /// nghỉ — tức đang ở giữa lò xo, hoặc trong cú mờ trao tay.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// VÌ SAO KHÔNG CHỈ DỰA VÀO `isCardResting`
    /// ─────────────────────────────────────────────────────────────────────
    /// `isCardResting` chỉ lật khi cú thu đã **xong hẳn** — thẻ đã tới đích (xem
    /// `PlayerCard.morph(to:curves:)`). Trong khi ấy thẻ phải biết mình đang
    /// thu hay đang mở: chỉ khi thu, mặt thẻ mới chuyển sang kính ở đoạn cuối
    /// (`cardSurfaceIsGlass`). Chiều mở và lúc kéo thì thẻ đặc từ khung đầu.
    ///
    /// **Không** còn quyết accessory hiện nội dung lúc nào. Bản trước
    /// (`fbc0837`) cho accessory hiện ngay lúc quyết thu, nằm sẵn dưới một tấm
    /// thẻ đặc rồi thẻ mờ đi ở 2% cuối. Thẻ giờ là kính trong suốt từ lúc còn
    /// cao gấp đôi viên kính — hàng mini của nó khi ấy còn ở trên hàng của
    /// accessory tới ~40pt — nên một hàng nằm dưới sẽ **hiện xuyên qua** thành
    /// hai dòng chữ lệch nhau. Xem `showsAccessoryContent`.
    ///
    /// Lật bên trong `withAnimation` của cú thu, nên lớp kính (`CardSurface`)
    /// đi theo đường cong của hình học thay vì bật một bậc — chuyện này chỉ lộ
    /// khi thả tay lúc thẻ đã gần bằng viên kính.
    private(set) var isCollapsing = false

    /// Accessory có nên vẽ nội dung của nó không: **chỉ lúc nghỉ**.
    ///
    /// Suốt cú thu, chính thẻ vẽ hàng mini — trên một mặt kính trong suốt, và
    /// lệch khỏi viên kính cho tới khi hình học tới đích — nên hàng của
    /// accessory phải vắng mặt, không thì nó hiện xuyên qua thẻ. Kể cả khi đã
    /// trùng chỗ: chữ của hai hàng chồng nhau qua một lớp kính không đọc ra là
    /// một hàng. Nó hiện lại đúng lúc thẻ về nghỉ — bước hai của cú trao tay
    /// (`BottomBarStyle.collapseHandoff`): thẻ đã tới đích, mặt kính của thẻ đã
    /// tan, và hàng y hệt của thẻ biến mất trong cùng lượt ấy.
    var showsAccessoryContent: Bool { isCardResting }

    /// Bước một của cú trao tay đã chạy: **mặt** thẻ đã nhường cho viên kính của
    /// hệ thống, chỉ còn hàng mini của thẻ — xem
    /// `BottomBarStyle.collapseHandoff`. Giữ nguyên lúc nghỉ (thẻ vô hình
    /// thì nó không vẽ ra gì), và tắt ngay khi rời nghỉ, ngoài mọi animation:
    /// thẻ mở ra đặc từ khung đầu như trước.
    private(set) var cardSurfaceHandedOver = false

    /// Mặt thẻ có được phép là kính không — xem `CardSurface` trong
    /// `PlayerCard.swift`. Đúng khi thẻ đang thu, và cả lúc nghỉ.
    ///
    /// Lúc nghỉ vì cú trao tay: `arriveAtRest()` hạ `isCollapsing` trong cùng
    /// lượt nó dựng `isCardResting`, ở bước hai của cú trao tay. Mặt thẻ khi ấy
    /// đã tan (`cardSurfaceHandedOver`), nhưng giữ nó là kính thì bước hai
    /// không có gì phải đổi ở mặt thẻ cả. Thẻ nghỉ thì vô hình, nên kính ở đó
    /// không vẽ ra gì; rời nghỉ là cờ này tắt ngay, ngoài mọi animation, và
    /// thẻ đặc từ khung đầu.
    var cardSurfaceIsGlass: Bool { isCollapsing || isCardResting }

    /// Phần `progress` do cú kéo trên accessory đóng góp; 0 khi không kéo.
    /// `PlayerCard` cộng nó vào `progress` của mình mỗi khung. Không đi qua
    /// `onChange`, vì mỗi `onChange` là thêm một lượt cập nhật.
    private(set) var accessoryDragDelta: Double = 0
    private(set) var accessoryDragging = false

    /// Ý định gửi từ accessory sang thẻ. Chỉ thẻ thực hiện được cú bung có
    /// animation, vì `morph` và trạng thái `settled` là của riêng nó.
    private(set) var intent: PlayerIntent?

    /// Đã gửi `.release` cho cú kéo hiện tại và thẻ chưa nhận nó. Chặn
    /// `cancelAccessoryDrag()` gửi lần hai khi trạng thái cử chỉ reset ngay sau
    /// một cú thả bình thường. Không quan sát: không view nào vẽ theo nó.
    @ObservationIgnored private var releasePending = false

    /// Bản chụp lúc rời nghỉ: cỡ màn, khung và vị trí inline. Xoay đi rồi xoay
    /// về đúng cỡ này thì neo về lại đúng bản chụp.
    @ObservationIgnored private var anchorScreen: CGSize = .zero
    @ObservationIgnored private var capturedAnchor = (frame: CGRect.zero, isInline: false)
    /// Lần báo khung gần nhất **từ lúc rời nghỉ**. Không dùng khi cỡ màn còn
    /// là cỡ lúc chụp; chỉ để `reanchor()` lấy khi màn hình xoay.
    @ObservationIgnored private var awayReport: (frame: CGRect, isInline: Bool)?

    func reportAccessoryTextStyle(_ style: AccessoryTextStyle) {
        accessoryTextStyle = style
    }

    func reportAccessoryFrame(_ frame: CGRect, isInline: Bool) {
        guard isCardResting else {
            // Lúc thẻ mở, khung báo lên chỉ có nghĩa khi màn hình đã xoay khỏi
            // cỡ lúc chụp. Giữ lại cả khi chưa: accessory và `PlayerCard` báo
            // cỡ mới theo thứ tự không định trước, nên khung mới có thể tới
            // ngay **trước** cỡ màn mới.
            awayReport = (frame, isInline)
            if screenSize != anchorScreen { reanchor() }
            return
        }
        accessoryFrame = frame
        accessoryIsInline = isInline
    }

    /// Đặt lại neo cho cỡ màn **hiện tại**, khi màn hình xoay lúc thẻ mở.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// VÌ SAO — CÚ THU ĐÁP NGOÀI MÀN HÌNH
    /// ─────────────────────────────────────────────────────────────────────
    /// `PlayerCard` ghép neo với cỡ màn mỗi lần dựng. Neo chụp lúc dọc (y 735)
    /// ghép với cỡ màn ngang (cao 402) cho viên thuốc ở y 735 — cú thu bay ra
    /// ngoài mép dưới, rồi thẻ trao chỗ cho một accessory ở chỗ khác hẳn.
    ///
    /// Thứ tự ưu tiên:
    ///   1. Về đúng cỡ lúc chụp: bản chụp ấy, y nguyên.
    ///   2. Một khung accessory đã báo từ lúc rời nghỉ và nằm trong màn mới:
    ///      chính chỗ accessory đang đứng. `recedeScale` giờ là 1, nên khung
    ///      đo lúc thẻ mở không còn bị co.
    ///   3. Không thì khung dự phòng của màn mới — ít nhất viên thuốc ở trong
    ///      màn hình, và lần báo khung kế tiếp sẽ sửa nó.
    ///
    /// Quãng kéo đi theo neo — cả hai cú kéo đều chia cho
    /// `PlayerAnchor.dragTravel(for: anchorFrame)` — nên không có gì phải
    /// đổi thêm ở đó. Cỡ chữ: lấy lại cái accessory đang báo.
    private func reanchor() {
        let next: (frame: CGRect, isInline: Bool)
        if screenSize == anchorScreen {
            next = capturedAnchor
        } else if let report = awayReport,
                  PlayerAnchor.resolve(measured: report.frame, screen: screenSize) == report.frame {
            next = report
        } else {
            next = (PlayerAnchor.fallbackFrame(screen: screenSize), false)
        }
        // Có điều kiện: mỗi lần ghi một thuộc tính quan sát là một lần mời các
        // view đọc nó dựng lại.
        if anchorFrame != next.frame { anchorFrame = next.frame }
        if anchorIsInline != next.isInline { anchorIsInline = next.isInline }
        if anchorTextStyle != accessoryTextStyle { anchorTextStyle = accessoryTextStyle }
    }

    /// Số thứ tự của chuyển động **mới nhất** của thẻ: mỗi cú morph, mỗi lần rời
    /// nghỉ (kể cả từng khung của một cú kéo trên accessory) đều tăng nó.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// VÌ SAO CẦN — MỘT `completion` CŨ KHÔNG BIẾT MÌNH ĐÃ CŨ
    /// ─────────────────────────────────────────────────────────────────────
    /// Thẻ về nghỉ trong `completion` của hình học cú thu, ~0,5s sau khi thả.
    /// Animation của SwiftUI cộng dồn chứ không huỷ, nên một cú thu bị cắt
    /// ngang — kéo accessory giữa chừng rồi thả, hay mở lại rồi thu lần nữa — vẫn chạy
    /// tới cuối và vẫn gọi `completion` **của nó**, giữa cú thu mới. Hỏi trạng
    /// thái hiện tại (`settled == 0`, không ai đang kéo) thì câu trả lời là
    /// "đúng, đang thu về 0" — của cú khác. Thẻ về nghỉ sớm: mờ đi khi còn
    /// đang bay, và hàng accessory hiện ra dưới nó, lệch nhau qua lớp kính.
    ///
    /// Nên mỗi `completion` mang theo số của cú đã đăng ký nó, và chỉ được về
    /// nghỉ nếu số ấy vẫn là số mới nhất. Không quan sát: không view nào vẽ
    /// theo nó.
    @ObservationIgnored private(set) var motion = 0

    /// Thẻ gọi ở đầu mỗi cú morph; trả số của cú ấy — xem `motion`.
    func beginMotion() -> Int {
        motion &+= 1
        return motion
    }

    func leaveRest() {
        // Một cú kéo hay một cú mở bắt đầu: mọi `completion` đang chờ thành cũ.
        motion &+= 1
        // Trước `guard`: chạm hoặc kéo giữa đuôi cú thu thì thẻ chưa về nghỉ,
        // nhưng cú thu đã bị huỷ và thẻ lại đè lên accessory. Có điều kiện vì
        // cú kéo trên accessory gọi hàm này mỗi khung, và mỗi lần ghi một
        // thuộc tính `@Observable` là một lần mời các view đọc nó dựng lại.
        if isCollapsing { isCollapsing = false }
        if cardSurfaceHandedOver { cardSurfaceHandedOver = false }
        // Cú hạ cánh bị cắt ngang: thẻ lại phủ lên viên kính, nên hiện nó lại
        // ngay — thẻ đặc che nó.
        capsule.restore()
        guard isCardResting else { return }
        anchorFrame = PlayerAnchor.resolve(measured: accessoryFrame, screen: screenSize)
        anchorIsInline = accessoryIsInline
        if anchorTextStyle != accessoryTextStyle { anchorTextStyle = accessoryTextStyle }
        anchorScreen = screenSize
        capturedAnchor = (anchorFrame, anchorIsInline)
        awayReport = nil
        isCardResting = false
    }

    /// Thẻ gọi lúc bắt đầu một cú thu về 0, **bên trong** `withAnimation` của
    /// hình học — xem `isCollapsing`.
    func commitCollapse() {
        guard !isCollapsing else { return }
        isCollapsing = true
    }

    /// Bước một của cú trao tay — xem `cardSurfaceHandedOver`. Chỉ khi đang
    /// thu và không ai đang kéo accessory, cùng điều kiện với `arriveAtRest()`.
    func handOverCardSurface() {
        guard isCollapsing, !accessoryDragging, !cardSurfaceHandedOver else { return }
        cardSurfaceHandedOver = true
    }

    func arriveAtRest() {
        guard !accessoryDragging else { return }
        // Cùng lượt với thẻ biến mất: không khung nào thiếu cả hai.
        capsule.restore()
        isCardResting = true
        isCollapsing = false
    }

    func requestExpand() {
        intent = PlayerIntent(kind: .expand)
    }

    func accessoryDragChanged(translationHeight: CGFloat) {
        leaveRest()
        accessoryDragging = true
        let offset = PlayerCard.dragOffset(translationHeight: translationHeight,
                                           threshold: AccessoryDragAxis.lockDistance)
        setAccessoryDragDelta(-Double(offset / PlayerAnchor.dragTravel(for: anchorFrame)))
    }

    /// Tách riêng để `PlayerCardCommitCostTests` ghi được đúng đầu vào mà một
    /// cú kéo thật ghi, mỗi khung.
    func setAccessoryDragDelta(_ delta: Double) {
        accessoryDragDelta = delta
        set(progress: min(max(delta, 0), 1), animation: nil)
    }

    func accessoryDragEnded(predictedTranslationHeight: CGFloat, verticalVelocity: CGFloat) {
        let offset = PlayerCard.dragOffset(translationHeight: predictedTranslationHeight,
                                           threshold: AccessoryDragAxis.lockDistance)
        let predicted = -Double(offset / PlayerAnchor.dragTravel(for: anchorFrame))
        releasePending = true
        intent = PlayerIntent(kind: .release(predictedProgress: predicted,
                                             verticalVelocity: verticalVelocity))
    }

    /// Cú kéo trên accessory bị **huỷ** — hệ thống cắt ngang, app xuống nền,
    /// accessory bị dỡ khỏi cây giữa chừng. SwiftUI không gọi `onEnded` cho cú
    /// kéo bị huỷ, nên không có đường này thì `accessoryDragging` kẹt ở `true`,
    /// `arriveAtRest()` từ chối mãi mãi, và thẻ vô hình tràn màn hình nằm chắn
    /// thư viện tới lần mở app sau.
    ///
    /// Thả ở đúng chỗ đang đứng, vận tốc 0: thẻ tự quyết mở hay đóng như mọi
    /// cú thả khác, và `handle(_:)` vẫn gọi `takeAccessoryDrag()`.
    ///
    /// Vô hại khi gọi thừa: không có cú kéo nào, hoặc cú thả đã được gửi, thì
    /// không làm gì.
    func cancelAccessoryDrag() {
        guard accessoryDragging, !releasePending else { return }
        releasePending = true
        intent = PlayerIntent(kind: .release(predictedProgress: min(max(accessoryDragDelta, 0), 1),
                                             verticalVelocity: 0))
    }

    /// Thẻ gọi lúc nhận `.release`: chuyển phần kéo sang `dragDelta` của nó
    /// trong cùng một transaction, nên `progress` không nhảy.
    func takeAccessoryDrag() -> Double {
        let carried = accessoryDragDelta
        accessoryDragDelta = 0
        accessoryDragging = false
        releasePending = false
        return carried
    }
}

/// Recedes content as the player opens, the way a sheet pushes its presenting
/// screen back.
///
/// The transform lives in a modifier rather than at the call site so that its
/// `body` — and nothing else — is what re-runs when `progress` changes.
///
/// Scale only. An earlier version also clipped to a rounded rectangle, which is
/// a mask and forces an offscreen pass over the whole screen every frame. If
/// the corners are wanted, round a static backdrop *behind* the content; do not
/// mask the content itself.
private struct RecedeBehindPlayer: ViewModifier {
    let expansion: PlayerExpansion

    func body(content: Content) -> some View {
        content
            .scaleEffect(
                1 - (1 - BottomBarStyle.recedeScale) * expansion.progress
            )
            // Đường cong tới từ `expansion`, không từ transaction bao ngoài —
            // xem `PlayerExpansion.animation` về lý do và về con số đo được.
            .animation(expansion.animation, value: expansion.progress)
    }
}

extension View {
    func recedesBehindPlayer(_ expansion: PlayerExpansion) -> some View {
        modifier(RecedeBehindPlayer(expansion: expansion))
    }
}

/// Môi trường chữ mà `tabViewBottomAccessory` của hệ thống áp lên nội dung của
/// nó — và hàng mini trong thẻ phải vẽ theo đúng như thế.
///
/// ─────────────────────────────────────────────────────────────────────────
/// VÌ SAO CẦN — HAI HÀNG "TRÙNG KHÍT" ĐÃ KHÔNG TRÙNG
/// ─────────────────────────────────────────────────────────────────────────
/// Cú trao tay cuối cú thu dựa trên một tiền đề: hàng mini của thẻ và hàng của
/// accessory là một. Cùng code (`MiniPlayerTitle`, `MiniPlayerControls`) nhưng
/// **không cùng môi trường**. Đo trên simulator iOS 26 (vòng sửa 8), hệ thống
/// đặt cho nội dung accessory `imageScale` `.large` — thẻ thì `.medium` — và
/// kẹp cỡ chữ vào `.large … .xxLarge` (máy để XS vẫn ra `.large`, AX3 ra
/// `.xxLarge`). Nên ▶ ⏭ và nốt nhạc của accessory to hơn của thẻ thấy rõ (đo
/// trên simulator để cỡ chữ `.medium`: ▶ cao ~20pt so với ~14,5pt, chữ rộng hơn
/// ~7%), và ở mọi cỡ chữ ngoài khoảng kẹp thì cả chữ cũng lệch. Suốt cú mờ trao
/// tay, hai hàng lệch nhau chồng lên nhau — chữ và nút nhân đôi — rồi cả hàng
/// "nảy" to ra khi thẻ tan: một phần của cú chớp người dùng thấy ở cuối cú thu
/// (phần kia: `BottomBarStyle.collapseHandoff`).
///
/// Đọc từ accessory chứ không chép hằng số: thẻ vẽ theo cái hệ thống **đang**
/// đặt, nên một bản iOS đổi luật kẹp không tách hai hàng ra lần nữa.
struct AccessoryTextStyle: Equatable {
    var imageScale: Image.Scale
    var typeSize: DynamicTypeSize

    /// Trước khi accessory kịp báo: cái hệ thống đặt ở cỡ chữ mặc định.
    static let systemDefault = AccessoryTextStyle(imageScale: .large, typeSize: .large)
}

/// Một việc accessory nhờ thẻ làm. `id` riêng cho mỗi lần gửi, để hai lần chạm
/// liền nhau vẫn là hai giá trị khác nhau và `onChange` nổ cả hai.
struct PlayerIntent: Equatable {
    enum Kind: Equatable {
        case expand
        case release(predictedProgress: Double, verticalVelocity: CGFloat)
    }

    let id = UUID()
    let kind: Kind
}
