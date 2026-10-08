//  SPIKE — chế độ thứ ba: trình bày full player bằng UIKit
//  (`UIHostingController` + `preferredTransition = .zoom`), để nắm được
//  view nguồn và `UIZoomTransitionOptions` mà SwiftUI không cho chạm tới.
//
//  `-uikit pill`   nguồn = viên thuốc của hệ thống (tổ tiên của neo), căn cả thẻ
//  `-uikit strip`  nguồn = viên thuốc, căn một dải trên cùng của player cùng tỉ lệ viên thuốc
//  `-uikit art`    nguồn = ô bìa 30pt, căn ô bìa lớn của player (bìa bay về bìa)

import SwiftUI
import UIKit

// MARK: - Neo: một UIView trống đặt trong hàng accessory

final class ZoomAnchors {
    static let shared = ZoomAnchors()
    weak var row: UIView?
    weak var art: UIView?
    /// Khung ô bìa lớn của full player, toạ độ màn hình (= toạ độ view của VC toàn màn).
    var bigArt: CGRect = .zero
}

final class AnchorUIView: UIView {
    var onWindow: ((UIView) -> Void)?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { onWindow?(self) }
    }
}

struct ZoomAnchor: UIViewRepresentable {
    enum Kind { case row, art }
    let kind: Kind
    func makeUIView(context: Context) -> AnchorUIView {
        let v = AnchorUIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        v.onWindow = { v in
            switch kind {
            case .row: ZoomAnchors.shared.row = v; if Args.all.contains("-logChain") { UIKitZoom.logChain(from: v) }
            case .art: ZoomAnchors.shared.art = v
            }
        }
        return v
    }
    func updateUIView(_ uiView: AnchorUIView, context: Context) {}
}

// MARK: - Trình bày

final class PlayerHostingController: UIHostingController<AnyView> {
    var onDidDisappear: (() -> Void)?
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override func viewDidLoad() {
        super.viewDidLoad()
        // Chỉ ghi lúc chạm xuống — không bao giờ nhận diện, không chặn/hoãn chạm.
        view.addGestureRecognizer(TouchDownLogger())
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Với cú vuốt tương tác: đây là lúc hệ thống thật sự bắt đầu thu thẻ.
        ZoomLog.write("viewWillDisappear (dismiss begins) \(ZoomLog.sinceTouch())")
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ZoomLog.opening = false
        ZoomLog.write("viewDidAppear")
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        ZoomLog.write("viewDidDisappear")
        onDidDisappear?()
    }
}

/// Recognizer thụ động: ghi thời điểm ngón tay chạm xuống trên full player rồi
/// tự hỏng ngay — không cancel, không delay chạm, không chặn recognizer nào.
final class TouchDownLogger: UIGestureRecognizer {
    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let t = touches.first, let v = view {
            ZoomLog.touchDown(at: t.location(in: v))
        }
        state = .failed
    }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

/// Nhật ký nhẹ, luôn bật, ghi vào Documents/zoom.log trong container của app —
/// lấy về từ máy thật bằng `devicectl device copy from` để đo độ trễ vuốt.
enum ZoomLog {
    private static let t0 = CACurrentMediaTime()
    private static var lastTouch: CFTimeInterval = 0
    /// true từ lúc present tới viewDidAppear: lò xo mở còn chạy (đuôi dài ~1 s
    /// dù mắt thấy xong ở ~0,4 s). Chạm trong khoảng này được đánh dấu.
    static var opening = false
    private static let url: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("zoom.log")
    }()
    private static let handle: FileHandle? = {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let h = try? FileHandle(forWritingTo: url)
        h?.seekToEndOfFile()
        h?.write("---- launch \(Date())\n".data(using: .utf8)!)
        return h
    }()

    static func write(_ s: String) {
        let line = String(format: "%9.3f  ", CACurrentMediaTime() - t0) + s + "\n"
        handle?.write(line.data(using: .utf8)!)
        HitchLog.shared.mark(s)
    }
    static func touchDown(at p: CGPoint) {
        lastTouch = CACurrentMediaTime()
        write("touchDown \(Int(p.x)),\(Int(p.y))" + (opening ? "  [DURING OPEN TRANSITION]" : ""))
    }
    static func sinceTouch() -> String {
        lastTouch == 0 ? "" : String(format: "(+%.0f ms after touchDown)", (CACurrentMediaTime() - lastTouch) * 1000)
    }
}

/// Biến thể cú vuốt đóng — chọn trên full player, áp dụng cho LẦN MỞ SAU.
/// Không lưu gì; mặc định lấy từ `-dismiss default|direction|full|swiftui`.
enum DismissVariant: String, CaseIterable, Identifiable {
    case standard = "Default"
    case direction = "Direction"
    case full = "Full"
    case swiftui = "SwiftUI"
    var id: String { rawValue }

    static var current: DismissVariant = {
        switch Args.value("-dismiss") {
        case "direction": return .direction
        case "full": return .full
        case "swiftui": return .swiftui
        default: return .standard
        }
    }()
}

enum UIKitZoom {
    static var style: String { Args.value("-uikit") ?? "pill" }

    static func logChain(from v: UIView) {
        var cur: UIView? = v
        var i = 0
        while let c = cur, i < 30 {
            let f = c.convert(c.bounds, to: nil)
            print("CHAIN[\(i)] \(type(of: c)) frame=\(f.integral) r=\(c.layer.cornerRadius) clips=\(c.clipsToBounds)")
            HitchLog.shared.mark("CHAIN[\(i)] \(type(of: c)) frame=\(f.integral) r=\(c.layer.cornerRadius) clips=\(c.clipsToBounds)")
            cur = c.superview; i += 1
        }
    }

    /// Viên thuốc của hệ thống = tổ tiên CAO NHẤT của neo còn trùng khung với hàng
    /// accessory (cha kế tiếp đã là thanh tab / cả màn hình). Không dựa vào tên
    /// lớp riêng: hôm nay đó là `_UITabAccessoryContainer`, chứa cả kính lẫn nội
    /// dung — nguồn phải CHỨA phần vẽ thật thì zoom mới morph sạch, không mờ.
    static func pillView() -> UIView? {
        guard let anchor = ZoomAnchors.shared.row else { return nil }
        let row = anchor.convert(anchor.bounds, to: nil)
        var best: UIView = anchor
        var cur = anchor.superview
        while let c = cur {
            let f = c.convert(c.bounds, to: nil)
            if abs(f.width - row.width) > 2 || abs(f.height - row.height) > 2 { break }
            best = c
            cur = c.superview
        }
        return best
    }

    static func topViewController(from v: UIView) -> UIViewController? {
        var vc = v.window?.rootViewController
        while let p = vc?.presentedViewController { vc = p }
        return vc
    }

    static func present(setArtHidden: @escaping (Bool) -> Void) {
        guard let row = ZoomAnchors.shared.row, let presenter = topViewController(from: row) else { return }
        let style = self.style
        var hosting: PlayerHostingController!
        hosting = PlayerHostingController(rootView: AnyView(
            LeanFullPlayer(onClose: { hosting?.dismiss(animated: true) })
        ))
        // `.overFullScreen`: view của TabView ở nguyên trong cửa sổ. Với
        // `.fullScreen` UIKit gỡ nó ra sau khi trình bày và gắn lại đúng lúc bắt
        // đầu vuốt xuống — dựng lại cả cây TabView ngay khung đầu của cú kéo.
        let variant = DismissVariant.current
        hosting.modalPresentationStyle = (variant == .full || Args.value("-present") == "full") ? .fullScreen : .overFullScreen
        hosting.onDidDisappear = { setArtHidden(false) }

        let options = UIViewController.Transition.ZoomOptions()
        // Lần 2 dùng `velocity.dy > 0 && |dy| > |dx|` — header: khối này được gọi
        // MỘT lần khi cú dismiss tương tác bắt đầu, trả false là bỏ cả cú vuốt
        // đó. Context chỉ có location / velocity / willBegin, không có translation.
        // Default và Full: không đặt gì (hành vi hệ thống), không đổi màu dimming.
        if variant == .direction {
            options.interactiveDismissShouldBegin = { ctx in
                // Không có translation: tin quyết định của hệ thống (`willBegin`),
                // chỉ từ chối khi vận tốc rõ ràng là ngang — không bao giờ từ chối
                // vì vận tốc ~0 lúc mới chạm.
                let v = ctx.velocity
                let clearlySideways = abs(v.dx) > 2 * abs(v.dy) && abs(v.dx) > 150
                let ok = ctx.willBegin && !clearlySideways
                ZoomLog.write(String(format: "shouldBegin loc=%.0f,%.0f vel=%.0f,%.0f willBegin=%@ → %@ %@",
                                     ctx.location.x, ctx.location.y, v.dx, v.dy,
                                     ctx.willBegin ? "Y" : "N", ok ? "Y" : "N", ZoomLog.sinceTouch()))
                return ok
            }
        }
        switch style {
        case "strip":
            options.alignmentRectProvider = { ctx in
                let b = ctx.zoomedViewController.view.bounds
                let src = ctx.sourceView.bounds
                let h = b.width * src.height / max(1, src.width)
                return CGRect(x: 0, y: ctx.zoomedViewController.view.safeAreaInsets.top, width: b.width, height: h)
            }
        case "art":
            options.alignmentRectProvider = { _ in
                ZoomAnchors.shared.bigArt == .zero ? nil : ZoomAnchors.shared.bigArt
            }
        default:
            break
        }

        hosting.preferredTransition = .zoom(options: options) { _ in
            style == "art" ? ZoomAnchors.shared.art : pillView()
        }
        if style == "art" { setArtHidden(true) }
        ZoomLog.write("present variant=\(variant.rawValue) style=\(hosting.modalPresentationStyle == .fullScreen ? "fullScreen" : "overFullScreen") source=\(String(describing: style == "art" ? ZoomAnchors.shared.art.map { type(of: $0) } : pillView().map { type(of: $0) }))")
        hosting.modalPresentationCapturesStatusBarAppearance = true  // .overFullScreen
        ZoomLog.opening = true
        presenter.present(hosting, animated: true)
    }
}
