//
//  PlayerMorphUIKitView.swift
//  Bản thử thứ hai: cùng cú morph, nhưng động cơ là UIKit.
//
//  ─────────────────────────────────────────────────────────────────────────
//  ĐỂ TRẢ LỜI ĐÚNG MỘT CÂU HỎI
//  ─────────────────────────────────────────────────────────────────────────
//  Cú khựng ở đầu hành trình thu nhỏ có phải là **thuộc tính của kiến trúc
//  "dựng lại cây view mỗi khung hình"** hay không.
//
//  Bản SwiftUI ghi `@State` trong `DragGesture.onChanged`, ở tần suất chạm —
//  đo được ~250 lần/giây — nên mỗi khung hình màn hình có khoảng bốn lượt
//  dựng lại cây view, ba trong số đó bị vứt đi.
//
//  Bản này thì không có lượt nào. `UIViewPropertyAnimator` dựng animation
//  **một lần**, cử chỉ chỉ đặt `fractionComplete`, và render server nội suy
//  thuộc tính layer. Luồng chính gần như rảnh suốt cử chỉ. Đây là cách
//  Apple Music làm.
//
//  Nếu bản này mượt → chẩn đoán kiến trúc được xác nhận, và port player thật
//  là quyết định có cơ sở. Nếu vẫn khựng y hệt → nguyên nhân nằm chỗ khác, và
//  ta vừa tiết kiệm được một cuộc viết lại 1855 dòng.
//
//  ─────────────────────────────────────────────────────────────────────────
//  BA CHỖ KHÁC BẢN SWIFTUI, VÀ ĐỀU LÀ RÀNG BUỘC CỦA UIKIT
//  ─────────────────────────────────────────────────────────────────────────
//  1. **Nội dung không re-layout giữa chừng.** Animator nội suy `frame`,
//     `transform`, `alpha`, `cornerRadius` — không chạy lại layout. Nên chrome
//     mini và chrome đầy đủ **crossfade** thay vì tính vị trí theo progress.
//     Đây chính là điều Apple Music làm, không phải chỗ cắt xén.
//  2. **Góc bo là `cornerRadius` đều + `maskedCorners`.** Layer không có kiểu
//     bốn bán kính độc lập, nên đoạn "bo đều 27 → chỉ hai góc trên 38" là xấp
//     xỉ: giữ hai góc trên suốt, nội suy bán kính.
//  3. **Chrome mini mờ dần suốt hành trình** thay vì tắt trong 30% đầu.
//     `delayFactor` chỉ **hoãn** điểm bắt đầu, không rút ngắn điểm kết thúc —
//     nên chrome đầy đủ vẫn vào ở 60% đúng như bản kia, còn chiều ngược lại
//     thì không diễn đạt được bằng một animator duy nhất.
//

// `#if DEBUG`, không loại khỏi target: dự án dùng Xcode 16 synced folders, nên
// loại một file khỏi target đòi sửa `.pbxproj` — việc bị cấm với agent. Bọc
// toàn file để nó biên dịch ở Debug (vẫn tra cứu được) và biến mất khỏi
// Release.
#if DEBUG

import SwiftUI
import UIKit

// MARK: - Cửa vào từ SwiftUI

struct PlayerMorphUIKitView: UIViewControllerRepresentable {
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> MorphContainerController {
        MorphContainerController(onClose: onClose)
    }

    func updateUIViewController(_ controller: MorphContainerController, context: Context) {}
}

// MARK: - Container

final class MorphContainerController: UIViewController {

    private let onClose: () -> Void
    private let song = DemoSong.mock

    /// Nền: danh sách vẫn là SwiftUI, và điều đó không sao — nó **không** đọc
    /// `progress`, được dựng một lần rồi chỉ bị biến đổi bằng `transform`.
    /// Thứ cần rời khỏi SwiftUI là *cơ chế chuyển động*, không phải nội dung.
    private lazy var library = UIHostingController(rootView: DemoLibraryList(topInset: 0))

    private let tabBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let card = UIView()
    private let cardMaterial = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let cardGradient = CAGradientLayer()
    private let artwork = UIView()
    private let artworkGradient = CAGradientLayer()
    private let miniChrome = UIStackView()
    private let fullChrome = UIStackView()
    private let grabber = UIView()
    private let closeButton = UIButton(type: .system)
    private let readout = UILabel()

    /// Animation được dựng **một lần cho mỗi cử chỉ**, rồi tạm dừng để ngón tay
    /// tua. Đây là toàn bộ khác biệt so với bản SwiftUI.
    private var animator: UIViewPropertyAnimator?
    /// 0 = viên thuốc, 1 = toàn màn hình. Giá trị đã *chốt*, không phải giá trị
    /// giữa chừng — giữa chừng thì animator giữ.
    private var settled: CGFloat = 0
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private var probeLast: CFTimeInterval = 0
    private var probeWorst: CFTimeInterval = 0
    private var probeFrames = 0
    private var displayLink: CADisplayLink?

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Vòng đời

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        buildLibrary()
        buildTabBar()
        buildCard()
        buildOverlays()
        // Chuẩn bị trước Taptic Engine, đúng thứ bản SwiftUI thiếu và phải
        // chuyển sang `.sensoryFeedback` mới tránh được.
        haptic.prepare()

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        card.addGestureRecognizer(pan)
        card.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        library.view.frame = view.bounds
        layoutTabBar()
        // Đặt thẻ về đúng trạng thái đã chốt. Chỉ chạy khi không có animation
        // nào đang giữ layer — nếu không nó sẽ giật khỏi tay animator.
        if animator == nil { applyCollapsedOrExpanded(settled) }
    }

    override var prefersStatusBarHidden: Bool { settled > 0.5 }

    // MARK: Hình học — cùng số với bản SwiftUI

    private var collapsedFrame: CGRect {
        let margin = BottomBarMetrics.sideMargin
        let h = PlayerCard.collapsedHeight
        return CGRect(x: margin,
                      y: view.bounds.height - BottomBarMetrics.playerBottomOffset - h,
                      width: view.bounds.width - margin * 2,
                      height: h)
    }

    private var expandedFrame: CGRect { view.bounds }

    private var collapsedArtworkFrame: CGRect {
        CGRect(x: 18, y: (PlayerCard.collapsedHeight - 36) / 2, width: 36, height: 36)
    }

    private var expandedArtworkFrame: CGRect {
        let h = min(view.bounds.height * 0.59, max(view.bounds.height - 120, 0))
        return CGRect(x: 0, y: 0, width: view.bounds.width, height: h)
    }

    // MARK: Dựng view

    private func buildLibrary() {
        addChild(library)
        view.addSubview(library.view)
        library.didMove(toParent: self)
    }

    private func buildTabBar() {
        tabBar.layer.cornerRadius = BottomBarMetrics.tabBarHeight / 2
        tabBar.clipsToBounds = true
        view.addSubview(tabBar)

        let items = ["Bài hát", "Album", "Nghệ sĩ", "Tài khoản"]
        let glyphs = ["music.note.list", "square.stack", "music.mic", "person.crop.circle"]
        let row = UIStackView(arrangedSubviews: zip(glyphs, items).map { glyph, title in
            let v = UIStackView(arrangedSubviews: [
                imageView(glyph, size: 18, colour: .label),
                label(title, font: .systemFont(ofSize: 10), colour: .label)
            ])
            v.axis = .vertical
            v.alignment = .center
            v.spacing = 2
            return v
        })
        row.distribution = .fillEqually
        row.translatesAutoresizingMaskIntoConstraints = false
        tabBar.contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: tabBar.contentView.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: tabBar.contentView.trailingAnchor),
            row.centerYAnchor.constraint(equalTo: tabBar.contentView.centerYAnchor)
        ])
    }

    private func layoutTabBar() {
        let margin = BottomBarMetrics.sideMargin
        tabBar.frame = CGRect(x: margin,
                              y: view.bounds.height - BottomBarMetrics.screenBottomInset
                                  - BottomBarMetrics.tabBarHeight,
                              width: view.bounds.width - margin * 2,
                              height: BottomBarMetrics.tabBarHeight)
    }

    private func buildCard() {
        card.clipsToBounds = true
        card.layer.cornerCurve = .continuous
        // Chỉ bo hai góc trên — xem ghi chú 2 ở đầu file: layer không có kiểu
        // bốn bán kính độc lập.
        card.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.addSubview(card)

        cardMaterial.frame = card.bounds
        cardMaterial.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        card.addSubview(cardMaterial)

        cardGradient.colors = [
            UIColor(song.colours[0]).cgColor,
            UIColor(song.colours[1]).cgColor,
            UIColor.black.cgColor
        ]
        cardGradient.opacity = 0
        card.layer.addSublayer(cardGradient)

        artworkGradient.colors = [UIColor(song.colours[0]).cgColor,
                                  UIColor(song.colours[1]).cgColor]
        artworkGradient.startPoint = CGPoint(x: 0, y: 0)
        artworkGradient.endPoint = CGPoint(x: 1, y: 1)
        artwork.layer.addSublayer(artworkGradient)
        artwork.layer.cornerCurve = .continuous
        artwork.clipsToBounds = true
        card.addSubview(artwork)

        buildMiniChrome()
        buildFullChrome()

        grabber.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        grabber.layer.cornerRadius = 2.5
        grabber.alpha = 0
        card.addSubview(grabber)
    }

    private func buildMiniChrome() {
        let title = label(song.title, font: .preferredFont(forTextStyle: .footnote), colour: .label)
        let artist = label(song.artist, font: .preferredFont(forTextStyle: .caption2), colour: .secondaryLabel)
        let text = UIStackView(arrangedSubviews: [title, artist])
        text.axis = .vertical
        text.spacing = 1
        text.alignment = .leading

        miniChrome.axis = .horizontal
        miniChrome.spacing = 10
        miniChrome.alignment = .center
        miniChrome.addArrangedSubview(spacer(width: 18 + 36 + 10 - 10))
        miniChrome.addArrangedSubview(text)
        miniChrome.addArrangedSubview(UIView())
        miniChrome.addArrangedSubview(imageView("pause.fill", size: 17, colour: .label))
        miniChrome.addArrangedSubview(imageView("forward.fill", size: 15, colour: .label))
        miniChrome.isLayoutMarginsRelativeArrangement = true
        miniChrome.directionalLayoutMargins = .init(top: 0, leading: 0, bottom: 0, trailing: 16)
        card.addSubview(miniChrome)
    }

    private func buildFullChrome() {
        let title = label(song.title, font: .preferredFont(forTextStyle: .title3).bold(), colour: .white)
        let artist = label("\(song.artist) · \(song.album)",
                           font: .preferredFont(forTextStyle: .subheadline),
                           colour: UIColor.white.withAlphaComponent(0.7))
        let scrub = UISlider()
        scrub.value = 0.32
        scrub.minimumTrackTintColor = .white

        let transport = UIStackView(arrangedSubviews: [
            imageView("backward.fill", size: 26, colour: .white),
            imageView("pause.fill", size: 38, colour: .white),
            imageView("forward.fill", size: 26, colour: .white)
        ])
        transport.spacing = 48
        transport.alignment = .center

        let volume = UISlider()
        volume.value = 0.6
        volume.minimumTrackTintColor = UIColor.white.withAlphaComponent(0.85)

        fullChrome.axis = .vertical
        fullChrome.spacing = 24
        fullChrome.alignment = .fill
        [title, artist, scrub, transport, volume].forEach(fullChrome.addArrangedSubview)
        fullChrome.setCustomSpacing(4, after: title)
        fullChrome.alpha = 0
        card.addSubview(fullChrome)
    }

    private func buildOverlays() {
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .label
        closeButton.backgroundColor = .secondarySystemBackground
        closeButton.layer.cornerRadius = 16
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose() }, for: .touchUpInside)
        view.addSubview(closeButton)

        readout.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        readout.textColor = .white
        readout.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        readout.numberOfLines = 0
        readout.text = " UIKit · vuốt để đo "
        view.addSubview(readout)
    }

    // MARK: Đặt trạng thái tĩnh

    private func applyCollapsedOrExpanded(_ p: CGFloat) {
        let expanded = p > 0.5
        card.frame = expanded ? expandedFrame : collapsedFrame
        card.layer.cornerRadius = expanded ? 38 : PlayerCard.collapsedHeight / 2
        cardGradient.frame = card.bounds
        cardGradient.opacity = expanded ? 1 : 0
        artwork.frame = expanded ? expandedArtworkFrame : collapsedArtworkFrame
        artwork.layer.cornerRadius = expanded ? 0 : 36 * 0.12
        artworkGradient.frame = artwork.bounds
        miniChrome.frame = CGRect(x: 0, y: 0, width: card.bounds.width,
                                  height: PlayerCard.collapsedHeight)
        miniChrome.alpha = expanded ? 0 : 1
        layoutFullChrome()
        fullChrome.alpha = expanded ? 1 : 0
        grabber.frame = CGRect(x: card.bounds.midX - 18, y: view.safeAreaInsets.top + 8,
                               width: 36, height: 5)
        grabber.alpha = expanded ? 1 : 0
        library.view.transform = expanded ? CGAffineTransform(scaleX: 0.92, y: 0.92) : .identity
        tabBar.alpha = expanded ? 0 : 1
        closeButton.frame = CGRect(x: view.bounds.width - BottomBarMetrics.sideMargin - 32,
                                   y: view.safeAreaInsets.top + 4, width: 32, height: 32)
        closeButton.alpha = expanded ? 0 : 1
        readout.frame = CGRect(x: BottomBarMetrics.sideMargin, y: view.safeAreaInsets.top + 44,
                               width: view.bounds.width - BottomBarMetrics.sideMargin * 2, height: 30)
        readout.alpha = expanded ? 0 : 1
        setNeedsStatusBarAppearanceUpdate()
    }

    private func layoutFullChrome() {
        let inset: CGFloat = 24
        let top = view.bounds.height - (440 - 40)
        fullChrome.frame = CGRect(x: inset, y: top,
                                  width: view.bounds.width - inset * 2, height: 260)
    }

    // MARK: Animator — dựng một lần cho mỗi cử chỉ

    /// Toàn bộ điểm của bản thử này nằm ở hàm này: mọi thuộc tính được khai báo
    /// **một lần** trong một khối, rồi animation bị tạm dừng để ngón tay tua.
    /// Không có gì chạy trên luồng chính giữa các khung hình.
    private func makeAnimator(to target: CGFloat) -> UIViewPropertyAnimator {
        let expanded = target > 0.5
        let spring = UISpringTimingParameters(dampingRatio: 1.0)
        let a = UIViewPropertyAnimator(duration: expanded ? 0.46 : 0.38,
                                       timingParameters: spring)
        a.isUserInteractionEnabled = true

        a.addAnimations { [self] in
            card.frame = expanded ? expandedFrame : collapsedFrame
            card.layer.cornerRadius = expanded ? 38 : PlayerCard.collapsedHeight / 2
            cardGradient.frame = expanded ? expandedFrame.offsetBy(dx: -expandedFrame.minX,
                                                                   dy: -expandedFrame.minY)
                                          : CGRect(origin: .zero, size: collapsedFrame.size)
            cardGradient.opacity = expanded ? 1 : 0
            artwork.frame = expanded ? expandedArtworkFrame : collapsedArtworkFrame
            artwork.layer.cornerRadius = expanded ? 0 : 36 * 0.12
            artworkGradient.frame = expanded ? expandedArtworkFrame
                                             : CGRect(origin: .zero,
                                                      size: collapsedArtworkFrame.size)
            miniChrome.alpha = expanded ? 0 : 1
            grabber.alpha = expanded ? 1 : 0
            library.view.transform = expanded ? CGAffineTransform(scaleX: 0.92, y: 0.92) : .identity
            tabBar.alpha = expanded ? 0 : 1
            closeButton.alpha = expanded ? 0 : 1
            readout.alpha = expanded ? 0 : 1
        }
        // Chrome đầy đủ vào ở 60% — `delayFactor` hoãn điểm bắt đầu, đúng con
        // số bản SwiftUI dùng.
        a.addAnimations({ [self] in fullChrome.alpha = expanded ? 1 : 0 }, delayFactor: 0.6)
        a.addCompletion { [weak self] _ in
            guard let self else { return }
            settled = target
            animator = nil
            stopProbe()
            applyCollapsedOrExpanded(target)
        }
        return a
    }

    // MARK: Cử chỉ

    @objc private func handleTap() {
        guard settled < 0.5, animator == nil else { return }
        startProbe()
        haptic.impactOccurred()
        let a = makeAnimator(to: 1)
        animator = a
        a.startAnimation()
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        let travel = view.bounds.height
        switch pan.state {
        case .began:
            startProbe()
            let target: CGFloat = settled > 0.5 ? 0 : 1
            let a = makeAnimator(to: target)
            animator = a
            a.startAnimation()
            // Tạm dừng ngay: từ đây ngón tay là thứ điều khiển, không phải đồng hồ.
            a.pauseAnimation()

        case .changed:
            guard let a = animator else { return }
            let dy = pan.translation(in: view).y
            // Kéo xuống khi đang mở, hoặc kéo lên khi đang thu — cả hai đều là
            // "đi về phía đích", nên lấy trị tuyệt đối theo chiều đúng.
            let raw = settled > 0.5 ? dy / travel : -dy / travel
            a.fractionComplete = min(max(raw, 0), 1)

        case .ended, .cancelled:
            guard let a = animator else { return }
            let dy = pan.translation(in: view).y
            let vy = pan.velocity(in: view).y
            let goingToTarget = a.fractionComplete > 0.3
                || abs(vy) > 800 && (settled > 0.5 ? vy > 0 : vy < 0)

            haptic.impactOccurred()
            if goingToTarget {
                // Vận tốc bàn giao cho lò xo, chuẩn hoá theo quãng còn lại —
                // cùng phép quy đổi `PlayerCard.settleVelocity` làm.
                let remaining = max(1 - a.fractionComplete, 0.0001)
                let unit = abs(vy) / travel / remaining
                let params = UISpringTimingParameters(
                    dampingRatio: 1.0,
                    initialVelocity: CGVector(dx: 0, dy: min(unit, 18))
                )
                a.continueAnimation(withTimingParameters: params, durationFactor: 0)
            } else {
                a.isReversed = true
                a.continueAnimation(withTimingParameters: UISpringTimingParameters(dampingRatio: 1),
                                    durationFactor: 0)
            }
            _ = dy

        default:
            break
        }
    }

    // MARK: Thước đo — cùng cách đọc với bản SwiftUI

    /// `CADisplayLink` chứ không phải đếm trong callback cử chỉ: bản này **cố
    /// tình** không có callback nào mỗi khung hình, nên phải hỏi màn hình.
    private func startProbe() {
        stopProbe()
        probeLast = 0; probeWorst = 0; probeFrames = 0
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { probeLast = now; probeFrames += 1 }
        guard probeLast > 0 else { return }
        probeWorst = max(probeWorst, now - probeLast)
    }

    private func stopProbe() {
        displayLink?.invalidate()
        displayLink = nil
        guard probeFrames > 3 else { return }
        let expected = 1.0 / Double(view.window?.screen.maximumFramesPerSecond ?? 60)
        let worst = probeWorst * 1000
        readout.text = worst > expected * 1000 * 1.6
            ? String(format: " UIKit: VẤP %.0fms (chuẩn %.0f) · %d frame ", worst, expected * 1000, probeFrames)
            : String(format: " UIKit: sạch · tệ nhất %.0fms/%.0f · %d frame ", worst, expected * 1000, probeFrames)
    }
}

// MARK: - Tiện ích dựng view

private extension MorphContainerController {
    func label(_ text: String, font: UIFont, colour: UIColor) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = font
        l.textColor = colour
        l.lineBreakMode = .byTruncatingTail
        return l
    }

    func imageView(_ glyph: String, size: CGFloat, colour: UIColor) -> UIImageView {
        let v = UIImageView(image: UIImage(systemName: glyph,
                                          withConfiguration: UIImage.SymbolConfiguration(pointSize: size)))
        v.tintColor = colour
        v.contentMode = .center
        return v
    }

    func spacer(width: CGFloat) -> UIView {
        let v = UIView()
        v.widthAnchor.constraint(equalToConstant: width).isActive = true
        return v
    }
}

private extension UIFont {
    func bold() -> UIFont {
        guard let d = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: d, size: 0)
    }
}

#endif
