//
//  ContentView.swift
//  Mini player → full player, một component, một giá trị progress.
//  iOS 17+, không thư viện ngoài. Dán thẳng vào project SwiftUI mới.
//
//  ─────────────────────────────────────────────────────────────────────────
//  VỀ `matchedGeometryEffect`, VÀ VÌ SAO FILE NÀY KHÔNG DÙNG NÓ
//  ─────────────────────────────────────────────────────────────────────────
//  Spec yêu cầu ảnh bìa morph liên tục và *không bao giờ* cross-fade, đồng
//  thời yêu cầu mọi thuộc tính là hàm thuần của một `progress` bám theo ngón
//  tay. Hai điều đó không cùng tồn tại với `matchedGeometryEffect`:
//
//  `matchedGeometryEffect` nội suy giữa frame của view *nguồn* và view *đích*
//  theo một đường cong animation. Không có API công khai nào tua nó tới một
//  phần trăm cụ thể. Nghĩa là nó không thể theo ngón tay, và nó cần **hai**
//  view (một biến mất, một xuất hiện) — tức là vẫn có một cú swap, chỉ được
//  giấu đi bằng chuyển động.
//
//  Cách ở đây mạnh hơn chứ không phải yếu hơn: ảnh bìa là **một view duy
//  nhất**, tồn tại suốt, và frame/bo góc/bóng của nó tính từ `progress`. Nó
//  không thể cross-fade vì không có gì để fade sang. Và vì `progress` là một
//  con số, ngón tay lái được nó trực tiếp.
//
//  Đây cũng là lý do Apple Music làm được cả hai chiều: bên trong nó là
//  `UIViewPropertyAnimator`, thứ có `fractionComplete` — bản UIKit của đúng
//  một biến progress.
//
//  ─────────────────────────────────────────────────────────────────────────
//  TOÀN BỘ PHÉP NỘI SUY NẰM Ở `PlayerGeometry`
//  ─────────────────────────────────────────────────────────────────────────
//  Không có công thức nào rải trong view. Mọi thứ đi qua `lerp(a, b, p)` với
//  cùng một `p`, nên hai đầu mút luôn đúng và không có lớp nào lệch pha với
//  lớp khác.
//

import SwiftUI
import UIKit

// MARK: - Dữ liệu giả

struct Song {
    let title: String
    let artist: String
    let album: String
    /// Ảnh bìa giả: hai màu để dựng gradient.
    let colours: [Color]
    let glyph: String

    static let mock = Song(
        title: "Chiều nay không có mưa bay",
        artist: "Vũ.",
        album: "Bảo tàng của nuối tiếc",
        colours: [Color(red: 0.29, green: 0.42, blue: 0.68), Color(red: 0.13, green: 0.16, blue: 0.30)],
        glyph: "cloud.rain.fill"
    )
}

// MARK: - Số học nội suy

/// Nội suy tuyến tính. Mọi thuộc tính động trong file này đi qua đúng hàm này.
@inline(__always)
private func lerp(_ from: CGFloat, _ to: CGFloat, _ t: CGFloat) -> CGFloat {
    from + (to - from) * t
}

/// Cắt một đoạn con của progress rồi trải nó về 0…1.
///
/// Đây là công cụ dựng mọi hiệu ứng lệch pha (yêu cầu 4). `ramp(p, 0, 0.3)`
/// nghĩa là "chạy hết trong 30% đầu rồi đứng yên"; `ramp(p, 0.6, 1)` nghĩa là
/// "nằm im tới 60% rồi mới bắt đầu".
@inline(__always)
private func ramp(_ p: CGFloat, _ start: CGFloat, _ end: CGFloat) -> CGFloat {
    guard end > start else { return p >= end ? 1 : 0 }
    return min(max((p - start) / (end - start), 0), 1)
}

/// Giảm dần độ nhạy khi kéo quá biên, thay vì chặn cứng.
///
/// Chặn cứng ở 1.0 làm ngón tay đang di chuyển mà màn hình đứng im — đọc ra
/// như treo máy. Hàm này cho nó vẫn nhúc nhích nhưng ngày càng ít, tiệm cận
/// `limit`. Cùng dạng đường cong UIScrollView dùng khi kéo quá đầu danh sách.
private func rubberBand(_ overflow: CGFloat, limit: CGFloat = 0.12) -> CGFloat {
    limit * (1 - 1 / (overflow / limit + 1))
}

// MARK: - Hằng số hình học

private enum Metrics {
    static let miniHeight: CGFloat = 64
    static let tabBarHeight: CGFloat = 49

    static let miniArtwork: CGFloat = 40
    static let miniArtworkLeading: CGFloat = 16
    static let miniArtworkCorner: CGFloat = 6

    static let fullArtworkInset: CGFloat = 48
    static let fullArtworkCorner: CGFloat = 12
    /// Khoảng cách từ mép trên safe area tới đỉnh ảnh bìa khi mở hết.
    static let fullArtworkTop: CGFloat = 44

    static let backdropScale: CGFloat = 0.94
    static let backdropCorner: CGFloat = 14
    static let backdropShift: CGFloat = 10
    static let dimOpacity: CGFloat = 0.35

    /// Kéo qua bao nhiêu phần màn hình thì buông tay là đóng (yêu cầu 3).
    static let dismissFraction: CGFloat = 0.30
    /// Điểm/giây. Trên ngưỡng này thì đóng bất kể đã kéo được bao xa.
    static let dismissVelocity: CGFloat = 800
}

/// Bán kính bo góc màn hình thật của máy.
///
/// `_displayCornerRadius` là KVC vào một thuộc tính riêng tư của `UIScreen`.
/// Nó chạy từ iOS 11 tới nay và được dùng rất rộng rãi, nhưng **vẫn là API
/// riêng tư**: nếu anh e ngại khâu duyệt App Store thì xoá nhánh KVC đi và
/// giữ mỗi `fallback`. Chênh lệch thị giác gần như bằng không — 39pt đúng cho
/// hầu hết iPhone có notch/Dynamic Island.
private enum Display {
    static let fallbackCornerRadius: CGFloat = 39

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

// MARK: - Hình học của thẻ, ở một chỗ

/// Mọi con số động, tính một lần cho mỗi frame từ đúng một `progress`.
///
/// Là struct chứ không phải một mớ computed property rải trong view, vì hai
/// lý do: đọc được toàn bộ phép nội suy trong một màn hình, và test được nếu
/// muốn — không cần dựng view nào để hỏi "ở progress 0.5 thì ảnh bìa ở đâu".
private struct PlayerGeometry {
    let progress: CGFloat
    let screen: CGSize
    let safeTop: CGFloat
    let safeBottom: CGFloat

    // MARK: Thẻ

    /// Đáy thẻ: thu gọn thì nằm ngay trên tab bar, mở hết thì chạm đáy màn hình.
    var bottomGap: CGFloat {
        lerp(Metrics.tabBarHeight + safeBottom, 0, progress)
    }

    var height: CGFloat {
        lerp(Metrics.miniHeight, screen.height, progress)
    }

    var top: CGFloat {
        screen.height - bottomGap - height
    }

    /// Yêu cầu 6: 0 khi là thanh, tới bán kính màn hình thật khi mở hết.
    ///
    /// Đi hết trong 60% đầu chứ không phải cả hành trình: khi thẻ đã cao quá
    /// nửa màn hình thì góc dưới của nó đã ra khỏi tầm nhìn, và một bán kính
    /// còn đang bò tiếp chỉ là chi phí không ai thấy.
    var cornerRadius: CGFloat {
        lerp(0, Display.cornerRadius, ramp(progress, 0, 0.6))
    }

    // MARK: Ảnh bìa

    var artworkSide: CGFloat {
        lerp(Metrics.miniArtwork, screen.width - Metrics.fullArtworkInset, progress)
    }

    var artworkCorner: CGFloat {
        lerp(Metrics.miniArtworkCorner, Metrics.fullArtworkCorner, progress)
    }

    /// Tâm ảnh bìa, trong toạ độ **của thẻ** (y = 0 là đỉnh thẻ).
    ///
    /// Toạ độ thẻ chứ không phải toạ độ màn hình, nên khi thẻ tự trượt lên thì
    /// ảnh bìa đi theo miễn phí — không có hai chuyển động phải khớp nhau.
    var artworkCentre: CGPoint {
        let collapsed = CGPoint(
            x: Metrics.miniArtworkLeading + Metrics.miniArtwork / 2,
            y: Metrics.miniHeight / 2
        )
        let expandedSide = screen.width - Metrics.fullArtworkInset
        let expanded = CGPoint(
            x: screen.width / 2,
            y: safeTop + Metrics.fullArtworkTop + expandedSide / 2
        )
        return CGPoint(
            x: lerp(collapsed.x, expanded.x, progress),
            y: lerp(collapsed.y, expanded.y, progress)
        )
    }

    /// Bóng của ảnh bìa: nhẹ khi là thumbnail, lớn và mềm khi mở.
    ///
    /// Lưu ý một chi phí thật: một view **vừa đổi kích thước vừa có bóng** buộc
    /// bộ dựng hình phải raster nó ra buffer ngoài màn hình mỗi frame để lấy
    /// hình bao. Ở đây chấp nhận được vì chỉ có ảnh bìa mang bóng, không phải
    /// cả thẻ. Đổ bóng cho cả thẻ đang phóng to là cách chắc chắn nhất để mất
    /// frame.
    var artworkShadowRadius: CGFloat { lerp(4, 26, progress) }
    var artworkShadowOpacity: CGFloat { lerp(0.18, 0.38, progress) }
    var artworkShadowY: CGFloat { lerp(2, 14, progress) }

    // MARK: Lệch pha (yêu cầu 4)

    /// Chrome của thanh mini tắt trong 30% đầu.
    var miniChromeOpacity: CGFloat { 1 - ramp(progress, 0, 0.30) }

    /// Điều khiển của player đầy đủ chỉ bật trong 40% cuối. 0.60 > 0.30, nên
    /// hai lớp không bao giờ cùng hiện rõ.
    var fullChromeOpacity: CGFloat { ramp(progress, 0.60, 1) }

    /// Kèm một cú trượt lên nhẹ, để nó "tới" chứ không chỉ "hiện ra".
    var fullChromeOffset: CGFloat { lerp(24, 0, fullChromeOpacity) }

    /// Nội dung dưới ảnh bìa bắt đầu ở đâu (toạ độ thẻ).
    var contentTop: CGFloat {
        artworkCentre.y + artworkSide / 2 + 36
    }

    // MARK: Nền phía sau (yêu cầu 5)

    var backdropScale: CGFloat { lerp(1, Metrics.backdropScale, progress) }
    var backdropCorner: CGFloat { lerp(0, Metrics.backdropCorner, progress) }
    var backdropShift: CGFloat { lerp(0, Metrics.backdropShift, progress) }
    var dimOpacity: CGFloat { Metrics.dimOpacity * progress }
}

// MARK: - Root

struct ContentView: View {

    /// 0 = thanh mini, 1 = toàn màn hình. Nguồn sự thật duy nhất cho chuyển
    /// động; không có `isExpanded` song song để hai thứ lệch nhau.
    @State private var progress: CGFloat = 0
    /// Giá trị `progress` tại thời điểm ngón tay chạm xuống, để cú kéo cộng
    /// dồn lên nó thay vì luôn bắt đầu từ 0.
    @State private var dragStart: CGFloat = 0
    @State private var isDragging = false

    @State private var isPlaying = true
    @State private var scrub: Double = 0.32
    @State private var volume: Double = 0.6

    private let song = Song.mock

    /// Mở sẵn ở một điểm bất kỳ của hành trình. Mặc định 0, nên project mới
    /// chỉ cần `ContentView()`.
    ///
    /// Có mặt vì preview một trạng thái *giữa chừng* là cách duy nhất nhìn
    /// được phần khó nhất của file này: ở 0.5 thì chrome mini phải tắt hẳn,
    /// chrome đầy đủ chưa được hiện, nền đã thu và ảnh bìa đang trên đường
    /// bay. Ba lỗi trong prototype này bị bắt đúng bằng cách nhìn khung đó.
    init(initialProgress: CGFloat = 0) {
        _progress = State(initialValue: min(max(initialProgress, 0), 1))
    }

    var body: some View {
        GeometryReader { proxy in
            // Reader này **không** `ignoresSafeArea`: chỉ reader còn tôn trọng
            // safe area mới trả về `safeAreaInsets` thật. Thẻ bên trong tự
            // tràn ra mép, nhưng số dùng để xếp chỗ phải đúng, nếu không
            // grabber sẽ chui vào sau Dynamic Island.
            let insets = proxy.safeAreaInsets
            let screen = CGSize(
                width: proxy.size.width,
                height: proxy.size.height + insets.top + insets.bottom
            )
            let geo = PlayerGeometry(
                progress: progress,
                screen: screen,
                safeTop: insets.top,
                safeBottom: insets.bottom
            )

            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()

                backdrop(geo: geo, safeTop: insets.top, safeBottom: insets.bottom)

                Color.black
                    .opacity(geo.dimOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                card(geo: geo)
            }
            .ignoresSafeArea()
        }
        .statusBarHidden(progress > 0.5)
        .preferredColorScheme(.dark)
    }

    // MARK: Nền: thư viện + tab bar, biến đổi như một khối

    private func backdrop(geo: PlayerGeometry, safeTop: CGFloat, safeBottom: CGFloat) -> some View {
        VStack(spacing: 0) {
            // `.equatable()` là cách thực thi yêu cầu "không dựng lại danh sách
            // trong lúc chuyển cảnh". `LibraryList` không đọc `progress`, và
            // vì nó Equatable với dữ liệu không đổi, SwiftUI bỏ qua luôn việc
            // chạy lại `body` của nó ở mỗi frame — chỉ các modifier biến đổi
            // bên ngoài chạy lại, và những cái đó Core Animation lo.
            LibraryList(topInset: safeTop).equatable()
            TabBar(safeBottom: safeBottom)
        }
        // Thứ tự có ý nghĩa: bo góc trước, rồi mới thu nhỏ và đẩy xuống. Đảo
        // lại thì bán kính bị chính phép thu nhỏ nhân theo và góc trông nhỏ
        // hơn con số đã đặt.
        .clipShape(RoundedRectangle(cornerRadius: geo.backdropCorner, style: .continuous))
        .scaleEffect(geo.backdropScale)
        .offset(y: geo.backdropShift)
    }

    // MARK: Thẻ: một view, hai trạng thái

    private func card(geo: PlayerGeometry) -> some View {
        ZStack(alignment: .topLeading) {
            // Nền thẻ. Thu gọn là ultraThinMaterial (nhìn xuyên thấy danh
            // sách); mở ra thì gradient từ màu bìa dâng lên phía trên nó.
            Rectangle()
                .fill(.ultraThinMaterial)

            LinearGradient(
                colors: [song.colours[0], song.colours[1], .black],
                startPoint: .top,
                endPoint: .bottom
            )
            // Đục hẳn từ 35% trở đi. Vật liệu là một lớp làm mờ sống, tính lại
            // mỗi frame, và nó tốn y như nhau ở opacity 0.01 lẫn 1 — nên khi
            // gradient đã che kín thì lớp dưới không còn lý do tồn tại.
            .opacity(ramp(geo.progress, 0, 0.35))

            grabber(geo: geo)
            miniChrome(geo: geo)
            fullChrome(geo: geo)

            // Ảnh bìa nằm trên cùng: nó là thứ đi xuyên suốt hai trạng thái,
            // và không lớp chrome nào được phép cắt ngang đường bay của nó.
            artwork(geo: geo)
        }
        .frame(width: geo.screen.width, height: geo.height, alignment: .top)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: geo.cornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: geo.cornerRadius,
                style: .continuous
            )
        )
        .offset(y: geo.top)
        // Chạm để mở, nhưng chỉ khi đang thu gọn — chạm giữa player đang mở
        // không được đóng nó.
        .onTapGesture {
            if progress < 0.5 { setExpanded(true, velocity: 0) }
        }
        .gesture(dragGesture(screenHeight: geo.screen.height))
    }

    private func grabber(geo: PlayerGeometry) -> some View {
        Capsule()
            .fill(.white.opacity(0.4))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            // `safeTop + 6`, không phải một phần của nó: bản đầu dùng
            // `safeTop * 0.35 + 10` = 30pt trên iPhone 17 và grabber nằm gọn
            // sau Dynamic Island (đảo kết thúc ở ~48pt). Mốc duy nhất đúng
            // trên mọi máy là chính safe area, không phải một tỉ lệ của nó.
            .padding(.top, geo.safeTop + 6)
            .opacity(geo.fullChromeOpacity)
    }

    // MARK: Chrome của thanh mini

    private func miniChrome(geo: PlayerGeometry) -> some View {
        HStack(spacing: 0) {
            // Chỗ trống đúng bằng ảnh bìa thu gọn: ảnh bìa được `.position`
            // đặt chỗ nên nó không tham gia layout của hàng này.
            Color.clear
                .frame(width: Metrics.miniArtworkLeading + Metrics.miniArtwork + 12)

            Text(song.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            Button { togglePlay() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            Button { } label: {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .padding(.trailing, 4)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .frame(height: Metrics.miniHeight)
        .opacity(geo.miniChromeOpacity)
        // Ngừng nhận chạm ngay khi bắt đầu mờ, nếu không hai nút vô hình vẫn
        // ăn mất cú chạm ở nửa đầu hành trình.
        .allowsHitTesting(geo.progress < 0.02)
    }

    // MARK: Chrome của player đầy đủ

    private func fullChrome(geo: PlayerGeometry) -> some View {
        VStack(spacing: 26) {
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                Text(song.artist)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 4) {
                Slider(value: $scrub)
                    .tint(.white.opacity(0.9))
                HStack {
                    Text("1:12")
                    Spacer()
                    Text("-2:31")
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
            }

            HStack(spacing: 52) {
                Button { } label: { Image(systemName: "backward.fill") }
                Button { togglePlay() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 42))
                        .frame(width: 60, height: 60)
                }
                Button { } label: { Image(systemName: "forward.fill") }
            }
            .font(.system(size: 30))
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                Slider(value: $volume)
                    .tint(.white.opacity(0.9))
                Image(systemName: "speaker.wave.3.fill")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.55))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.top, geo.contentTop)
        .opacity(geo.fullChromeOpacity)
        .offset(y: geo.fullChromeOffset)
        .allowsHitTesting(geo.progress > 0.98)
    }

    // MARK: Ảnh bìa — một view duy nhất, tồn tại suốt

    private func artwork(geo: PlayerGeometry) -> some View {
        RoundedRectangle(cornerRadius: geo.artworkCorner, style: .continuous)
            .fill(
                LinearGradient(
                    colors: song.colours,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: song.glyph)
                    .font(.system(size: lerp(18, 64, geo.progress)))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: geo.artworkSide, height: geo.artworkSide)
            // Yêu cầu 7: co lại khi tạm dừng, với lò xo nảy hơn phần còn lại.
            // Chỉ áp dụng khi đã mở — thumbnail 40pt co xuống 32pt trông như
            // lỗi layout chứ không như một nhịp nhạc.
            .scaleEffect(pausedScale(progress: geo.progress))
            .shadow(
                color: .black.opacity(geo.artworkShadowOpacity * pausedShadow(progress: geo.progress)),
                radius: geo.artworkShadowRadius * pausedShadow(progress: geo.progress),
                y: geo.artworkShadowY
            )
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isPlaying)
            .position(geo.artworkCentre)
            .allowsHitTesting(false)
    }

    private func pausedScale(progress: CGFloat) -> CGFloat {
        guard progress > 0.5, !isPlaying else { return 1 }
        return 0.8
    }

    private func pausedShadow(progress: CGFloat) -> CGFloat {
        guard progress > 0.5, !isPlaying else { return 1 }
        return 0.5
    }

    // MARK: Cử chỉ

    /// Ngón tay lái thẳng `progress`, không qua animation nào.
    ///
    /// `progress = dragStart - translation / screenHeight`: kéo xuống là
    /// `translation` dương nên `progress` giảm. Chia cho chiều cao màn hình để
    /// "kéo hết màn hình" đúng bằng "đi hết hành trình", bất kể máy nào.
    private func dragGesture(screenHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStart = progress
                }
                let raw = dragStart - value.translation.height / screenHeight

                // Quá biên thì giảm nhạy chứ không chặn cứng — xem `rubberBand`.
                if raw > 1 {
                    progress = 1 + rubberBand(raw - 1)
                } else if raw < 0 {
                    progress = -rubberBand(-raw)
                } else {
                    progress = raw
                }
            }
            .onEnded { value in
                isDragging = false

                // Vận tốc điểm/giây, dương là xuống. iOS 17 cho thẳng, không
                // cần suy ra từ `predictedEndTranslation` nữa.
                let velocity = value.velocity.height
                let travelled = -value.translation.height / screenHeight

                // Quyết định bằng **cả hai**: đã đi được bao xa, và đang bay
                // nhanh thế nào. Chỉ xét quãng đường thì một cú hất dứt khoát
                // ở 10% màn hình bị bỏ qua; chỉ xét vận tốc thì kéo chậm rồi
                // thả sẽ luôn bật ngược về.
                let goingOpen: Bool
                if velocity < -Metrics.dismissVelocity {
                    goingOpen = true
                } else if velocity > Metrics.dismissVelocity {
                    goingOpen = false
                } else if dragStart > 0.5 {
                    goingOpen = -travelled < Metrics.dismissFraction
                } else {
                    goingOpen = travelled > Metrics.dismissFraction
                }

                setExpanded(goingOpen, velocity: velocity, screenHeight: screenHeight)
            }
    }

    /// Chạy nốt phần còn lại của hành trình, mang theo quán tính của ngón tay.
    ///
    /// `interpolatingSpring` chứ không phải `spring`, vì chỉ nó nhận
    /// `initialVelocity`. Bộ số quy từ đúng `response: 0.5, dampingFraction:
    /// 0.82` mà spec yêu cầu, với khối lượng 1:
    ///
    ///     ω = 2π / response         = 12.566
    ///     stiffness = ω² · m        = 157.9
    ///     damping   = 2 · ζ · ω · m = 20.6
    ///
    /// `initialVelocity` tính theo **đơn vị của giá trị đang animate mỗi
    /// giây**, mà giá trị ở đây là `progress` (0…1) — nên điểm/giây phải chia
    /// cho chiều cao màn hình. Đây là chỗ hay sai: nhét thẳng 2000 điểm/giây
    /// vào sẽ cho một cú giật văng ra khỏi màn hình.
    private func setExpanded(_ expanded: Bool, velocity: CGFloat, screenHeight: CGFloat = 1) {
        let target: CGFloat = expanded ? 1 : 0
        let initialVelocity = screenHeight > 1 ? -velocity / screenHeight : 0

        withAnimation(
            .interpolatingSpring(
                mass: 1,
                stiffness: 157.9,
                damping: 20.6,
                initialVelocity: initialVelocity
            )
        ) {
            progress = target
        }

        // Haptic ở thời điểm *quyết định*, không phải khi lò xo dừng: cái tay
        // cảm nhận được là khoảnh khắc thẻ được thả ra, không phải khoảnh khắc
        // nó ngừng rung.
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func togglePlay() {
        isPlaying.toggle()
    }
}

// MARK: - Nền: danh sách

/// `Equatable` một cách có chủ đích, với dữ liệu không đổi, để `.equatable()`
/// ở chỗ gọi cắt hẳn việc chạy lại `body` trong suốt cú chuyển cảnh.
private struct LibraryList: View, Equatable {
    /// Safe-area trên, truyền vào chứ không tự đọc: root đã `ignoresSafeArea`
    /// để toạ độ của thẻ tính từ mép màn hình thật, nên bên trong đó không còn
    /// safe area nào để đọc nữa. Là hằng số theo máy, nên nó không phá vỡ phép
    /// so sánh Equatable bên dưới.
    let topInset: CGFloat

    static func == (lhs: LibraryList, rhs: LibraryList) -> Bool {
        lhs.topInset == rhs.topInset
    }

    private let rows = [
        ("Chiều nay không có mưa bay", "Vũ."),
        ("Có hẹn với thanh xuân", "MONSTAR"),
        ("Nhất thời", "Hoàng Dũng"),
        ("Đông kiếm em", "Nguyên Hà"),
        ("Bước qua nhau", "Vũ."),
        ("Đông Kiếm Em", "Nguyên Hà")
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(rows, id: \.0) { row in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: Song.mock.colours,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.0).font(.body).lineLimit(1)
                            Text(row.1).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // Xám rất nhẹ chứ không đen tuyền: trên nền đen, một tấm card đen
            // thu nhỏ lại là một tấm card vô hình, và cả hiệu ứng chồng thẻ
            // coi như không có.
            //
            // Phải đặt **bên trong** `NavigationStack`. Đặt ở ngoài thì nó nằm
            // sau nền đục của chính NavigationStack và không bao giờ nhìn thấy
            // — bản đầu của file này đặt sai chỗ, và danh sách vẫn đen thui dù
            // màu đã được khai báo.
            .background(Color(white: 0.09))
            .navigationTitle("Bài hát")
        }
        .padding(.top, topInset)
        // Cái này thì phủ dải status bar mà `padding` ở trên vừa chừa ra.
        .background(Color(white: 0.09))
    }
}

// MARK: - Nền: tab bar

private struct TabBar: View {
    let safeBottom: CGFloat

    var body: some View {
        HStack {
            item("music.note.house.fill", "Nghe ngay")
            item("square.stack.fill", "Thư viện")
            item("magnifyingglass", "Tìm kiếm")
        }
        .frame(height: Metrics.tabBarHeight)
        .padding(.bottom, safeBottom)
        .background(.ultraThinMaterial)
    }

    private func item(_ glyph: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: glyph).font(.system(size: 18))
            Text(label).font(.system(size: 10))
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white.opacity(0.8))
    }
}

// MARK: - Preview

#Preview("Thu gọn") {
    ContentView()
}

#Preview("Giữa chừng") {
    ContentView(initialProgress: 0.5)
}

#Preview("Mở hết") {
    ContentView(initialProgress: 1)
}
