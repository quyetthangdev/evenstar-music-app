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


/// Giữ thanh tab **nổi trên** tấm thẻ, và cho nó tan đi theo cú mở.
///
/// ─────────────────────────────────────────────────────────────────────────
/// LỖI NÓ SỬA
/// ─────────────────────────────────────────────────────────────────────────
/// Lúc player đã thu nhỏ, viên thuốc và thanh tab là hai mặt *nổi* trên nội
/// dung — nhìn thấy danh sách phía sau và quanh chúng. Vẻ ấy **biến mất suốt cú
/// thu nhỏ rồi bật lại ở khung cuối**, và người dùng báo đúng chuyện đó.
///
/// Cơ chế là hình học, không phải màu: `PlayerCard` vẽ **trên** thanh tab, và
/// mép **dưới** của thẻ chỉ đi được `collapsedBottomOffset` (~79pt) trong cả cú
/// morph, trong khi thanh tab cao ~70pt. Nên thanh tab bị che gần trọn cú thu
/// và chỉ lộ ra ở đoạn cuối — một cú bật, không phải một cú chuyển.
///
/// Đảo thứ tự vẽ thì thanh tab không bao giờ bị che nữa; nó chỉ mờ đi theo cú
/// mở và đậm lại theo cú thu, đều đặn suốt quãng.
///
/// ─────────────────────────────────────────────────────────────────────────
/// VÌ SAO HAI TẦNG MODIFIER
/// ─────────────────────────────────────────────────────────────────────────
/// Tầng ngoài đọc `expansion.progress` **bên trong thân của chính nó**, không
/// phải ở chỗ gọi — cùng lý do `RecedeBehindPlayer` làm thế: cú kéo tay ghi
/// `expansion.set(progress:animation: nil)` mỗi khung, và đọc nó trong
/// `RootView.body` sẽ dựng lại `TabView` cùng cả năm tab ở mỗi khung của một cú
/// kéo.
///
/// Tầng trong là `Animatable`, nên độ mờ **và** hit testing đi theo giá trị
/// đang được *vẽ* chứ không phải giá trị đích. Không có nó, cú thu nhỏ bằng
/// `withAnimation` sẽ bật hit testing của thanh tab ngay khung đầu — lúc tấm
/// thẻ vẫn còn tràn màn hình — và một cú chạm gần đáy sẽ đổi tab thay vì rơi
/// vào player. Đây là đúng cái bẫy `CardSurface` ghi lại, ở một chỗ khác.
private struct FloatOverPlayer: ViewModifier {
    let expansion: PlayerExpansion

    func body(content: Content) -> some View {
        content
            .modifier(PresentedFloat(progress: expansion.progress))
            // Đường cong tới từ `expansion`, không từ transaction bao ngoài —
            // giống `RecedeBehindPlayer` ngay trên.
            .animation(expansion.animation, value: expansion.progress)
    }
}

/// Độ mờ và hit testing theo giá trị đang được vẽ. Xem `FloatOverPlayer`.
private struct PresentedFloat: ViewModifier, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity(1 - progress)
            // Không phải `== 0`: một cú kéo dừng sát đáy vẫn là một player đang
            // mở về phía người dùng, và thanh tab ở độ mờ 0,98 mà ăn chạm thì
            // đọc ra như một cú chạm rơi vào chỗ không nhìn thấy.
            .allowsHitTesting(progress < 0.02)
    }
}

extension View {
    func recedesBehindPlayer(_ expansion: PlayerExpansion) -> some View {
        modifier(RecedeBehindPlayer(expansion: expansion))
    }

    /// Thanh tab nổi trên tấm thẻ và tan theo cú mở. Xem `FloatOverPlayer`.
    func floatsOverPlayer(_ expansion: PlayerExpansion) -> some View {
        modifier(FloatOverPlayer(expansion: expansion))
    }
}
