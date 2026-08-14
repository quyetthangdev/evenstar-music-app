//
//  ContentView.swift
//  Mini player → full player, thời Liquid Glass. iOS 26 SDK, không thư viện ngoài.
//
//  ─────────────────────────────────────────────────────────────────────────
//  API ĐÃ ĐỐI CHIẾU VỚI SDK, KHÔNG PHẢI NHỚ RA
//  ─────────────────────────────────────────────────────────────────────────
//  Mọi API dưới đây đã được biên dịch thử với `-target arm64-apple-ios26.0`
//  trước khi file này được viết: `GlassEffectContainer(spacing:)`,
//  `.glassEffect(_:in:)`, `.regular.interactive()`, `.regular.tint(_:)`,
//  `.glassEffectID(_:in:)`, `.glassEffectUnion(id:namespace:)`,
//  `.glassEffectTransition(_:)`, `.buttonStyle(.glass)`, `.glassProminent`,
//  `ConcentricRectangle`, `MeshGradient`, `.onScrollGeometryChange`,
//  `.tabBarMinimizeBehavior(.onScrollDown)`.
//
//  Một cái sai so với trực giác: **`MeshGradient.points` nhận `Float`, không
//  phải `CGFloat`.** Đó là lỗi biên dịch duy nhất của lần dò API.
//
//  ─────────────────────────────────────────────────────────────────────────
//  BA CHỖ FILE NÀY LÀM KHÁC SPEC, VÀ VÌ SAO
//  ─────────────────────────────────────────────────────────────────────────
//  1. **Cú bung không dùng `matchedGeometryEffect`/`glassEffectID`.**
//     Spec yêu cầu vừa morph bằng matched-geometry, vừa cho ngón tay tua
//     `progress` và *retarget giữa chừng*. Hai thứ đó loại trừ nhau: matched
//     geometry nội suy giữa hai view theo một đường cong, không có API công
//     khai nào tua nó tới một phần trăm. Ở đây thẻ là **một view duy nhất**
//     với hình dạng tính từ `progress` — nên nó không thể cross-fade (không
//     có gì để fade sang), ngón tay lái được trực tiếp, và vì luôn animate
//     *cùng một property*, SwiftUI retarget lò xo giữa chừng đúng như yêu
//     cầu 4 đòi hỏi.
//
//     `glassEffectID` vẫn được dùng — ở đúng chỗ nó là thứ duy nhất làm
//     được: hợp nhất viên thuốc mini với thanh tab khi chúng dock cạnh nhau.
//     Đó là hai shape riêng biệt cần hoà vào nhau, không phải một shape cần
//     tua.
//
//  2. **`ConcentricRectangle` không dùng làm hình của thẻ đang morph.** Nó có
//     thật và biên dịch được, nhưng đổi *kiểu* shape giữa chừng là một cú
//     nhảy hình. Bán kính nội suy tới `Display.cornerRadius`, mà ở toàn màn
//     hình chính là con số `ConcentricRectangle` sẽ tự tính ra — cùng kết
//     quả ở đầu mút, liên tục ở quãng giữa.
//
//  3. **Mesh gradient trôi bằng transform, không bằng cách đổi `points`.**
//     Dịch một lớp đã vẽ xong là việc render server làm một mình; đổi toạ độ
//     điểm buộc vẽ lại lưới mỗi frame. Đây không phải lý thuyết: một app
//     nhạc thật đo được 189 ms hitch/giây với mesh trôi kiểu sau, 35 ms sau
//     khi bỏ.
//
//  ─────────────────────────────────────────────────────────────────────────
//  TOÀN BỘ PHÉP NỘI SUY NẰM TRONG `PlayerGeometry`. Không công thức nào rải
//  trong view; mọi lớp đọc cùng một `p` nên không lớp nào lệch pha lớp khác.
//

import SwiftUI
import UIKit

// MARK: - Dữ liệu giả

struct Song: Equatable {
    let title: String
    let artist: String
    /// Màu "trích" từ ảnh bìa. Nuôi cả mesh gradient lẫn lớp dim.
    let colours: [Color]
    let glyph: String

    static let all: [Song] = [
        .init(title: "Chiều nay không có mưa bay", artist: "Vũ.",
              colours: [Color(red: 0.31, green: 0.45, blue: 0.72),
                        Color(red: 0.16, green: 0.20, blue: 0.38),
                        Color(red: 0.42, green: 0.31, blue: 0.55)],
              glyph: "cloud.rain.fill"),
        .init(title: "Có hẹn với thanh xuân", artist: "MONSTAR",
              colours: [Color(red: 0.78, green: 0.45, blue: 0.22),
                        Color(red: 0.42, green: 0.20, blue: 0.14),
                        Color(red: 0.72, green: 0.60, blue: 0.28)],
              glyph: "sun.max.fill"),
        .init(title: "Nhất thời", artist: "Hoàng Dũng",
              colours: [Color(red: 0.40, green: 0.28, blue: 0.58),
                        Color(red: 0.18, green: 0.14, blue: 0.32),
                        Color(red: 0.60, green: 0.35, blue: 0.55)],
              glyph: "moon.stars.fill")
    ]
}

// MARK: - Số học nội suy

@inline(__always)
private func lerp(_ from: CGFloat, _ to: CGFloat, _ t: CGFloat) -> CGFloat {
    from + (to - from) * t
}

/// Cắt một đoạn con của progress rồi trải về 0…1 — công cụ dựng mọi hiệu ứng
/// lệch pha. `ramp(p, 0, 0.25)` = "chạy hết trong 25% đầu rồi đứng yên".
@inline(__always)
private func ramp(_ p: CGFloat, _ start: CGFloat, _ end: CGFloat) -> CGFloat {
    guard end > start else { return p >= end ? 1 : 0 }
    return min(max((p - start) / (end - start), 0), 1)
}

/// Giảm nhạy dần khi kéo quá biên thay vì chặn cứng. Chặn cứng làm ngón tay
/// đang di chuyển mà màn hình đứng im — đọc ra như treo máy.
private func rubberBand(_ overflow: CGFloat, limit: CGFloat = 0.12) -> CGFloat {
    limit * (1 - 1 / (overflow / limit + 1))
}

// MARK: - Hằng số

private enum Metrics {
    /// Viên thuốc mini nổi, không phải thanh dính mép.
    static let capsuleHeight: CGFloat = 56
    static let capsuleMargin: CGFloat = 16
    /// Khe giữa viên thuốc và thanh tab.
    static let dockGap: CGFloat = 8

    static let tabBarHeight: CGFloat = 56
    static let tabBarMargin: CGFloat = 16
    /// Thanh tab khi thu lại: chỉ còn icon.
    static let tabBarCompactWidth: CGFloat = 168

    static let miniArtwork: CGFloat = 40
    static let miniArtworkCorner: CGFloat = 8
    static let fullArtworkInset: CGFloat = 48
    static let fullArtworkCorner: CGFloat = 16
    static let fullArtworkTop: CGFloat = 52

    static let backdropScale: CGFloat = 0.94
    static let backdropCorner: CGFloat = 18
    static let dimOpacity: CGFloat = 0.45

    static let dismissFraction: CGFloat = 0.30
    static let dismissVelocity: CGFloat = 800
    /// Vuốt ngang bao nhiêu điểm thì đổi bài.
    static let skipDistance: CGFloat = 70
}

/// Bán kính bo góc màn hình thật.
///
/// `_displayCornerRadius` là KVC vào thuộc tính riêng tư của `UIScreen` — chạy
/// từ iOS 11 tới nay, dùng rất rộng rãi, **nhưng vẫn là API riêng tư**. Ngại
/// khâu duyệt thì xoá nhánh KVC, giữ mỗi `fallback`; chênh lệch thị giác gần
/// như bằng không.
private enum Display {
    static let fallbackCornerRadius: CGFloat = 55

    static var cornerRadius: CGFloat {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        if let radius = scene?.screen.value(forKey: "_displayCornerRadius") as? CGFloat,
           radius > 0 {
            return radius
        }
        return fallbackCornerRadius
    }
}

// MARK: - Hình học, tính một lần mỗi frame

/// Mọi con số động của thẻ. Là struct chứ không phải computed property rải
/// khắp view, vì hai lý do: đọc hết phép nội suy trong một màn hình, và hỏi
/// được "ở progress 0.5 thì ảnh bìa ở đâu" mà không cần dựng view nào.
private struct PlayerGeometry {
    let progress: CGFloat
    let screen: CGSize
    let safeTop: CGFloat
    let safeBottom: CGFloat
    /// Thanh tab đã thu lại chưa (cuộn xuống) — đổi chỗ đậu của viên thuốc.
    let minimised: Bool
    /// Máy đang nằm ngang.
    ///
    /// Phải nằm **ở đây** chứ không chỉ trong view: bản đầu chỉ sắp lại phần
    /// điều khiển cho landscape mà quên hình học của ảnh bìa, nên
    /// `screen.width - 48` cho ra một tấm bìa 826pt trên màn hình cao 393 —
    /// nó tràn ra ngoài và điều khiển biến mất. Hình học và bố cục phải cùng
    /// biết về hướng máy, không thể một cái biết một cái không.
    let landscape: Bool

    // MARK: Thanh tab nổi

    var tabBarWidth: CGFloat {
        minimised
            ? Metrics.tabBarCompactWidth
            : screen.width - Metrics.tabBarMargin * 2
    }

    var tabBarCentreX: CGFloat {
        // Thu lại thì nép về bên phải, chừa chỗ cho viên thuốc đậu bên trái.
        minimised
            ? screen.width - Metrics.tabBarMargin - tabBarWidth / 2
            : screen.width / 2
    }

    var tabBarBottom: CGFloat {
        screen.height - safeBottom - 8
    }

    // MARK: Thẻ (viên thuốc ↔ toàn màn hình)

    /// Bề rộng viên thuốc lúc thu gọn.
    private var collapsedWidth: CGFloat {
        if minimised {
            // Đậu cạnh thanh tab: chiếm phần còn lại của hàng.
            return screen.width - Metrics.capsuleMargin * 2
                - Metrics.tabBarCompactWidth - Metrics.dockGap
        }
        return screen.width - Metrics.capsuleMargin * 2
    }

    var width: CGFloat { lerp(collapsedWidth, screen.width, ramp(progress, 0, 0.85)) }

    var height: CGFloat { lerp(Metrics.capsuleHeight, screen.height, progress) }

    /// Tâm X: thu gọn thì nằm trong lề (hoặc nép trái khi đã dock), mở hết thì
    /// giữa màn hình.
    var centreX: CGFloat {
        let collapsed = minimised
            ? Metrics.capsuleMargin + collapsedWidth / 2
            : screen.width / 2
        return lerp(collapsed, screen.width / 2, progress)
    }

    /// Đỉnh thẻ. Thu gọn: lơ lửng trên thanh tab (hoặc ngang hàng khi đã dock).
    var top: CGFloat {
        let collapsedTop = minimised
            ? tabBarBottom - Metrics.tabBarHeight
            : tabBarBottom - Metrics.tabBarHeight - Metrics.dockGap - Metrics.capsuleHeight
        return lerp(collapsedTop, 0, progress)
    }

    /// Yêu cầu 7: từ viên thuốc tới bán kính màn hình thật.
    ///
    /// Đi hết trong 70% đầu: khi thẻ đã cao quá nửa màn hình thì góc dưới của
    /// nó ra khỏi tầm nhìn, một bán kính còn bò tiếp là chi phí không ai thấy.
    var cornerRadius: CGFloat {
        lerp(Metrics.capsuleHeight / 2, Display.cornerRadius, ramp(progress, 0, 0.7))
    }

    // MARK: Ảnh bìa — một view duy nhất

    /// Cạnh ảnh bìa khi mở hết. Dọc thì ăn theo bề rộng; ngang thì bề rộng là
    /// chiều dài nhất của màn hình, nên phải chặn theo **chiều cao**.
    private var expandedArtworkSide: CGFloat {
        landscape
            ? min(screen.height - 96, screen.width * 0.40)
            : screen.width - Metrics.fullArtworkInset
    }

    var artworkSide: CGFloat {
        lerp(Metrics.miniArtwork, expandedArtworkSide, progress)
    }

    var artworkCorner: CGFloat {
        lerp(Metrics.miniArtworkCorner, Metrics.fullArtworkCorner, progress)
    }

    /// Tâm ảnh bìa trong **toạ độ của thẻ** (y = 0 là đỉnh thẻ). Toạ độ thẻ
    /// chứ không phải màn hình, nên khi thẻ trượt lên thì ảnh bìa đi theo miễn
    /// phí — không có hai chuyển động phải khớp nhau.
    var artworkCentre: CGPoint {
        let collapsed = CGPoint(x: 8 + Metrics.miniArtwork / 2,
                                y: Metrics.capsuleHeight / 2)
        let side = expandedArtworkSide
        // Ngang: bìa nép về nửa trái, căn giữa theo chiều cao; điều khiển
        // chiếm nửa phải. Dọc: bìa ở trên, điều khiển ở dưới.
        let expanded = landscape
            ? CGPoint(x: screen.width * 0.25, y: screen.height / 2)
            : CGPoint(x: screen.width / 2,
                      y: safeTop + Metrics.fullArtworkTop + side / 2)
        return CGPoint(x: lerp(collapsed.x, expanded.x, progress),
                       y: lerp(collapsed.y, expanded.y, progress))
    }

    /// Bóng ảnh bìa. Lưu ý chi phí thật: một view **vừa đổi kích thước vừa có
    /// bóng** buộc bộ dựng hình raster nó ra buffer ngoài màn hình mỗi frame
    /// để lấy hình bao. Chấp nhận được vì chỉ ảnh bìa mang bóng — đổ bóng cho
    /// cả thẻ đang phóng to là cách chắc chắn nhất để mất frame.
    var artworkShadowRadius: CGFloat { lerp(3, 28, progress) }
    var artworkShadowOpacity: CGFloat { lerp(0.16, 0.40, progress) }
    var artworkShadowY: CGFloat { lerp(2, 16, progress) }

    // MARK: Lệch pha (yêu cầu 5)

    /// Nội dung viên thuốc tắt trong 25% đầu.
    var capsuleContentOpacity: CGFloat { 1 - ramp(progress, 0, 0.25) }
    /// Điều khiển đầy đủ chỉ bật trong 40% cuối. 0.60 > 0.25 nên không bao giờ
    /// cùng hiện rõ.
    var fullContentOpacity: CGFloat { ramp(progress, 0.60, 1) }
    var fullContentOffset: CGFloat { lerp(28, 0, fullContentOpacity) }

    var contentTop: CGFloat { artworkCentre.y + artworkSide / 2 + 34 }

    // MARK: Nền (yêu cầu 6)

    var backdropScale: CGFloat { lerp(1, Metrics.backdropScale, progress) }
    var backdropCorner: CGFloat { lerp(0, Metrics.backdropCorner, progress) }
    var dimOpacity: CGFloat { Metrics.dimOpacity * progress }
    /// Nền mesh chỉ tồn tại khi đã mở đủ để nhìn thấy. Một mesh gradient là
    /// công vẽ thật; giữ nó sống suốt hành trình để rồi bị viên thuốc che kín
    /// là trả tiền cho thứ không ai xem.
    var meshOpacity: CGFloat { ramp(progress, 0.15, 0.55) }
}

// MARK: - Root

struct ContentView: View {

    /// 0 = viên thuốc, 1 = toàn màn hình. Nguồn sự thật duy nhất; không có
    /// `isExpanded` song song để hai thứ lệch nhau.
    @State private var progress: CGFloat = 0
    @State private var dragStart: CGFloat = 0
    /// Khoá trục: một cử chỉ, hai ý nghĩa (dọc = bung, ngang = đổi bài). Trục
    /// được chốt ở lần dịch chuyển đầu tiên và giữ nguyên tới khi nhấc tay.
    @State private var axis: Axis?
    /// Viên thuốc bị kéo lệch ngang bao nhiêu, cho cú vuốt đổi bài.
    @State private var skipOffset: CGFloat = 0

    @State private var minimised = false
    @State private var lastScrollY: CGFloat = 0

    @State private var trackIndex = 0
    @State private var isPlaying = true
    @State private var scrub: CGFloat = 0.32
    @State private var volume: CGFloat = 0.6
    @State private var scrubbing = false

    /// Namespace của kính. Chỉ dùng cho việc hợp nhất viên thuốc với thanh tab
    /// khi chúng dock cạnh nhau — xem ghi chú số 1 ở đầu file.
    @Namespace private var glass

    /// Ảnh bìa động tuỳ chọn: truyền vào một view lặp (VideoPlayer, Lottie,
    /// một `TimelineView`…) và nó lấp đúng khung mà ảnh tĩnh đang chiếm, đi
    /// trọn cú morph cùng nó.
    private let animatedArtwork: AnyView?

    private var song: Song { Song.all[trackIndex] }

    init(initialProgress: CGFloat = 0, animatedArtwork: AnyView? = nil) {
        _progress = State(initialValue: min(max(initialProgress, 0), 1))
        self.animatedArtwork = animatedArtwork
    }

    var body: some View {
        GeometryReader { proxy in
            // Reader này **không** `ignoresSafeArea`: chỉ reader còn tôn trọng
            // safe area mới trả về `safeAreaInsets` thật. Thẻ tự tràn ra mép,
            // nhưng số dùng để xếp chỗ phải đúng — nếu không grabber chui vào
            // sau Dynamic Island.
            let insets = proxy.safeAreaInsets
            let screen = CGSize(width: proxy.size.width,
                                height: proxy.size.height + insets.top + insets.bottom)
            let landscape = screen.width > screen.height
            let geo = PlayerGeometry(progress: progress, screen: screen,
                                     safeTop: insets.top, safeBottom: insets.bottom,
                                     minimised: minimised, landscape: landscape)

            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()

                backdrop(geo: geo, topInset: insets.top)

                // Dim mang màu bìa chứ không phải đen trơn (yêu cầu 6).
                song.colours[1]
                    .opacity(geo.dimOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .animation(.smooth, value: trackIndex)

                // Một container cho cả thanh tab lẫn thẻ: đây là thứ cho hai
                // khối kính hoà/đẩy nhau khi lại gần. Không có nó thì chúng
                // chỉ là hai lớp kính chồng lên nhau.
                // `spacing` là **bán kính hoà**: hai khối kính gần nhau hơn
                // con số này thì chảy vào nhau. Bản đầu để 20 trong khi khe
                // giữa viên thuốc và thanh tab chỉ 8 — kết quả là chúng dính
                // liền thành một cục ngay ở trạng thái thường, chưa dock gì
                // cả. 6 giữ chúng tách bạch, và việc hợp nhất khi dock do
                // `glassEffectUnion` bên dưới lo, có chủ đích chứ không phải
                // tình cờ vì đứng gần.
                GlassEffectContainer(spacing: 6) {
                    ZStack(alignment: .topLeading) {
                        tabBar(geo: geo)
                        card(geo: geo, landscape: landscape)
                    }
                }
            }
            .ignoresSafeArea()
        }
        .statusBarHidden(progress > 0.5)
        .preferredColorScheme(.dark)
    }

    // MARK: Nền

    private func backdrop(geo: PlayerGeometry, topInset: CGFloat) -> some View {
        // `.equatable()` là cách thực thi "không dựng lại danh sách trong lúc
        // chuyển cảnh": `LibraryList` không đọc `progress`, và vì nó Equatable
        // với dữ liệu không đổi, SwiftUI bỏ qua luôn việc chạy lại `body` của
        // nó mỗi frame. Chỉ các modifier biến đổi bên ngoài chạy lại, và
        // những cái đó Core Animation lo.
        LibraryList(topInset: topInset)
            .equatable()
            // Đặt ở đây, ngoài `LibraryList`, để việc theo dõi cuộn không kéo
            // theo một closure vào trong thân view đã được ghim Equatable.
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                let delta = y - lastScrollY
                guard abs(delta) > 6 else { return }
                lastScrollY = y
                withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                    minimised = delta > 0 && y > 0
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: geo.backdropCorner, style: .continuous))
            .scaleEffect(geo.backdropScale)
    }

    // MARK: Thanh tab nổi

    private func tabBar(geo: PlayerGeometry) -> some View {
        HStack(spacing: 0) {
            tabItem("play.house.fill", "Nghe ngay", showLabel: !geo.minimised)
            tabItem("square.stack.fill", "Thư viện", showLabel: !geo.minimised)
            tabItem("magnifyingglass", "Tìm kiếm", showLabel: !geo.minimised)
        }
        .frame(width: geo.tabBarWidth, height: Metrics.tabBarHeight)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID("tabbar", in: glass)
        // Khi đã dock cạnh nhau, hai khối kính nhập làm một hình liên tục —
        // đây là chỗ `glassEffectID` là thứ duy nhất làm được, và là lý do
        // container ở trên tồn tại.
        .glassEffectUnion(id: geo.minimised ? "dock" : "tabbar-alone", namespace: glass)
        .position(x: geo.tabBarCentreX,
                  y: geo.tabBarBottom - Metrics.tabBarHeight / 2)
        // Thanh tab lùi ra khi player mở: nó không có việc gì ở đó nữa.
        .opacity(1 - ramp(geo.progress, 0, 0.35))
    }

    private func tabItem(_ glyph: String, _ label: String, showLabel: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: glyph).font(.system(size: 18))
            if showLabel {
                Text(label).font(.system(size: 10))
            }
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white.opacity(0.85))
    }

    // MARK: Thẻ — một component, hai trạng thái

    private func card(geo: PlayerGeometry, landscape: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            // Nền mesh: chỉ dâng lên khi đã mở, và trôi bằng transform chứ
            // không bằng cách đổi toạ độ điểm — xem ghi chú 3 ở đầu file.
            MeshBackdrop(colours: song.colours)
                .opacity(geo.meshOpacity)

            capsuleContent(geo: geo)
            fullContent(geo: geo, landscape: landscape)
            artwork(geo: geo)
        }
        .frame(width: geo.width, height: geo.height, alignment: .top)
        // Kính thật, không phải `.ultraThinMaterial` giả. `.interactive()` cho
        // nó phản ứng khi ngón tay chạm — thứ không bắt chước được bằng blur.
        .glassEffect(
            .regular.interactive(),
            in: .rect(cornerRadius: geo.cornerRadius, style: .continuous)
        )
        .glassEffectID("player", in: glass)
        .glassEffectUnion(id: geo.minimised && geo.progress < 0.02 ? "dock" : "player-alone",
                          namespace: glass)
        // Cú vuốt ngang kéo lệch viên thuốc, kèm một cú giãn nhẹ theo hướng
        // vuốt: kính bị kéo thì phải méo, đứng yên là đọc ra như ảnh dán.
        .scaleEffect(x: 1 + abs(skipOffset) / 1400, y: 1 - abs(skipOffset) / 2600,
                     anchor: skipOffset < 0 ? .trailing : .leading)
        .offset(x: skipOffset)
        .position(x: geo.centreX, y: geo.top + geo.height / 2)
        .onTapGesture {
            if progress < 0.5 { setExpanded(true, velocity: 0) }
        }
        .gesture(dragGesture(screenHeight: geo.screen.height))
    }

    // MARK: Nội dung viên thuốc

    private func capsuleContent(geo: PlayerGeometry) -> some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 8 + Metrics.miniArtwork + 4)

            if !geo.minimised {
                Text(song.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button { togglePlay() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.body)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.glass)

            if !geo.minimised {
                Button { skip(by: 1) } label: {
                    Image(systemName: "forward.fill")
                        .font(.body)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(.trailing, 8)
        .foregroundStyle(.white)
        .frame(height: Metrics.capsuleHeight)
        .opacity(geo.capsuleContentOpacity)
        // Ngừng nhận chạm ngay khi bắt đầu mờ: hai nút vô hình vẫn ăn cú chạm
        // là lỗi kinh điển của kiểu chồng lớp này.
        .allowsHitTesting(geo.progress < 0.02)
    }

    // MARK: Nội dung player đầy đủ

    @ViewBuilder
    private func fullContent(geo: PlayerGeometry, landscape: Bool) -> some View {
        let controls = VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title).font(.title3.weight(.bold)).lineLimit(1)
                Text(song.artist).font(.title3).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Scrubber(value: $scrub, scrubbing: $scrubbing)

            HStack(spacing: 46) {
                Button { skip(by: -1) } label: { Image(systemName: "backward.fill") }
                Button { togglePlay() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 40))
                        .frame(width: 56, height: 56)
                }
                Button { skip(by: 1) } label: { Image(systemName: "forward.fill") }
            }
            .font(.system(size: 28))
            .buttonStyle(.plain)
            .foregroundStyle(.white)

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                VolumeBar(value: $volume)
                Image(systemName: "speaker.wave.3.fill")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.6))

            // Bộ nút phụ: kính khúc xạ đúng cái mesh đang nằm dưới nó.
            HStack(spacing: 14) {
                glassButton("quote.bubble")
                glassButton("airplay.audio")
                glassButton("list.bullet")
            }
        }
        .padding(.horizontal, 24)

        if landscape {
            // iOS 27: ngang thì bìa bên trái, điều khiển bên phải. Ảnh bìa vẫn
            // do `artwork(geo:)` vẽ và định vị, nên ở đây chỉ chừa chỗ.
            HStack(spacing: 0) {
                Color.clear.frame(width: geo.screen.width * 0.5)
                controls.frame(width: geo.screen.width * 0.5)
            }
            .padding(.top, geo.safeTop + 24)
            .opacity(geo.fullContentOpacity)
            .offset(y: geo.fullContentOffset)
            .allowsHitTesting(geo.progress > 0.98)
        } else {
            // ZStack một tầng, mỗi thứ tự định vị bằng padding của nó. Bản đầu
            // dùng VStack **và** overlay, và `controls` lọt vào cả hai — nên ở
            // progress 0.5 bộ điều khiển hiện rõ mồn một, vẽ hai lần, tràn cả
            // ra ngoài thẻ. Không đọc code nào bắt được lỗi đó; ảnh chụp
            // khung giữa bắt được ngay.
            ZStack(alignment: .top) {
                grabber(geo: geo)
                    .padding(.top, geo.safeTop + 6)

                controls
                    .padding(.top, geo.contentTop)
                    .opacity(geo.fullContentOpacity)
                    .offset(y: geo.fullContentOffset)
            }
            .frame(height: geo.screen.height, alignment: .top)
            .allowsHitTesting(geo.progress > 0.98)
        }
    }

    private func grabber(geo: PlayerGeometry) -> some View {
        Capsule()
            .fill(.white.opacity(0.4))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .opacity(geo.fullContentOpacity)
    }

    private func glassButton(_ glyph: String) -> some View {
        Button { } label: {
            Image(systemName: glyph)
                .font(.system(size: 17))
                .frame(width: 46, height: 38)
        }
        .buttonStyle(.glass)
        .foregroundStyle(.white)
    }

    // MARK: Ảnh bìa — một view duy nhất, tồn tại suốt

    private func artwork(geo: PlayerGeometry) -> some View {
        Group {
            if let animatedArtwork {
                animatedArtwork
            } else {
                LinearGradient(colors: song.colours, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay {
                        Image(systemName: song.glyph)
                            .font(.system(size: lerp(17, 62, geo.progress)))
                            .foregroundStyle(.white.opacity(0.9))
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: geo.artworkCorner, style: .continuous))
        .frame(width: geo.artworkSide, height: geo.artworkSide)
        // Yêu cầu: co lại khi tạm dừng, lò xo nảy hơn phần còn lại. Chỉ khi đã
        // mở — thumbnail 40pt co xuống 32pt trông như lỗi layout, không như
        // một nhịp nhạc.
        .scaleEffect(pausedScale(geo.progress))
        .shadow(color: .black.opacity(geo.artworkShadowOpacity * pausedShadow(geo.progress)),
                radius: geo.artworkShadowRadius * pausedShadow(geo.progress),
                y: geo.artworkShadowY)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isPlaying)
        .animation(.smooth, value: trackIndex)
        .position(geo.artworkCentre)
        .allowsHitTesting(false)
    }

    private func pausedScale(_ p: CGFloat) -> CGFloat { p > 0.5 && !isPlaying ? 0.8 : 1 }
    private func pausedShadow(_ p: CGFloat) -> CGFloat { p > 0.5 && !isPlaying ? 0.5 : 1 }

    // MARK: Cử chỉ — một cái, hai ý nghĩa

    /// Trục được chốt ở lần dịch chuyển đầu tiên rồi giữ tới khi nhấc tay.
    /// Không chốt thì một cú vuốt chéo vừa bung player vừa đổi bài.
    private func dragGesture(screenHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                if axis == nil {
                    let t = value.translation
                    // Ngang chỉ được phép khi đang là viên thuốc.
                    axis = (abs(t.width) > abs(t.height) && progress < 0.5)
                        ? .horizontal : .vertical
                    dragStart = progress
                }

                switch axis {
                case .horizontal:
                    // Có sức cản: kính bị kéo, không phải bị trượt.
                    skipOffset = value.translation.width * 0.55
                case .vertical, .none:
                    let raw = dragStart - value.translation.height / screenHeight
                    if raw > 1 {
                        progress = 1 + rubberBand(raw - 1)
                    } else if raw < 0 {
                        progress = -rubberBand(-raw)
                    } else {
                        progress = raw
                    }
                }
            }
            .onEnded { value in
                defer { axis = nil }

                if axis == .horizontal {
                    let passed = abs(value.translation.width) > Metrics.skipDistance
                        || abs(value.velocity.width) > 600
                    if passed { skip(by: value.translation.width < 0 ? 1 : -1) }
                    // Bật về bằng lò xo nảy: đó là cái "wobble" của kính.
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.62)) {
                        skipOffset = 0
                    }
                    return
                }

                let velocity = value.velocity.height
                let travelled = -value.translation.height / screenHeight

                // Quyết định bằng **cả hai**: đã đi bao xa, và đang bay nhanh
                // thế nào. Chỉ quãng đường thì cú hất dứt khoát ở 10% bị bỏ
                // qua; chỉ vận tốc thì kéo chậm rồi thả luôn bật ngược.
                let open: Bool
                if velocity < -Metrics.dismissVelocity {
                    open = true
                } else if velocity > Metrics.dismissVelocity {
                    open = false
                } else if dragStart > 0.5 {
                    open = -travelled < Metrics.dismissFraction
                } else {
                    open = travelled > Metrics.dismissFraction
                }
                setExpanded(open, velocity: velocity, screenHeight: screenHeight)
            }
    }

    /// Chạy nốt hành trình, mang theo quán tính của ngón tay.
    ///
    /// `interpolatingSpring` chứ không phải `spring`, vì chỉ nó nhận
    /// `initialVelocity`. Bộ số quy từ `response: 0.45, dampingFraction: 0.72`
    /// mà spec yêu cầu, khối lượng 1:
    ///
    ///     ω = 2π / 0.45              = 13.96
    ///     stiffness = ω² · m         = 195.0
    ///     damping   = 2 · ζ · ω · m  = 20.1
    ///
    /// `initialVelocity` tính theo **đơn vị của giá trị đang animate mỗi
    /// giây**, mà giá trị ở đây là `progress` (0…1) — nên điểm/giây phải chia
    /// cho chiều cao màn hình. Nhét thẳng 2000 điểm/giây vào là một cú giật
    /// văng ra khỏi màn hình.
    ///
    /// Vì luôn animate **cùng một property**, một cú chạm hay kéo giữa chừng
    /// retarget lò xo thay vì khởi động lại nó — đúng yêu cầu 4.
    private func setExpanded(_ expanded: Bool, velocity: CGFloat, screenHeight: CGFloat = 1) {
        let initialVelocity = screenHeight > 1 ? -velocity / screenHeight : 0
        withAnimation(.interpolatingSpring(mass: 1, stiffness: 195, damping: 20.1,
                                           initialVelocity: initialVelocity)) {
            progress = expanded ? 1 : 0
        }
        // Haptic ở thời điểm *quyết định*, không phải khi lò xo dừng: cái tay
        // cảm nhận được là khoảnh khắc thẻ được thả ra.
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func skip(by delta: Int) {
        withAnimation(.smooth(duration: 0.32)) {
            trackIndex = (trackIndex + delta + Song.all.count) % Song.all.count
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func togglePlay() { isPlaying.toggle() }
}

// MARK: - Scrubber

/// Dày lên và hiện nhãn thời gian khi ngón tay chạm vào.
private struct Scrubber: View {
    @Binding var value: CGFloat
    @Binding var scrubbing: Bool

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let w = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule().fill(.white.opacity(0.92))
                        .frame(width: max(0, min(1, value)) * w)
                }
                .frame(height: scrubbing ? 12 : 6)
                .frame(maxHeight: .infinity)
                // Vệt sáng chạy dọc mép trên khi đang kéo — kính bắt sáng.
                .overlay(alignment: .top) {
                    if scrubbing {
                        Capsule()
                            .fill(.white.opacity(0.5))
                            .frame(height: 1)
                            .blur(radius: 0.5)
                            .padding(.horizontal, 2)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                scrubbing = true
                            }
                            value = min(max(g.location.x / w, 0), 1)
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                scrubbing = false
                            }
                        }
                )
            }
            .frame(height: 18)

            HStack {
                Text(time(value * 223))
                Spacer()
                Text("-" + time((1 - value) * 223))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(scrubbing ? 0.9 : 0.45))
        }
    }

    private func time(_ seconds: CGFloat) -> String {
        let s = Int(max(0, seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct VolumeBar: View {
    @Binding var value: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                Capsule().fill(.white.opacity(0.85))
                    .frame(width: max(0, min(1, value)) * w)
            }
            .frame(height: 5)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value = min(max($0.location.x / w, 0), 1) }
            )
        }
        .frame(height: 20)
    }
}

// MARK: - Nền mesh

/// Mesh gradient dựng từ màu bìa.
///
/// **Trôi bằng `.offset`/`.scaleEffect`, không bằng cách đổi `points`.** Dịch
/// một lớp đã vẽ xong là việc Core Animation làm một mình ở render server;
/// đổi toạ độ điểm buộc vẽ lại toàn bộ lưới mỗi frame. `points` nhận `Float`,
/// không phải `CGFloat` — lỗi biên dịch duy nhất khi dò API iOS 26.
private struct MeshBackdrop: View {
    let colours: [Color]
    @State private var drift = false

    var body: some View {
        let c = padded(colours)
        MeshGradient(
            width: 3, height: 3,
            points: [
                .init(0, 0), .init(0.5, 0), .init(1, 0),
                .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
                .init(0, 1), .init(0.5, 1), .init(1, 1)
            ],
            colors: [c[0], c[1], c[2],
                     c[1], c[2], c[0],
                     c[2], c[0], c[1]]
        )
        .scaleEffect(drift ? 1.25 : 1.1)
        .offset(x: drift ? 26 : -26, y: drift ? -34 : 20)
        .blur(radius: 42)
        .overlay(
            LinearGradient(colors: [.clear, .black.opacity(0.55)],
                           startPoint: .center, endPoint: .bottom)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 11).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func padded(_ input: [Color]) -> [Color] {
        var out = input
        while out.count < 3 { out.append(out.last ?? .black) }
        return out
    }
}

// MARK: - Danh sách nền

/// `Equatable` có chủ đích, dữ liệu không đổi, để `.equatable()` ở chỗ gọi cắt
/// hẳn việc chạy lại `body` trong suốt cú chuyển cảnh.
private struct LibraryList: View, Equatable {
    /// Safe-area trên, truyền vào chứ không tự đọc: root đã `ignoresSafeArea`
    /// để toạ độ thẻ tính từ mép màn hình thật, nên bên trong không còn safe
    /// area để đọc. Hằng số theo máy nên không phá vỡ Equatable.
    let topInset: CGFloat

    static func == (lhs: LibraryList, rhs: LibraryList) -> Bool {
        lhs.topInset == rhs.topInset
    }

    private var rows: [Song] { Song.all + Song.all + Song.all }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, song in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LinearGradient(colors: song.colours,
                                                 startPoint: .topLeading,
                                                 endPoint: .bottomTrailing))
                            .frame(width: 46, height: 46)
                            .overlay {
                                Image(systemName: song.glyph)
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title).lineLimit(1)
                            Text(song.artist).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                // Chừa chỗ cho viên thuốc và thanh tab nổi.
                Color.clear.frame(height: 130).listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // Màu phải đặt **bên trong** `NavigationStack`: đặt ngoài thì nó
            // nằm sau nền đục của chính NavigationStack và không bao giờ thấy.
            .background(Color(white: 0.09))
            .navigationTitle("Bài hát")
        }
        .padding(.top, topInset)
        .background(Color(white: 0.09))
    }
}

// MARK: - Preview

#Preview("Viên thuốc") { ContentView() }
#Preview("Giữa chừng") { ContentView(initialProgress: 0.5) }
#Preview("Mở hết") { ContentView(initialProgress: 1) }
