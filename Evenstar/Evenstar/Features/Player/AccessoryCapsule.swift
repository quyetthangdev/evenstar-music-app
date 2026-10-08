import SwiftUI
import UIKit
import OSLog

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
/// nhưng code này không biết và không cần biết điều đó. Nó chỉ đòi thêm một
/// điều: view ấy nằm trên vật chủ SwiftUI của nội dung ta — xem
/// `container(of:)`. Không tìm thấy — hình học không như thế nữa — thì
/// `hide()` trả `false` và thẻ không nảy: cú co mềm như cũ. Kiểm lại mỗi bản
/// iOS lớn.
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
        weak var blocker: UIView?
        var alpha: CGFloat = 1
        var observers: [NSObjectProtocol] = []

        /// Lớp này không thừa hưởng `@MainActor` của lớp ngoài (cô lập mặc
        /// định của target là `nonisolated`), nên phải nói thẳng ra ở đây.
        @MainActor
        func putBack() {
            removeBlocker()
            guard let view = take() else { return }
            // Chỉ cú mờ của chính mình, theo khoá riêng. `"opacity"` là khoá
            // UIKit đặt cho **mọi** animation `alpha` — của hệ thống cũng vậy
            // (accessory đang được dỡ đi…) — nên gỡ theo khoá ấy là gỡ cả của
            // người khác. Animation vị trí, khung (thanh tab đang thu nhỏ…)
            // cũng để yên.
            view.layer.removeAnimation(forKey: AccessoryCapsule.fadeKey)
            view.alpha = alpha
        }

        /// View còn đúng như ta để lại — `alpha` đúng số 0 ta đặt — thì trả nó
        /// ra để hiện lại; không thì `nil`. Cả hai trường hợp đều buông nó ra.
        ///
        /// Không hiện lại mù quáng: một `alpha` khác 0 là hệ thống đã tự đặt
        /// lại (hay đang chạy animation của nó), ép về số cũ ở đó có thể để lại
        /// một viên kính rỗng trên màn hình. Nhưng **không đòi view còn trong
        /// cửa sổ**: bài về `nil` làm hệ thống gỡ view ấy khỏi cây (đo trên iOS
        /// 26), và UIKit có thể gắn chính view ấy lại về sau — còn ở `alpha` 0
        /// thì nó vô hình mãi, và lần `hide()` kế tiếp sẽ nhớ 0 làm số gốc. Đặt
        /// `alpha` của một view không ở trong cửa sổ thì vô hại, nên số 0 của ta
        /// luôn được trả lại, ở đâu cũng vậy.
        @MainActor
        func take() -> UIView? {
            defer { view = nil }
            guard let view, view.alpha == 0 else { return nil }
            return view
        }

        @MainActor
        func removeBlocker() {
            blocker?.removeFromSuperview()
            blocker = nil
        }
    }

    /// Thay viên kính nhận chạm trong lúc nó ẩn.
    ///
    /// Một view ở `alpha` 0 thì UIKit bỏ qua khi tìm view nhận chạm, còn thẻ ở
    /// `progress` 0 không nhận chạm (và không được nhận: vùng chạm của thẻ là
    /// cả màn hình). Không có lớp này, một cú chạm vào viên thuốc giữa cú hạ
    /// cánh rơi xuống hàng thư viện bên dưới — **phát một bài khác**. Trước
    /// vòng 9, cùng cú chạm ấy mở lại thẻ; lớp này giữ đúng điều ấy.
    ///
    /// Trong suốt, `alpha` 1, ẩn với VoiceOver, đặt ngay trên viên kính trong
    /// cùng view cha, ở khung của viên kính **lúc ẩn**. Khung ấy không bám theo
    /// nếu hệ thống dời viên kính trong lúc ẩn — chấp nhận: lâu nhất ~0,8s,
    /// và thẻ khi ấy đang nằm đúng ở khung cũ.
    final class Blocker: UIView {
        var onTap: (@MainActor () -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isAccessibilityElement = false
            accessibilityElementsHidden = true
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        @objc func handleTap() { onTap?() }
    }

    /// Chạm vào viên thuốc trong lúc viên kính ẩn — `PlayerExpansion` nối nó
    /// với `requestExpand()`.
    var onTap: (@MainActor () -> Void)?

    private let hidden = Hidden()

    /// Viên kính có đang bị ẩn không.
    private(set) var isHidden = false

    /// Lâu nhất viên kính được ẩn. Cú hạ cánh dài nhất (thả tay đã bị kẹp biên
    /// độ) là ~0,6s; gấp ba vẫn ngắn hơn một nhịp người dùng kịp nhận ra.
    static let watchdog: Duration = .seconds(2)

    /// Viên kính mờ đi trong chừng này lúc bị ẩn — xa trước lúc thẻ chạm đích
    /// (~0,3s sau đầu cú thu).
    static let fadeOut: TimeInterval = 0.1

    /// Khoá riêng cho cú mờ của chính ta.
    static let fadeKey = "evenstar.accessoryCapsule.fade"

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
        guard hidden.view != nil || hidden.blocker != nil else { return }
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
        // Không bao giờ nhớ 0 làm số gốc: hiện lại sẽ trả view về 0, viên kính
        // vô hình mãi. Một view đang ở 0 khi ta tìm thấy — vết của một lần ẩn
        // chưa hiện lại, hay hệ thống đặt — coi như 1. Chọn "coi là 1" thay vì
        // từ chối ẩn: từ chối để một view kẹt ở 0 kẹt mãi (không ai chữa nó),
        // còn một viên kính đang được ta hiển thị mà ở 0 thì không có gì khác để
        // giữ nguyên.
        hidden.alpha = container.alpha == 0 ? 1 : container.alpha
        hidden.view = container
        if let parent = container.superview {
            let blocker = Blocker(frame: container.frame)
            blocker.onTap = { [weak self] in self?.onTap?() }
            parent.insertSubview(blocker, aboveSubview: container)
            hidden.blocker = blocker
        }
        // Mờ đi chứ không tắt phụt: bóng đổ của viên kính nằm ngoài thẻ, và một
        // cú thu bắt đầu khi thẻ đã nhỏ thì không phủ hết bóng ấy.
        Self.fade(container, to: 0, duration: Self.fadeOut)
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
        guard isHidden else {
            completion()
            return
        }
        // Viên kính nhận chạm lại ngay — giá trị mô hình của nó đã là 1.
        hidden.removeBlocker()
        isHidden = false
        // Không còn như ta để lại (`alpha` đã khác 0, xem `Hidden.take()`):
        // không có gì của ta để hiện — trao tay ngay.
        guard let view = hidden.take() else {
            completion()
            return
        }
        // Đã rời cửa sổ (hệ thống dỡ accessory): không ai thấy một cú mờ, và
        // một animation trên layer không hiển thị có thể không bao giờ gọi
        // `completion`. Trả số cũ ngay, gỡ cú mờ của ta.
        guard view.window != nil else {
            view.layer.removeAnimation(forKey: Self.fadeKey)
            view.alpha = hidden.alpha
            completion()
            return
        }
        Self.fade(view, to: hidden.alpha, duration: duration, completion: completion)
    }

    /// Đổi `alpha` của `view` thành `alpha` bằng một animation **mang khoá
    /// riêng** (`fadeKey`), không qua `UIView.animate`: khoá UIKit đặt cho cú
    /// mờ ấy là `"opacity"`, chung với mọi animation `alpha` của hệ thống, và
    /// lúc hiện lại thì chỉ được gỡ cú của chính ta. Bắt đầu từ độ mờ **đang
    /// vẽ**, như `.beginFromCurrentState`.
    ///
    /// `completion` đi qua `delegate` của **chính animation** (`FadeEnd`),
    /// không qua `CATransaction.setCompletionBlock`. Đo trên iPhone 12, iOS
    /// 27: cú mờ 0 → 1 trên viên kính vừa nằm ở 0 thì completion của
    /// transaction không nổ khi animation xong — chỉ nổ khi một transaction
    /// sau chạm vào layer ấy (lần ẩn kế tiếp, vài giây sau) — còn
    /// `animationDidStop` nổ đúng hạn. Cú trao tay chờ completion ấy, nên thẻ
    /// không bao giờ về nghỉ và mini player chỉ mở được một lần. Xem
    /// `AccessoryCapsuleTests.testFadingBackInIsReportedByTheAnimationItself`.
    private static func fade(_ view: UIView, to alpha: CGFloat, duration: TimeInterval,
                             completion: (@MainActor () -> Void)? = nil) {
        let layer = view.layer
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = layer.presentation()?.opacity ?? layer.opacity
        animation.toValue = Float(alpha)
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        if let completion { animation.delegate = FadeEnd(completion) }
        view.alpha = alpha
        layer.add(animation, forKey: fadeKey)
    }

    /// Báo cú mờ đã xong — chạy hết, hay bị gỡ (lần ẩn kế tiếp thay nó bằng
    /// cú của mình, cùng khoá) — đúng một lần. `CAAnimation` giữ `delegate`
    /// bằng tham chiếu mạnh, nên không ai khác phải giữ nó.
    ///
    /// `@MainActor` để được gửi vào `assumeIsolated` (Core Animation gọi
    /// `animationDidStop` trên luồng chính).
    @MainActor
    private final class FadeEnd: NSObject, CAAnimationDelegate {
        private var completion: (@MainActor () -> Void)?

        init(_ completion: @escaping @MainActor () -> Void) {
            self.completion = completion
        }

        nonisolated func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
            MainActor.assumeIsolated {
                let completion = self.completion
                self.completion = nil
                completion?()
            }
        }
    }

    /// Tổ tiên cao nhất của `anchor` mà khung (toạ độ cửa sổ) còn trùng khung
    /// của `anchor`, sai số `tolerance` điểm — hoặc `nil` nếu không có tổ tiên
    /// nào như thế, nếu đi tới tận gốc mà khung vẫn trùng (khi ấy thứ tìm
    /// được không phải một viên kính nằm trong thanh tab), hay nếu thứ tìm
    /// được vẫn còn là nội dung của chính ta.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// VÌ SAO PHẢI VƯỢT QUA RANH GIỚI VẬT CHỦ
    /// ─────────────────────────────────────────────────────────────────────
    /// Nếu một bản iOS sau cho view chứa viên kính khung **lớn hơn** hàng, tổ
    /// tiên cao nhất còn đúng khung hàng sẽ là view SwiftUI đang chứa nội
    /// dung accessory của ta. Ẩn nó là ẩn chữ: `hide()` vẫn trả `true`, và
    /// thẻ lún qua một viên kính đứng yên — đúng thứ cú ẩn tồn tại để tránh.
    ///
    /// "Chứa thứ gì ngoài chuỗi tổ tiên của neo" không phân biệt được hai
    /// trường hợp ấy: đo trên iOS 26, view chứa nội dung của ta có sẵn những
    /// view con ngoài chuỗi (bìa, chữ, nút — `PortalGroupMarkerView`,
    /// `_UIInheritedView`…), còn kính của view hệ thống thì **không** là một
    /// view con nào cả. Thứ phân biệt được là **chuỗi responder**: view gốc của
    /// một vật chủ SwiftUI (hay của một view controller) không trao `next` cho
    /// view cha mà cho responder của vật chủ — `UIKitTabBarBottomAccessory.next`
    /// là `UIKitKeyPressResponder`, không phải `_UITabAccessoryContainer`. Mọi
    /// view bên dưới ranh giới ấy là của ta. Nên view tìm được phải nằm **trên**
    /// ít nhất một ranh giới như thế; không thì không ẩn gì, và thẻ co mềm.
    /// Chỉ dùng `UIResponder.next`, API công khai, không tên lớp nào.
    static func container(of anchor: UIView, tolerance: CGFloat = 1) -> UIView? {
        let row = anchor.convert(anchor.bounds, to: nil)
        guard row.width > 0, row.height > 0 else { return nil }
        func matches(_ view: UIView) -> Bool {
            let frame = view.convert(view.bounds, to: nil)
            return abs(frame.minX - row.minX) <= tolerance && abs(frame.minY - row.minY) <= tolerance
                && abs(frame.width - row.width) <= tolerance && abs(frame.height - row.height) <= tolerance
        }
        func isHostingBoundary(_ view: UIView) -> Bool { view.next !== view.superview }
        var best: UIView?
        var bestIsAboveAHost = false
        var crossedAHost = isHostingBoundary(anchor)
        var current = anchor.superview
        while let view = current, !(view is UIWindow), matches(view) {
            best = view
            bestIsAboveAHost = crossedAHost
            if isHostingBoundary(view) { crossedAHost = true }
            current = view.superview
        }
        // Chuỗi phải dừng ở một cha **lớn hơn** hàng. Hết chuỗi (một view
        // không cha), hay một cửa sổ cỡ đúng bằng hàng: không có thanh tab nào
        // bao quanh, nên không dám ẩn gì.
        guard let best, let stop = current, !matches(stop), bestIsAboveAHost else { return nil }
        return best
    }

    private static var reportedMissing = false

    /// Một lần mỗi lần chạy, cả bản Release: trên một bản iOS mới mà hình học
    /// đã khác, đây là dấu vết duy nhất cho biết vì sao thẻ không còn nảy.
    private static func reportMissingOnce() {
        guard !reportedMissing else { return }
        reportedMissing = true
        AppLog.player.notice("No view with the accessory row's frame was found; collapsing without the landing bounce")
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
