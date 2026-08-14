//
//  PlayerMorphDemoView.swift
//  Bản thử: mini player → full player bằng **một** giá trị progress.
//
//  Không phải player thật. `PlayerCard` vẫn là player của app; file này tồn
//  tại để so cách bung mở, mở từ Cài đặt → Bản thử. Xoá nó = xoá file này và
//  một `Section` trong `SettingsView`.
//
//  ─────────────────────────────────────────────────────────────────────────
//  VÌ SAO KHÔNG DÙNG `matchedGeometryEffect`
//  ─────────────────────────────────────────────────────────────────────────
//  Nó nội suy giữa frame của view *nguồn* và view *đích* theo một đường cong,
//  và không có API công khai nào tua nó tới một phần trăm cụ thể — nên nó
//  không theo được ngón tay. Nó cũng cần **hai** view (một biến mất, một xuất
//  hiện), tức là vẫn có một cú swap, chỉ được giấu bằng chuyển động.
//
//  Ở đây ảnh bìa là **một view duy nhất**, tồn tại suốt, frame/bo góc/bóng
//  tính từ `progress`. Không thể cross-fade vì không có gì để fade sang, và vì
//  `progress` là một con số, ngón tay lái được trực tiếp. Đây cũng là cách
//  `PlayerCard` thật được viết, và là lý do Apple Music làm được cả hai chiều
//  — bên trong nó là `UIViewPropertyAnimator`, thứ có `fractionComplete`.
//
//  ─────────────────────────────────────────────────────────────────────────
//  UI MƯỢN CỦA APP THẬT, KHÔNG TỰ NGHĨ RA
//  ─────────────────────────────────────────────────────────────────────────
//  Bản thử này nằm trong target Evenstar, nên nó đọc thẳng `BottomBarMetrics`,
//  `BottomBarStyle` và `PlayerCard.collapsedHeight` thay vì chép số. Những
//  hằng số `private` bên trong `PlayerCard` thì phải khai lại — mỗi chỗ như
//  vậy đều ghi rõ nguồn, để khi bên kia đổi thì grep ra được.
//
//  Khác biệt duy nhất còn cố ý: dữ liệu giả, và không phát được gì.
//

import SwiftUI
import UIKit

// MARK: - Dữ liệu giả

struct DemoSong {
    let title: String
    let artist: String
    let album: String
    /// Ảnh bìa giả: hai màu để dựng gradient.
    let colours: [Color]
    let glyph: String

    static let mock = DemoSong(
        title: "Chiều nay không có mưa bay",
        artist: "Vũ.",
        album: "Bảo tàng của nuối tiếc",
        colours: [Color(red: 0.29, green: 0.42, blue: 0.68), Color(red: 0.13, green: 0.16, blue: 0.30)],
        glyph: "cloud.rain.fill"
    )

    static let library: [DemoSong] = [
        .mock,
        .init(title: "Có hẹn với thanh xuân", artist: "MONSTAR", album: "Single",
              colours: [Color(red: 0.72, green: 0.42, blue: 0.20), Color(red: 0.34, green: 0.17, blue: 0.12)],
              glyph: "sun.max.fill"),
        .init(title: "Nhất thời", artist: "Hoàng Dũng", album: "25",
              colours: [Color(red: 0.35, green: 0.24, blue: 0.48), Color(red: 0.17, green: 0.13, blue: 0.28)],
              glyph: "moon.stars.fill"),
        .init(title: "Đông kiếm em", artist: "Nguyên Hà", album: "Single",
              colours: [Color(red: 0.20, green: 0.45, blue: 0.45), Color(red: 0.10, green: 0.22, blue: 0.24)],
              glyph: "snowflake")
    ]
}

// MARK: - Số học nội suy

/// Nội suy tuyến tính. Mọi thuộc tính động trong file này đi qua đúng hàm này.
@inline(__always)
private func lerp(_ from: CGFloat, _ to: CGFloat, _ t: CGFloat) -> CGFloat {
    from + (to - from) * t
}

/// Cắt một đoạn con của progress rồi trải nó về 0…1.
///
/// Công cụ dựng mọi hiệu ứng lệch pha. `ramp(p, 0, 0.3)` = "chạy hết trong
/// 30% đầu rồi đứng yên"; `ramp(p, 0.6, 1)` = "nằm im tới 60% rồi mới bắt đầu".
@inline(__always)
private func ramp(_ p: CGFloat, _ start: CGFloat, _ end: CGFloat) -> CGFloat {
    guard end > start else { return p >= end ? 1 : 0 }
    return min(max((p - start) / (end - start), 0), 1)
}

/// Giảm dần độ nhạy khi kéo quá biên thay vì chặn cứng. Chặn cứng làm ngón tay
/// đang di chuyển mà màn hình đứng im — đọc ra như treo máy.
private func rubberBand(_ overflow: CGFloat, limit: CGFloat = 0.12) -> CGFloat {
    limit * (1 - 1 / (overflow / limit + 1))
}

// MARK: - Hằng số, lấy từ app thật

private enum DemoMetrics {
    /// Từ `PlayerCard.collapsedHeight` — không khai lại được thì đọc thẳng.
    static let pillHeight = PlayerCard.collapsedHeight
    /// `private` trong `PlayerCard`: `collapsedHeight / 2`. Viên thuốc thật,
    /// hai đầu là nửa đường tròn.
    static let pillCorner = PlayerCard.collapsedHeight / 2
    /// `private` trong `PlayerCard`: `collapsedArtwork`, `collapsedArtworkInset`,
    /// `collapsedArtworkGap`.
    static let miniArtwork: CGFloat = 36
    static let miniArtworkInset: CGFloat = 18
    static let miniArtworkGap: CGFloat = 10
    /// `private` trong `PlayerCard`: `expandedCornerRadius`.
    static let expandedCorner: CGFloat = 38
    /// `private` trong `PlayerCard`: `artworkHeightFraction`.
    static let artworkHeightFraction: CGFloat = 0.59
    /// `private` trong `PlayerCard`: `contentBudget` và `contentInset`.
    static let contentBudget: CGFloat = 440
    static let contentInset: CGFloat = 40

    /// `MiniPlayerChrome`: 32pt là sàn của nó, và nó có ghi rõ vì sao.
    static let miniButton: CGFloat = 32
    static let miniButtonGap: CGFloat = 10
    static let miniTrailingInset: CGFloat = 16

    /// `NowPlayingContent`: `transportGlyphFrame` và khoảng cách hàng.
    static let transportGlyph: CGFloat = 44
    static let transportGap: CGFloat = 48
    static let contentStackSpacing: CGFloat = 24

    static let dismissFraction: CGFloat = 0.30
    static let dismissVelocity: CGFloat = 800

    /// `.smooth` — preset có sẵn của SwiftUI từ iOS 17, chỉ kéo dài hơn một
    /// chút.
    ///
    /// **Không cần tự chỉnh lò xo cho việc này.** SwiftUI có sẵn ba preset, và
    /// đây là số thật đọc từ SDK:
    ///
    ///                  duration   bounce   damping ratio   settling
    ///     .smooth          0.50     0.00            1.00       0.80
    ///     .snappy          0.50     0.15            0.85       0.88
    ///     .bouncy          0.50     0.30            0.70       1.05
    ///
    /// `.smooth` là **giảm chấn tới hạn**: damping ratio đúng 1.0, tức về đích
    /// nhanh nhất có thể mà không vọt lố một chút nào. Đó chính là "hãm phanh,
    /// không nảy".
    ///
    /// Bản đầu của file này quy `response: 0.5, dampingFraction: 0.82` ra
    /// `stiffness: 157.9, damping: 20.6` rồi tự đưa cho `interpolatingSpring`.
    /// Toán không sai nhưng kết quả đọc ra là **tuyến tính**, và con số cho
    /// biết vì sao:
    ///
    ///                                    50%     90%     99%   quãng đường
    ///                                                          trong ⅓ thời
    ///                                                          gian cuối
    ///     stiffness 157.9 / damping 20.6   0.121   0.244   0.329    13.9%
    ///     app thật: 0.52 / bounce 0.12     0.130   0.275   0.402     9.9%
    ///     .smooth(duration: 0.55)          0.143   0.315   0.502     7.0%
    ///
    /// Cảm giác hãm nằm ở **cái đuôi**: một quãng thời gian nhìn thấy được,
    /// trong đó vật gần như không đi thêm bao nhiêu. Đường cũ xong trong 0.33s
    /// với đuôi dài 0.11s — quá ngắn để mắt đọc ra, nên thành "chạy rồi dừng".
    /// Và damping 0.82 (bounce ~0.18) là *có* vọt lố, mà vọt lố đọc ra là nảy
    /// chứ không phải hãm — hai cảm giác ngược nhau.
    ///
    /// Đóng nhanh hơn mở, theo đúng quy ước `BottomBarStyle` của app: mở là
    /// "cho tôi xem cái này", chờ được; đóng là "bỏ đi", chờ là bực.
    ///
    /// Muốn nảy nhẹ như player thật thì đổi sang
    /// `.snappy(duration: 0.52, extraBounce: -0.03)`; muốn phanh gắt hơn nữa
    /// thì tăng `duration`. Không có núm thứ ba.
    ///
    /// 0.55 → 0.46 và 0.45 → 0.38 sau khi cầm thử. `duration` chỉ co giãn
    /// **thang thời gian**; damping ratio vẫn 1.0 nên tỉ lệ quãng đường dồn
    /// vào cái đuôi không đổi — nhanh hơn mà vẫn phanh, không quay lại thành
    /// "chạy rồi dừng" như bộ số tự chế ban đầu.
    static let expandSpring = Spring.smooth(duration: 0.46)
    static let collapseSpring = Spring.smooth(duration: 0.38)

    /// Thẻ có đổ bóng hay không — và đây là công tắc đáng giá nhất trong file.
    ///
    /// `PlayerCard` thật kết thúc chuỗi modifier bằng `.floatingBarShadow()`,
    /// nên chép đúng UI thật là phải có nó. Nhưng bản thử **trước** khi khớp UI
    /// thì không có bóng, và nó được nhận xét là mượt.
    ///
    /// Đó là một phép A/B có sẵn mà không phải đụng vào app thật: bật lên thấy
    /// nặng hơn, tắt đi thấy nhẹ hơn, thì audit đúng — một view vừa đổi kích
    /// thước mỗi frame vừa mang bóng buộc bộ dựng hình raster nó ra buffer
    /// ngoài màn hình để lấy hình bao, mỗi frame, và ở cuối hành trình cái
    /// buffer đó to bằng màn hình. Không thấy khác gì thì giả thuyết đó sai và
    /// chỗ tốn nằm nơi khác.
    ///
    /// Đổi đúng một chữ ở đây rồi ⌘R, không cần sửa gì thêm.
    static let cardShadow = true
}

// MARK: - Thước đo cú khựng

/// Ghi lại khoảng cách thời gian dài nhất giữa hai khung hình của một cú vuốt,
/// và cú vuốt đó đang ở `progress` nào lúc ấy.
///
/// Là **class** chứ không phải `@State` giá trị, và đó là điểm mấu chốt: sửa
/// thuộc tính của một kiểu tham chiếu không làm SwiftUI dựng lại view. Nếu
/// dùng `@State` thì mỗi khung hình của cú vuốt lại thêm một lần invalidate,
/// và thước đo sẽ tự tạo ra đúng cái nó định đo.
///
/// `CACurrentMediaTime()` chứ không phải `Date()`: đồng hồ đơn điệu, không
/// nhảy khi hệ thống chỉnh giờ, và rẻ hơn.
private final class DragProbe {
    var lastFrame: CFTimeInterval = 0
    var firstFrame: CFTimeInterval = 0
    var worstGap: CFTimeInterval = 0
    var worstAt: CGFloat = 0
    var frames = 0

    func reset() {
        lastFrame = 0
        firstFrame = 0
        worstGap = 0
        worstAt = 0
        frames = 0
    }

    func sample(progress: CGFloat) {
        let now = CACurrentMediaTime()
        defer { lastFrame = now; frames += 1 }
        if firstFrame == 0 { firstFrame = now }
        guard lastFrame > 0 else { return }
        let gap = now - lastFrame
        if gap > worstGap {
            worstGap = gap
            worstAt = progress
        }
    }

    /// Nhịp khung hình trung bình của chính lần đo này.
    ///
    /// Cần nó để đọc được `worstGap`: 17ms là **bình thường** trên màn 60Hz và
    /// là **một frame bị rớt** trên màn 120Hz. Không có mẫu số này thì con số
    /// tệ nhất không nói lên điều gì — đúng cái bẫy lần đo đầu tiên đã sập.
    var averageGap: CFTimeInterval {
        guard frames > 1, lastFrame > firstFrame else { return 0 }
        return (lastFrame - firstFrame) / Double(frames - 1)
    }

    /// Có thật là khựng không, hay chỉ là nhịp bình thường: tệ nhất phải vượt
    /// 1.6 lần nhịp trung bình mới đáng gọi là rớt frame.
    ///
    /// So với **cả** nhịp trung bình lẫn nhịp màn hình, lấy cái lớn hơn. Pha
    /// kéo tay gọi `onChanged` dày hơn nhịp màn hình nhiều — lần đo thật cho
    /// trung bình 4ms — nên nếu chỉ so với trung bình thì một khoảng 16ms hoàn
    /// toàn bình thường (đúng một khung 60Hz) bị gán nhãn VẤP kèm một cái tên
    /// thủ phạm bịa ra. Đó là lỗi của bản báo cáo đầu tiên.
    var isRealStall: Bool {
        averageGap > 0 && worstGap > max(averageGap, Self.displayInterval) * 1.6
    }

    /// Nhịp mà màn hình **có thể** chạy: 16.7ms trên 60Hz, 8.3ms trên ProMotion.
    ///
    /// Không có mẫu số này thì có một kiểu hỏng lọt lưới hoàn toàn: nếu *mọi*
    /// khung hình đều chậm gấp đôi, tệ nhất chia trung bình vẫn ≈ 1 và bản báo
    /// cáo sẽ nói "sạch" trong khi máy đang rớt một nửa số khung. So với chính
    /// nó thì cái gì cũng bình thường.
    static var displayInterval: CFTimeInterval {
        let fps = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.maximumFramesPerSecond }
            .max() ?? 60
        return 1.0 / Double(max(fps, 1))
    }

    /// Chậm **đều**, khác hẳn với khựng một cú: đây là hụt hơi, không phải vấp.
    var isUniformlySlow: Bool {
        averageGap > Self.displayInterval * 1.35
    }

    /// Ngưỡng nào của bản thử nằm gần chỗ khựng nhất. Đây là mục đích của cả
    /// cái thước: mỗi ngưỡng ở một giá trị khác nhau, nên chỗ khựng chỉ đích
    /// danh được thủ phạm.
    /// Một dòng đọc được trên máy thật, kèm mẫu số để con số tệ nhất có nghĩa.
    func summary(phase: String) -> String? {
        guard frames > 3 else { return nil }
        let worst = worstGap * 1000
        let avg = averageGap * 1000
        let target = Self.displayInterval * 1000

        if isUniformlySlow {
            return String(format: "%@: CHẬM ĐỀU %.0fms (đáng lẽ %.0f) · %d frame",
                          phase, avg, target, frames)
        }
        if isRealStall {
            return String(format: "%@: VẤP %.0fms @ p=%.2f (nhịp %.0f) · %@",
                          phase, worst, worstAt, avg, suspect)
        }
        return String(format: "%@: sạch · %.0fms/%.0f · %d frame",
                      phase, avg, target, frames)
    }

    var suspect: String {
        switch worstAt {
        case 0.95...: return "hit-test fullChrome (0.98)"
        case 0.55..<0.95: return "group opacity fullChrome (1.0 → 0.6)"
        case 0.45..<0.55: return "status bar hiện lại (0.5)"
        case 0.36..<0.45: return "material thanh tab bật (0.4)"
        case 0.28..<0.36: return "material trong thẻ được CHÈN (0.34)"
        case 0.15..<0.28: return "material nút đóng (0.2)"
        default: return "không trùng ngưỡng nào"
        }
    }
}

/// Đọc giá trị **đang được nội suy** của một animation, từng khung hình một.
///
/// Trong lúc `withAnimation` chạy, `progress` trong `@State` đã nhảy thẳng tới
/// đích ngay lập tức — chỉ bộ dựng hình mới biết các giá trị ở giữa. Cách duy
/// nhất để nhìn thấy chúng là tuân theo `Animatable`: SwiftUI gán
/// `animatableData` một lần mỗi khung hình của animation, với giá trị đã nội
/// suy. Ghi lại thời điểm mỗi lần gán là có đúng thứ mà cú vuốt không đo được.
///
/// Ghi vào một `class` nên không có invalidate nào bị kích hoạt; nếu không,
/// thước đo sẽ tự sinh ra cái nó định đo.
private struct AnimationProbe: ViewModifier, Animatable {
    var value: CGFloat
    let probe: DragProbe

    var animatableData: CGFloat {
        get { value }
        set {
            value = newValue
            probe.sample(progress: newValue)
        }
    }

    func body(content: Content) -> some View { content }
}

// MARK: - Hình học của thẻ, ở một chỗ

/// Mọi con số động, tính một lần cho mỗi frame từ đúng một `progress`.
///
/// Là struct chứ không phải một mớ computed property rải trong view, vì hai lý
/// do: đọc được toàn bộ phép nội suy trong một màn hình, và hỏi được "ở
/// progress 0.5 thì ảnh bìa ở đâu" mà không cần dựng view nào.
private struct PlayerGeometry {
    let progress: CGFloat
    let screen: CGSize
    let safeTop: CGFloat

    // MARK: Thẻ

    /// Thu gọn: viên thuốc nổi, thụt vào `sideMargin` mỗi bên. Mở: cả màn hình.
    var width: CGFloat {
        lerp(screen.width - BottomBarMetrics.sideMargin * 2, screen.width, progress)
    }

    var height: CGFloat {
        lerp(DemoMetrics.pillHeight, screen.height, progress)
    }

    /// Đáy viên thuốc nằm trên thanh tab đúng `playerBottomOffset` — cùng con
    /// số `RootView` dùng cho player thật.
    var top: CGFloat {
        let collapsedTop = screen.height - BottomBarMetrics.playerBottomOffset
            - DemoMetrics.pillHeight
        return lerp(collapsedTop, 0, progress)
    }

    var centreX: CGFloat { screen.width / 2 }

    /// 27 → 38. Đáy vuông khi mở hết, như thẻ thật: nó tì vào cạnh dưới màn
    /// hình nên góc dưới không có gì để bo.
    var cornerRadius: CGFloat {
        lerp(DemoMetrics.pillCorner, DemoMetrics.expandedCorner, progress)
    }

    var bottomCornerRadius: CGFloat {
        DemoMetrics.pillCorner * (1 - progress)
    }

    // MARK: Ảnh bìa — full-bleed như app thật, không phải ô vuông giữa màn

    /// Chiều cao ảnh bìa khi mở. `PlayerCard.artworkHeight(fullSize:)` là
    /// `private`; công thức giống hệt, kể cả cái chặn 120pt cho landscape.
    private var expandedArtworkHeight: CGFloat {
        min(screen.height * DemoMetrics.artworkHeightFraction,
            max(screen.height - 120, 0))
    }

    var artworkWidth: CGFloat { lerp(DemoMetrics.miniArtwork, screen.width, progress) }
    var artworkHeight: CGFloat {
        lerp(DemoMetrics.miniArtwork, expandedArtworkHeight, progress)
    }

    /// Bo góc ảnh bìa: 12% bề rộng lúc là thumbnail, vuông khi full-bleed —
    /// đúng biểu thức `PlayerCard` dùng.
    var artworkCorner: CGFloat { artworkWidth * 0.12 * (1 - progress) }

    /// Tâm ảnh bìa, trong toạ độ **của thẻ** (y = 0 là đỉnh thẻ).
    ///
    /// Toạ độ thẻ chứ không phải màn hình, nên khi thẻ tự trượt lên thì ảnh bìa
    /// đi theo miễn phí — không có hai chuyển động phải khớp nhau.
    var artworkCentre: CGPoint {
        let collapsed = CGPoint(
            x: DemoMetrics.miniArtworkInset + DemoMetrics.miniArtwork / 2,
            y: DemoMetrics.pillHeight / 2
        )
        let expanded = CGPoint(x: screen.width / 2, y: expandedArtworkHeight / 2)
        return CGPoint(x: lerp(collapsed.x, expanded.x, progress),
                       y: lerp(collapsed.y, expanded.y, progress))
    }

    /// Ảnh bìa tan dần vào nền ở mép dưới khi mở — chữ nằm đè lên phần đã tan.
    /// Thẻ thật dùng bảy chặng smoothstep để không để lại vệt gấp; ở đây ba
    /// chặng là đủ cho một bản thử.
    var dissolveStrength: CGFloat { ramp(progress, 0.25, 1) }

    // MARK: Lệch pha

    /// Chrome của viên thuốc tắt trong 30% đầu.
    var miniChromeOpacity: CGFloat { 1 - ramp(progress, 0, 0.30) }
    /// Điều khiển đầy đủ chỉ bật trong 40% cuối. 0.60 > 0.30 nên hai lớp không
    /// bao giờ cùng hiện rõ.
    var fullChromeOpacity: CGFloat { ramp(progress, 0.60, 1) }
    var fullChromeOffset: CGFloat { lerp(24, 0, fullChromeOpacity) }

    /// Nội dung bắt đầu ở đâu, đo **từ đáy thẻ** chứ không phải từ ảnh bìa —
    /// cùng lý do `PlayerCard.contentOffset(fullSize:)` làm vậy: đo từ đáy thì
    /// điều khiển nằm cùng một chỗ trên mọi bài và mọi máy.
    var contentTop: CGFloat {
        screen.height - (DemoMetrics.contentBudget - DemoMetrics.contentInset)
    }

    // MARK: Nền phía sau

    var backdropScale: CGFloat { lerp(1, 0.92, progress) }
    // Không còn `backdropCorner`. Xem `backdrop(geo:insets:)`: bo góc nền là
    // một mask toàn màn hình dựng lại mỗi frame, và app thật đã gỡ nó khỏi
    // player vì chính nó làm cú thu nhỏ sần. Xoá hẳn chứ không để đấy chờ ai
    // đó nối lại.
    var dimOpacity: CGFloat { 0.28 * progress }
}

// MARK: - Root

struct PlayerMorphDemoView: View {

    /// 0 = viên thuốc, 1 = toàn màn hình. Nguồn sự thật duy nhất cho chuyển
    /// động; không có `isExpanded` song song để hai thứ lệch nhau.
    @State private var progress: CGFloat = 0
    /// `progress` tại thời điểm ngón tay chạm xuống, để cú kéo cộng dồn lên nó
    /// thay vì luôn bắt đầu từ 0.
    @State private var dragStart: CGFloat = 0
    @State private var isDragging = false

    @State private var isPlaying = true
    @State private var scrub: Double = 0.32
    @State private var volume: Double = 0.6
    /// Đếm số lần thẻ chốt vào một đầu. Chỉ để `.sensoryFeedback` có cái mà
    /// bám vào — xem `setExpanded`.
    @State private var snapCount = 0
    /// Lớp làm nóng đã được vẽ xong chưa — xem `warmUpLayer`.
    @State private var warmedUp = false

    /// Thước đo — xem `DragProbe`. Chỉ ghi trong lúc ngón tay còn trên màn
    /// hình; báo cáo hiện ra sau khi nhấc tay.
    @State private var probe = DragProbe()
    /// Hai pha, hai báo cáo. Lần đo đầu chỉ có pha kéo, và nó sạch — nên cái
    /// cần nhìn là pha còn lại.
    @State private var dragReport: String?
    /// Hai ô riêng cho hai chiều. Một ô chung thì báo cáo `bung` luôn bị cú
    /// `thu` ngay sau đó ghi đè — mà lần bung **đầu tiên** mới là lần đắt
    /// nhất, và nó không lặp lại để đo lần hai.
    @State private var expandReport: String?
    @State private var collapseReport: String?

    private let song = DemoSong.mock
    /// Đóng màn demo. `nil` trong preview, nơi không có gì để đóng về.
    private let onClose: (() -> Void)?

    /// Mở sẵn ở một điểm bất kỳ của hành trình. Mặc định 0.
    ///
    /// Có mặt vì xem một trạng thái *giữa chừng* là cách duy nhất nhìn được
    /// phần khó nhất: ở 0.5 thì chrome viên thuốc phải tắt hẳn, chrome đầy đủ
    /// chưa được hiện, nền đã thu và ảnh bìa đang trên đường bay.
    init(initialProgress: CGFloat = 0, onClose: (() -> Void)? = nil) {
        _progress = State(initialValue: min(max(initialProgress, 0), 1))
        self.onClose = onClose
    }

    var body: some View {
        GeometryReader { proxy in
            // Reader này **không** `ignoresSafeArea`: chỉ reader còn tôn trọng
            // safe area mới trả về `safeAreaInsets` thật. Thẻ bên trong tự tràn
            // ra mép, nhưng số dùng để xếp chỗ phải đúng — nếu không grabber
            // chui vào sau Dynamic Island.
            let insets = proxy.safeAreaInsets
            let screen = CGSize(width: proxy.size.width,
                                height: proxy.size.height + insets.top + insets.bottom)
            let geo = PlayerGeometry(progress: progress, screen: screen, safeTop: insets.top)

            ZStack(alignment: .topLeading) {
                Color(.systemBackground).ignoresSafeArea()

                // Làm nóng, và nó nằm **dưới cùng** nên bị thư viện đục che kín.
                //
                // Đo được: cú bung *đầu tiên* vấp 56ms ngay ở khung mở màn,
                // những lần sau sạch. Chữ ký của chi phí một-lần: lần đầu chrome
                // mở rộng được vẽ, máy phải rasterize glyph cho các cỡ chữ chưa
                // dùng ở đâu khác (`.title3.semibold`, `.caption2` chữ số đều
                // nhau), rasterize ký hiệu ở cỡ mới, và dựng hai `Slider`.
                //
                // Vẽ nó một lần ở chỗ không ai thấy thì hoá đơn ấy được trả lúc
                // màn hình vừa mở, nơi 56ms chìm vào cú present — thay vì giữa
                // một animation đang chạy.
                //
                // Trên màn hình chứ không phải `offset` ra ngoài: một lớp nằm
                // ngoài khung nhìn có thể bị bỏ qua hoàn toàn, và thế thì chẳng
                // có gì được làm nóng. Opacity 0.02 để nó vẫn buộc phải vẽ.
                if !warmedUp {
                    warmUpLayer
                }

                backdrop(geo: geo, insets: insets)

                Color.black
                    .opacity(geo.dimOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                tabBar(geo: geo)
                card(geo: geo)
                closeButton(insets: insets)
                probeReadout(insets: insets)
            }
            .ignoresSafeArea()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: snapCount)
        .statusBarHidden(progress > 0.5)
        .task {
            // Nửa giây là quá đủ cho một lượt vẽ; giữ lâu hơn chỉ tốn công vô ích.
            try? await Task.sleep(for: .milliseconds(500))
            warmedUp = true
        }
    }

    // MARK: Nền: thư viện

    private func backdrop(geo: PlayerGeometry, insets: EdgeInsets) -> some View {
        // `.equatable()`: `DemoLibraryList` không đọc `progress`, và vì nó
        // Equatable với dữ liệu không đổi, SwiftUI bỏ qua luôn việc chạy lại
        // `body` của nó ở mỗi frame chuyển cảnh. Chỉ các modifier biến đổi bên
        // ngoài chạy lại, và những cái đó Core Animation lo.
        DemoLibraryList(topInset: insets.top)
            .equatable()
            // **Không bo góc nền, và đó là lý do cú vuốt mượt.**
            //
            // Ở đây từng có `.clipShape(RoundedRectangle(cornerRadius:))` với
            // bán kính chạy theo `progress` — chép cái vẻ "chồng thẻ" của
            // sheet. Nó là một **mask trên toàn màn hình, dựng lại mỗi frame**,
            // và `BottomBarStyle` của app đã gỡ đúng thứ đó ra khỏi player
            // thật với ghi chú "the recede was visibly rough because of it".
            //
            // `scaleEffect` là một phép biến đổi: render server làm một mình,
            // không tốn gì. Bo góc là vẽ lại. Em chép hình dáng của app thật
            // mà quên chép bài học của nó.
            //
            // Muốn góc bo trở lại thì theo đúng lời khuyên ở đó: bo một tấm
            // nền **tĩnh** phía sau, đừng mask chính nội dung.
            .scaleEffect(geo.backdropScale)
    }

    private func closeButton(insets: EdgeInsets) -> some View {
        Group {
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(.regularMaterial, in: Circle())
                }
                .padding(.trailing, BottomBarMetrics.sideMargin)
                .padding(.top, insets.top + 4)
                .frame(maxWidth: .infinity, alignment: .trailing)
                // Chỉ hiện khi đang thu gọn: mở hết thì cách thoát *là* cú vuốt
                // xuống, và một nút X nổi trên đó vừa thừa vừa che thứ cần xem.
                .opacity(1 - ramp(progress, 0, 0.2))
                .allowsHitTesting(progress < 0.02)
            }
        }
    }

    /// Kết quả đo, hiện ngay trên màn hình.
    ///
    /// `./device.sh` không gắn debugger nên không có console để `print` vào —
    /// muốn đọc số trên máy thật thì số phải nằm trên màn hình.
    ///
    /// Chỉ hiện khi đã thu gọn, và nằm dưới cùng của `ZStack` để không lọt vào
    /// đường bay của thẻ.
    private func probeReadout(insets: EdgeInsets) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let dragReport { line(dragReport) }
            if let expandReport { line(expandReport) }
            if let collapseReport { line(collapseReport) }
        }
        .padding(.leading, BottomBarMetrics.sideMargin)
        .padding(.top, insets.top + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(1 - ramp(progress, 0, 0.2))
        .allowsHitTesting(false)
    }

    private func line(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.black.opacity(0.78), in: Capsule())
    }

    // MARK: Thanh tab nổi — hình dáng của `FloatingTabBar`

    private func tabBar(geo: PlayerGeometry) -> some View {
        HStack(spacing: BottomBarMetrics.tabBarSearchGap) {
            HStack(spacing: 0) {
                tabItem("music.note.list", "Bài hát", current: true)
                tabItem("square.stack", "Album", current: false)
                tabItem("music.mic", "Nghệ sĩ", current: false)
                tabItem("person.crop.circle", "Tài khoản", current: false)
            }
            .frame(height: BottomBarMetrics.tabBarHeight)
            .background(.regularMaterial, in: Capsule())
            .clipShape(Capsule())
            .floatingBarShadow()

            // Nút tìm kiếm là một vòng tròn tách rời, không phải tab thứ năm —
            // đúng như `FloatingTabBar` dựng nó.
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: BottomBarMetrics.tabBarHeight,
                       height: BottomBarMetrics.tabBarHeight)
                .background(.regularMaterial, in: Circle())
                .clipShape(Circle())
                .floatingBarShadow()
        }
        .padding(.horizontal, BottomBarMetrics.sideMargin)
        .frame(width: geo.screen.width, alignment: .center)
        .position(x: geo.screen.width / 2,
                  y: geo.screen.height - BottomBarMetrics.screenBottomInset
                      - BottomBarMetrics.tabBarHeight / 2)
        // Lùi ra khi player mở: nó không còn việc gì ở đó.
        .opacity(1 - ramp(geo.progress, 0, 0.4))
    }

    private func tabItem(_ glyph: String, _ label: String, current: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: glyph).font(.system(size: 18))
            Text(verbatim: label).font(.caption2)
        }
        .foregroundStyle(current ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .frame(maxWidth: .infinity)
    }

    // MARK: Thẻ — một view, hai trạng thái

    private func card(geo: PlayerGeometry) -> some View {
        ZStack(alignment: .topLeading) {
            cardBackground(geo: geo)
            miniChrome(geo: geo)
            fullChrome(geo: geo)
            grabber(geo: geo)
            // Ảnh bìa trên cùng: nó là thứ đi xuyên suốt hai trạng thái, không
            // lớp chrome nào được cắt ngang đường bay của nó.
            artwork(geo: geo)
        }
        .frame(width: geo.width, height: geo.height, alignment: .top)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: geo.cornerRadius,
                bottomLeadingRadius: geo.bottomCornerRadius,
                bottomTrailingRadius: geo.bottomCornerRadius,
                topTrailingRadius: geo.cornerRadius,
                style: .continuous
            )
        )
        // Xem `DemoMetrics.cardShadow`: giữ hay bỏ dòng này là một phép A/B về
        // hiệu năng, chạy được mà không đụng tới player thật.
        .modifier(OptionalFloatingShadow(enabled: DemoMetrics.cardShadow))
        // Đọc từng khung hình của lò xo — xem `AnimationProbe`. Trong lúc kéo
        // thì `progress` đổi ngoài animation nên modifier này im lặng; đúng
        // phân công cần có, vì pha kéo đã có thước riêng.
        .modifier(AnimationProbe(value: progress, probe: probe))
        .offset(x: (geo.screen.width - geo.width) / 2, y: geo.top)
        .onTapGesture {
            if progress < 0.5 { setExpanded(true, velocity: 0) }
        }
        .gesture(dragGesture(screenHeight: geo.screen.height))
    }

    /// Vật liệu khi là viên thuốc, gradient màu bìa khi đã mở.
    private func cardBackground(geo: PlayerGeometry) -> some View {
        ZStack {
            // **Gỡ hẳn, không phải làm mờ đi.** Một vật liệu là lớp làm mờ
            // sống, tính lại mỗi frame, và nó tốn y hệt nhau ở opacity 0.01
            // lẫn ở 1. Bản trước để nó tồn tại suốt hành trình, nghĩa là ở đầu
            // cú vuốt thu nhỏ — đúng lúc thẻ đang to bằng cả màn hình — máy
            // đang làm mờ nguyên màn hình mỗi frame để vẽ ra một thứ nằm dưới
            // một lớp gradient đã đục kín. `PlayerCard` thật cắt nó ở 1/3 và
            // ghi rõ vì sao; đây là lần thứ hai bài học đó phải được chép lại.
            //
            // 0.34 khớp với chỗ gradient bên dưới chạm opacity 1, nên tại
            // khoảnh khắc lớp này biến mất nó vốn đã bị che kín hoàn toàn.
            if geo.progress < 0.34 {
                Rectangle()
                    .fill(.regularMaterial)
                    .opacity(1 - geo.progress)
            }

            LinearGradient(
                colors: [song.colours[0], song.colours[1], .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(ramp(geo.progress, 0, 0.34))
        }
    }

    private func grabber(geo: PlayerGeometry) -> some View {
        Capsule()
            .fill(.white.opacity(0.5))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.top, geo.safeTop + 8)
            .opacity(geo.fullChromeOpacity)
    }

    // MARK: Chrome của viên thuốc — hàng của `MiniPlayerChrome`

    private func miniChrome(geo: PlayerGeometry) -> some View {
        HStack(spacing: DemoMetrics.miniButtonGap) {
            // Chỗ trống đúng bằng ảnh bìa: ảnh bìa được `.position` đặt chỗ nên
            // nó không tham gia layout của hàng này.
            Color.clear
                .frame(width: DemoMetrics.miniArtworkInset + DemoMetrics.miniArtwork
                       + DemoMetrics.miniArtworkGap - DemoMetrics.miniButtonGap)

            VStack(alignment: .leading, spacing: 1) {
                Text(song.title).font(.footnote).lineLimit(1)
                Text(song.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.title3)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: DemoMetrics.miniButton, height: DemoMetrics.miniButton)
                .contentShape(Rectangle())
                .onTapGesture { isPlaying.toggle() }

            Image(systemName: "forward.fill")
                .font(.body)
                .frame(width: DemoMetrics.miniButton, height: DemoMetrics.miniButton)
        }
        .padding(.trailing, DemoMetrics.miniTrailingInset)
        .frame(height: DemoMetrics.pillHeight)
        .opacity(geo.miniChromeOpacity)
        // Ngừng nhận chạm ngay khi bắt đầu mờ: hai nút vô hình vẫn ăn cú chạm
        // là lỗi kinh điển của kiểu chồng lớp này.
        .allowsHitTesting(geo.progress < 0.02)
    }

    /// Đúng những thứ đắt tiền của chrome mở rộng, vẽ một lần rồi bỏ.
    ///
    /// Không tái dùng `fullChrome` vì nó bị `fullChromeOpacity` khoá — ở
    /// `progress` 0 thì opacity bằng 0, và một lớp trong suốt hoàn toàn có thể
    /// bị bỏ qua, tức chẳng làm nóng được gì. Ở đây liệt kê lại đúng các cỡ chữ,
    /// cỡ ký hiệu và hai `Slider` cần được rasterize.
    private var warmUpLayer: some View {
        VStack(spacing: DemoMetrics.contentStackSpacing) {
            Text(song.title).font(.title3.weight(.semibold))
            Text(verbatim: "\(song.artist) · \(song.album)").font(.subheadline)
            Text(verbatim: "0:00").font(.caption2.monospacedDigit())
            Slider(value: .constant(0.3))
            HStack(spacing: DemoMetrics.transportGap) {
                Image(systemName: "backward.fill").font(.title2)
                Image(systemName: "pause.fill").font(.system(size: 38))
                Image(systemName: "play.fill").font(.system(size: 38))
                Image(systemName: "forward.fill").font(.title2)
            }
            HStack {
                Image(systemName: "speaker.fill")
                Slider(value: .constant(0.6))
                Image(systemName: "speaker.wave.3.fill")
            }
            .font(.caption)
        }
        .padding(.horizontal, 24)
        .opacity(0.02)
        .allowsHitTesting(false)
    }

    // MARK: Chrome đầy đủ — hàng của `NowPlayingContent`

    private func fullChrome(geo: PlayerGeometry) -> some View {
        VStack(spacing: DemoMetrics.contentStackSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title).font(.title3.weight(.semibold)).lineLimit(1)
                Text(verbatim: "\(song.artist) · \(song.album)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 4) {
                Slider(value: $scrub).tint(.white.opacity(0.9))
                HStack {
                    Text(verbatim: "1:12")
                    Spacer()
                    Text(verbatim: "-2:31")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
            }

            HStack(spacing: DemoMetrics.transportGap) {
                Image(systemName: "backward.fill")
                    .font(.title2)
                    .frame(width: DemoMetrics.transportGlyph, height: DemoMetrics.transportGlyph)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 38))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: DemoMetrics.transportGlyph, height: DemoMetrics.transportGlyph)
                    .contentShape(Rectangle())
                    .onTapGesture { isPlaying.toggle() }
                Image(systemName: "forward.fill")
                    .font(.title2)
                    .frame(width: DemoMetrics.transportGlyph, height: DemoMetrics.transportGlyph)
            }

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                Slider(value: $volume).tint(.white.opacity(0.9))
                Image(systemName: "speaker.wave.3.fill")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.55))
        }
        // Thẻ mở buộc chữ trắng, như `PlayerChromeScheme` làm với player thật:
        // nền là ảnh bìa, không phải màu do view này chọn.
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .frame(width: geo.width)
        .padding(.top, geo.contentTop)
        // **`compositingGroup` trước `opacity`, và đây là giả thuyết khớp nhất
        // với triệu chứng "khựng ở đầu cú thu nhỏ".**
        //
        // Khối này có nhiều con có thể chồng lên nhau, nên khi opacity là số
        // lẻ, SwiftUI buộc phải gộp cả cây con vào một buffer ngoài màn hình
        // rồi mới pha mờ — pha mờ từng lá một sẽ cho kết quả khác ở chỗ chúng
        // giao nhau. Vấn đề nằm ở *thời điểm* buffer ấy được cấp:
        //
        //   - Đứng yên ở trạng thái mở, opacity đúng **bằng 1.0** → không cần
        //     gộp, không có buffer nào tồn tại.
        //   - Ngay khung hình đầu tiên của cú thu nhỏ, nó thành số lẻ → buffer
        //     cỡ vài trăm điểm được cấp và vẽ lần đầu, đúng lúc ngón tay vừa
        //     bắt đầu di chuyển.
        //
        // Và nó bất đối xứng đúng chiều anh thấy: lúc bung, opacity chỉ rời
        // khỏi 0 ở `progress` 0.6 — giữa đoạn chạy nhanh nhất, nơi một khung
        // hình rơi mất chìm đi; lúc thu, nó rời khỏi 1.0 ở ngay khung đầu.
        //
        // `compositingGroup()` khai báo việc gộp một cách tường minh và **ổn
        // định**: buffer tồn tại từ lúc thẻ còn nằm yên, nên cú thu nhỏ chỉ
        // đổi alpha của một lớp đã có sẵn — việc mà bộ dựng hình làm không mất
        // gì. Trả hoá đơn lúc đứng yên thay vì giữa cử chỉ.
        .compositingGroup()
        .opacity(geo.fullChromeOpacity)
        .offset(y: geo.fullChromeOffset)
        .allowsHitTesting(geo.progress > 0.98)
    }

    // MARK: Ảnh bìa — một view duy nhất, tồn tại suốt

    private func artwork(geo: PlayerGeometry) -> some View {
        LinearGradient(colors: song.colours, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                Image(systemName: song.glyph)
                    .font(.system(size: lerp(16, 76, geo.progress)))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: geo.artworkWidth, height: geo.artworkHeight)
            .clipShape(RoundedRectangle(cornerRadius: geo.artworkCorner, style: .continuous))
            // Tan vào nền ở mép dưới khi mở, để chữ có chỗ đứng. Là `.mask`
            // chứ không phải overlay vì nền bên dưới là gradient hai chiều,
            // không có màu phẳng nào để vẽ đè lên.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: lerp(1, 0.62, geo.dissolveStrength)),
                        .init(color: .white.opacity(1 - geo.dissolveStrength),
                              location: lerp(1, 0.86, geo.dissolveStrength)),
                        .init(color: .white.opacity(1 - geo.dissolveStrength), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            .position(geo.artworkCentre)
            .allowsHitTesting(false)
    }

    // MARK: Cử chỉ

    /// Ngón tay lái thẳng `progress`, không qua animation nào.
    ///
    /// `progress = dragStart - translation / screenHeight`: kéo xuống là
    /// `translation` dương nên `progress` giảm. Chia cho chiều cao màn hình để
    /// "kéo hết màn hình" đúng bằng "đi hết hành trình", bất kể máy nào.
    private func dragGesture(screenHeight: CGFloat) -> some Gesture {
        // Ngưỡng và phép trừ ngưỡng đều mượn thẳng của `PlayerCard` — app đã
        // gặp đúng lỗi này và đã giải, kèm test (`DragOffsetTests`). Chép lại
        // số ở đây là tự chuốc lấy phiên bản thứ hai để lệch nhau.
        //
        // Hai nửa của cùng một defect:
        //   - `dragThreshold(progress:)` trả 2 khi thẻ đã mở, 10 khi thu gọn.
        //     Ngưỡng chỉ tồn tại để một cú tap không bị đọc thành drag, mà cái
        //     tap đó lại `guard progress < 0.5` — trả tiền cho sự bảo vệ ấy
        //     lúc nó không thể xảy ra chính là vùng chết đầu mỗi cú vuốt.
        //   - `dragOffset(translationHeight:threshold:)` trừ lại phần ngưỡng.
        //     Thiếu nó thì đúng lúc cử chỉ được nhận, `translation` đã sẵn
        //     mang đủ 8–10pt và thẻ nhảy một phát chừng ấy: 10pt đứng im rồi
        //     10pt nhảy bù, đọc ra là giật.
        let threshold = PlayerCard.dragThreshold(progress: progress)
        return DragGesture(minimumDistance: threshold, coordinateSpace: .global)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStart = progress
                    probe.reset()
                }
                probe.sample(progress: progress)
                let travel = PlayerCard.dragOffset(
                    translationHeight: value.translation.height,
                    threshold: threshold
                )
                let raw = dragStart - travel / screenHeight
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
                // Tính chuỗi ở đây nhưng **chưa** ghi vào `@State`: một lần
                // ghi state kéo theo một lượt dựng lại view, và nó sẽ rơi
                // đúng vào khung hình bàn giao — thước đo tự tạo ra thứ nó
                // định đo. Chuyển giao cho `completion` của lò xo bên dưới.
                let dragLine = probe.summary(phase: "kéo")
                let velocity = value.velocity.height
                // Cùng phép trừ ngưỡng như `onChanged`: quyết định phải dựa
                // trên quãng đường thẻ **đã đi trên màn hình**, không phải
                // quãng đường ngón tay đi. Lệch nhau thì ngưỡng 30% sẽ chốt ở
                // một chỗ khác với chỗ mắt nhìn thấy.
                let travelled = -PlayerCard.dragOffset(
                    translationHeight: value.translation.height,
                    threshold: threshold
                ) / screenHeight

                // Quyết định bằng **cả hai**: đã đi được bao xa, và đang bay
                // nhanh thế nào. Chỉ xét quãng đường thì một cú hất dứt khoát ở
                // 10% màn hình bị bỏ qua; chỉ xét vận tốc thì kéo chậm rồi thả
                // sẽ luôn bật ngược về.
                let open: Bool
                if velocity < -DemoMetrics.dismissVelocity {
                    open = true
                } else if velocity > DemoMetrics.dismissVelocity {
                    open = false
                } else if dragStart > 0.5 {
                    open = -travelled < DemoMetrics.dismissFraction
                } else {
                    open = travelled > DemoMetrics.dismissFraction
                }
                setExpanded(open, velocity: velocity, screenHeight: screenHeight,
                            dragLine: dragLine)
            }
    }

    /// Chạy nốt phần còn lại của hành trình, mang theo quán tính của ngón tay.
    ///
    /// `interpolatingSpring(_ spring:initialVelocity:)` là dạng duy nhất nhận
    /// **cả hai**: một mô tả lò xo theo duration/bounce (thứ tai và mắt cảm
    /// nhận được — xem `DemoMetrics.expandSpring`) và vận tốc ngón tay lúc
    /// buông. Dạng `mass/stiffness/damping` nhận được vận tốc nhưng bắt mình
    /// tự quy đổi, và bản đầu quy ra một đường cong ngắn tới mức mất hẳn cú
    /// phanh.
    ///
    /// `initialVelocity` đi qua `PlayerCard.settleVelocity` thay vì tự quy đổi.
    ///
    /// **Đây là chỗ gây ra cú khựng.** Phép quy đổi có ba bước, em chỉ làm hai:
    ///
    ///   1. Đảo dấu — `velocity.height` dương khi kéo xuống, còn `progress`
    ///      lớn lên khi kéo *lên*. Em có làm.
    ///   2. Điểm/giây → progress/giây, chia cho quãng đường của cả hành trình.
    ///      Em có làm.
    ///   3. **progress/giây → tương đối với quãng đường CÒN LẠI.** Em bỏ mất.
    ///      SwiftUI muốn vận tốc so với đoạn animation còn phải đi, không phải
    ///      so với cả dải.
    ///
    /// Bỏ bước 3 không chỉ sai độ lớn mà **sai dấu**: lúc thu nhỏ, quãng còn
    /// lại là âm (0 − 0.87), nên phép chia thiếu đó lật ngược hướng. Lò xo
    /// nhận một vận tốc chỉ ngược phía nó đang đi — comment của
    /// `settleVelocity` gọi đúng tên hiện tượng: *"reads as the card being
    /// knocked backwards before it recovers"*. Thẻ bị đẩy lùi một nhịp rồi mới
    /// hồi lại, và đó là cú khựng.
    ///
    /// Bung bằng cú chạm có vận tốc 0 nên không dính — đúng tính bất đối xứng
    /// quan sát được: thu thì khựng, bung thì mượt.
    ///
    /// Hàm của app còn kẹp ở `BottomBarStyle.maxSettleVelocity` (18), thứ em
    /// cũng không có: một cú hất thật mạnh không kẹp sẽ vọt lố văng khỏi màn
    /// hình. Nó có test riêng (`SettleVelocityTests`), nên gọi thẳng vẫn tốt
    /// hơn tự viết lại lần thứ hai.
    private func setExpanded(_ expanded: Bool, velocity: CGFloat, screenHeight: CGFloat = 1,
                             dragLine: String? = nil) {
        let initialVelocity = screenHeight > 1
            ? PlayerCard.settleVelocity(
                verticalVelocity: velocity,
                travel: screenHeight,
                from: Double(progress),
                to: expanded ? 1 : 0
              )
            : 0
        let spring = expanded ? DemoMetrics.expandSpring : DemoMetrics.collapseSpring
        // Thước đo lại từ đầu cho pha lò xo, và `completion:` (có từ iOS 17)
        // là chỗ duy nhất biết chắc animation đã dừng.
        probe.reset()
        withAnimation(.interpolatingSpring(spring, initialVelocity: initialVelocity)) {
            progress = expanded ? 1 : 0
        } completion: {
            if let dragLine { dragReport = dragLine }
            let line = probe.summary(phase: expanded ? "bung" : "thu")
            if expanded {
                // Chỉ ghi lần bung **đầu tiên** và giữ nguyên. Những lần sau
                // đều rẻ vì mọi thứ đã nằm trong cache, nên chúng sẽ xoá mất
                // đúng con số cần nhìn.
                if expandReport == nil { expandReport = line }
            } else {
                collapseReport = line
            }
        }
        // Haptic ở thời điểm *quyết định*, không phải khi lò xo dừng: cái tay
        // cảm nhận được là khoảnh khắc thẻ được thả ra.
        //
        // **Chỉ tăng một biến đếm.** Trước đây chỗ này là
        // `UIImpactFeedbackGenerator(style: .light).impactOccurred()` — dựng
        // một generator mới rồi bắn ngay, đồng bộ, ngay trong `onEnded`.
        // Taptic Engine cần thời gian khởi động, và Apple bảo gọi `prepare()`
        // trước chính vì thế; dựng-và-bắn tại chỗ bắt luồng chính đứng chờ nó.
        //
        // Đó là một khung hình chết nằm đúng khe giữa lần `onChanged` cuối và
        // khung đầu tiên của lò xo — vô hình với cả hai thước đo, mà video 30
        // fps thì bắt được: kéo đều 14, rồi 1.02, rồi lò xo 31.
        //
        // `.sensoryFeedback` đẩy việc đó ra khỏi đường đi của cử chỉ, và đó
        // cũng là API mà app thật vẫn dùng — lần thứ năm bản thử đi chệch khỏi
        // thứ `PlayerCard` đã làm đúng.
        snapCount &+= 1
    }
}

/// Áp `.floatingBarShadow()` hoặc không, nhưng **không đổi cấu trúc view** ở
/// hai nhánh.
///
/// Một `if` trần trong `body` sẽ tạo hai kiểu view khác nhau; SwiftUI coi đó
/// là hai danh tính và dựng lại cả cây khi cờ đổi. Ở đây điều đó chỉ xảy ra
/// lúc biên dịch lại nên vô hại — nhưng viết kiểu này để nếu sau có ai nối cờ
/// vào một `@State` thì nó vẫn đúng.
private struct OptionalFloatingShadow: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.floatingBarShadow()
        } else {
            content
        }
    }
}

// MARK: - Thư viện giả

/// `Equatable` một cách có chủ đích, với dữ liệu không đổi, để `.equatable()` ở
/// chỗ gọi cắt hẳn việc chạy lại `body` trong suốt cú chuyển cảnh.
/// Không `private` nữa: bản UIKit dùng lại đúng danh sách này để hai bên thử
/// có cùng một tấm nền. Nội dung giống hệt thì phép so mới nói được điều gì về
/// *động cơ chuyển động*.
struct DemoLibraryList: View, Equatable {
    let topInset: CGFloat

    static func == (lhs: DemoLibraryList, rhs: DemoLibraryList) -> Bool {
        lhs.topInset == rhs.topInset
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(DemoSong.library.enumerated()), id: \.offset) { _, song in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(LinearGradient(colors: song.colours,
                                                 startPoint: .topLeading,
                                                 endPoint: .bottomTrailing))
                            .frame(width: 44, height: 44)
                            .overlay {
                                Image(systemName: song.glyph)
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title).lineLimit(1)
                            Text(song.artist).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                // Chừa chỗ cho viên thuốc và thanh tab nổi, đúng cách các màn
                // thật trong app chừa.
                Color.clear
                    .frame(height: BottomBarMetrics.playerBottomOffset)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .navigationTitle(Text(verbatim: "Bài hát"))
        }
        .padding(.top, topInset)
        .background(Color(.systemBackground))
    }
}

// MARK: - Preview

#Preview("Viên thuốc") { PlayerMorphDemoView() }
#Preview("Giữa chừng") { PlayerMorphDemoView(initialProgress: 0.5) }
#Preview("Mở hết") { PlayerMorphDemoView(initialProgress: 1) }
