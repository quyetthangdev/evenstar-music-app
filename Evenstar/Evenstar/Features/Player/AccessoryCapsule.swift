import SwiftUI
import UIKit

/// Ẩn tạm **viên kính của hệ thống** — view chứa cả kính lẫn nội dung của
/// `tabViewBottomAccessory` — trong lúc thẻ hạ cánh, để thẻ nảy được qua chỗ
/// nghỉ mà không lộ một viên kính đứng yên phía sau (spec, Phần 1, bổ sung
/// 2026-10-07). Cùng cách zoom transition của iOS ẩn view nguồn của nó.
///
/// ─────────────────────────────────────────────────────────────────────────
/// TÌM VIEW ẤY BẰNG HÌNH HỌC, KHÔNG BẰNG TÊN
/// ─────────────────────────────────────────────────────────────────────────
/// Một neo (`AccessoryCapsuleAnchor`) nằm sau hàng của accessory. Từ neo đi
/// ngược lên các view cha; view cần tìm là tổ tiên **cao nhất còn đúng khung
/// hàng** — cha kế tiếp đã là thanh tab, hay cả màn hình. Không tên lớp, không
/// API riêng: hôm nay view ấy là một lớp riêng của UIKit chứa cả kính lẫn nội
/// dung (spike `docs/prototypes/NativeAccessoryHandoff`, `UIKitZoom.pillView`),
/// nhưng code này không biết và không cần biết điều đó. Không tìm thấy — hình
/// học không như thế nữa — thì `hide()` trả `false` và thẻ không nảy: cú co mềm
/// như cũ. Kiểm lại mỗi bản iOS lớn.
///
/// Tìm lại **mỗi cú thu**: hệ thống có thể dựng lại view ấy (thanh tab thu nhỏ
/// rồi bung ra), và một tham chiếu cũ sẽ ẩn nhầm một view đã rời màn hình.
///
/// ─────────────────────────────────────────────────────────────────────────
/// LUÔN HIỆN LẠI
/// ─────────────────────────────────────────────────────────────────────────
/// Viên kính bị ẩn mà không hiện lại là mất mini player. Nên mọi lối ra đều
/// gọi `restore()`: thẻ trao chỗ hay rời nghỉ (`PlayerExpansion`), accessory
/// bị dỡ (bài về `nil`), app rời trạng thái active, đối tượng này bị huỷ — và
/// một chốt thời gian (`watchdog`) cho mọi trường hợp còn lại, kể cả một
/// `completion` không bao giờ nổ.
@MainActor
final class AccessoryCapsule {
    private weak var anchor: UIView?
    private var hideCount = 0

    /// View đang bị ẩn và độ mờ của nó trước đó, cùng các observer — tách ra
    /// một hộp hằng để `deinit` (không gắn actor) giữ được nó mà không chạm
    /// vào trạng thái nào của actor. **Không** `isolated deinit`: đo được (vòng
    /// 9), deinit nhảy sang main executor ấy làm runtime Swift hỏng bộ nhớ
    /// (`swift_task_deinitOnExecutorImpl` → `TaskLocal::StopLookupScope`) mỗi
    /// lần `PlayerExpansion` được giải phóng — test host sập hàng loạt.
    private final class Hidden: @unchecked Sendable {
        weak var view: UIView?
        var alpha: CGFloat = 1
        var observers: [NSObjectProtocol] = []

        /// Chỉ gọi trên main thread.
        func putBack() {
            guard let view else { return }
            view.layer.removeAllAnimations()
            view.alpha = alpha
            self.view = nil
        }
    }

    private let hidden = Hidden()

    /// Viên kính có đang bị ẩn không.
    private(set) var isHidden = false

    /// Lâu nhất viên kính được ẩn. Cú hạ cánh dài nhất (thả tay đã bị kẹp biên
    /// độ) là ~0,6s; gấp ba vẫn ngắn hơn một nhịp người dùng kịp nhận ra.
    static let watchdog: Duration = .seconds(2)

    /// Viên kính mờ đi trong chừng này lúc bị ẩn — xa trước lúc thẻ chạm đích
    /// (~0,3s sau đầu cú thu).
    static let fadeOut: TimeInterval = 0.1

    init() {
        let center = NotificationCenter.default
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
            hidden.observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.restore() }
            })
        }
    }

    /// Lưới an toàn cuối: chỉ hẹn trả viên kính về trên main actor, qua hộp
    /// hằng — không đọc trạng thái nào của actor ở đây.
    deinit {
        let hidden = hidden
        hidden.observers.forEach(NotificationCenter.default.removeObserver)
        Task { @MainActor in hidden.putBack() }
    }

    /// Neo báo nó đã vào một cửa sổ.
    func attach(_ anchor: UIView) {
        self.anchor = anchor
    }

    /// Ẩn viên kính. `false` nếu không tìm được nó — khi ấy không ẩn gì.
    @discardableResult
    func hide() -> Bool {
        if isHidden { return true }
        guard let anchor, anchor.window != nil, let container = Self.container(of: anchor) else {
            Self.reportMissingOnce()
            return false
        }
        hidden.alpha = container.alpha
        hidden.view = container
        // Mờ đi chứ không tắt phụt: bóng đổ của viên kính nằm ngoài thẻ, và một
        // cú thu bắt đầu khi thẻ đã nhỏ thì không phủ hết bóng ấy.
        UIView.animate(withDuration: Self.fadeOut, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            container.alpha = 0
        }
        isHidden = true
        hideCount &+= 1
        let ticket = hideCount
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.watchdog)
            guard let self, self.isHidden, self.hideCount == ticket else { return }
            self.restore()
        }
        return true
    }

    /// Hiện lại ngay — mọi lối ra trừ cú trao tay.
    func restore() {
        guard isHidden else { return }
        hidden.putBack()
        isHidden = false
    }

    /// Hiện lại dần, dưới thẻ đã nằm yên trên chỗ của nó — xem
    /// `BottomBarStyle.capsuleReturnDuration`. `completion` chạy khi viên kính
    /// đã hiện hẳn; không có gì để hiện thì chạy ngay.
    func restore(fadingIn duration: TimeInterval, completion: @escaping @MainActor () -> Void) {
        guard isHidden, let view = hidden.view else {
            restore()
            completion()
            return
        }
        let alpha = hidden.alpha
        hidden.view = nil
        isHidden = false
        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            view.alpha = alpha
        } completion: { _ in
            completion()
        }
    }

    /// Tổ tiên cao nhất của `anchor` mà khung (toạ độ cửa sổ) còn trùng khung
    /// của `anchor`, sai số `tolerance` điểm — hoặc `nil` nếu không có tổ tiên
    /// nào như thế, hay nếu đi tới tận gốc mà khung vẫn trùng (khi ấy thứ tìm
    /// được không phải một viên kính nằm trong thanh tab).
    static func container(of anchor: UIView, tolerance: CGFloat = 1) -> UIView? {
        let row = anchor.convert(anchor.bounds, to: nil)
        guard row.width > 0, row.height > 0 else { return nil }
        func matches(_ view: UIView) -> Bool {
            let frame = view.convert(view.bounds, to: nil)
            return abs(frame.minX - row.minX) <= tolerance && abs(frame.minY - row.minY) <= tolerance
                && abs(frame.width - row.width) <= tolerance && abs(frame.height - row.height) <= tolerance
        }
        var best: UIView?
        var current = anchor.superview
        while let view = current, !(view is UIWindow), matches(view) {
            best = view
            current = view.superview
        }
        // Chuỗi phải dừng ở một cha **lớn hơn** hàng. Hết chuỗi (một view
        // không cha), hay một cửa sổ cỡ đúng bằng hàng: không có thanh tab nào
        // bao quanh, nên không dám ẩn gì.
        guard let best, let stop = current, !matches(stop) else { return nil }
        return best
    }

    private static var reportedMissing = false

    private static func reportMissingOnce() {
        #if DEBUG
        guard !reportedMissing else { return }
        reportedMissing = true
        print("[AccessoryCapsule] no container with the accessory row's frame — collapsing without the landing bounce")
        #endif
    }
}

/// Neo của `AccessoryCapsule`: một `UIView` trống, không nhận chạm, nằm sau hàng
/// của accessory và mang đúng khung hàng ấy.
struct AccessoryCapsuleAnchor: UIViewRepresentable {
    let capsule: AccessoryCapsule

    final class AnchorView: UIView {
        var onWindow: ((UIView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { onWindow?(self) }
        }
    }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        let capsule = capsule
        view.onWindow = { capsule.attach($0) }
        return view
    }

    func updateUIView(_ uiView: AnchorView, context: Context) {}
}
