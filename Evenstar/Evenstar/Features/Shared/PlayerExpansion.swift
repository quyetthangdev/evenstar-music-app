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

extension View {
    func recedesBehindPlayer(_ expansion: PlayerExpansion) -> some View {
        modifier(RecedeBehindPlayer(expansion: expansion))
    }
}
