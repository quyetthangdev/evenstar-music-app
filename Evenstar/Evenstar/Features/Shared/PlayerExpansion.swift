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
    @ObservationIgnored var screenSize: CGSize = .zero

    /// Khung thẻ bung ra từ đó, chụp **lúc thẻ rời trạng thái nghỉ** và giữ
    /// nguyên tới khi thẻ về nghỉ. Không đọc thẳng `accessoryFrame` trong lúc
    /// bung, vì nội dung phía sau lùi lại làm khung đo được co theo.
    private(set) var anchorFrame: CGRect = .zero
    /// Accessory có đang ở `.inline` lúc thẻ rời nghỉ không. Hàng mini player
    /// trong thẻ đọc nó để ẩn ⏭ giống hệt accessory ở khung đầu.
    private(set) var anchorIsInline = false

    /// Thẻ đang nằm yên ở 0 và vô hình, còn accessory đang hiện nội dung của nó.
    private(set) var isCardResting = true

    /// Một cú thu đã được quyết (`PlayerCard.morph(to: 0…)`) và thẻ chưa về
    /// nghỉ — tức đang ở giữa lò xo, trong cú lún và nảy ở cuối, hoặc trong cú
    /// mờ trao tay.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// VÌ SAO KHÔNG CHỈ DỰA VÀO `isCardResting`
    /// ─────────────────────────────────────────────────────────────────────
    /// `isCardResting` chỉ lật khi cú thu đã **xong hẳn** — sau cú nảy (xem
    /// `PlayerCard.morph(to:curves:)`). Trong khi ấy thẻ phải biết mình đang
    /// thu hay đang mở: chỉ khi thu, mặt thẻ mới chuyển sang kính ở đoạn cuối
    /// (`cardSurfaceIsGlass`). Chiều mở và lúc kéo thì thẻ đặc từ khung đầu.
    ///
    /// **Không** còn quyết accessory hiện nội dung lúc nào. Bản trước
    /// (`fbc0837`) cho accessory hiện ngay lúc quyết thu, nằm sẵn dưới một tấm
    /// thẻ đặc rồi thẻ mờ đi ở 2% cuối. Thẻ giờ là kính trong suốt suốt đoạn
    /// cuối và lún lệch khỏi viên kính tới ~10pt, nên một hàng nằm dưới sẽ
    /// **hiện xuyên qua** thành hai dòng chữ lệch nhau. Xem
    /// `showsAccessoryContent`.
    ///
    /// Lật bên trong `withAnimation` của cú thu, nên lớp kính của `CardSurface`
    /// đi theo đường cong của hình học thay vì bật một bậc — chuyện này chỉ lộ
    /// khi thả tay lúc thẻ đã gần bằng viên kính.
    private(set) var isCollapsing = false

    /// Accessory có nên vẽ nội dung của nó không: **chỉ lúc nghỉ**.
    ///
    /// Suốt cú thu, chính thẻ vẽ hàng mini — trên một mặt kính trong suốt và
    /// lệch khỏi viên kính trong lúc lún — nên hàng của accessory phải vắng
    /// mặt, không thì nó hiện xuyên qua thẻ. Nó hiện lại đúng lúc thẻ về nghỉ:
    /// cú nảy đã xong, hai hàng trùng khít, và thẻ mờ đi phía trên nó
    /// (`BottomBarStyle.collapseHandoff`).
    var showsAccessoryContent: Bool { isCardResting }

    /// Mặt thẻ có được phép là kính không — xem `CardSurface` trong
    /// `PlayerCard.swift`. Đúng khi thẻ đang thu, và cả lúc nghỉ.
    ///
    /// Lúc nghỉ vì cú mờ trao tay: `arriveAtRest()` hạ `isCollapsing` trong
    /// cùng lượt nó dựng `isCardResting`, ngay lúc thẻ bắt đầu mờ. Chỉ dựa vào
    /// `isCollapsing` thì mặt thẻ quay về đặc **giữa** cú mờ — một mảng xám
    /// hiện lên trên viên kính rồi tan. Thẻ nghỉ thì vô hình, nên kính ở đó
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

    func reportAccessoryFrame(_ frame: CGRect, isInline: Bool) {
        guard isCardResting else { return }
        accessoryFrame = frame
        accessoryIsInline = isInline
    }

    func leaveRest() {
        // Trước `guard`: chạm hoặc kéo giữa đuôi cú thu thì thẻ chưa về nghỉ,
        // nhưng cú thu đã bị huỷ và thẻ lại đè lên accessory. Có điều kiện vì
        // cú kéo trên accessory gọi hàm này mỗi khung, và mỗi lần ghi một
        // thuộc tính `@Observable` là một lần mời các view đọc nó dựng lại.
        if isCollapsing { isCollapsing = false }
        guard isCardResting else { return }
        anchorFrame = PlayerAnchor.resolve(measured: accessoryFrame, screen: screenSize)
        anchorIsInline = accessoryIsInline
        isCardResting = false
    }

    /// Thẻ gọi lúc bắt đầu một cú thu về 0, **bên trong** `withAnimation` của
    /// hình học — xem `isCollapsing`.
    func commitCollapse() {
        guard !isCollapsing else { return }
        isCollapsing = true
    }

    func arriveAtRest() {
        guard !accessoryDragging else { return }
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
