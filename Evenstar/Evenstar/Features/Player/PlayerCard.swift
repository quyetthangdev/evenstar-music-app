import SwiftUI

/// The player. One card whose shape is a function of `progress`: 0 is the
/// collapsed bar above the library, 1 is the full screen.
///
/// Mini player and Now Playing are not separate views. They are this card at
/// two ends of one continuum, which is what lets the artwork grow continuously
/// instead of one view replacing another. `matchedGeometryEffect` cannot do
/// this: it interpolates between two discrete states as views appear and
/// disappear, and never tracks a finger.
struct PlayerCard: View {
    let playback: PlaybackService

    /// 0 collapsed on its own row above the tab bar, 1 slotted into the tab
    /// row between the leading circle and the search button. Interpolated
    /// rather than a `Bool` so the card can animate between the two.
    ///
    /// Three things read it and **all three must**: `collapsedSideMargin`,
    /// `collapsedBottomOffset`, and — through that offset — `dragTravel`.
    let minimised: Double

    // No explicit init. The one that stood here defaulted `minimised` to 0 so
    // `RootView` kept compiling while it was out of scope; it now passes a real
    // value, and a default of 0 would mean any future call site silently gets a
    // player that never joins the tab row — no compiler error, no failing test,
    // nothing visible. The synthesized memberwise init requires both arguments.

    /// The collapsed bar's own height. Lists do not read this directly — they
    /// apply `clearsBottomBar()`, which reaches
    /// `BottomBarMetrics.clearanceWithPlayer(bottomSafeAreaInset:)` and adds
    /// everything below the floating pill. Do not duplicate this as a literal.
    ///
    /// `nonisolated` because this type is a `View`, and under
    /// `InferIsolatedConformances` that makes the whole type — including its
    /// static constants — main-actor isolated. A `let CGFloat` has nothing for
    /// an actor to protect, and the isolation is not free: it stops any
    /// nonisolated type from reading the number, which is exactly what the
    /// paragraph above forbids solving by writing `54` again. `BottomBarMetrics`
    /// hands out its own constants the same way, from a plain nonisolated enum.
    nonisolated static let collapsedHeight: CGFloat = 54

    /// How far the collapsed pill is inset from each side of the safe area.
    ///
    /// Reads the bar's own margin rather than restating it. The pill and the
    /// tab bar are two floating surfaces one above the other, and their side
    /// edges have to line up; as two separate literals they lined up only for
    /// as long as nobody changed one of them.
    private static let pillSideMargin = BottomBarMetrics.sideMargin
    /// A true pill: half the collapsed height, so the caps are semicircles.
    private static let collapsedCornerRadius: CGFloat = collapsedHeight / 2

    private static let collapsedArtwork: CGFloat = 36

    /// Viên pill co bấy nhiêu khi đã thu hẳn, cho khớp với hai viên tròn hai bên.
    ///
    /// 0.90 chứ không 0.86 như `BottomBarStyle.collapsedChromeScale`: viên pill
    /// rộng gấp bốn lần viên tròn, và cùng một tỉ lệ phần trăm trên một vật dài
    /// hơn thì đọc ra là co nhiều hơn hẳn. Hai con số khác nhau để hai vật
    /// **trông như** co bằng nhau.
    private static let pillMinimisedScale: CGFloat = 0.90

    /// Lề của viên pill nới vào bấy nhiêu khi thu, để bù khe hở mà chính cú co
    /// vừa đẻ ra.
    ///
    /// Cùng bài toán với `BottomBarStyle.collapsedChromeInset` ở thanh bar, chỉ
    /// ngược dấu: ở đó hai viên tròn neo mép ngoài nên co làm khe rộng ra, và ta
    /// kéo chúng vào. Ở đây viên pill co quanh tâm nó, nên **cả hai** mép lùi
    /// vào và cả hai khe rộng ra. Nới lề cho khung rộng thêm trước khi co thì
    /// hai mép trở lại gần hai viên tròn.
    private static let pillMinimisedRelief: CGFloat = 10
    /// How far the collapsed artwork sits in from the pill's leading edge.
    ///
    /// Larger than it looks like it needs to be, because the pill's leading
    /// cap is a semicircle and the visible gap is therefore not uniform: at
    /// mid-height the pill's edge is at x = 0, but level with the artwork's
    /// top and bottom edges the curve has already come in — at this height, to
    /// x ≈ 6.9. The eye judges that tightest point, not the generous gap in
    /// the middle, so the inset has to be set against it.
    ///
    /// At 18 the tightest gap is ~11pt and the artwork's corner sits 20.1pt
    /// from the cap's centre against a 27pt radius. Room remains to go further,
    /// but not indefinitely — the corner starts touching the curve around 27,
    /// and past that the artwork clips.
    ///
    /// These three numbers move together. Changing `collapsedHeight` or
    /// `collapsedArtwork` changes where the curve is at the artwork's edge, so
    /// the inset has to be re-derived rather than carried over.
    private static let collapsedArtworkInset: CGFloat = 18
    /// Between the collapsed artwork's trailing edge and the title.
    private static let collapsedArtworkGap: CGFloat = 10
    /// Reference size for the placeholder glyph's `.scaleEffect`, and nothing
    /// else. Any fixed number works — see the note at the placeholder in
    /// `artworkView` for why the glyph is drawn at a constant `.font(size:)`
    /// and scaled rather than sized directly. It is emphatically **not** the
    /// expanded artwork's size any more; that is
    /// `artworkHeight(fullSize:)` and it varies by device.
    private static let placeholderGlyphBase: CGFloat = 280
    private static let expandedCornerRadius: CGFloat = 38

    /// How much of the artwork's own height dissolves into the background
    /// beneath it, at full expansion.
    ///
    /// The artwork is full-bleed, so it has to end *somewhere*; a hard edge
    /// across the screen would read as a seam. Its bottom is therefore masked
    /// away into the drifting field of its own colours beneath it, so nothing
    /// about the transition is a boundary the eye can find.
    ///
    /// Its history, because the number has moved twice and each move was for a
    /// different reason:
    ///
    /// **0.30 → 0.42** fixed *where* the dissolve ended. At 0.30 it finished
    /// well clear of the title, so the eye had a band of pure background to
    /// compare against and the cover read as cut off above it rather than
    /// dissolved into it. Ending near the title leaves nothing in between for
    /// the comparison.
    ///
    /// **0.42 → 0.55** widens the blend itself. The end was in the right place
    /// but the band was still narrow enough to read as a region — a stretch of
    /// screen where the picture was visibly *becoming* the background. Over
    /// more than half the artwork's height there is no stretch to point at.
    ///
    /// The cost is real and is the reason this is not simply maximised: every
    /// point of fade is a point of cover that is no longer crisp.
    ///
    /// **0.25, hạ từ 0.55.** Ở 0.55 hơn một nửa tấm bìa nằm trong vệt tan —
    /// nhìn ra là bìa bị mờ chứ không phải bìa hoà vào nền, và người xem mất
    /// hẳn nửa dưới của ảnh. Một phần tư đủ để không thấy mép mà vẫn giữ 75%
    /// tấm bìa sắc nét.
    ///
    /// Chỗ vệt tan kết thúc giờ được `background` bám theo: dải màu phía dưới
    /// giữ nguyên màu trội tới đúng điểm ấy rồi mới tối dần, nên chỗ nối không
    /// có bậc màu nào. Hai con số này đi cùng nhau — đổi cái này phải xem cái
    /// kia.
    private static let artworkFadeFraction: Double = 0.25

    /// Dải màu nền giữ nguyên màu trội tới đâu, tính theo chiều cao thẻ.
    ///
    /// Đúng chỗ bìa bắt đầu tan. Bìa tràn phủ cả chiều cao thẻ, nên điểm ấy là
    /// `1 − artworkFadeFraction` — dẫn xuất chứ không phải số gõ tay, để đổi độ
    /// dài vệt tan thì chỗ nối tự đi theo và không có hai con số phải nhớ giữ
    /// đồng bộ.
    private static var tintHoldLocation: Double {
        1 - Self.artworkFadeFraction
    }

    /// Màu trội, kéo tối lại theo mức mở của hàng đợi.
    ///
    /// **Vì sao sửa nền chứ không sửa màu chữ.** Mở hàng đợi thì dải màu này
    /// thôi làm nền cho tấm bìa và trở thành nền cho *chữ* — hai chục hàng chạy
    /// suốt chiều cao thẻ. Mà nó là một dải: đỉnh là màu trội, đáy là
    /// `systemGroupedBackground`. Với một tấm bìa sáng, dải ấy đi từ sáng xuống
    /// gần đen, nên **không màu chữ nào đúng cho cả hai đầu** — chọn đen thì
    /// chìm ở đáy, chọn trắng thì chìm ở đỉnh. Thứ sửa được là cái nền: kéo nó
    /// về một trường tối đều, rồi chữ trắng đúng ở mọi chỗ.
    ///
    /// Kéo *trần* độ sáng chứ không nhân: một tấm bìa vốn đã tối thì không tối
    /// thêm, nên phép này chỉ động tới đúng những tấm bìa gây ra vấn đề.
    ///
    /// Bão hoà giữ nguyên, có chủ đích — thứ nhận ra một tấm bìa là sắc màu của
    /// nó, không phải độ sáng. Đây cũng là chỗ Apple Music dừng: hàng đợi của
    /// họ nằm trên một bản tối của màu bìa, chữ trắng suốt, không lật sang chữ
    /// đen cho album sáng.
    ///
    /// Đi theo `queueFactor` chứ không bật tắt: nó là cùng con số mà tấm bìa
    /// đang co lại theo, nên nền tối dần *trong lúc* danh sách hiện ra thay vì
    /// nhảy một bậc ở giữa chừng.
    static func queueBackdrop(_ tint: Color, queueFactor: Double) -> Color {
        guard queueFactor > 0, let hsb = Self.hsb(tint) else { return tint }
        let ceiling = 1 - (1 - Self.queueBackdropBrightness) * queueFactor
        return Color(UIColor(hue: hsb.hue,
                             saturation: hsb.saturation,
                             brightness: min(hsb.brightness, ceiling),
                             alpha: hsb.alpha))
    }

    /// Cùng màu ấy, nhưng cho những mặt phẳng **đặt trên** nền: nền hàng lúc
    /// nhấc, nền viên thuốc lúc tắt, ô placeholder của hàng không có bìa.
    ///
    /// Độ sáng đặt cứng chứ không kéo trần, và cao hơn `queueBackdropBrightness`
    /// — đó là toàn bộ điểm của nó. Một lớp giấy đặt lên mặt bàn thì sáng hơn
    /// mặt bàn; lấy đúng màu nền cho nó thì nó biến mất, và một cái bóng quanh
    /// một mảng vô hình đọc ra như lỗi vẽ.
    ///
    /// Sắc màu và bão hoà giữ nguyên, nên nó vẫn là màu của tấm bìa chứ không
    /// phải một mảng xám hệ thống dán lên.
    static func queueSurface(_ tint: Color) -> Color {
        guard let hsb = Self.hsb(tint) else { return tint }
        return Color(UIColor(hue: hsb.hue,
                             saturation: hsb.saturation,
                             brightness: Self.queueSurfaceBrightness,
                             alpha: hsb.alpha))
    }

    private static func hsb(_ colour: Color)
        -> (hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat)? {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(colour).getHue(&hue, saturation: &saturation,
                                     brightness: &brightness, alpha: &alpha) else { return nil }
        return (hue, saturation, brightness, alpha)
    }

    /// Trần độ sáng của nền khi hàng đợi mở hẳn.
    ///
    /// `ArtworkStore.enrich` cho màu trội lên tới 0.88 — đủ sáng để chữ trắng
    /// biến mất. 0.34 là mức mà một mảng màu vẫn đọc ra được là *màu ấy* chứ
    /// không thành xám đen, mà chữ trắng trên nó vẫn thừa tương phản.
    private static let queueBackdropBrightness: CGFloat = 0.34

    /// Đủ trên `queueBackdropBrightness` để thấy là một lớp riêng, đủ dưới mức
    /// làm chữ trắng khó đọc.
    private static let queueSurfaceBrightness: CGFloat = 0.50

    /// Các chặng của dải màu nền.
    ///
    /// **Không `.blur` ở đây, và đó là một bài học.** Bản trước làm mềm các mối
    /// nối bằng `.blur(radius: 12)`. Một phép làm mờ lấy mẫu ra ngoài khung của
    /// chính nó, nên ở sát mép thẻ nó pha dần về trong suốt và để lớp bên dưới
    /// lộ ra — một viền sáng chạy quanh mép, thấy rõ ngay khi mở hàng đợi. Các
    /// chặng dưới đây đã đủ mềm mà không cần nó.
    /// `base` là màu ở đáy dải, truyền vào chứ không gõ cứng
    /// `Color(.systemGroupedBackground)` như trước.
    ///
    /// Vì cái đáy ấy cũng phải tối đi khi hàng đợi mở, và với lý do y hệt cái
    /// đỉnh — xem `queueBackdrop`. Ở chế độ sáng, `systemGroupedBackground` gần
    /// trắng: kéo tối màu trội ở đỉnh mà để nguyên đáy thì dải chạy từ tối
    /// xuống *sáng*, và nửa dưới danh sách lại chìm đúng như cũ, chỉ đổi đầu.
    private static func tintStops(tint: Color, base: Color, hold: Double,
                                  fullBleed: Bool) -> [Gradient.Stop] {
        guard fullBleed else {
            return [
                .init(color: tint, location: 0),
                .init(color: base, location: 1)
            ]
        }
        let clamped = min(max(hold, 0), 0.95)
        return [
            .init(color: tint, location: 0),
            .init(color: tint, location: clamped),
            .init(color: tint.opacity(0.55), location: (clamped + 1) / 2),
            .init(color: base, location: 1)
        ]
    }

    /// The dissolve's alpha ramp, eased rather than linear.
    ///
    /// **The shape matters more than the length.** A two-stop gradient is a
    /// straight line in alpha, and a straight line has corners at both ends: the
    /// rate of change jumps from nothing to constant where it starts, and back
    /// to nothing where it finishes. Those two corners are exactly what the eye
    /// picks up as edges — the same first-derivative discontinuity that put the
    /// crease above the title, one layer further in. Lengthening a linear ramp
    /// moves the corners apart; it does not remove them.
    ///
    /// These five stops sample smoothstep, `t² · (3 − 2t)`, whose slope is zero
    /// at both ends. The dissolve now begins and finishes without announcing
    /// either.
    ///
    /// `LinearGradient` interpolates linearly between stops, so each pair is
    /// still a straight segment and what this really builds is a polyline.
    /// Seven points, raised from five when `artworkFadeFraction` went to 0.55:
    /// what has to stay small is the slope change at each joint, and stretching
    /// the same five points over a third more screen makes each segment longer
    /// and every joint sharper. The count follows the span rather than being a
    /// number that was once right.
    private static func dissolveStops(progress: Double) -> [Gradient.Stop] {
        let span = Self.artworkFadeFraction * progress
        let start = 1 - span
        // Bảy điểm được chọn khi vệt tan dài 55% chiều cao bìa; ở 25% cùng
        // số điểm ấy nằm dày hơn, nên mỗi đoạn ngắn hơn và mỗi mối nối phẳng
        // hơn. Giữ nguyên: thứ phải nhỏ là độ gãy tại mối nối, và thu ngắn
        // nhịp chỉ làm nó nhỏ thêm.
        let steps = 6
        return (0...steps).map { step in
            let t = Double(step) / Double(steps)
            let eased = t * t * (3 - 2 * t)
            return Gradient.Stop(
                color: .white.opacity(1 - eased),
                location: start + span * t
            )
        }
    }


    /// Bao lâu thì lớp nền đục của `background` đục hẳn, tính theo `progress`.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// 3 → 10, VÀ ĐÂY LÀ LÝ DO
    /// ─────────────────────────────────────────────────────────────────────
    /// Người dùng báo: thu nhỏ player thì thanh tab bị mờ và tối đi suốt cú
    /// thu, rồi trả về nguyên trạng một phát khi xong.
    ///
    /// Cơ chế, đọc ra từ thứ tự lớp chứ không phải đoán: `.thinMaterial` nằm
    /// **trên** lớp nền đục trong `ZStack` của `background`, nên nó làm mờ mọi
    /// thứ lọt qua lớp nền ấy. Với `progress * 3`, lớp nền chỉ đục hẳn ở 1/3,
    /// nên suốt `0 < progress < 1/3` thanh tab phía sau lọt qua rồi bị làm mờ.
    /// Và đó **đúng** là khoảng tấm thẻ đè lên thanh tab: mép dưới của thẻ chỉ
    /// đi được `collapsedBottomOffset` (79pt ở `minimised` 0) trong cả cú morph,
    /// trong khi thanh tab cao hơn thế.
    ///
    /// Đo bằng ảnh chụp giữ tay giữa cú kéo: ở `progress` ≈ 0,28 lớp nền mới
    /// đục 0,84 — 16% còn lại là thanh tab lọt qua — và cả hàng tab đọc ra xám
    /// đi, viên chọn mất màu.
    ///
    /// Với 10, lớp nền đục hẳn ở 0,1. Từ đó trở lên thanh tab bị **che hẳn**
    /// thay vì bị nhìn xuyên qua, tức nó luôn rõ nét ở mọi chỗ còn nhìn thấy
    /// được — không còn gì để nhảy khi cú thu kết thúc.
    ///
    /// **Vẻ mờ của viên thuốc lúc nghỉ không mất.** Ở `progress` 0 lớp nền vẫn
    /// là 0 và `.thinMaterial` vẫn đục hoàn toàn, nên viên thuốc vẫn nhìn thấy
    /// danh sách phía sau đúng như trước — và ở đúng lúc ấy nó **không** đè lên
    /// thanh tab, nên hai chuyện không đụng nhau. Cái mất là vẻ mờ trong khoảng
    /// `0,1 < progress < 1/3` của một cú kéo dở tay, nơi thẻ giờ đục sớm hơn.
    ///
    /// Đừng đổi con số này mà quên `materialCutoff` ngay dưới: hai cái là một
    /// phép suy, không phải hai lựa chọn.
    /// **Đây là cái núm quyết định cú nháy ở cuối cú thu nhỏ.** Nó nói lớp nền
    /// đục hết đục ở `progress` nào, và vì thế cú chuyển từ *thẻ đặc* sang *thẻ
    /// mờ* trải ra bao lâu:
    ///
    ///     10   mờ từ progress 0,10   ~2–3 khung   ⇒ đọc ra như một cú nháy
    ///      3   mờ từ progress 0,33   ~6 khung     (giá trị gốc)
    ///      2   mờ từ progress 0,50   ~9 khung
    ///      1   mờ từ progress 1,00   cả cú morph
    ///
    /// Đo bằng cách đếm khung trên video người dùng quay: ở `progress` 0,34 và
    /// 0,13 thân thẻ vẫn đặc — không thấy hàng danh sách nào phía sau — rồi ở
    /// trạng thái nghỉ thì thấy hết. Cả cú chuyển gói trong 2–3 khung.
    ///
    /// Đánh đổi, và nó không tránh được: cú chuyển *là* chỗ tấm thẻ thôi đặc.
    /// Trải nó ra lâu hơn nghĩa là tấm thẻ nhìn xuyên thấy được sớm hơn, lúc nó
    /// còn to. Không có giá trị nào vừa giữ thẻ đặc lúc còn to vừa không có cú
    /// chuyển ở cuối.
    /// **1 nghĩa là không còn mốc nào cả.** Lớp nền đục đúng bằng `progress`,
    /// nên tấm thẻ mờ theo tỉ lệ ở mọi thời điểm và vẻ nổi trên nội dung giữ
    /// liên tục suốt cú morph — không có `progress` nào mà nó "bắt đầu mờ",
    /// nên không có gì để nhảy.
    ///
    /// Đo trên video người dùng quay bản hệ số 10: dải màn hình y600–700 tụt
    /// 12,05 đơn vị sáng **trong một khung** (khung 157), trong khi cùng đoạn
    /// ấy cú thu nhỏ nền trôi đều qua 11 khung và thanh tab đậm dần qua 13
    /// khung. Cú nhảy nằm gọn ở chỗ tấm thẻ thôi đặc, và hệ số này là thứ
    /// quyết định nó diễn ra trong bao lâu.
    static let opaqueBaseRamp: Double = 1

    /// Where the frosted layer in `background` stops being rendered at all.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// KHÔNG CÒN SUY RA TỪ `opaqueBaseRamp`, VÀ ĐÂY LÀ LÝ DO
    /// ─────────────────────────────────────────────────────────────────────
    /// Nó từng là `1 / opaqueBaseRamp + 0.01`, dẫn từ chỗ lớp nền đục hết đục:
    /// trên mốc ấy lớp sương bị che hoàn toàn nên tháo đi là miễn phí.
    ///
    /// Phép dẫn ấy **chết khi `opaqueBaseRamp` xuống 1**: lớp nền khi ấy không
    /// bao giờ đục hẳn trừ đúng `progress` = 1, nên công thức cho ra **1,01** —
    /// tức `progress < materialCutoff` luôn đúng, và một `.thinMaterial` cỡ
    /// màn hình nằm trong cây **vĩnh viễn**, ở opacity ~0,01.
    ///
    /// Bắt được bằng ảnh Color Offscreen-Rendered Yellow trên Release: màn
    /// player bài **không bìa** vàng trở lại toàn bộ, sau khi lần đo trước nó
    /// gần sạch. Đúng cái bẫy mà chú thích của chính lớp ấy đã gọi tên — "it
    /// costs the same at opacity 0.01 as at 1" — và tôi vô hiệu hoá cái rào ấy
    /// bằng cách cột nó vào một hằng số vừa đi xuống 1.
    ///
    /// Nay là một con số riêng, và nó trả lời một câu khác: **trên `progress`
    /// nào thì lớp sương không còn đóng góp gì nhìn thấy được.** Với
    /// `opacity(1 - progress / materialCutoff)` thì tại đúng mốc này độ mờ
    /// bằng 0, nên tháo nó ở đây không thể chớp.
    ///
    /// 0,5: lớp sương chỉ sống ở nửa dưới cú morph, nơi tấm thẻ đủ nhỏ để nó
    /// còn là một mặt kính chứ không phải một tấm phủ cả màn hình.
    static let materialCutoff: Double = 0.5

    // `@Environment(\.displayScale)` đã bị bỏ khỏi kiểu này.
    //
    // Nó tồn tại để nhân với cỡ vẽ ra cỡ giải mã, và cỡ giải mã giờ là
    // `ArtworkStore.fullScreenCoverPixels` — một hằng số dùng chung với màn
    // khoá, đích danh để hai chỗ không băm ra hai khoá cache khác nhau cho cùng
    // một tấm ảnh. Không còn ai trong file này đọc tỉ lệ màn hình.
    //
    // Đợt A2 của lộ trình đưa nó vào đây để thay `UIScreen.main.scale`, và điều
    // đó vẫn đúng ở `ArtworkThumbnail` cùng `JamendoResultRow`. Chỉ chỗ này
    // không còn việc cho nó.


    /// Where the card rests: 0 collapsed, 1 expanded. Changed only on release.
    @State private var settled: Double = 0
    /// How far the in-flight drag has moved it. Zeroed when the drag settles.
    @State private var dragDelta: Double = 0
    /// Whether a drag is in flight. Sizes the hit region — see the note at the
    /// `.contentShape` call site for why that cannot be derived from
    /// `progress`. Deliberately not folded into `dragDelta != 0`: a drag that
    /// has clamped `progress` to 0 is still in flight and must keep the large
    /// region, which is precisely the case that broke.
    @State private var isDragging = false

    /// Độ mờ của cả tấm thẻ. **Chỉ rời khỏi 1 khi Giảm chuyển động đang bật.**
    ///
    /// Đây là thứ thay cho cú morph ở chế độ giảm chuyển động: thẻ không lớn
    /// dần từ viên thuốc ra toàn màn hình nữa mà đổi hình học tức thì lúc đang
    /// vô hình rồi mờ vào ở đích. Xem `morph(to:curve:)`.
    ///
    /// Với Giảm chuyển động tắt, giá trị này không bao giờ bị ghi và
    /// `.opacity(1)` là một modifier không làm gì — đường đi cũ không đổi một
    /// dòng nào.
    ///
    /// **Trong `@State` nó chỉ ở 0 đúng một khoảnh khắc, không bao giờ chờ ai
    /// đặt lại**, và đó là lý do không cần con dấu, không cần cờ "đang hoà mờ",
    /// không cần `completion` nào. `morph(to:curve:)` hạ nó xuống 0 rồi đưa
    /// ngay về 1 trong cùng một lượt; thứ chạy tiếp sau đó là phần nội suy của
    /// SwiftUI, còn giá trị trong state đã là 1 rồi. Một cú morph mới cắt
    /// ngang cũng chỉ dựng lại đúng cú hoà mờ ấy, và một cú hoà mờ bị bỏ dở
    /// không để lại tấm thẻ vô hình — đích của nó vốn đã là 1.
    @State private var cardOpacity: Double = 1

    /// Độ mờ của **riêng tấm bìa** trong lúc nó đổi chỗ giữa cú mở và cú đóng
    /// hàng đợi, khi giảm chuyển động.
    ///
    /// Song song với `cardOpacity` và cùng một cơ chế ba dòng — xem
    /// `setQueueFactor(to:)` và `morph(to:curve:)`. Khác đúng hai điểm, và cả
    /// hai đều có lý do:
    ///
    ///   - **Chỉ bao tấm bìa, không bao cả thẻ.** Áp ở `artworkView`, phía trên
    ///     `.overlay` gắn `QueuePanel`, nên panel không bị hoà mờ lây: ba khối
    ///     của nó đã có nhịp hiện riêng (`queueContentReveal`) đo từ Apple
    ///     Music, và chồng thêm một cú hoà mờ nữa lên đó là hai đồng hồ trên
    ///     cùng một vật.
    ///   - **Không có ngưỡng kiểu `morphNeedsFade`.** Ở đây chỉ có hai đích, 0
    ///     và 1, và cả hai chiều đều là trọn quãng đường — không có cú gọi lặp
    ///     "1 tới 1" nào để mà chớp vô cớ. `showingQueue` là `Bool`, nên
    ///     `onChange` chỉ nổ khi nó thật sự đổi.
    ///
    /// Với Giảm chuyển động tắt, giá trị này không bao giờ bị ghi và
    /// `.opacity(1)` là một modifier không làm gì.
    @State private var queueArtworkOpacity: Double = 1

    /// Ba khối trong `QueuePanel` hiện ra tới đâu: 0 chưa có gì, 1 đã tới nơi.
    ///
    /// **Một giá trị riêng, không phải một phép ánh xạ trên `queueFactor`.**
    /// Apple cho ba khối ấy chạy ở đuôi cú morph — quãng 0.92 → 1.0 của lò xo —
    /// và đó đúng là chỗ SwiftUI cắt lò xo đi. Xem `BottomBarStyle.queueContentIn`.
    @State private var queueContentReveal: Double = 0

    /// Ba khối ấy đã **về chỗ** tới đâu: 0 còn ở dưới, 1 đã tới nơi.
    ///
    /// Tách khỏi `queueContentReveal` vì Apple cho hai thứ hai độ dài khác
    /// nhau — xem `BottomBarStyle.queueContentSlide`.
    @State private var queueContentSlide: Double = 0

    /// Khối chữ lớn bị giấu đi tới đâu: 0 đọc rõ, 1 mất hẳn.
    ///
    /// Cùng lý do với `queueContentReveal` — một cửa sổ trên `queueFactor` chạy
    /// ngược khi đóng và đặt cú hiện lại của khối chữ vào đúng quãng panel đang
    /// tan. Xem `BottomBarStyle.queueTitleOut`.
    @State private var queueTitleHidden: Double = 0

    /// Có một hàng trong hàng đợi đang được kéo.
    ///
    /// Cần vì hai cử chỉ dọc chồng lên nhau trên cùng một vùng: kéo một hàng
    /// **xuống** cũng chính là vuốt thẻ xuống để đóng, và ngưỡng của cử chỉ
    /// đóng chỉ là 2 điểm khi thẻ đang mở. Cả hai cùng nhận thì thẻ đóng lại
    /// giữa lúc người dùng đang sắp bài. Xem `.gesture(drag(...))` bên dưới.
    @State private var queueIsReordering = false

    /// Whether the artwork region is showing `QueuePanel` instead of the
    /// artwork.
    ///
    /// Reset when the card collapses, in the `progress` observer below: the
    /// queue is something you open while looking at the player, and reopening
    /// the player later should show the artwork rather than whatever was on
    /// screen last time.
    @State private var showingQueue = false

    /// Mirrors `showingQueue`, animated explicitly rather than read from a
    /// `showingQueue ? 1 : 0` ternary at the call site.
    ///
    /// **What was measured, before this state existed:** with the ternary,
    /// `artworkGeometry`'s `width`/`height`/`centre` glided smoothly, but the
    /// dissolve mask held fully opaque through most of the size animation —
    /// a 30fps, ~230ms, 7-frame capture showed frames 1-5 still hard-edged
    /// with no visible blend, by which point the artwork had already grown
    /// to roughly 60-90% of its final width/height — and then the dissolve
    /// appeared abruptly between frames 5 and 6, already near its full
    /// extent, inside the last ~33ms of the transition. (See the task-1
    /// report's "Evidence of the snap".)
    ///
    /// **What was measured after** introducing this `@State`, driven by its
    /// own `withAnimation(BottomBarStyle.settle)`: a 60fps re-capture of the
    /// same transition showed the dissolve already partially present and
    /// visibly growing frame-over-frame across roughly the 70-85% window of
    /// the size animation, instead of appearing only in the last frame.
    ///
    /// **What that does not establish is the mechanism.** `[Gradient.Stop]`
    /// has no `Animatable` conformance regardless of where the `Double`
    /// driving `dissolveStops(progress:)` is stored — moving it into `@State`
    /// does not, by itself, make SwiftUI interpolate between stop arrays; it
    /// still receives discrete `[Gradient.Stop]` values frame to frame either
    /// way. The improvement above may come from this being a separate,
    /// explicitly-scoped `withAnimation` transaction rather than from the
    /// value being stored — the two were changed together, so this
    /// comment cannot tell you which one did the work. The before/after
    /// comparison is also confounded: `QueuePanel`'s own content fades
    /// in/out over the same pixels with its own default insertion/removal
    /// transition, and its list sits on a solid background occupying almost
    /// the same screen region as the dissolve, so "the mask is fading in"
    /// and "the panel's own fade is covering the seam" could not be told
    /// apart by eye in the frames captured. Treat "smoother" as established
    /// and "why" as open — re-measure by driving `queueFactor`/`progress`
    /// from a slider with `QueuePanel` unmounted before trusting more than
    /// that.
    @State private var queueFactor: Double = 0

    @State private var artwork: UIImage?
    /// Which track `artwork` was loaded for.
    ///
    /// Without it there is no way to tell a *current* cover from the one the
    /// previous track left behind, and every read of `artwork` has to assume the
    /// worst. See `displayedArtwork`.
    @State private var artworkOwner: ArtworkIdentity?
    /// Bản giải mã sẵn có trong cache cho đường dẫn bìa hiện tại, tra **một
    /// lần** mỗi khi `artworkIdentity` đổi thay vì mỗi khung.
    ///
    /// `ArtworkStore.anyCachedImage` chỉ là một lần khoá và một lần băm trên
    /// `NSCache` — rẻ, nhưng `displayedArtwork` từng gọi nó từ một computed
    /// property, nên nó chạy mỗi lần `body` chạy: mỗi khung suốt cú kéo thẻ,
    /// cho một kết quả không đổi trong cả cú kéo ấy.
    ///
    /// Được ghi ở hai chỗ: `.onChange` trên `artworkIdentity` trong `body`, và
    /// cuối `loadArtwork`. Xem chú thích ở hai chỗ ấy để biết vì sao chừng ấy
    /// mốc là đủ.
    @State private var cachedCover: UIImage?
    /// Bài mà `cachedCover` được tra cho — cùng vai trò `artworkOwner` giữ cho
    /// `artwork`, và có mặt vì cùng một lý do.
    ///
    /// Một `@State` không tự hết hạn khi bài đổi. Ở khung đầu tiên của bài B,
    /// `cachedCover` vẫn còn là ảnh tra cho bài A cho tới khi `.onChange` chạy;
    /// không có chốt này thì `displayedArtwork` sẽ trả bìa của A cho B trong
    /// đúng khung ấy. Trước khi giá trị được cất vào `@State`, chuyện đó bất
    /// khả: chỗ tra cache đọc thẳng đường dẫn của bài hiện tại nên không bao giờ
    /// lệch bài.
    ///
    /// Chốt nằm ở chỗ gọi `preferredCover`, không nằm trong `preferredCover` —
    /// đúng như `loadedForThisTrack` đang làm. Nó đổi câu hỏi "`.onChange` có
    /// kịp khung không" từ chuyện *đúng/sai* thành chuyện *nhanh/chậm*: chậm
    /// một khung thì ô bìa là mảng màu phẳng, chứ không phải bìa bài trước.
    @State private var cachedCoverOwner: ArtworkIdentity?
    @State private var tint: Color?


    private var progress: Double { min(max(settled + dragDelta, 0), 1) }

    /// Publishes `progress` outward so the content behind the card can recede
    /// with it, the way a sheet pushes its presenting screen back.
    ///
    /// This state was private for most of the card's life, and deliberately: an
    /// earlier request to hide the tab bar behind the expanded card was turned
    /// down rather than exposing it, because the expanded card is opaque and
    /// full-screen and already covers the bar. The recede is different — it is
    /// visible for the whole transition, and there is no way to draw it from
    /// outside without knowing how far the card has travelled.
    ///
    /// Written from the gesture and from `expand()`/`collapse()`, never from an
    /// `onChange` on `progress`. That distinction is what made the recede smooth:
    /// an `onChange` runs *after* this view's body, so every dragged frame cost
    /// a second update pass, and the write invalidated whoever held the other
    /// end. Writing where the value actually changes keeps it to one pass.
    ///
    /// During the settle spring this is set once, to the destination, inside the
    /// same `withAnimation`. The recede then runs its own spring with the same
    /// parameters and lands with the card, rather than being driven frame by
    /// frame from here.
    let expansion: PlayerExpansion

    /// How far the collapsed pill is inset from each edge of the **safe area**
    /// *at collapsed rest*: `pillSideMargin` (21) on its own row, widening to
    /// `BottomBarMetrics.minimisedPlayerInset` (79) as the pill slots into the
    /// tab row between the leading circle and the search button.
    ///
    /// Safe-area-relative, and it stays that way even though the vertical
    /// measurements are now screen-relative: `FloatingTabBar` divides up the
    /// safe-area width (its `.padding(.horizontal,)` is applied inside the safe
    /// area), so the slot this pill has to land in is measured from there.
    ///
    /// Safe area, not screen: this is the space `FloatingTabBar` divides up,
    /// and the pill has to land in the slot the bar reserved. `card(size:insets:)`
    /// adds `insets.leading`/`insets.trailing` to convert it into the physical
    /// coordinates this view actually lays out in — separately per side, since
    /// those two are not equal in landscape. See the note there.
    ///
    /// Deliberately free of `progress`. The card's own layout multiplies it by
    /// `(1 - progress)` at the call site so an expanded card is unaffected; the
    /// hit region must NOT, and reads this resting value directly behind its
    /// drag-state gate — see the note at the `.contentShape` call site.
    private var collapsedSideMargin: CGFloat {
        Self.pillSideMargin
            + (BottomBarMetrics.minimisedPlayerInset - Self.pillMinimisedRelief
               - Self.pillSideMargin) * CGFloat(minimised)
    }

    /// Hệ số co của viên pill, **buộc vào cùng phép nội suy** mà mọi thứ khác
    /// trong khối này dùng.
    ///
    /// Đây là chỗ tôi đã làm sai một lần và đáng ghi lại. Bản đầu đặt một
    /// `.scaleEffect` lên `PlayerCard` từ `RootView`, keyed vào cờ nhị phân
    /// `isMinimisedActive` với `.animation` riêng — nên cú co chạy trên một
    /// đường cong còn `collapsedSideMargin` và `collapsedBottomOffset` chạy
    /// trên đường cong khác. Giữa chừng hai bên bất đồng, và viên pill không
    /// tới được chỗ nó phải tới.
    ///
    /// `minimised` là `Double` thẻ vốn nhận, `(1 - progress)` tắt hiệu ứng khi
    /// thẻ đang mở — đúng hình dạng `collapsedSideMargin` ngay trên dùng. Không
    /// `.animation` nào ở đây: nó cưỡi lên chính transaction đang lái hai giá
    /// trị kia, nên ba thứ không thể lệch nhau.
    private var pillShrink: CGFloat {
        1 - (1 - Self.pillMinimisedScale) * CGFloat(minimised) * (1 - progress)
    }

    /// **Physical screen** bottom edge up to the collapsed pill's bottom edge:
    /// `BottomBarMetrics.playerBottomOffset` (79) on its own row above the tab
    /// bar, dropping to `BottomBarMetrics.screenBottomInset` (21) as the pill
    /// joins that row.
    ///
    /// The screen, not the safe area. Both endpoints are measured from the
    /// physical edge now, matching where the tab bar itself is anchored, and
    /// this view is the right place for that: the card `.ignoresSafeArea()`, so
    /// it already lays out in physical coordinates and this offset is already
    /// in the units the padding below needs. That is why `insets.bottom` no
    /// longer appears in either the padding or `dragTravel` — adding it back
    /// would push the pill 34pt above where the bar reserved room for it on a
    /// phone with a home indicator, and leave it correct on an SE, which is the
    /// worst way for this to be wrong.
    ///
    /// **This is the one expression both the bottom padding and `dragTravel`
    /// read.** It exists as a single value precisely because those two have
    /// drifted apart twice already, and it is now worse than a forgotten
    /// constant: this distance changes continuously while the user scrolls, so
    /// a `dragTravel` left reading the literal `playerBottomOffset` would lag
    /// the finger by 58pt while minimised and by a fraction of that mid-morph.
    /// Do not restate either half of it anywhere.
    private var collapsedBottomOffset: CGFloat {
        BottomBarMetrics.playerBottomOffset
            + (BottomBarMetrics.screenBottomInset - BottomBarMetrics.playerBottomOffset)
            * CGFloat(minimised)
    }

    // The spring that used to live here is now `BottomBarStyle.settle`, shared
    // with `expand()` and with the fade that accompanies `collapse()` when the
    // queue ends (F7), so the card disappears on the same curve it moves on.
    //
    // `expand()` used to define its own inline, described in a comment as
    // "slightly snappier". Converted to the same units the rest of the app uses
    // — 0.42/0.14 against 0.45/0.15 — the two differed by three hundredths of a
    // second, and the "snappier" one was the slower. The distinction was not
    // real, so there is now one spring.

    /// The height reserved below the artwork for everything
    /// `NowPlayingContent` stacks there. The artwork gets what is left.
    ///
    /// This is what makes the artwork's size derived from the space available
    /// rather than fixed. A fixed size alone put the title/scrubber/transport
    /// row below the card's own bottom edge in landscape on an iPhone 12 —
    /// `expandedContent` offset the content by a constant that exceeded the
    /// card's full landscape height, so everything below the artwork was
    /// clipped away and the expanded player had no controls at all. See F2.
    ///
    /// `440` is a rough allowance for everything `NowPlayingContent` stacks
    /// below the artwork — a starting point, like the other constants here, not
    /// a measured minimum. The stack is five elements in a
    /// `VStack(spacing: 24)`:
    ///
    ///   1. the title block — two reserved `.title2` lines + a `.subheadline`,
    ///      measured at 81pt
    ///   2. `ScrubberBar`, ~53pt with its time labels
    ///   3. the transport row, ~82pt — **not** the 44pt glyph frame plus its
    ///      8pt top padding. The play button is `.font(.system(size: 64))` and
    ///      draws ~74pt tall, which is what actually sizes the `HStack`. Sizing
    ///      this row from `transportGlyphFrame` under-counts it by 30pt.
    ///   4. the repeat row — 32pt frame + `.padding(.top, 4)` = 36pt
    ///   5. `SystemVolumeSlider`, 44pt
    ///
    /// The five elements are the title block (81), scrubber (53), transport
    /// row (82), volume row (28) and repeat row (40, being a 36pt frame plus
    /// 4pt of top padding). With four 24pt gaps that is **~380pt**.
    ///
    /// The transport row is 82 and not the 44 of `transportGlyphFrame`: the
    /// play button is `.font(.system(size: 64))` with no frame of its own, so
    /// it, not its neighbours, sizes that `HStack`. The heights here were
    /// measured off a screenshot of the real expanded player, not estimated.
    ///
    /// Its history is a list of the same mistake. It was raised from 350 when
    /// the volume slider was added, but only by the slider's own 44pt — the
    /// extra `VStack` gap that came with a fourth element (+24pt) was
    /// forgotten, leaving it 18pt short and clipping the slider on a two-line
    /// title on a 4.7" device. It was then left at 380 when the repeat row was
    /// added as a fifth element, which is another 36 + 24 = 60pt, and clipped
    /// the volume slider again on a 4.7" device in portrait and on every
    /// iPhone in landscape. Hence 440.
    ///
    /// 440 was kept when the volume row later shrank from 44 to
    /// `ScrubberBar.touchHeight` (28) and the repeat row grew by 4, a net −12.
    /// The number did not need to move — this is the direction that is always
    /// safe — and the slack it buys is spent below.
    ///
    /// **Adding anything else to that stack means raising this by the new
    /// element's height *plus* the 24pt `VStack` spacing, not just the
    /// element's height.** That omission is the mistake this number has now
    /// been corrected for twice.
    ///
    /// Why the value is what the content actually gets: when the height term
    /// of this used to bind, the region left below the artwork came to exactly
    /// `440 - 40 = 400pt`. It is now that 400pt directly and unconditionally:
    /// `contentOffset(fullSize:)` measures up from the card's bottom, so the
    /// region is the same on every device and no longer depends on the artwork
    /// at all. Against the ~380pt stack this was last measured for that left
    /// ~20pt; the fifth element is `queueToggleRow` now, not the repeat pill
    /// row (see `jamendoCredit`'s comment on `NowPlayingContent`) — a plain
    /// 44pt frame where the pill row's 36pt frame plus 4pt of top padding
    /// contributed 40, four points taller — so the real stack is ~384pt and
    /// the real slack is **~16pt**, not 20. `contentBudget` was correctly not
    /// raised for that four-point difference (still comfortably inside the
    /// existing floor), but do not read either number as headroom:
    /// `NowPlayingContent` has no `.dynamicTypeSize` cap, so one step up in
    /// accessibility text grows the two `.title2` lines and the
    /// `.subheadline` beneath them by more than 16pt and clips the bottom
    /// again on a 4.7" screen. The durable fix is to measure the stack
    /// instead of allowing for it; until then this constant is a floor, not a
    /// margin. At 380
    /// the region was 340pt, 52pt short, and the whole volume slider sat below
    /// the card's bottom edge where it could not be dragged.
    ///
    /// Verified by screenshot rather than by arithmetic alone, on both ends of
    /// the change: at 380 the repeat glyph landed 15pt above the bottom edge on
    /// a 4.7" screen in portrait (and 17pt on an iPhone 17 in landscape), with
    /// no room for the 24pt gap and 44pt slider that follow it; at 440 it
    /// landed 75pt above, which fits them both.
    ///
    /// One case this cannot fix, and it is worth knowing before the number is
    /// nudged again: a 375pt-tall screen in landscape (a 4.7" device rotated)
    /// has less height than the stack needs, so something is always clipped
    /// there. At 380 it was the volume slider; at 440 it is the title — and
    /// not merely its top line. At that width the title fits on one line, so
    /// the whole line sits above the card and only the tips of its descenders
    /// show. The artist and album line, scrubber, transport, volume and repeat
    /// rows all survive.
    ///
    /// Losing the title is still the better end to lose: it is information the
    /// user can get elsewhere, where an unreachable volume slider is a control
    /// they cannot operate at all. But it is a real regression on a supported
    /// orientation, not a cosmetic trim, and no value of this constant fixes
    /// it — a stack that tall does not fit a screen that short. Landscape on
    /// every taller iPhone fits at 440.
    ///
    /// **This no longer bounds the artwork, and that is the change.** The two
    /// regions overlap now: the controls are anchored to the bottom of the card
    /// and the artwork reaches down behind them, dissolved to near-nothing by
    /// the time it gets there. Before, the artwork stopped where this region
    /// began, which is what held it to a square on every phone.
    private static let contentBudget: CGFloat = 440

    /// The gap between where the artwork's frame ends and where the content
    /// starts, back when the two could not overlap. Kept as the amount the
    /// content region is *smaller* than `contentBudget`, so the region below the
    /// controls stays exactly the 400pt every measurement in that doc was taken
    /// against.
    private static let contentInset: CGFloat = 40

    /// Lề hai bên của bìa vuông khi mở hết.
    ///
    /// **Bìa mở rộng giờ là một khối vuông ở giữa, không còn tràn màn hình.**
    /// Bản trước cao 59% chiều cao thẻ và rộng bằng cả thẻ, nên `scaledToFill`
    /// cắt mất ~22% bề ngang — và quan trọng hơn, tỉ lệ khung đổi suốt cú morph
    /// nên bức ảnh vừa lớn lên vừa tự zoom bên trong khung của nó. Mắt đọc ra
    /// là bị kéo giãn, không phải đang lớn lên.
    ///
    /// Vuông thì cú morph là một phép phóng to đều từ đầu tới cuối: thumbnail
    /// 36pt trượt lên giữa màn hình, nở ra thành khối vuông, bo góc tăng dần.
    /// Không có gì bị cắt, không có chuyển động thứ hai chồng lên.
    private static let expandedArtworkInset: CGFloat = 24

    /// Khoảng hở trên và dưới khối vuông: dưới grabber, và trên khối điều khiển.
    private static let expandedArtworkTopGap: CGFloat = 24
    private static let expandedArtworkBottomGap: CGFloat = 24

    /// Bo góc của bìa khi mở hết. Thumbnail dùng 12% bề rộng của chính nó
    /// (36 → ~4.3), nên bán kính **tăng dần** suốt cú mở.
    private static let expandedArtworkCorner: CGFloat = 18


    // `artworkHeightFraction` và `artworkHeight(fullSize:)` từng ở đây, hồi bìa
    // tràn chỉ cao 59% thẻ. Bìa tràn giờ phủ cả chiều cao và `artworkFadeFraction`
    // là thứ duy nhất quyết định nhìn thấy bao nhiêu, nên cả hai không còn ai
    // gọi. Lịch sử ở git.


    /// Cạnh của khối vuông khi mở hết.
    ///
    /// Lấy cái nhỏ hơn giữa bề rộng còn lại sau lề, và chỗ trống thẳng đứng
    /// giữa grabber với khối điều khiển. Chặn theo chiều cao là bắt buộc:
    /// ngang máy, hoặc trên một màn hình thấp, bề rộng trừ lề vẫn còn lớn hơn
    /// khoảng trống dọc — và một khối vuông cao hơn chỗ chứa nó sẽ đè lên
    /// scrubber.
    private static func artworkSide(fullSize: CGSize, topInset: CGFloat) -> CGFloat {
        let vertical = Self.contentOffset(fullSize: fullSize)
            - Self.artworkTop(topInset: topInset)
            - Self.expandedArtworkBottomGap
        return max(min(fullSize.width - Self.expandedArtworkInset * 2, vertical), 0)
    }

    /// Mép trên của khối vuông, đo từ đỉnh thẻ: dưới safe area và grabber.
    private static func artworkTop(topInset: CGFloat) -> CGFloat {
        topInset + Self.grabberTopGap + Self.grabberHeight + Self.expandedArtworkTopGap
    }

    /// Where `NowPlayingContent` starts, measured from the card's top.
    ///
    /// **Anchored to the bottom of the card, not to the artwork.** It used to be
    /// `artworkHeight + 40`, which was correct only while the artwork could not
    /// reach the controls; with the two overlapping, that expression would push
    /// the stack off the bottom. Measuring from the bottom also makes the
    /// controls sit in the same place on every track and every device, which the
    /// old form only did by coincidence of the artwork being square.
    ///
    /// Allowed to go negative on a card shorter than the content region — see
    /// `contentBudget`'s note on landscape. The offset consumes the signed
    /// value, which is what keeps a short screen reserving its full region
    /// rather than being pushed down and clipped.
    private static func contentOffset(fullSize: CGSize) -> CGFloat {
        fullSize.height - (Self.contentBudget - Self.contentInset)
    }

    /// How far the queue list may grow past `contentOffset`, into the space
    /// `NowPlayingContent`'s title block reserves but leaves invisible in
    /// queue mode (`titleBlock` stays in the layout at `opacity(0)` rather
    /// than being removed — see its own doc comment for why).
    ///
    /// 81 (the title block's own measured height, per `contentBudget`'s doc)
    /// plus 24 (the `VStack(spacing: 24)` gap before the scrubber) lands the
    /// cap exactly on `ScrubberBar`'s own top edge — the top of its **28pt**
    /// touch strip — never past it. That strip is what a Critical was fixed
    /// over once already: `QueuePanel`'s `List` is a `UIScrollView`, and its
    /// pan recogniser swallowed it, making seeking impossible while the
    /// queue was open. This constant is the boundary that keeps this change
    /// from reopening that defect — close to the scrubber is the
    /// requirement, touching it is the regression.
    private static let queueListReclaimedHeight: CGFloat = 81 + 24 - queueListScrubberGap

    /// Khe giữa hàng cuối của danh sách và thanh tiến trình.
    ///
    /// Trừ vào phần chiều cao mà danh sách được đòi thêm, không cộng vào một
    /// padding riêng: hai cách cho cùng một kết quả nhìn, nhưng cách này giữ
    /// đúng bất biến mà hằng số trên đang canh — mép dưới của panel *tiến sát*
    /// dải chạm 28pt của thanh tua và không bao giờ chạm vào. Một padding ở
    /// dưới panel sẽ đẩy nội dung lên mà vẫn để nguyên vùng nhận chạm, tức là
    /// làm cho khe *trông* có mà không thật có.
    private static let queueListScrubberGap: CGFloat = 14

    /// What has to change for the card to reload its artwork.
    ///
    /// **The path, not only the track ID.** Keyed on the ID alone — which is
    /// what this was — the card kept whatever picture it had loaded when the
    /// track started, because a `Track`'s `id` does not change when its cover
    /// does. Changing a cover from the list updated the row (`ArtworkThumbnail`
    /// keys on the path) and left the mini pill and the expanded player showing
    /// the old one, for as long as that track stayed loaded.
    ///
    /// Same class of bug as the one `LibraryService.setArtwork`'s fresh-filename
    /// rule exists to prevent, in the one place that rule could not reach: the
    /// card has its own copy of the image, so a new path on disk means nothing
    /// until something tells the card to go and read it.
    private struct ArtworkIdentity: Equatable {
        let trackID: UUID?
        let artworkPath: String?
    }

    /// What the artwork slot draws on a given frame.
    ///
    /// Split out of `artworkView` because the rule it encodes is the answer to a
    /// reported bug and could not be tested where it was — inside a view body,
    /// mid-animation.
    enum ArtworkSource: Equatable {
        /// A cover to draw. May briefly be the *previous* track's while the new
        /// one decodes; that is deliberate, and it is what the working case
        /// already did.
        case image
        /// This track has a cover, but no decoded copy is in hand yet. A plain
        /// fill, with no glyph — see `source(hasArtwork:loaded:)`.
        case pending
        /// This track genuinely has no cover. The glyph belongs here and only
        /// here.
        case placeholder
    }

    /// **`hasArtwork` comes from the model, `loaded` comes from a `.task`.**
    /// That difference is the whole bug.
    ///
    /// `artwork` is `@State` written only by `loadArtwork`, which runs from
    /// `.task(id:)` — asynchronously, after the body has already rendered and
    /// after the expand animation has already begun. Branching on it meant the
    /// slot's *structure* changed mid-flight, and SwiftUI cannot interpolate
    /// across a structural change:
    ///
    /// - cover → no cover: the card opened still showing the **previous**
    ///   track's cover, then snapped to the grey placeholder part-way through.
    /// - no cover → cover: it opened on the placeholder glyph and snapped to the
    ///   image.
    /// - cover → cover: no structural change, so this one always looked right —
    ///   which is exactly the pattern that was reported, down to "open another
    ///   track with a cover and it is correct again".
    ///
    /// `hasArtwork` is `artworkRelativePath != nil` on the current track: known
    /// synchronously, on the first frame, with no I/O. Deciding the branch from
    /// it means the structure is settled before the animation starts and only
    /// the image content arrives late.
    ///
    /// `.pending` rather than `.placeholder` for "has a cover, still decoding"
    /// is the other half. Falling back to the glyph there would reintroduce the
    /// same snap for any cover not already in the cache.
    static func source(hasArtwork: Bool, loaded: Bool) -> ArtworkSource {
        guard hasArtwork else { return .placeholder }
        return loaded ? .image : .pending
    }

    /// Synchronous, from the model. Never from `artwork`.
    private var hasArtwork: Bool {
        playback.currentTrack?.artworkRelativePath != nil
    }

    /// The cover to draw **on this frame**, resolved without waiting for
    /// anything.
    ///
    /// The remaining half of the reported bug, after the structure was settled:
    /// opening a cover track straight after a coverless one, the card's frame
    /// grew correctly but the picture "appeared underneath" part-way instead of
    /// growing with it. Nothing was wrong with the animation — there were simply
    /// no pixels to animate. `artwork` is `nil` at that moment (the coverless
    /// track cleared it) and the decode lands tens of milliseconds into a 360ms
    /// spring, so the cover fades in over a frame that has already half opened.
    ///
    /// The list row the user just tapped has *already* decoded this picture, at
    /// its own small size. `ArtworkStore` keys its cache by path **and** size,
    /// so the player could never reach that entry; `anyCachedImage(for:)` is the
    /// way in. Scaled up for the few frames until the full decode arrives it is
    /// the same picture, and the swap between them is invisible — where the
    /// absence was not.
    ///
    /// Order matters. The full-strength image wins only when it belongs to
    /// *this* track; otherwise a correct small cover beats a stale large one.
    ///
    /// Bản trong cache đọc từ `cachedCover` chứ không tra thẳng
    /// `ArtworkStore.anyCachedImage` nữa: quy tắc thì không đổi, chỉ *khi nào*
    /// tra mới đổi. Xem `cachedCover`.
    ///
    /// Hai nhánh đều qua chốt chủ sở hữu, vì cả hai đều là `@State` không tự hết
    /// hạn khi bài đổi. `cachedForThisPath` trong tên tham số là một lời hứa, và
    /// đây là chỗ giữ lời hứa ấy.
    private var displayedArtwork: UIImage? {
        Self.preferredCover(
            hasArtwork: hasArtwork,
            loadedForThisTrack: artworkOwner == artworkIdentity ? artwork : nil,
            cachedForThisPath: cachedCoverOwner == artworkIdentity ? cachedCover : nil
        )
    }

    /// Tra cache một lần cho `owner`, và ghi lại cả ảnh lẫn chủ của nó.
    ///
    /// Một chỗ cho cả hai mốc, vì ghi ảnh mà quên ghi chủ thì ảnh sẽ bị chốt ở
    /// `displayedArtwork` loại đi và cả việc này thành vô nghĩa — im lặng.
    ///
    /// Cả hai lần gán đều có rào so sánh: `@State` không so sánh giá trị trước
    /// khi làm mất hiệu lực (`UIImage?` thì cũng không có gì để so), nên một lần
    /// gán nil-đè-nil — ca rất thường gặp: bài không bìa, hoặc cache chưa có gì —
    /// vẫn tốn trọn một lượt `body` của một view rất lớn, đúng vào lúc đổi bài.
    /// `!==` chứ không phải `==`: cùng một đối tượng ảnh mới là "không có gì
    /// đổi"; `UIImage` không định nghĩa so sánh nội dung, và có định nghĩa thì so
    /// pixel ở đây cũng là sai chỗ.
    private func refreshCachedCover(for path: String?, owner: ArtworkIdentity) {
        let cover = ArtworkStore.anyCachedImage(for: path)
        if cover !== cachedCover { cachedCover = cover }
        if cachedCoverOwner != owner { cachedCoverOwner = owner }
    }

    /// The ordering above, on its own so it can be tested.
    ///
    /// Generic because the rule has nothing to do with images: it is "prefer the
    /// one that is certainly right and certainly current, then anything correct,
    /// then nothing — and never anything at all if the track has no cover."
    static func preferredCover<T>(
        hasArtwork: Bool,
        loadedForThisTrack: T?,
        cachedForThisPath: T?
    ) -> T? {
        guard hasArtwork else { return nil }
        return loadedForThisTrack ?? cachedForThisPath
    }

    private var artworkIdentity: ArtworkIdentity {
        ArtworkIdentity(
            trackID: playback.currentTrack?.id,
            artworkPath: playback.currentTrack?.artworkRelativePath
        )
    }

    var body: some View {
        // `outer` must NOT itself ignore the safe area: only a reader that
        // still respects it reports real `safeAreaInsets`. `ignoresSafeArea()`
        // is applied to the card view produced from it instead, so the card
        // can still visually reach the physical edges while the insets we
        // read to lay it out stay correct. See F2 in the Phase 2a task-2
        // review for why the naive `GeometryReader { }.ignoresSafeArea()`
        // ordering zeroes the insets.
        GeometryReader { outer in
            card(size: outer.size, insets: outer.safeAreaInsets)
                .ignoresSafeArea()
                // **Cỡ giải mã không còn tới từ `outer`, và chú thích cũ ở
                // đây đã hết đúng.** Nó viết: "Attached here, rather than
                // outside the reader, so the artwork's target size can be
                // derived from the same `outer` geometry the card lays out
                // with. See F2." Cỡ giải mã giờ là
                // `ArtworkStore.fullScreenCoverPixels`, một hằng số dùng chung
                // với màn khoá — xem doc của nó về vì sao.
                //
                // Vẫn để trong reader chứ không dời ra: dời nó là một thay đổi
                // cấu trúc trên cây view, và không có gì đòi thay đổi ấy. Chỗ
                // này giờ chỉ là một chỗ, không còn là một ràng buộc.
                .task(id: artworkIdentity) { await loadArtwork() }
        }
        // Cú hoà mờ thay cho cú morph khi giảm chuyển động — xem
        // `cardOpacity` và `morph(to:curve:)`. Ở chế độ thường nó là hằng số 1.
        //
        // Một modifier riêng, nhân vào modifier bên dưới chứ không gộp thành
        // một biểu thức với nó. Hai giá trị này trả lời hai câu hỏi khác nhau
        // — "có bài nào không" và "đang ở giữa cú hoà mờ nào không" — và cái
        // bên dưới đã có `.animation(_:value:)` gắn đích danh câu hỏi của nó.
        // Gộp lại thì hai câu hỏi ấy đi chung một biểu thức và chỉ còn một chỗ
        // để nói đường cong cho cả hai; tách ra thì mỗi cái tự nói lấy, và cú
        // hoà mờ nhận đường cong từ chính `withAnimation` đã đặt nó.
        //
        // Áp ở ngoài cùng, một lần, chứ không rải xuống các lớp trong
        // `card(size:insets:)`: cả thẻ phải tan như **một** vật. Nền, ảnh bìa,
        // chrome thu nhỏ và chrome mở rộng chồng lên nhau, nên nhiều `.opacity`
        // lồng nhau sẽ cho chúng nhìn xuyên qua nhau giữa chừng cú tan thay vì
        // cùng nhạt đi. Ở đây nó cũng bao luôn bóng đổ và mọi thứ
        // `card(size:insets:)` dựng ra, khỏi phải nhớ lớp nào đã được bao.
        //
        // **`.opacity` của `View`, và ở đây điều đó là load-bearing.** Giá trị
        // này đi *xuống dưới 0* khi một cú morph đè lên cú hoà mờ đang chạy —
        // xem `morph(to:curve:)` — và `View.opacity` kẹp số âm thành trong
        // suốt hoàn toàn. `ShapeStyle.opacity` (tức `Color.blue.opacity(x)`)
        // thì **không**: nó nhân thẳng vào alpha của màu và một alpha âm vẽ ra
        // một bóng ma âm bản. Hai thứ trùng tên và khác hẳn nhau. Đo ở
        // `SwiftUIAnimationTransactionEvidenceTests.testViewOpacityClampsNegativesWhereColourOpacityDoesNot`.
        //
        // Qua `PresentedOpacity` chứ không phải `.opacity(cardOpacity)` trần,
        // và cái nó thêm vào là hit testing, không phải cách vẽ: một view ở độ
        // mờ 0 trong SwiftUI **vẫn ăn chạm**, nên tấm thẻ tràn màn hình vô hình
        // suốt 0,37s của cú hoà mờ sẽ nuốt cú chạm vào một hàng thư viện mà
        // người dùng vẫn còn trông thấy. Phải là `Animatable` vì `cardOpacity`
        // đọc trong `body` đã là 1 rồi — chỉ giá trị SwiftUI đang nội suy mới
        // biết thẻ đang mờ tới đâu. Cả lý lẽ nằm ở ghi chú của kiểu ấy.
        //
        // Vẫn là `View.opacity` bên trong, nên đoạn văn ngay trên còn nguyên
        // hiệu lực.
        .modifier(PresentedOpacity(opacity: cardOpacity))
        .opacity(playback.currentTrack == nil ? 0 : 1)
        .animation(BottomBarStyle.settle, value: playback.currentTrack == nil)
        // Mốc chính để tra lại cache: bài đổi, hoặc đường dẫn bìa của chính bài
        // ấy đổi. `artworkIdentity` bắt được cả hai — `setArtwork` luôn ghi ra
        // một tên file mới, nên thay bìa cho bài đang phát cũng đổi định danh.
        //
        // `onChange` chứ không phải thân `.task` bên dưới, vì `onChange` chạy
        // sớm hơn: nó chạy ngay sau `body` trong cùng lượt cập nhật, còn thân
        // `.task` là một `Task` trên main actor và chỉ chạy sau khi lượt ấy
        // xong. Sớm hơn là đáng, vì bìa dự phòng có mặt chỉ để cứu vài chục mili
        // giây đầu.
        //
        // Sớm bao nhiêu thì **không** khẳng định ở đây. Chú thích của
        // `expansion` phía trên chỉ chứng cho một điều: `onChange` chạy sau
        // `body` và tốn thêm một lượt cập nhật — ở đó điều ấy được nêu như lý do
        // *tránh* `onChange`, chứ không phải bằng chứng rằng lần ghi kịp khung
        // đang dựng. Nếu nó không kịp, cái mất là một khung bìa dự phòng, không
        // phải một khung bìa sai: `cachedCoverOwner` gác chỗ đó.
        //
        // Một lượt `body` thừa mỗi lần đổi bài là giá phải trả, và đó đúng là
        // cái giá mà chú thích `expansion` cảnh báo — chỉ khác ở chỗ nó rơi vào
        // lúc đổi bài, không phải mỗi khung của một cú kéo.
        //
        // `initial: true` cho lần đầu thẻ xuất hiện đã có sẵn bài đang phát
        // (khôi phục phiên trước). Ở đúng lúc ấy cache thường rỗng vì tiến
        // trình vừa khởi động, nhưng một lần tra rẻ hơn là phải suy luận xem
        // trường hợp nào thì rỗng.
        .onChange(of: artworkIdentity, initial: true) {
            refreshCachedCover(
                for: playback.currentTrack?.artworkRelativePath,
                owner: artworkIdentity
            )
        }
        .onChange(of: progress) { _, newValue in
            // Collapsed, or nearly. Not `== 0`: a drag that ends just short of
            // closed still means the player is gone from the user's view, and
            // reopening it should start from the artwork.
            //
            // **`withAnimation` is load-bearing, and its absence was a real
            // defect.** `settled` is plain `@State`, and `drag(...).onEnded`
            // assigns its final value *synchronously* — so `progress` reads 0
            // on the very next evaluation, the instant the finger lifts, while
            // the card is still visibly mid-spring for another ~0.4s. A bare
            // write here therefore fired at release, not at arrival, and
            // `QueuePanel` is mounted behind a plain `if showingQueue`: SwiftUI
            // removed it from the tree on the next frame with no transition at
            // all, at whatever opacity it happened to have.
            //
            // What that looked like: flick the card down and let go before it
            // reaches the bottom, and the queue's header, pills and list
            // vanished in one frame while the cover carried on shrinking toward
            // the pill for several hundred milliseconds. Two objects on
            // different clocks — the failure this transition was designed to
            // avoid, arriving by a route nobody was watching.
            //
            // Note what does *not* fix it: `BottomBarStyle.queue`'s own doc
            // suggests pointing it at `settle` if a collapse ever reads as two
            // objects. That addresses a spring-character mismatch. Here there
            // was no spring — the removal was not animated by anything.
            if newValue < 0.05, showingQueue {
                withAnimation(BottomBarStyle.queue) {
                    showingQueue = false
                }
            }
        }
        .allowsHitTesting(playback.currentTrack != nil)
        // Nothing is announced or focusable while the card is invisible —
        // without this a screen reader can still reach the "—" title, the
        // scrubber and the transport buttons of a card no one can see. See F4.
        .accessibilityHidden(playback.currentTrack == nil)
        .onChange(of: playback.currentTrack?.id) { _, id in
            if id == nil { collapse() }
        }
        // Drives `queueFactor` from `showingQueue`, in its own explicit
        // animation rather than inline with whatever transaction toggled the
        // boolean — see `queueFactor`'s doc comment for what was observed on
        // device about the ternary this replaced.
        // Fires for every path that sets `showingQueue`, including the
        // collapse-triggered reset above: at that point `progress` is already
        // under 0.05, where `artworkGeometry`'s response to `queueFactor` is
        // bounded and vanishing, not gated off — `width`/`height` scale
        // `queueFactor`'s effect by `progress` rather than by a cutoff, so a
        // full 0→1 swing still moves `width` by
        // `progress * (cardSize.width - queueThumbSide)`: on an iPhone
        // 17-sized card (~402pt-wide artwork, 44pt header slot) that is
        // ~18pt at `progress == 0.05`, not 0. The claim of no visible effect
        // is exact only at `progress == 0`, which is what
        // `testTheCollapsedPillIsUnchangedByTheQueueFactor` pins — below
        // that, animating `queueFactor` back to 0 here still nudges the
        // artwork, by an amount that shrinks toward 0 as `progress` keeps
        // falling.
        .onChange(of: showingQueue) { _, newValue in
            setQueueFactor(to: newValue ? 1 : 0)
            // **Nối bằng `completion`, không bằng hai con số cộng lại.**
            //
            // Hai khối chữ không được phép cùng đọc được. Diễn đạt điều đó bằng
            // `delay` là diễn đạt gián tiếp: nó đúng chỉ khi
            // `delay₂ ≥ delay₁ + duration₁`, một bất đẳng thức không nằm ở đâu
            // trong mã và vỡ ngay lần đầu ai đó chỉnh một trong ba số. Nó đã vỡ
            // vài lần ở đây.
            //
            // `completion` nói thẳng thứ tự: cái sau bắt đầu khi cái trước
            // **chạy xong**, kể cả phần `delay` của nó. Không còn phép trừ nào
            // để sai, và mỗi animation tự do đổi độ dài mà thứ tự vẫn đứng.
            //
            // Chiều mở và chiều đóng là nghịch đảo của nhau, không phải cùng
            // một cặp chạy ngược: mở thì chữ lớn nhường chỗ cho panel, đóng thì
            // panel nhường chỗ cho chữ lớn.
            if newValue {
                withAnimation(BottomBarStyle.queueTitleOut) {
                    queueTitleHidden = 1
                } completion: {
                    // Bấm đóng lại trước khi cú tan xong thì closure này vẫn
                    // nổ. Hỏi lại ý định hiện tại thay vì tin vào ý định lúc
                    // đăng ký.
                    guard showingQueue else { return }
                    withAnimation(BottomBarStyle.queueContentIn) {
                        queueContentReveal = 1
                    }
                    withAnimation(BottomBarStyle.queueContentSlide) {
                        queueContentSlide = 1
                    }
                }
            } else {
                withAnimation(BottomBarStyle.queueContentOut) {
                    queueContentReveal = 0
                    queueContentSlide = 0
                } completion: {
                    guard !showingQueue else { return }
                    withAnimation(BottomBarStyle.queueTitleIn) {
                        queueTitleHidden = 0
                    }
                }
            }
        }
        // Picking a track from a list opens the full player.
        //
        // Keyed on `explicitSelections`, NOT on `currentTrack` changing. The
        // track changes for reasons the user did not ask for and must not be
        // interrupted by: auto-advance when one finishes, Next from the lock
        // screen, a skip past a file that failed to load. Yanking the screen
        // open on any of those would be hostile — the phone is in a pocket for
        // most of them. `explicitSelections` counts only the one gesture that
        // means "show me this": a row tapped in a list.
        //
        // No `guard progress < 1`: `expand()` from an already-expanded card
        // animates 1 to 1, which is a no-op the spring resolves on its first
        // frame. Adding the guard would only skip work that costs nothing, and
        // would be one more branch to get wrong.
        .onChange(of: playback.explicitSelections) { _, _ in
            expand()
        }
    }

    /// - Parameter size: the *safe-area* size of the reader (not the full
    ///   screen — see the note on `outer` above).
    /// - Parameter insets: the reader's real safe-area insets.
    private func card(size: CGSize, insets: EdgeInsets) -> some View {
        let fullHeight = size.height + insets.top + insets.bottom
        // Same reconstruction as the height, mirrored horizontally: `size`
        // is the safe-area size, so in landscape (where the horizontal
        // insets are nonzero) `size.width` alone is narrower than the
        // screen. Every site that used to read `size.width` reads
        // `fullWidth` instead. See R1.
        let fullWidth = size.width + insets.leading + insets.trailing
        let fullSize = CGSize(width: fullWidth, height: fullHeight)
        let travel = max(fullHeight - Self.collapsedHeight, 1)
        let height = Self.collapsedHeight + travel * progress
        // The collapsed card is a floating pill inset from each edge of the
        // SAFE AREA; the expanded card still spans the whole display.
        //
        // The safe area, not the physical screen, and the two are not the same
        // space. This view reconstructs `fullWidth` and sits inside
        // `.ignoresSafeArea()`, so its own coordinates start at the physical
        // edge — but `FloatingTabBar`, whose row the pill has to slot into,
        // applies its `.padding(.horizontal, sideMargin)` OUTSIDE its
        // `GeometryReader` and never ignores the safe area, so the bar divides
        // up the *safe-area* width. Measuring the pill from the physical edge
        // therefore placed it `insets.leading`/`insets.trailing` outside the
        // slot the bar had reserved for it. In portrait those insets are 0 and
        // the two spaces coincide, which is why this looked correct; in
        // landscape on an iPhone 17 they are 59, and the minimised pill
        // overhung the leading circle and the search button by 59pt on each
        // side — and, being last in `RootView`'s `ZStack`, ate their taps,
        // including the only tap-to-restore affordance. Đợt A's Critical
        // defect again, in a supported orientation.
        //
        // **Leading and trailing are computed separately and never averaged.**
        // A single symmetric margin cannot express this: rotate a notched
        // device one way and the notch's inset lands on one side while the
        // other side gets only the rounded-corner allowance, so the two are
        // genuinely unequal. Averaging them, or taking `max`, would centre the
        // pill in a slot the bar has not centred and reintroduce the overhang
        // on one side at half the size — harder to see and no less wrong.
        //
        // Both are scaled by `(1 - progress)` and so are exactly 0 at
        // progress 1: `cardWidth == fullWidth` when expanded, the card still
        // reaches both physical edges, and every layout inside it is unchanged
        // there. Minimisation, like the pill margin it generalises, applies
        // only while the card is collapsed.
        let collapsedLeadingMargin = insets.leading + collapsedSideMargin
        let collapsedTrailingMargin = insets.trailing + collapsedSideMargin
        let leadingMargin = collapsedLeadingMargin * (1 - progress)
        let trailingMargin = collapsedTrailingMargin * (1 - progress)
        let cardWidth = fullWidth - leadingMargin - trailingMargin
        // The size everything laid out *inside* the card measures against.
        // Note this is deliberately NOT what `artworkHeight` below is given —
        // see the comment there.
        let cardSize = CGSize(width: cardWidth, height: fullHeight)
        // `fullSize`, never `cardSize`: this is the artwork's *expanded*
        // target side, which must not vary with `progress`. Feeding it the
        // interpolating `cardWidth` would make the artwork pulse through the
        // morph, and `loadArtwork` computes its decode target by calling
        // `artworkHeight(fullSize:)` from its own geometry — the two must
        // agree or the decoded image no longer matches what is drawn.
        let artworkSide = Self.artworkSide(fullSize: fullSize, topInset: insets.top)
        // Distinct from `travel` above: that one sizes the frame so it
        // still reaches exactly `fullHeight` at progress 1. This one is
        // only the pixel-to-progress divisor for the gesture below. The
        // card's top edge doesn't actually travel the full `travel`
        // distance — the bottom padding shortens the visible range by
        // `collapsedBottomOffset` (the tab bar, its gap below the screen edge,
        // and the gap between the bar and the pill — shrinking to just that
        // first gap as the pill joins the tab row) — so using `travel` there
        // made the card trail the finger by exactly that much. The same term
        // must appear here and in that padding, or they drift apart again —
        // which has now happened twice. See R2.
        //
        // `insets.bottom` used to be a third term in both, and is now in
        // neither. It was there while `collapsedBottomOffset` was measured from
        // the safe area and had to be converted into the physical coordinates
        // this view lays out in; the offset is measured from the screen now, so
        // the conversion is gone. Adding it back to one site alone puts the
        // card 34pt behind the finger on a phone with a home indicator and
        // leaves it exactly right on an iPhone SE — do not.
        //
        // The offset is not a constant somebody can forget to update in one of
        // the two places either: it moves continuously with `minimised` while
        // the user scrolls. That is why it is written once, as
        // `collapsedBottomOffset`, and read here and by the padding rather than
        // restated. Substituting the literal `playerBottomOffset` back into
        // either site puts the card 58pt behind the finger while minimised.
        //
        // The derivation that keeps them honest, with the card bottom-aligned
        // in a full-screen frame whose height this padding shortens, writing
        // `B` for `collapsedBottomOffset`, `H` for `fullHeight` and `C` for
        // `collapsedHeight`. The padding is applied outside that frame, so it
        // shortens the region rather than moving the card inside it: the
        // region's bottom, and hence the card's bottom, lands at H − B(1−p),
        // and the card's height is C + (H − C)p. Therefore
        //
        //   top(p) = H − B(1−p) − C − (H − C)p
        //   top(0) = H − B − C
        //   top(1) = H − C − (H − C) = 0
        //
        // Visible travel is top(0) − top(1) = H − C − B, which is exactly the
        // expression below, term for term, for *every* value of `B` and hence
        // of `minimised`. The slope is what the finger actually feels, and it
        // is constant rather than merely right at the ends:
        //
        //   d top / d p = B − (H − C) = −(H − C − B) = −dragTravel
        //
        // so one point of upward finger travel raises the card by exactly one
        // point at every progress, at either end of `minimised` and mid-morph.
        //
        // On an iPhone 17 (H 874, C 50, insets.bottom 34 — which appears
        // nowhere): at minimised 0, B 79, top(0) 745 and dragTravel 745; at
        // minimised 1, B 21, top(0) 803 and dragTravel 803. If you change one,
        // change the other.
        let dragTravel = max(
            fullHeight - Self.collapsedHeight - collapsedBottomOffset,
            1
        )

        return ZStack(alignment: .topLeading) {
            background
            // Behind the controls, not in front of them.
            //
            // It used to sit last, above `expandedContent`, and that was
            // harmless only because it covered the top of the card and the
            // controls lived below it — the order was never right, it just
            // never mattered. Once the picture filled the whole card it was
            // drawing over the scrubber, the transport row and the volume
            // slider, and its frost was hazing all three: the player looked
            // like something translucent had been laid over it.
            //
            // Disabling its hit testing fixed the touches and not the
            // appearance, because those are two different problems — one is
            // who receives a tap, the other is who is painted last.
            //
            // `QueuePanel` rides inside this view as an overlay, so it moves
            // back here too. That is correct: the panel occupies the region
            // above `contentOffset`, where the content stack begins, so the
            // two do not overlap and nothing needs to be painted over
            // anything.
            artworkView(size: cardSize, artworkSide: artworkSide, topInset: insets.top)
            miniChrome(width: cardWidth)
            // Tối chỉ trong phạm vi này. `\.colorScheme` là environment nên nó
            // đi **xuống**, khác `preferredColorScheme` vốn đi ngược lên cửa sổ
            // và kéo theo cả app — xem ghi chú ở `RootView`.
            expandedContent(size: cardSize, topInset: insets.top)
                .environment(\.colorScheme, .dark)
            grabber(topInset: insets.top)
        }
        .frame(width: cardWidth, height: height, alignment: .top)
        // Neo **đáy**: mép dưới viên pill phải đứng yên trong hàng nó vừa hạ
        // xuống, nên nó co lên trên và vào trong chứ không trôi khỏi hàng.
        //
        // `scaleEffect` chứ không sửa `collapsedHeight`: doc của
        // `collapsedArtworkInset` ghi rõ ba con số ấy đi cùng nhau, nên đổi
        // chiều cao là phải tính lại chỗ ô bìa chạm đường cong. Một phép biến
        // đổi đều thì co tất cả theo cùng tỉ lệ — bán kính bo, ô bìa, chữ — và
        // không có hằng số nào phải tính lại.
        .modifier(CardClip(progress: progress, insets: insets))
        // **Sau `CardClip`, không phải trước.** Đặt trước thì nội dung bị co
        // rồi mới cắt, và mặt nạ cắt vẫn ở kích thước khung chưa co — viên pill
        // mất luôn hình pill.
        //
        // Ở đây nó co **hình đã cắt xong**, như một vật: bán kính bo, ô bìa,
        // chữ, tất cả theo cùng một tỉ lệ. Đó cũng là lý do dùng `scaleEffect`
        // thay vì sửa `collapsedHeight` — xem `pillShrink`.
        //
        // Neo đáy: mép dưới đứng yên trong hàng viên pill vừa hạ xuống.
        .scaleEffect(pillShrink, anchor: .bottom)
        // Lifts the collapsed pill off the list behind it, with the same shadow
        // the tab bar's surfaces use — they share a screen, and while minimised
        // they share a row, so a lift on one and none on the other is visible
        // immediately. Shared rather than restated so a surface added later
        // cannot land with a slightly different one.
        //
        // Its colour, radius and offset are constant by design and must not be
        // interpolated with `progress`: this view moves every frame during a
        // drag, and animating a shadow forces a fresh offscreen pass each time.
        // No fade-out is needed — expanded, the card fills the screen and the
        // shadow is occluded anyway.
        .floatingBarShadow()
        // Positions the card horizontally. It cannot be centred in the frame
        // below any more: with `leadingMargin` and `trailingMargin` unequal —
        // which is exactly the landscape case this pair exists for — centring
        // would split the difference and put the pill in neither the slot the
        // bar reserved nor anywhere principled. Padding one side and aligning
        // to the other states the asymmetry directly: the card's leading edge
        // lands at `leadingMargin`, its trailing edge at `fullWidth -
        // trailingMargin`, whatever those two happen to be. When they are
        // equal (every portrait case) this is identical to the centring it
        // replaces.
        //
        // Inside the flexible frame, not outside it, for the same reason the
        // bottom padding is outside: this one must move the card *within* the
        // full-width region, while that one must shorten the region itself.
        .padding(.leading, leadingMargin)
        // The card is laid out bottom-aligned in a full-screen frame, and
        // hit-testing binds to *that* frame rather than to the card, so the
        // region's size is ours to choose instead of being whatever the card
        // currently measures. The frame still spans the full width — only the
        // alignment moved, from `.bottom` to `.bottomLeading`, so the padding
        // above resolves against the leading edge rather than being centred
        // away.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        // This line has now been wrong in BOTH directions, so read before you
        // touch it.
        //
        // Attached to the full-screen frame with a plain `Rectangle()`, a
        // collapsed card hit-tests the whole display and the library behind it
        // becomes untappable: rows expand the player instead of playing, the
        // toolbar `+` is unreachable, and the list neither scrolls nor swipes
        // to delete — from launch, since restoring persisted state sets a
        // current track. That was F1 (Critical).
        //
        // Attached to the card-sized view instead, the region SHRINKS WITH THE
        // CARD. During a collapse the card's top edge rises past the finger,
        // the finger falls outside the region, and the in-flight drag is
        // dropped and re-recognised — frames "held back", continuous flicker.
        // Expanding grows the card towards the finger and is unaffected, which
        // is why only collapsing stuttered. Four probes ruled out drawing
        // entirely: even a bare resizing `Rectangle` dropped frames.
        //
        // Both versions shared one assumption — that the region should track
        // the card's size. It must not. It keys on whether a drag is in
        // flight: while dragging (or whenever the card is off its collapsed
        // rest) the region is the whole screen and cannot shrink out from
        // under the finger; at collapsed rest it is exactly the bar, so the
        // library stays fully usable. Do not re-derive this height from
        // `progress` alone.
        //
        // The same reasoning governs the horizontal dimension, added with the
        // floating pill: at collapsed rest the region is inset by
        // `collapsedSideMargin` so the strips beside the pill fall through to
        // the library — without it, tapping near a screen edge expands the
        // player. But the inset must come from this same drag-state gate, NOT
        // from the interpolated `sideMargin`: derived from `progress` it would
        // narrow the region mid-drag and drop the finger sideways, exactly the
        // failure described above in the vertical direction.
        //
        // `collapsedSideMargin` widens 12 -> 76 with `minimised`, and the rest
        // inset must follow it. Left at the bare `pillSideMargin`, a minimised
        // player hit-tests the full width of the row and swallows both the
        // leading circle and the search button — Đợt A's Critical defect, one
        // layer down. Note this changes only the region's *horizontal extent at
        // rest*: `minimised` is not `progress`, it does not move during a drag,
        // and the `isDragging || progress > 0` gate on all three dimensions is
        // untouched, so the region is still the whole screen for the entire
        // duration of a drag.
        //
        // The two sides are passed separately and read the *collapsed* margins,
        // not `leadingMargin`/`trailingMargin`: those carry the `(1 - progress)`
        // factor, and a region that narrows with `progress` would drop the
        // finger sideways mid-drag — the failure described above, in the
        // horizontal direction. These two are functions of `minimised` and the
        // safe area only. They must match the card's own edges exactly, or the
        // region and the pill disagree about where the pill is.
        //
        // Moving the bar's anchor from the safe area to the screen changed
        // nothing here, and that is worth stating rather than leaving to be
        // rediscovered. The horizontal insets read `collapsedSideMargin`, which
        // is still safe-area-relative because the tab bar still divides up the
        // safe-area width — they took the 12 -> 21 change through
        // `pillSideMargin` and needed nothing else. The vertical dimension
        // follows the anchor on its own: `BottomHitRegion` measures `height` up
        // from `rect.maxY`, and `rect` is the frame the bottom padding below
        // shortens, so the region's bottom edge *is* the card's bottom edge at
        // whatever the offset now says — which is exactly why that padding has
        // to stay outside this frame.
        .contentShape(
            BottomHitRegion(
                height: isDragging || progress > 0 ? fullHeight : Self.collapsedHeight,
                leadingInset: isDragging || progress > 0 ? 0 : collapsedLeadingMargin,
                trailingInset: isDragging || progress > 0 ? 0 : collapsedTrailingMargin
            )
        )
        // `.subviews` chứ không phải tắt hẳn: cử chỉ của chính thẻ ngừng nhận,
        // nhưng mọi thứ bên trong — kể cả hai recogniser của danh sách hàng đợi
        // — vẫn chạy. Tắt hẳn sẽ giết luôn cú kéo đang diễn ra.
        .gesture(
            drag(travel: dragTravel, threshold: Self.dragThreshold(progress: progress)),
            including: queueIsReordering ? .subviews : .all
        )
        .onTapGesture { if progress < 0.5 { expand() } }
        // At progress 0 this holds the card's bottom `collapsedBottomOffset`
        // above the **physical** bottom edge, so the pill floats clear of the
        // floating tab bar — which is anchored to that same edge — and matches
        // where every list's `clearsBottomBar` spacer stops; or, once
        // minimised, drops onto the tab row itself. At progress 1 it goes to 0
        // so the expanded card reaches the physical bottom edge. See F3.
        // `dragTravel` above subtracts exactly this same term, reading the very
        // same `collapsedBottomOffset` — see the note there. No `insets.bottom`
        // in either: this view lays out in physical coordinates and the offset
        // is already stated in them.
        //
        // It must stay *outside* the frame and the hit region above. Applied
        // here it shortens the height proposed to that frame, so the frame's
        // bottom edge lands exactly where the card's bottom edge is, and
        // `BottomHitRegion` — which measures up from `rect.maxY` — lines up
        // with the collapsed bar. Moved inside (padding the card itself), the
        // frame would still span the full screen and the collapsed region
        // would sit `insets.bottom` too low, missing the top of the bar.
        .padding(.bottom, collapsedBottomOffset * (1 - progress))
    }

    /// The bottom `height` points of whatever it is applied to, inset by
    /// `leadingInset` and `trailingInset` on the respective sides.
    ///
    /// Used instead of `Rectangle()` so the hit region's size can be chosen
    /// by state rather than inherited from the card's current size. See the
    /// note at the `.contentShape` call site.
    ///
    /// The two insets are separate rather than one `horizontalInset` because
    /// the safe area they now include is not symmetric: in landscape on a
    /// notched device one side carries the notch's inset and the other does
    /// not. A single number would have to average them and would leave the
    /// region overhanging the tab bar's circles on one side.
    ///
    /// `path(in:)` has no access to the environment, so `leadingInset` is
    /// applied at `rect.minX` — correct under a left-to-right layout, which is
    /// the only direction this app currently ships. If it is ever localised
    /// right-to-left the card's own `.padding(.leading, …)` would flip and this
    /// would not, so the two would have to be reconciled here.
    private struct BottomHitRegion: Shape {
        var height: CGFloat
        var leadingInset: CGFloat
        var trailingInset: CGFloat

        func path(in rect: CGRect) -> Path {
            Path(
                CGRect(
                    x: rect.minX + leadingInset,
                    y: rect.maxY - height,
                    width: rect.width - leadingInset - trailingInset,
                    height: height
                )
            )
        }
    }

    // MARK: - Pieces

    private var background: some View {
        ZStack {
            // Lớp nền đục cộng lớp sương, cả hai đọc **giá trị đang được vẽ**
            // chứ không phải giá trị đích. Toàn bộ lý lẽ, và số đo từ video cú
            // thu nhỏ của người dùng, nằm ở doc của `CardSurface`.
            //
            // Lớp nền tồn tại vì hai lớp trên hoà vào nhau bằng opacity, mà
            // opacity **hợp thành** chứ không cộng — không có nó thì tấm thẻ
            // trong suốt suốt quãng giữa cú morph (F4). Nó chỉ vắng mặt ở
            // `progress` 0, nên viên thuốc lúc nghỉ vẫn là một mặt sương nhìn
            // thấy danh sách phía sau chứ không phải một mảng xám phẳng. Xem R3.
            CardSurface(progress: progress)
            LinearGradient(
                // **Bám theo vệt tan của bìa, không phải trải đều cả thẻ.**
                //
                // Dải này giữ nguyên màu trội cho tới hết chỗ tấm bìa tan —
                // `1 − artworkFadeFraction` tính từ đỉnh thẻ — nên ở chỗ nối, màu dưới bìa đúng bằng màu của
                // chính bìa và không có bậc nào để mắt bắt. Từ đó mới tối dần
                // xuống đáy.
                //
                // Trước đây nó nội suy thẳng từ đỉnh xuống đáy, nên ngay dưới
                // tấm bìa màu đã nhạt đi đáng kể và chỗ nối lộ ra thành một
                // đường ngang.
                stops: Self.tintStops(
                    tint: Self.queueBackdrop(tintColour, queueFactor: queueFactor),
                    base: Self.queueBackdrop(hasArtwork ? Color(.systemGroupedBackground)
                                                        : Self.artworklessBase,
                                             queueFactor: queueFactor),
                    // Chỗ giữ màu chỉ có nghĩa khi tấm bìa tràn đang nằm trên
                    // nó. Mở hàng đợi thì bìa co về ô 44pt trong header, dải
                    // này thành nền chính — và giữ nguyên màu trội tới 75% chỗ
                    // ấy biến cả màn thành một mảng nâu, chữ trong danh sách
                    // chìm hẳn. `queueFactor` kéo chỗ giữ về 0 để nó trở lại
                    // một dốc màu bình thường.
                    hold: Self.tintHoldLocation * (1 - queueFactor),
                    // Không bìa thì không có gì để hoà vào: `tintColour` lúc
                    // đó là màu nền hệ thống, và giữ nó rồi lại tối dần chỉ
                    // tạo ra một dải xám vô nghĩa.
                    fullBleed: hasArtwork
                ),
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(progress)
            // Darkens everything below the artwork so the controls stay
            // readable.
            //
            // Needed now that the background is the cover rather than a colour
            // this view chose: a pale cover would otherwise put white text — the
            // card's own chrome is forced dark (`expandedContent` đặt
            // `\.colorScheme`) — on a pale
            // field. The first build anchored this at `.center`, which measured
            // wrong: the title sits *above* the card's midpoint, so it got no
            // darkening at all and sat white on bright green.
            //
            // Starts at 0.42 — just above where the artwork ends on a phone in
            // portrait — so the ramp is already underway by the time the title
            // arrives. Beginning it inside the artwork rather than at its edge
            // is deliberate: a ramp that starts exactly where the artwork stops
            // puts a slope change at the same line the mask is dissolving, and
            // that is how the crease got there in the first place. Up here the
            // alpha is still near zero, so the change of slope has nothing to
            // show.
            // Three stops, because two were not enough where it mattered. A
            // straight ramp from 0.42 to 0.5 black at the bottom is still under
            // 8% black at 0.50, which is where the title sits — measured off a
            // screenshot, the title looked no different with the ramp than
            // without it. The middle stop front-loads the darkening so the
            // controls get most of it, and the tail keeps going for the volume
            // and repeat rows below.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.38),
                    .init(color: .black.opacity(0.35), location: 0.56),
                    .init(color: .black.opacity(0.6), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(progress)
        }
    }

    /// The artwork's average colour, or the plain background when there is no
    /// artwork to take one from.
    ///
    /// Only reached when there is no cover at all; with one, the background is
    /// the blurred cover itself and no averaged colour is involved.
    private var tintColour: Color {
        tint ?? Self.artworklessTint
    }

    /// Nền cho bài **không có bìa**, và nó là một màu cố định chứ không phải
    /// `systemGroupedBackground`.
    ///
    /// Chrome của thẻ mở bị ép `\.colorScheme = .dark` — chữ trắng, glyph
    /// trắng. `systemGroupedBackground` thì phân giải theo chế độ của *hệ
    /// thống*: ở chế độ sáng nó gần trắng, nên cả màn hình thành chữ trắng trên
    /// nền trắng. Đó là thứ nhìn thấy trong ảnh chụp gửi tới trước đó, và là
    /// khác biệt lớn nhất so với Apple Music — player không-bìa của họ là một
    /// mảng xám tối đều, ở cả hai chế độ.
    ///
    /// **Đen tuyền, và dải nền cố tình phẳng.** Câu ở đây từng viết "hai màu
    /// chứ không một: đỉnh sáng hơn đáy một chút, nên dải nền vẫn có chiều sâu
    /// thay vì là một mảng phẳng" — 0.26 xuống 0.13. Chiều sâu ấy là chiều sâu
    /// của một thứ không có gì để mà sâu: dốc màu trong thẻ có bìa tồn tại để
    /// hoà từ tấm bìa xuống nền, và bài không bìa thì không có tấm bìa nào ở
    /// đầu dốc. Cái còn lại chỉ là một mảng xám hơi loang, đọc ra như nền chưa
    /// tải xong.
    ///
    /// Đen thật thì mảng ấy đọc ra như một quyết định. Trên màn OLED nó cũng
    /// tắt điểm ảnh thật, nên viền thẻ biến mất vào thân máy thay vì hiện ra
    /// thành một hình chữ nhật xám nổi trên nền đen của hệ thống.
    ///
    /// Ô placeholder của tấm bìa vẫn xám (`placeholderTileBrightness` 0.38, tính
    /// từ sắc màu này) — nó phải nhìn thấy được, nếu không thì chỗ đáng lẽ có
    /// bìa trở thành một lỗ hổng không đọc ra là gì.
    private static let artworklessTint = Color.black

    /// Một pixel trong suốt, để ô bìa luôn có **một** tấm `Image` trong cây kể
    /// cả khi chưa có gì để vẽ. Xem chú thích ở chỗ dùng trong `artworkView`
    /// về việc vì sao định danh view là thứ phải giữ.
    ///
    /// `1×1` và `.resizable().scaledToFill()`: kéo một pixel trong suốt ra cỡ
    /// màn hình không vẽ gì và không tốn gì — không có kênh alpha nào khác 0 để
    /// hợp thành.
    static let transparentPixel: UIImage = {
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: 1, height: 1),
            format: {
                let format = UIGraphicsImageRendererFormat.default()
                format.opaque = false
                format.scale = 1
                return format
            }()
        )
        return renderer.image { _ in }
    }()


    /// Ô placeholder của tấm bìa: cùng sắc màu với nền, sáng hơn một bậc.
    ///
    /// Một bậc nhỏ hơn `queueSurface` (0.38 so với 0.50): đây là một mảng lớn
    /// chiếm gần cả bề ngang thẻ, không phải một tấm giấy nhỏ đặt lên. Cùng
    /// một độ chênh, mảng càng lớn càng kêu.
    static func placeholderTile(_ tint: Color) -> Color {
        guard let hsb = Self.hsb(tint) else { return tint }
        return Color(UIColor(hue: hsb.hue,
                             saturation: hsb.saturation,
                             brightness: Self.placeholderTileBrightness,
                             alpha: 1))
    }

    /// 0.38 → 0.28, sau khi nền bài không-bìa chuyển sang đen tuyền.
    ///
    /// Con số cũ được chọn khi nền còn là dốc xám 0.26→0.13, và một ô 0.38 trên
    /// nền ấy là chênh vừa phải. Trên nền đen thì cùng con số ấy thành mảng sáng
    /// nhất màn hình — mắt đi thẳng vào một ô trống, đúng thứ đáng lẽ phải lùi
    /// lại phía sau.
    ///
    /// Không hạ sâu hơn, và đây là chỗ dễ quá tay: ô này cũng là thứ nhìn thấy
    /// trong khoảnh khắc bài CÓ bìa đang giải mã. Hạ tới gần đen thì khoảnh khắc
    /// ấy thành một cú tối sập rồi ảnh loé lên — tệ hơn hẳn một ô hơi sáng.
    private static let placeholderTileBrightness: CGFloat = 0.28
    /// Đáy dải, bằng đúng đỉnh — xem `artworklessTint` về lý do phẳng.
    private static let artworklessBase = Color.black

    /// Between the safe area and the grabber capsule's own top edge.
    ///
    /// Named so `QueuePanel`'s header clearance (see `artworkView`) can read
    /// the same gap instead of restating it — the two sit one above the
    /// other at the top of the same card and must not drift apart the way
    /// `BottomBarMetrics`' doc warns the bottom-edge measurements did.
    private static let grabberTopGap: CGFloat = 8
    /// The grabber capsule's own height.
    private static let grabberHeight: CGFloat = 5

    /// How far `QueuePanel` is inset from each side of the card.
    private static let queuePanelSideMargin: CGFloat = 24

    /// Hints that the expanded card can be dragged away, the way the
    /// `.sheet` this replaced showed `.presentationDragIndicator(.visible)`.
    /// Fades in with `progress` so it is invisible while collapsed. See F8.
    private func grabber(topInset: CGFloat) -> some View {
        Capsule()
            .fill(Color.secondary)
            .opacity(0.4)
            .frame(width: 36, height: Self.grabberHeight)
            .padding(.top, topInset + Self.grabberTopGap)
            .frame(maxWidth: .infinity, alignment: .top)
            .opacity(progress)
            .allowsHitTesting(false)
    }

    private func miniChrome(width: CGFloat) -> some View {
        MiniPlayerChrome(
            playback: playback,
            minimised: minimised,
            // The artwork's centre, which the row's trailing inset mirrors —
            // derived here because these two constants are private to this
            // type, and restating either of them there would let the two ends
            // of the pill drift apart the moment one of them moved.
            artworkCentreInset: Self.collapsedArtworkInset + Self.collapsedArtwork / 2
        )
            // Derived rather than a literal so the text cannot drift out of
            // step with the artwork: this is where the artwork ends, plus the
            // gap. The old `collapsedArtwork + 24` folded the inset and the
            // gap into one number, so moving the artwork silently changed the
            // gap instead of moving the text with it.
            .padding(.leading, Self.collapsedArtworkInset + Self.collapsedArtwork + Self.collapsedArtworkGap)
            // The trailing inset moved into `MiniPlayerChrome`: it depends on
            // which button is last, and that now changes with `minimised`.
            .frame(width: width, height: Self.collapsedHeight)
            // The whole row takes the long press, not just the words.
            //
            // Same rule the tab bar's slots needed: a `.frame` is layout and
            // draws nothing, so without this the menu would only open on the
            // title and artist text and feel broken everywhere else on the pill.
            .contentShape(Rectangle())
            // Stopping lives here rather than on a visible control.
            //
            // There was no way to end playback at all: `stopPlayback()` only
            // ever ran when the queue emptied itself, so the pill stayed for the
            // rest of the session. Apple Music has no equivalent either — its
            // mini player persists and pause is the end state — and the HIG says
            // nothing about dismissing one, so this is a deliberate departure.
            //
            // A long press, not a swipe. It discards the queue and the position
            // for real, and the pill is a 54pt strip the thumb passes over
            // constantly; a horizontal swipe would lose someone's place by
            // accident, and there is no undo to offer them. A context menu is
            // also what the platform already uses for infrequent destructive
            // actions on a row, so it needs no explaining.
            .contextMenu {
                Button(role: .destructive) {
                    playback.stop()
                } label: {
                    Label("Dừng phát", systemImage: "stop.fill")
                }
            }
            .opacity(max(0, 1 - progress * 3))
            .allowsHitTesting(progress < 0.1)
    }

    /// Tên bài và nghệ sĩ bám theo **mép dưới tấm bìa** trên đường bìa co về
    /// header, rồi tan đi ở đoạn cuối.
    ///
    /// Mép dưới, không phải tâm: ở trạng thái nghỉ khối chữ nằm ngay dưới tấm
    /// bìa, nên bám mép dưới giữ đúng khoảng cách người ta đang nhìn thấy. Bám
    /// tâm thì chữ tụt lại phía sau một nửa chiều cao bìa và cặp đôi ấy rời ra
    /// giữa chừng.
    ///
    /// Hiệu số của hai lần gọi cùng một hàm hình học, khác nhau đúng một tham
    /// số — nên nó không thể lệch khỏi đường bay của tấm bìa dù đường ấy có đổi.
    ///
    /// **Giảm chuyển động: 0, và không có nửa đường nào ở giữa.** Quãng này là
    /// một phần của cú bay đã bị bỏ đi ở `setQueueFactor(to:)` — cả đoạn văn
    /// trên nói về việc bám theo mép dưới tấm bìa *đang đi*, mà tấm bìa không
    /// còn đi nữa. Giữ lại thì khối chữ là vật duy nhất trên màn hình còn trượt
    /// vài trăm điểm, đuổi theo một thứ đã tới đích từ khung đầu.
    ///
    /// Khối chữ vẫn **tan** đúng như cũ: `titleOpacity` chạy trên
    /// `queueTitleHidden`, không trên quãng này, nên hai khối chữ vẫn không bao
    /// giờ cùng đọc được và thứ tự khi đóng vẫn là nghịch đảo của chiều mở.
    private func queueTitleTravel(size: CGSize, topInset: CGFloat) -> CGFloat {
        guard !BottomBarStyle.reduceMotion else { return 0 }
        guard queueFactor > 0 else { return 0 }
        func bottom(_ factor: Double) -> CGFloat {
            let geometry = Self.artworkGeometry(
                progress: progress,
                queueFactor: factor,
                cardSize: size,
                fullBleed: hasArtwork,
                artworkSide: Self.artworkSide(fullSize: size, topInset: topInset),
                artworkTop: Self.artworkTop(topInset: topInset),
                queueThumbCentre: Self.queueThumbCentre(topInset: topInset),
                queueThumbSide: QueuePanel.headerArtwork
            )
            return geometry.centre.y + geometry.height / 2
        }
        // **Chỉ đi một phần quãng đường ấy.**
        //
        // Đo ở Apple Music: khối chữ lớn của họ chạy 488 → 275 trong bốn khung,
        // tức 57% quãng đường, trong khi tấm bìa đã đi 76%. Chữ **đi chậm hơn**
        // tấm bìa, không bám cứng vào nó.
        //
        // Và đó không phải chi tiết trang trí. Bám cứng thì tới lúc tan, khối
        // chữ đã lên gần sát chỗ chữ header sắp hiện — hai bóng chữ mờ ở cùng
        // một chỗ, đọc ra là lệch pha ngay cả khi trên trục thời gian chúng
        // không lấn nhau. Đi chậm hơn thì nó tan khi còn ở giữa màn hình, và
        // chỗ ấy trống.
        return (bottom(queueFactor) - bottom(0)) * Self.queueTitleTravelShare
    }

    /// Xem `queueTitleTravel`.
    private static let queueTitleTravelShare: CGFloat = 0.7

    private func expandedContent(size: CGSize, topInset: CGFloat) -> some View {
        NowPlayingContent(
            playback: playback,
            showingQueue: $showingQueue,
            titleTravel: queueTitleTravel(size: size, topInset: topInset),
            titleOpacity: 1 - queueTitleHidden
        )
            .padding(.horizontal, 24)
            .frame(width: size.width)
            // Measured from the card's bottom, not from the artwork — see
            // `contentOffset(fullSize:)`. The artwork reaches down behind this,
            // dissolved to almost nothing by the time it arrives.
            .offset(y: Self.contentOffset(fullSize: size))
            .opacity(max(0, (progress - 0.5) * 2))
            .allowsHitTesting(progress > 0.9)
    }

    /// Space between the grabber's bottom edge and `QueuePanel`'s header,
    /// once the header has cleared the safe area and the grabber above it.
    /// Purely a breathing-room number — the safe-area and grabber terms
    /// above it are the ones that actually vary by device.
    private static let queuePanelHeaderGap: CGFloat = 12

    /// - Parameter topInset: the real top safe-area inset from
    ///   `card(size:insets:)`'s `GeometryReader` — **not** a literal 44 or
    ///   59. Devices differ (notch vs. no notch, portrait vs. landscape on a
    ///   Dynamic Island phone), the same reason `BottomBarMetrics` takes
    ///   `bottomSafeAreaInset` as a parameter rather than assuming one.
    ///   Used only to pad `QueuePanel` below; the artwork itself reads
    ///   neither this parameter nor any safe-area term, so its own framing
    ///   is untouched by queue mode.
    private func artworkView(size: CGSize, artworkSide: CGFloat, topInset: CGFloat) -> some View {
        // The queue panel's own horizontal inset, named because two things
        // depend on it: the panel's `.padding(.horizontal,)` below, and the
        // header slot's centre computed here. A literal in both places is two
        // numbers that must agree and nothing to notice when they stop.
        let sideMargin = Self.queuePanelSideMargin
        // The panel's own top offset, `queuePanelHeaderGap` folded in — see
        // `queuePanelTop`'s doc comment. Read once, here, and used again at
        // the `.padding(.top,)` call site below instead of re-derived
        // there: that re-derivation is what used to drop the gap from the
        // point the artwork animates to while keeping it in the panel's own
        // padding, landing the cover 12pt above the header it was aiming
        // for.
        let panelTop = Self.queuePanelTop(topInset: topInset)
        let geometry = Self.artworkGeometry(
            progress: progress,
            // `queueFactor`, not `showingQueue ? 1 : 0` — see that property's
            // doc comment for why the mask needs a genuinely animated number
            // here rather than a ternary re-evaluated at two discrete points.
            queueFactor: queueFactor,
            cardSize: size,
            // The card's whole height, not `artworkHeight`.
            //
            // **One picture, not two.** A separate full-screen blurred layer
            // behind a sharp cover drew the same image twice, and where the
            // cover dissolved you could see it begin again underneath — a
            // visible repeat, which is precisely what the reference does not
            // do: Apple Music's player is a single photograph filling the top
            // of the screen and blurring into the dark as it descends.
            //
            // So this layer *is* the backdrop. It fills the card; `scaledToFill`
            // then crops it at the bottom rather than at the sides, where the
            // frost and the darkening overlay are already hiding it, and the
            // top of the cover stays sharp and uncropped — the part anyone
            // actually looks at.
            //
            // It also makes the queue transition read the way it was asked to.
            // The whole screen shrinks into the header slot, because the whole
            // screen is now this one view.
            fullBleed: hasArtwork,
            artworkSide: artworkSide,
            artworkTop: Self.artworkTop(topInset: topInset),
            // The header slot, derived from constants rather than measured: a
            // measurement would depend on a layout pass that has not run on
            // the first frame of the transition.
            queueThumbCentre: Self.queueThumbCentre(topInset: topInset),
            queueThumbSide: QueuePanel.headerArtwork
        )
        let width = geometry.width
        let height = geometry.height
        let centre = geometry.centre

        // Decided from the model, not from the loaded image — see `source(_:_:)`
        // for why, and for the bug that rule fixes.
        let shown = displayedArtwork
        let source = Self.source(hasArtwork: hasArtwork, loaded: shown != nil)

        return ZStack {
            // Drawn in every one of the three states, so moving between them
            // never tears down the layer underneath. The fill is what the cover
            // covers and what the glyph sits on; only the layer above it
            // changes, which is a content change rather than a structural one.
            //
            // **Một màu phẳng, đục hẳn.**
            //
            // Trước đây là `tertiarySystemFill` trộn dần sang màu mặt phẳng
            // theo `queueFactor`. Cái trộn ấy tồn tại để cứu đúng một tình
            // huống: hàng đợi đóng, bài không bìa, hệ thống ở chế độ sáng —
            // lúc ấy nền là `systemGroupedBackground` gần trắng nên màu hệ
            // thống mới đúng.
            //
            // Tình huống ấy không còn: nền của bài không bìa giờ là
            // `artworklessTint`, tối ở cả hai chế độ. Nên không còn gì để trộn
            // giữa, và một mảng `tertiarySystemFill` bán trong suốt ở đây chỉ
            // còn là một lớp đục mờ cho thấy nền phía sau — đọc ra là bẩn, chứ
            // không ra là một tấm bìa vắng mặt.
            //
            // Bám sắc màu của bài, không phải một màu xám gõ tay: với bài có
            // bìa đang giải mã, lớp này là thứ nhìn thấy trong khoảnh khắc
            // trước khi ảnh tới, và một mảng xám ở đó nhấp nháy sai màu.
            Rectangle().fill(Self.placeholderTile(tintColour))

            // **Luôn gắn, không bao giờ chèn.** Một `if source == .image` ở đây
            // là một rẽ nhánh **cấu trúc**, và cú giải mã ghi `artwork` bằng
            // một cú ghi `@State` trần từ `loadArtwork` — nên tấm ảnh được
            // *chèn* vào cây giữa lúc cú morph đang bay, và SwiftUI dựng nó ở
            // hình học **đích** vì một view vừa chèn không có giá trị "từ đâu"
            // để nội suy.
            //
            // Đo được, `PlayerCardColdArtworkArrivalTests`, bìa lạnh chưa từng
            // giải mã trong tiến trình: dải mốc trên tấm bìa hiện ra ở đúng
            // 380–463pt — vị trí **cuối cùng** của nó — trong khi mép trên tấm
            // thẻ còn ở 120pt, tức progress 0,83. Vẽ theo khung thẻ lúc ấy thì
            // dải phải ở 446–518pt. Tấm bìa không lớn lên cùng thẻ; nó đứng sẵn
            // ở đích và được tấm thẻ đang lớn dần hé ra. Người dùng báo đúng
            // chuyện này: *"như kiểu ảnh có sẵn, chỉ có player bung"*, và doc
            // của `ArtworkStore.anyCachedImage` đã gọi tên nó từ trước —
            // *"the cover failing to grow with the card"*.
            //
            // Đây là **cùng một lỗi** mà `source(hasArtwork:loaded:)` ở trên đã
            // sửa một tầng, chỉ là còn sót một tầng nữa: ở đó cú rẽ nhánh giữa
            // *ô placeholder* và *tấm bìa* được chuyển từ `loaded` (bất đồng
            // bộ) sang `hasArtwork` (đồng bộ); ở đây cú rẽ nhánh giữa *chưa có
            // ảnh* và *có ảnh* vẫn còn treo vào `loaded`.
            //
            // Một pixel trong suốt thay cho `nil`, chứ không phải `.opacity(0)`
            // trên một nhánh vẫn có `if`: thứ phải giữ nguyên là **định danh**
            // của view, và chỉ có việc luôn dựng ra đúng một `Image` mới giữ
            // được nó. Nội dung đổi từ pixel trong suốt sang tấm bìa là một
            // thay đổi *nội dung*, và SwiftUI không tháo gì ra để làm nó.
            Image(uiImage: shown ?? Self.transparentPixel)
                .resizable()
                .scaledToFill()

            if source == .placeholder {
                // `.font(size:)` isn't animatable, so during the expand spring
                // the glyph would otherwise jump to its final size immediately
                // while the surrounding frame is still interpolating. Render it
                // at a fixed base size and use `.scaleEffect`, which does
                // animate, to track `side` continuously. Ratio matches
                // ArtworkThumbnail's placeholder (size * 0.5). See F6.
                Image(systemName: "music.note")
                    .font(.system(size: Self.placeholderGlyphBase * 0.5))
                    // Trắng 0.62, không phải `.secondary`. Nốt nhạc nằm trên
                    // một mảng có độ sáng đã biết (`placeholderTileBrightness`),
                    // nên độ tương phản là thứ tính được chứ không phải thứ để
                    // môi trường quyết — và `.secondary` ở chế độ sáng cho một
                    // nốt xám đậm trên mảng ấy, gần như không thấy.
                    .foregroundStyle(.white.opacity(0.62))
                    .scaleEffect(min(width, height) / Self.placeholderGlyphBase)
                    // **`scaleEffect` không đổi kích thước layout.**
                    //
                    // Nốt nhạc vẽ ở `font(size: 140)` nên nó CHIẾM một hộp 140pt
                    // dù được thu nhỏ tới đâu. Trong thẻ mở rộng thì vừa. Trong
                    // player thu nhỏ, ô bìa chỉ khoảng 40pt, và một hộp 140pt
                    // nằm trong đó lấn ra ngoài — nốt nhạc tràn khỏi ô bìa và
                    // đẩy hàng chữ bên cạnh.
                    //
                    // `.frame` ở đây ghim layout về đúng cạnh ô bìa. Nó không
                    // cắt gì: nốt vẽ ra đúng `min(w,h) * 0.5` nên vẫn nằm gọn
                    // bên trong. Và nó giữ được `scaleEffect` — thứ có hoạt hoá
                    // được, lý do cả khối này không dùng `.font(size:)` tính
                    // thẳng từ cạnh.
                    //
                    // Cùng loại bẫy với ghi chú `clipped()` trong
                    // `MiniPlayerChrome`: glyph không co theo `.frame` bọc ngoài.
                    .frame(width: min(width, height), height: min(width, height))
            }
        }
        .frame(width: width, height: height)
        // Frosts the picture progressively as it descends, so one photograph
        // goes from sharp at the top to soft at the bottom rather than being
        // sharp everywhere and then simply ending.
        //
        // **A gradient-masked material, not `.blur(radius:)`.** A real blur is
        // an offscreen pass over this view on every frame, and this is the one
        // view in the card that moves *and* resizes on every frame of a drag —
        // the same argument that stopped its shadow being interpolated, and the
        // same class of cost that had `AmbientMesh` removed after Instruments
        // traced 81% of the app's dropped frames to it. A material is composited
        // by the same machinery that draws the system's own chrome, and masking
        // it costs a gradient.
        //
        // Clear until 0.30 so the top of the cover is untouched, fully frosted
        // by 0.72 — before the dissolve below begins in earnest, so the two read
        // as one continuous softening rather than two effects taking turns.
        //
        // `shapeProgress`, so the collapsed pill's thumbnail and the queue's
        // 54pt slot are not frosted: both are small, sharp objects, and this is
        // a treatment for a picture the size of a screen.
        .overlay {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.30),
                            .init(color: .white.opacity(0.55), location: 0.52),
                            .init(color: .white, location: 0.72)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                // Cùng lý do cú tan ở mép dưới đã được gác bằng `hasArtwork`:
                // đây là cách xử lý cho một **bức ảnh** cỡ màn hình, không cho
                // một mảng màu phẳng. Trên khối vuông placeholder nó chỉ là một
                // dải sương chạy dọc — một gradient trên thứ đáng ra không có
                // gradient nào, và là thứ duy nhất còn sót lại làm ô bìa mặc
                // định trông không phẳng.
                .opacity(hasArtwork ? geometry.shapeProgress : 0)
                .allowsHitTesting(false)
        }
        // Dissolves the artwork's bottom edge into the background colour
        // beneath it as the card opens.
        //
        // An overlay, deliberately, and not a `.mask`. A mask forces an
        // offscreen pass over this view every frame, and this is the one view
        // in the card that moves *and* resizes on every frame of a drag — the
        // same reason its shadow had to stop being interpolated. Painting the
        // background's own colour on top costs nothing and is
        // indistinguishable, because the colour is the same on both sides of
        // the seam: `background` holds `tintColour` flat down to
        // `backgroundTintHold`, which is below where the artwork ends.
        //
        // A mask, so the artwork genuinely becomes transparent at its bottom
        // and the drifting colour field behind it shows through.
        //
        // This was an overlay painting flat `tintColour`, chosen because an
        // overlay costs nothing while a mask forces an offscreen pass. That
        // reasoning held only while the thing underneath was a single colour a
        // vertical gradient could reproduce. The mesh behind it varies
        // horizontally as well, and no vertical gradient can match it — an
        // overlay would paint a uniform band across a field that is not
        // uniform, and put back a visible edge on the other side of the seam.
        //
        // The cost is real and accepted: one offscreen pass over the artwork
        // per frame during the drag. It buys the only thing that removes the
        // crease. If it ever measures badly, the answer is to stop compositing
        // this per frame — not to go back to painting over it.
        //
        // Every stop collapses to location 1 at progress 0, making the whole
        // mask opaque white — so the collapsed pill's thumbnail is untouched,
        // with no view inserted or removed mid-morph to pop.
        // Cú tan chỉ thuộc về đường tràn màn hình: nó tồn tại để hoà mép dưới
        // vào nền. Khối vuông có mép rõ, không có gì để hoà, và một cú tan
        // trên nó chỉ làm bìa trông như bị mờ.
        .mask(
            Group {
                if hasArtwork {
                    LinearGradient(
                        stops: Self.dissolveStops(progress: geometry.shapeProgress),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                } else {
                    Color.white
                }
            }
        )
        // Interpolates to a square corner as it opens: the expanded artwork is
        // full-bleed, and a rounded corner floating against the screen's own
        // rounded corner reads as a mistake. The card's `clipShape` supplies
        // the top corners at that point.
        //
        // Reads `geometry.shapeProgress`, not `progress`: while the queue is
        // open this is 0 even at full expansion, so the artwork stays rounded
        // like the 44pt thumbnail it has become instead of squaring off like
        // a full-bleed cover.
        // Tràn màn hình thì góc phải về 0 — một góc bo lơ lửng cạnh góc bo của
        // chính màn hình đọc ra như lỗi. Khối vuông thì ngược lại: bán kính
        // **tăng** theo cú mở, đúng như một tấm bìa lớn dần.
        .clipShape(
            RoundedRectangle(
                cornerRadius: hasArtwork
                    ? width * 0.12 * (1 - geometry.shapeProgress)
                    : width * 0.12
                        + (Self.expandedArtworkCorner - width * 0.12) * geometry.shapeProgress,
                style: .continuous
            )
        )
        // Constant, for the same reason the card's own shadow is constant —
        // see the note at `.floatingBarShadow()` above. This was
        // `radius: 10 * progress, y: 4 * progress`, which broke that rule on
        // the one view in the card that has it worst: the artwork changes
        // *size* every frame as well as position, so an interpolated shadow
        // could not be cached between frames even in principle. It had to be
        // regenerated from scratch, 36pt to 280pt, for the whole drag.
        //
        // Constant means the collapsed thumbnail now carries the shadow too,
        // where it used to fade to nothing. At 36pt under a 6pt radius that
        // reads as the same lift the pill itself has, which is the intent —
        // one lighting model for every surface on this screen.
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
        .position(centre)
        // Cú hoà mờ thay cho cú bay khi giảm chuyển động — xem
        // `setQueueFactor(to:)`. Ở chế độ thường nó là hằng số 1 và modifier
        // này không làm gì.
        //
        // **Ở đây, chứ không ở ngoài `.overlay` bên dưới.** Dưới đó là
        // `QueuePanel`, và panel đã có nhịp hiện riêng đo từ Apple Music. Bao
        // cả hai thì panel chạy hai cú hoà mờ chồng lên nhau — cùng loại lỗi
        // "hai đồng hồ trên một vật" mà `queueFactor` được tạo ra để tránh.
        //
        // Trên `.position`, nên nó bao cả bóng đổ và cả hai lớp mask/overlay
        // phía trên: tấm bìa phải tan như **một** vật, cùng lý do
        // `cardOpacity` được áp một lần ở ngoài cùng `body`.
        .opacity(queueArtworkOpacity)
        // The picture takes no touches, and it must not — it now covers the
        // whole card.
        //
        // Before it filled the card it only covered the top of it, so the
        // controls beneath were reachable simply because nothing was over
        // them. Growing it to full height put it in front of the scrubber,
        // the transport row, the volume slider and the queue button all at
        // once, and the player stopped responding to anything: a screen that
        // looked normal and answered nothing.
        //
        // Applied *here*, above the `.overlay` that adds `QueuePanel` below,
        // so the panel keeps its own hit testing. Disabling the whole result
        // would take the queue's rows and pills down with it.
        //
        // The card's own drag and its tap-to-expand live one level up, on the
        // card rather than on this view, so they are unaffected — touches that
        // land on the artwork now fall through to them, which is what happened
        // before this view grew.
        .allowsHitTesting(false)
        // The panel occupies the artwork's frame rather than being pushed
        // below it — the artwork is the only region on this screen with
        // room, and `contentBudget` documents that there is none to spare
        // anywhere else.
        //
        // No `.opacity(showingQueue ? 0 : 1)` here any more: the artwork no
        // longer disappears when the queue opens, it *becomes* the header
        // thumbnail — `geometry` above already carries it down onto that
        // 44pt slot. Fading it out here would shrink an invisible view onto
        // an invisible slot.
        // `alignment: .top`, not the default `.center` — load-bearing for
        // the `.frame(maxHeight:)` cap below. `.overlay` centers its content
        // within the base view's bounds by default; the artwork's own frame
        // is `artworkHeight` tall (~515pt at full expansion) but the panel,
        // once capped to `contentOffset` (~474–480pt), is shorter than that.
        // Centered, the capped panel's top would float ~20pt down from the
        // artwork's own top edge and its bottom would land ~20pt past
        // `contentOffset` — back into the scrubber's touch strip, silently
        // reopening the exact overlap the cap exists to close. Top-aligning
        // pins the panel's top to the artwork's top (y=0 in this ZStack,
        // per `expandedCentre`'s comment), which is also where
        // `expandedContent`'s own `.offset(y: contentOffset(...))`
        // effectively starts its stack from — so a panel capped to
        // `contentOffset` and top-aligned here ends exactly where that
        // stack begins, with nothing between them to fight over.
        .overlay(alignment: .top) {
            // **Gắn theo `queueFactor`, không theo `showingQueue`.**
            //
            // `showingQueue` là ý định, `queueFactor` là vị trí. Gắn theo ý
            // định thì panel bị gỡ khỏi cây ngay khung sau cú chạm đóng, trong
            // khi chính nó còn đang phải chạy nốt cú trượt xuống — và khi bấm
            // đóng rồi mở lại thật nhanh, nó được gắn lại ở giữa hành trình
            // với `factor` đang ở đâu đó quãng giữa. Ba khối bên trong đọc
            // `factor` qua các cửa sổ `smoothstep`, nên chúng hiện ra ngay ở
            // 70–80% và cú trượt biến mất, đúng triệu chứng: bìa với chữ vẫn
            // bay vì chúng không nằm sau cái `if` này.
            //
            // Theo vị trí thì panel sống đúng bằng thời gian nó còn nhìn thấy
            // được, và mọi cú bấm liên tiếp chỉ đổi đích của một lò xo đang
            // chạy — không có lần gắn lại nào để mất trạng thái.
            if showingQueue || queueFactor > 0 {
                // The artwork above is deliberately flush with the card's
                // top edge — full-bleed art under the status bar is the
                // design (see `expandedCentre`'s comment). `QueuePanel`'s
                // header is text, not art, and flush the same way it
                // collides with the status bar and, one element lower, with
                // `grabber`. The padding here is what fixes that; it is
                // applied to the panel alone, inside this overlay, so the
                // artwork's own frame and `.position(centre)` above are
                // untouched by queue mode — only the panel's content starts
                // lower.
                QueuePanel(
                    playback: playback,
                    factor: queueFactor,
                    reveal: queueContentReveal,
                    slide: queueContentSlide,
                    // **Luôn có màu, kể cả khi bài không có bìa.**
                    //
                    // Trước đây chỗ này truyền `nil` cho bài không bìa, với lý
                    // do "lúc ấy nền là màu hệ thống và màu hệ thống là đúng".
                    // Lý do ấy hết đúng từ khi `queueBackdrop` kéo nền về một
                    // trường tối cố định: `tertiarySystemFill` phân giải theo
                    // chế độ sáng/tối của *hệ thống*, không theo cái nền thật
                    // sự nằm dưới nó, nên ở chế độ sáng nó ra một mảng gần như
                    // vô hình trên nền tối — đúng những viên thuốc mờ tịt trong
                    // ảnh chụp.
                    //
                    // `queueSurface` của chính màu nền hệ thống cho một màu xám
                    // trung tính sáng hơn trường một bậc, và bậc ấy là bậc đã
                    // biết chứ không phải bậc mà môi trường quyết định hộ.
                    tint: Self.queueSurface(tint ?? Color(.systemGroupedBackground)),
                    isReordering: $queueIsReordering
                )
                    .padding(.horizontal, sideMargin)
                    .padding(.top, panelTop)
                    // Bounded to where `NowPlayingContent` starts, not to
                    // the artwork's own frame the overlay would otherwise
                    // propose.
                    //
                    // The artwork is allowed to reach past `contentOffset`
                    // — that overlap is `contentBudget`'s documented,
                    // deliberate design, and it is harmless there because
                    // the artwork carries no gesture of its own; a touch
                    // over it falls through to the scrubber underneath.
                    // `QueuePanel`'s `upcomingList` is a real `List` once
                    // the queue is non-empty, and a `List` given an
                    // unconstrained proposed height claims all of it —
                    // including the blank space below the last row — and
                    // its pan recognizer covers that whole claimed bounds.
                    // Unbounded, that reached down into the scrubber's own
                    // 28pt touch strip and ate the drag before
                    // `ScrubberBar` ever saw it, silently, because the
                    // recognizer sits in front of the scrubber in the
                    // card's `ZStack` with nothing to arbitrate the two.
                    //
                    // `contentOffset(fullSize:)` is the one number that
                    // actually answers "where is it safe to end": it is
                    // where the content stack begins, in this same
                    // top-anchored coordinate space (both this overlay and
                    // `expandedContent` are laid out against `cardSize`
                    // inside the same `.topLeading` `ZStack` — see
                    // `card(size:insets:)`). Capping here to that value
                    // rather than to a fixed point means this stays correct
                    // if `contentOffset`'s own inputs ever change, instead
                    // of drifting the way a literal would.
                    //
                    // `max(0, …)`: `contentOffset` is allowed to go
                    // negative on a card shorter than the content region
                    // (`contentBudget`'s note on landscape) and a negative
                    // `maxHeight` is not a valid frame.
                    .frame(
                        maxHeight: max(0, Self.contentOffset(fullSize: size) + Self.queueListReclaimedHeight),
                        alignment: .top
                    )
                    // `.frame(maxHeight:)` only bounds what `QueuePanel`
                    // *reports upward* as its size — it does not draw
                    // anything, and it does not stop a child from drawing
                    // past the space it was proposed. `List` happens to
                    // honour a small proposed height by clipping itself,
                    // which is the only reason the comment above could once
                    // say the frame was enough. `header` and `pillRow` are
                    // ordinary `HStack`/`VStack` content with no such
                    // self-discipline: a `VStack` does not compress
                    // non-flexible children below their natural size, so on
                    // a card short enough that `contentOffset` collapses
                    // toward (or past) zero — every supported iPhone in
                    // landscape — they render at full size regardless of
                    // the cap and spill into the band `ScrubberBar` occupies,
                    // just less obviously than the `List` bug this frame was
                    // first added for: nothing here has a UIKit pan
                    // recognizer to visibly steal the drag, so the failure
                    // is a silent visual collision (the header's artwork and
                    // title painting over the scrubber's time labels) rather
                    // than a dead control. Verified by screenshot on iPhone
                    // 17 landscape: without this modifier the header's
                    // artwork thumbnail visibly overlaps the scrubber's
                    // elapsed-time label.
                    //
                    // `.clipped()` makes the frame above true in the way its
                    // own comment already claims: content that does not fit
                    // the region `NowPlayingContent` needs is cut, not
                    // spilled. This is a deliberate choice among the real
                    // alternatives — scrolling the header and pills along
                    // with the list would fight the list's own drag-to-
                    // reorder recognizer for the same gesture, and hiding
                    // the whole panel below some arbitrary height threshold
                    // would need a second number to invent and keep in sync
                    // with `contentOffset` — and it costs nothing new: it
                    // only ever removes pixels `List` would already have
                    // removed from itself if it were the thing overflowing,
                    // and on every portrait size `contentOffset` comfortably
                    // exceeds the panel's ~380pt natural height, so nothing
                    // here is visibly cropped there. `.clipped()` also
                    // bounds hit-testing to the same rectangle, so a pill
                    // that a future, tighter layout pushed into this same
                    // overflow can no longer be tapped from outside the
                    // region it is visible in either.
                    .clipped()
                    .opacity(progress)
                    .allowsHitTesting(progress > 0.9)
            }
        }
        // **Một chỗ đặt cho cả tấm bìa và panel, thay cho hai chỗ lồng bên
        // trong.**
        //
        // Trước đây `\.colorScheme` được đặt ở hai nơi sâu hơn: một ở lớp phủ
        // sương, một ở `QueuePanel`. Cả hai nằm trong thân view dựng lại **mỗi
        // khung** suốt cú kéo, và mỗi lần dựng lại là một lượt đẩy environment
        // xuống cây con — thứ SwiftUI phải phân giải lại thành `UITraitCollection`
        // cho mọi view do UIKit dựng bên dưới.
        //
        // Đo được trong trace: `_UIHostingView.updateEnvironment`,
        // `UITraitCollection.resolvedEnvironment`, `-[UIView
        // _traitCollectionDidChangeInternal:]` và `PropertyList.subscript` là
        // nhóm ký hiệu dày nhất trong 17 lần main thread bị chặn còn lại.
        //
        // Đặt ở đây thì cả tấm bìa lẫn panel cùng thừa hưởng một lượt đẩy, và
        // nó nằm ngoài phần thân chạy lại theo từng khung. Không đổi gì về
        // hình: hai cây con vốn đã tối, chỉ là trước đây mỗi cây tự nói.
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Gesture

    /// The finger's speed at release, in the units
    /// `BottomBarStyle.settle(initialVelocity:)` wants.
    ///
    /// Three conversions, and each one is a place this could be silently wrong:
    ///
    ///   1. **Sign.** `value.velocity.height` is positive downward, while
    ///      `progress` grows as the card is dragged *up*. Miss the negation and
    ///      every flick hands the spring a velocity pointing away from where the
    ///      card is going, which reads as the card being knocked backwards
    ///      before it recovers.
    ///   2. **Points to progress.** Dividing by `travel` turns points per second
    ///      into progress per second, the same conversion `onChanged` makes for
    ///      the position.
    ///   3. **Progress to remaining.** SwiftUI wants the velocity relative to
    ///      the distance the animation still has to cover, not to the whole
    ///      range — so it is divided again by what is left.
    ///
    /// Zero when there is nothing left to travel: dividing by that remainder is
    /// undefined, and a spring with no distance to cover has no use for a speed.
    ///
    /// Takes the bare number rather than the `DragGesture.Value` it comes from.
    /// That type has no public initialiser, so a function that took one could
    /// not be tested at all — and the three conversions below are exactly the
    /// kind that stay silently wrong.
    ///
    /// - Parameter verticalVelocity: points per second, positive downward, as
    ///   `DragGesture.Value.velocity.height` reports it.
    static func settleVelocity(
        verticalVelocity: CGFloat,
        travel: CGFloat,
        from current: Double,
        to target: Double
    ) -> Double {
        let remaining = target - current
        guard abs(remaining) > 0.0001, travel > 0 else { return 0 }
        let progressPerSecond = Double(-verticalVelocity / travel)
        let relative = progressPerSecond / remaining
        return min(max(relative, -BottomBarStyle.maxSettleVelocity), BottomBarStyle.maxSettleVelocity)
    }

    /// How far the finger must move before the card starts following it.
    ///
    /// **Near zero once the card is open, because there is nothing left to
    /// disambiguate.** A threshold exists to stop a tap being read as a drag,
    /// and the tap it protects — `onTapGesture`, which expands — is guarded on
    /// `progress < 0.5` and does nothing at all while the card is open. Paying
    /// for that protection when it cannot fire is what put a dead zone at the
    /// start of every downward swipe.
    ///
    /// Not literally zero: at zero this gesture recognises on touch-down and
    /// competes with the controls inside the expanded card for the same touch.
    /// Two points is below the threshold of a deliberate movement and above the
    /// jitter of a stationary finger.
    static func dragThreshold(progress: Double) -> CGFloat {
        progress > 0.5 ? 2 : 10
    }

    /// The finger's travel with the recognition threshold taken back out.
    ///
    /// `DragGesture.Value.translation` is measured from **touch-down**, not from
    /// the moment the gesture recognised — so the very first `onChanged` already
    /// carries the whole threshold, and assigning it straight across makes the
    /// card jump that far in a single frame. Ten points of jump after ten points
    /// of nothing is the stutter at the start of a swipe: the dead zone and the
    /// catch-up are one defect with two halves.
    ///
    /// Subtracting leaves the card trailing the finger by the threshold forever
    /// after, which at two points is not visible and is the right trade: a
    /// constant offset nobody can see, against a discontinuity everybody can.
    ///
    /// Clamped to the movement's own magnitude rather than subtracted blindly.
    /// `minimumDistance` measures distance in two dimensions, so a finger that
    /// moved mostly sideways can recognise with a vertical component smaller
    /// than the threshold — and a blind subtraction would flip its sign and send
    /// the card the wrong way.
    static func dragOffset(translationHeight: CGFloat, threshold: CGFloat) -> CGFloat {
        if translationHeight > 0 { return max(0, translationHeight - threshold) }
        if translationHeight < 0 { return min(0, translationHeight + threshold) }
        return 0
    }

    /// Where the artwork is and what shape it is, for one pair of progresses.
    ///
    /// `shapeProgress` is deliberately separate from the size and position: the
    /// mask and the corner radius only need to know whether the artwork
    /// currently looks like a thumbnail or like a full-bleed cover, and both
    /// existing expressions already answer that from a single number.
    struct ArtworkGeometry: Equatable {
        let width: CGFloat
        let height: CGFloat
        let centre: CGPoint
        let shapeProgress: Double
    }

    /// Ở `progress` nào thì bề rộng tấm bìa **đuổi kịp** bề rộng thẻ, trên
    /// đường `fullBleed == true`.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// VÌ SAO CẦN CÓ NÓ
    /// ─────────────────────────────────────────────────────────────────────
    /// Thẻ và bìa không xuất phát từ cùng một chỗ. Lề thu gọn chỉ là
    /// `collapsedSideMargin` (21pt, hoặc `minimisedPlayerInset` khi thu nhỏ)
    /// mỗi bên, nên **thẻ đã rộng ~92% ngay ở `progress == 0`**, trong khi bìa
    /// bò lên từ `collapsedArtwork` — 36pt. Hai đường tuyến tính, hai điểm
    /// xuất phát cách nhau xa như thế thì suốt gần cả hành trình còn một dải
    /// hở bên phải mà bìa không phủ tới. Đo trên video bản Release, iPhone
    /// 390pt: ở `progress` 0,69 thẻ rộng 380 còn bìa 273 — phủ **72%**, dải hở
    /// 107pt, và chữ của danh sách phía dưới đọc được xuyên qua đó năm dòng.
    /// Không phải khung rơi: 15 cú mở/đóng, 0 khung rơi. Là số học.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// CÁI BẪY — `width` VÀ `centre.x` PHẢI ĐI CÙNG MỘT ĐƯỜNG CONG
    /// ─────────────────────────────────────────────────────────────────────
    /// Tăng tốc riêng `width` mà để `centre.x` chạy tuyến tính trên `progress`
    /// là **tệ hơn hiện trạng**, không phải đỡ hơn. Ở `progress` 0,3 với thẻ
    /// 367,6pt: tâm mới đi được tới x = 36 + (183,8 − 36)·0,3 = 80,3, còn nửa
    /// bề rộng đã là 183,8 — dải phủ chạy từ **−103,5 tới 264,1**. Tràn trái
    /// 103,5pt (ra ngoài mép bo của thẻ) và **vẫn hở 103,5pt bên phải**. Đúng
    /// cái dải cũ, chỉ dịch chỗ.
    ///
    /// Nên `horizontalProgress` dưới kia lái **cả hai**. Khi ấy hai mép có
    /// dạng đóng, và đó là toàn bộ chứng minh của bản sửa này — với
    /// `queueFactor == 0`, `openWidth == cardWidth` và `openCentre.x ==
    /// cardWidth/2`, viết `h` cho `horizontalProgress`:
    ///
    ///   trái  = centre.x − width/2 = collapsedArtworkInset · (1 − h)
    ///   phải  = centre.x + width/2
    ///         = (collapsedArtworkInset + collapsedArtwork)
    ///           + h · (cardWidth − collapsedArtworkInset − collapsedArtwork)
    ///
    /// Tức trái đi 18 → 0 và phải đi 54 → `cardWidth`, **tuyến tính trên `h`,
    /// với mọi `cardWidth`**. Hệ quả: không bao giờ tràn ra ngoài
    /// `[0, cardWidth]`, và phủ trọn nó đúng ở `h == 1` — không sớm hơn, không
    /// muộn hơn. `cardWidth` tự nó cũng đổi theo `progress`, và dạng đóng trên
    /// vẫn đứng vì nó đúng ở từng giá trị `cardWidth` một.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// VÌ SAO LÀ ⅓
    /// ─────────────────────────────────────────────────────────────────────
    /// Dải bên phải **không** rỗng ở đầu hành trình: nó là chỗ ở của chrome
    /// mini, và chrome ấy tan trên đúng cửa sổ `1 - progress * 3` — hết ở ⅓.
    /// Nền thẻ cũng đục dần trên cùng cửa sổ ấy, `min(1, progress * 3)`. ⅓ là
    /// ranh giới file này đã có sẵn ở hai chỗ cho cùng một ý: "viên thuốc đã
    /// trở thành tấm thẻ". Cho bìa phủ xong đúng ở đó thì dải bên phải không
    /// lúc nào vô chủ — chrome giữ nó tới ⅓, bìa nhận nó từ ⅓. Ba con số
    /// thống nhất một mốc thay vì ba mốc.
    ///
    /// Sớm hơn thì được gì cũng phải trả bằng hình dáng: ở đúng `progress` ==
    /// ngưỡng, bìa dẹt nhất, và tỉ lệ khung ở đó là ngưỡng 0,25 → 1,49:1;
    /// ngưỡng ⅓ → 1,17:1. 1,17 đọc ra là một khung ảnh cắt bình thường; 1,49
    /// bắt đầu đọc ra là một dải ngang. Muộn hơn ⅓ thì dải hở sống quá lúc
    /// chrome đã tan hẳn — không còn gì che, và đó chính là khung 0,69 đo được.
    ///
    /// Đừng "đơn giản hoá" chỗ này về lại một `progress` duy nhất. Đọc lại
    /// đoạn CÁI BẪY trước khi động vào.
    static let artworkWidthCatchUp: Double = 1.0 / 3

    /// The artwork's geometry across all three states it can be in.
    ///
    /// Pure and `static` for the reason `dragOffset` and `dragThreshold` are:
    /// this is the arithmetic that is easy to get wrong and impossible to see
    /// wrong, and a view modifier chain cannot be asserted against.
    ///
    /// **`queueFactor` is folded into `progress` for shape, and applied after
    /// it for position.** That asymmetry is the design. For shape,
    /// `progress * (1 - queueFactor)` reuses the appearance the code already
    /// draws at `progress == 0` — rounded, opaque, no dissolve — which is
    /// exactly what a 44pt thumbnail wants, so no new formula is written and
    /// the two shipped ends cannot move. For position, the queue slot is a
    /// third destination the collapsed→expanded interpolation has to reach
    /// *through*, so it is applied to the expanded end before that
    /// interpolation runs.
    ///
    /// **Trục ngang chạy trên đường cong riêng, và nó là một bản sửa.** Xem
    /// `artworkWidthCatchUp`.
    static func artworkGeometry(
        progress: Double,
        queueFactor: Double,
        cardSize: CGSize,
        /// Bài có ảnh bìa thật hay không, và nó chọn hẳn một trong hai hình
        /// dáng: tràn cả thẻ, hay khối vuông ở giữa.
        fullBleed: Bool,
        artworkSide: CGFloat,
        artworkTop: CGFloat,
        queueThumbCentre: CGPoint,
        queueThumbSide: CGFloat
    ) -> ArtworkGeometry {
        // Where the artwork ends up once the card is fully open — full bleed,
        // or the header slot if the queue is showing.
        // **Hai hình dáng, chọn theo bài đang phát.**
        //
        // Có ảnh bìa thật → tràn màn hình: bìa rộng bằng thẻ, cao 59%, mép dưới
        // tan vào nền. Đó là dáng vẻ ảnh bìa xứng đáng có.
        //
        // Không có → khối vuông ở giữa: một glyph placeholder kéo tràn màn hình
        // chỉ là một nốt nhạc khổng lồ. Vuông thì nó đọc như một tấm bìa vắng
        // mặt, đúng bản chất.
        //
        // Vuông cũng là hình duy nhất morph mà không méo — cả ba đích đều
        // vuông nên tỉ lệ khung không đổi. Đường tràn màn hình chấp nhận việc
        // tỉ lệ đổi, và trả bằng cú tan ở mép dưới để không ai thấy mép.
        // Tràn màn hình thì bìa phủ **cả chiều cao thẻ**, không phải một phần
        // của nó. Vệt tan mới là thứ quyết định nhìn thấy bao nhiêu: ở
        // `artworkFadeFraction` 0.25, ảnh sắc nét 75% trên và mềm dần trong 25%
        // dưới. Cho bìa chỉ cao 59% rồi tan 25% của *phần đó* thì ảnh sắc nét
        // chỉ còn 44% màn hình — hai cách hiểu khác hẳn nhau về cùng con số.
        let openBase = fullBleed ? cardSize.width : artworkSide
        let openTall = fullBleed ? cardSize.height : artworkSide
        let openWidth = openBase + (queueThumbSide - openBase) * queueFactor
        let openHeight = openTall + (queueThumbSide - openTall) * queueFactor
        // Flush with the card's top edge: the artwork's centre sits exactly
        // half its own height down, with no safe-area term. The status bar is
        // drawn over it, in white — the expanded chrome forces its own
        // whole window dark while the card is open. Two comments elsewhere in
        // `PlayerCard` (`artworkView` and the `QueuePanel` overlay) point back
        // here for that reasoning.
        // Tràn màn hình thì tì vào mép trên thẻ; khối vuông thì nằm dưới
        // grabber, giữa khoảng trống phía trên khối điều khiển.
        let expandedCentre = CGPoint(
            x: cardSize.width / 2,
            y: fullBleed ? openTall / 2 : artworkTop + artworkSide / 2
        )
        let openCentre = CGPoint(
            x: expandedCentre.x + (queueThumbCentre.x - expandedCentre.x) * queueFactor,
            y: expandedCentre.y + (queueThumbCentre.y - expandedCentre.y) * queueFactor
        )

        // The collapsed end is untouched by any of this — see the tests.
        let collapsedCentre = CGPoint(
            x: Self.collapsedArtworkInset + Self.collapsedArtwork / 2,
            y: Self.collapsedHeight / 2
        )

        // Trục ngang chạy trước trục dọc — xem `artworkWidthCatchUp` cho toàn
        // bộ lý do, con số đo được và cái bẫy. `height` và `centre.y` giữ
        // nguyên trên `progress`; chỉ `width` và `centre.x` đọc con số này, và
        // chúng **phải** đọc cùng một con số.
        //
        // Hai điều kiện làm nó không chạm được vào bất cứ thứ gì đã ship:
        //
        //   1. **Chỉ đường `fullBleed == true`.** Đường không-bìa là khối vuông
        //      ở giữa, và vuông là hình duy nhất morph mà không méo vì cả ba
        //      đích đều vuông (đọc khối chú thích đầu hàm). Tách `width` khỏi
        //      `height` ở đó là kéo giãn cái placeholder. Ở đây
        //      `horizontalProgress == progress`, từng bit một.
        //   2. **`queueFactor` kéo nó về lại `progress`.** Cùng thủ pháp
        //      `openWidth`/`openCentre` ngay trên dùng: nội suy về đích hàng
        //      đợi theo `queueFactor`. Cần thật, không phải phòng xa —
        //      `showingQueue` chỉ tự tắt ở `progress < 0.05`, nên kéo thẻ
        //      xuống lúc hàng đợi đang mở là cả quãng `progress` 1 → 0,05 với
        //      `queueFactor == 1`. Ở đó đích là ô 44pt vuông trong header, và
        //      hai trục lệch nhau sẽ biến nó thành 44×40 giữa chừng. Với
        //      `queueFactor == 1` biểu thức này ra đúng `progress`, nên cú thu
        //      về ô header không đổi một chút nào.
        //
        // Ở `progress` 0 và 1 nó ra đúng 0 và 1 với **mọi** `queueFactor`, nên
        // hai đầu đã ship không nhúc nhích. Có test ghim cả hai.
        let horizontalProgress: Double
        if fullBleed {
            let rushed = min(1, progress / Self.artworkWidthCatchUp)
            horizontalProgress = rushed + (progress - rushed) * queueFactor
        } else {
            horizontalProgress = progress
        }

        let width = Self.collapsedArtwork + (openWidth - Self.collapsedArtwork) * horizontalProgress
        let height = Self.collapsedArtwork + (openHeight - Self.collapsedArtwork) * progress

        return ArtworkGeometry(
            width: width,
            height: height,
            centre: CGPoint(
                x: collapsedCentre.x + (openCentre.x - collapsedCentre.x) * horizontalProgress,
                y: collapsedCentre.y + (openCentre.y - collapsedCentre.y) * progress
            ),
            shapeProgress: progress * (1 - queueFactor)
        )
    }

    /// The panel's own top offset from the safe area — exactly what
    /// `QueuePanel`'s `.padding(.top,)` in `artworkView`'s overlay applies,
    /// `queuePanelHeaderGap` folded in.
    ///
    /// Read by `queueThumbCentre` below **and** by that `.padding(.top,)`
    /// call site (via `artworkView`'s own `panelTop` local, assigned from
    /// this), so the two name the same offset instead of each restating
    /// `topInset + grabberTopGap + grabberHeight + queuePanelHeaderGap`.
    /// Two independently-typed copies of that sum is exactly how the
    /// artwork used to land 12pt above the header it was flying to: the
    /// fold-in lived in the panel's own padding and not in the point the
    /// artwork animated toward, and nothing made the two agree once they
    /// diverged. `sideMargin`, two lines into `artworkView`, exists for the
    /// identical reason on the horizontal axis — "a literal in both places
    /// is two numbers that must agree and nothing to notice when they
    /// stop." The same mistake was live on the vertical axis at the same
    /// time.
    static func queuePanelTop(topInset: CGFloat) -> CGFloat {
        topInset + Self.grabberTopGap + Self.grabberHeight + Self.queuePanelHeaderGap
    }

    /// Where the artwork animates to when the queue opens: the header
    /// slot's centre, in this card's own coordinate space.
    ///
    /// `QueuePanel.header` sits at the very top of the panel's own
    /// `VStack` with no further offset, so its centre is `queuePanelTop`
    /// plus half the header artwork — nothing else.
    static func queueThumbCentre(topInset: CGFloat) -> CGPoint {
        CGPoint(
            x: Self.queuePanelSideMargin + QueuePanel.headerArtwork / 2,
            y: Self.queuePanelTop(topInset: topInset) + QueuePanel.headerArtwork / 2
        )
    }

    private func drag(travel: CGFloat, threshold: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: threshold)
            .onChanged { value in
                // Guarded rather than assigned unconditionally: this fires on
                // every touch move, and a redundant `@State` write would
                // invalidate the view again for nothing.
                if !isDragging { isDragging = true }
                // Written here rather than from an `onChange` on `progress` —
                // see the note on `expansion`.
                // `animation: nil` — trong lúc kéo, mỗi khung là một giá trị
                // mới và một lò xo ở đây chỉ là một khoảng trễ giữa ngón tay
                // và màn hình.
                defer { expansion.set(progress: progress, animation: nil) }
                // No rubber-band past either end: `progress` (settled +
                // dragDelta, clamped) is rigid at 0 and 1. An earlier version
                // of this method shaved the excess off `delta` here to fake
                // give, but that landed after the clamp already applied, so
                // it had no visible effect at any input — the code and its
                // comment disagreed. See F5; overshoot geometry was judged
                // more risk than the interaction is worth for this pass.
                dragDelta = -Self.dragOffset(
                    translationHeight: value.translation.height,
                    threshold: threshold
                ) / travel
            }
            .onEnded { value in
                // Cleared outside the `withAnimation` below: the hit region
                // is not an animatable property, and the settle should hand
                // the screen back as soon as the finger lifts.
                isDragging = false
                // Decide on the predicted end, not the current offset, so a
                // quick flick settles the card even though the finger barely
                // moved. Comparing raw distance is what makes hand-rolled
                // sheets feel heavy.
                // Compensated the same way as the live position above, so the
                // decision is taken in the same coordinates the card was moving
                // in rather than ones a threshold apart.
                let predicted = settled - Self.dragOffset(
                    translationHeight: value.predictedEndTranslation.height,
                    threshold: threshold
                ) / travel
                let target: Double = predicted > 0.5 ? 1 : 0
                // Đặt tên cho nó, vì cùng một đường cong phải tới hai nơi: thẻ
                // tự animate bằng `@State` của mình, còn cú thu nhỏ nội dung
                // nhận nó qua `expansion`. Hai bản khác nhau ở đây là hai vật
                // rời nhau trên màn hình.
                let curve = BottomBarStyle.settle(
                    initialVelocity: Self.settleVelocity(
                        verticalVelocity: value.velocity.height,
                        travel: travel,
                        from: progress,
                        to: target
                    )
                )
                // Cú đáp cũng đi qua `morph(to:curve:)`, không tự gọi
                // `withAnimation`. Nó là **animation**, không phải thao tác
                // trực tiếp: ngón tay đã rời màn hình, và quãng còn lại — một
                // cú búng từ thẻ đang mở là gần trọn 750 điểm — là đúng thứ
                // Giảm chuyển động tồn tại để bỏ đi. Phần bám ngón tay nằm ở
                // `onChanged` phía trên và không đổi.
                morph(to: target, curve: curve)
            }
    }

    private func expand() {
        morph(to: 1, curve: BottomBarStyle.expand)
    }

    private func collapse() {
        morph(to: 0, curve: BottomBarStyle.expand)
    }

    // MARK: - Morph

    /// Đưa `queueFactor` tới `target`, bằng **hai** đường tuỳ theo Giảm chuyển
    /// động — cùng ranh giới, cùng cơ chế và cùng lý do như `morph(to:curve:)`
    /// ngay bên dưới. Đọc ghi chú ấy trước; chỗ này chỉ nói phần khác.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// VÌ SAO ĐỔI CURVE THÔI LÀ KHÔNG ĐỦ, LẦN NỮA
    /// ─────────────────────────────────────────────────────────────────────
    /// `BottomBarStyle.queue` đã có nhánh phẳng, và suốt một thời gian đó là
    /// tất cả những gì cú chuyển này nhận được. Nhưng thứ nó lái không phải
    /// hình dáng gia tốc — nó lái `queueFactor`, mà `artworkGeometry` nội suy
    /// **quãng đường** trên chính con số ấy: `openWidth`/`openHeight` đi từ tấm
    /// bìa tràn màn hình (cỡ 402×874 trên iPhone 17) về ô 60 điểm ở header, và
    /// `openCentre` kéo tâm từ giữa thẻ lên góc trên bên trái. Tức cả bức ảnh
    /// co lại chừng 6,7 lần theo chiều ngang, 14,6 lần theo chiều dọc, rồi bay
    /// chéo lên góc. Đó là cú chuyển động lớn nhất trong app, và một
    /// `easeInOut` 0,29s chỉ làm nó đi theo một đường cong khác.
    ///
    /// Ghi chú của `BottomBarStyle.queueContentSlide` đã treo đúng câu hỏi này
    /// lại — *"quãng đường sẽ do B3/B4 quyết có còn hay không"* — và đây là câu
    /// trả lời: không còn.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// CÚ ĐỔI VẪN XẢY RA
    /// ─────────────────────────────────────────────────────────────────────
    /// Hàng đợi vẫn mở và vẫn đóng, và tấm bìa vẫn **về đúng ô header**:
    /// `queueFactor` vẫn tới 1, nên `artworkGeometry` vẫn cho ra đúng hình học
    /// ở đích, `shapeProgress` vẫn về 0 và tấm bìa vẫn bo góc như một
    /// thumbnail. Chỉ có quãng giữa là biến mất, và nó biến mất theo cách
    /// người dùng không thấy: hình học nhảy trong một transaction `nil`, cùng
    /// lượt ấy `queueArtworkOpacity` bị hạ về 0, rồi `withAnimation` đưa nó về
    /// 1. Khung duy nhất có hình học mới ở độ mờ 0 là khung không vẽ ra gì.
    ///
    /// Cái mất, nói thẳng, giống hệt `morph(to:curve:)`: trạng thái **cũ** bị
    /// cắt phụt chứ không tan dần. Một cú hoà mờ chéo thật sự đòi hai bản tấm
    /// bìa cùng tồn tại ở hai `queueFactor` khác nhau, tức đúng cái tái cấu
    /// trúc đang bị chặn ở file này.
    ///
    /// `queueArtworkOpacity` chỉ bao tấm bìa. Ba khối trong `QueuePanel` giữ
    /// nguyên nhịp hiện riêng của chúng (`queueContentIn`/`queueContentOut`,
    /// đo từ Apple Music) — đó vốn đã là hoà mờ, và HIG cho phép hoà mờ. Cái
    /// phải bỏ ở phía panel là cú **trượt** kèm theo, và nó được bỏ ở chính
    /// `QueuePanel.riseDistance`/`headerTextRise`.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// NĂM CHỖ, KHÔNG PHẢI MỘT
    /// ─────────────────────────────────────────────────────────────────────
    /// Hàm này bỏ được đúng một quãng: quãng bay của tấm bìa. Cú chuyển hàng
    /// đợi cưỡi lên bốn quãng nữa, và mỗi quãng được gác ở chính chỗ nó sống,
    /// chứ không ở đây — một chỗ gác từ xa thì chỗ đọc nó không biết mình đang
    /// bị gác. Danh sách đủ, để lần sau không phải đi tìm lại:
    ///
    ///   1. Tấm bìa — chính hàm này, cộng `.opacity(queueArtworkOpacity)` ở
    ///      `artworkView`.
    ///   2. Khối chữ của `NowPlayingContent` — `queueTitleTravel(size:topInset:)`
    ///      trả 0 ngay ở dòng đầu.
    ///   3. Hai khối dưới của panel — `QueuePanel.riseDistance`.
    ///   4. Khối chữ header của panel — `QueuePanel.headerTextRise`.
    ///   5. Mảng nền nút hàng đợi — `NowPlayingContent.queueBadgeScale`.
    ///
    /// Cái *không* nằm trong danh sách cũng có ý: mọi cú `.opacity` ở năm chỗ
    /// ấy đều ở nguyên. Hàng đợi vẫn mở, vẫn đóng, và thứ tự hiện/tan của hai
    /// khối chữ vẫn là nghịch đảo của nhau.
    ///
    /// `withAnimation` ở nhánh thường giữ nguyên si cú gọi cũ.
    private func setQueueFactor(to target: Double) {
        guard BottomBarStyle.reduceMotion else {
            withAnimation(BottomBarStyle.queue) {
                queueFactor = target
            }
            return
        }

        // `Transaction(animation: nil)` viết rõ ràng, cùng lẽ với `morph`: chỗ
        // gọi duy nhất của hàm này nằm trong `onChange(of: showingQueue)`, và
        // một trong hai đường tới đó — `progress` tụt xuống dưới 0.05 lúc kéo
        // đóng thẻ — ghi `showingQueue` từ bên trong
        // `withAnimation(BottomBarStyle.queue)` của chính nó. Không nói rõ thì
        // cú nhảy hình học lại thành cú bay.
        withTransaction(Transaction(animation: nil)) {
            queueFactor = target
            queueArtworkOpacity = 0
        }

        withAnimation(BottomBarStyle.queue) { queueArtworkOpacity = 1 }
    }

    /// Đưa thẻ tới `target`, bằng một trong **hai** đường tuỳ theo Giảm chuyển
    /// động.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// RANH GIỚI: ANIMATION ĐỔI, THAO TÁC TRỰC TIẾP KHÔNG
    /// ─────────────────────────────────────────────────────────────────────
    /// `progress` đổi theo hai đường hoàn toàn khác nhau, và chỉ một đường đi
    /// qua đây.
    ///
    ///   - **Thao tác trực tiếp** — `drag(...).onChanged` ghi `dragDelta` từng
    ///     khung, ngoài mọi transaction. Không có gì nội suy: thẻ ở đâu là do
    ///     ngón tay ở đó. **Đường ấy không đổi một dòng nào khi giảm chuyển
    ///     động**, và đó là chủ ý. Thẻ đi theo ngón tay là *phản hồi*; tắt nó
    ///     đi là làm hỏng cách điều khiển chứ không phải làm app dễ tiếp cận
    ///     hơn — người dùng sẽ không vuốt đóng được player nữa.
    ///   - **Animation** — chạm mở, chạm đóng, cú đáp sau khi thả. Cả ba đều
    ///     gọi hàm này, và chỉ ở đây mới có gì để bỏ đi.
    ///
    /// Nhánh thường giữ nguyên si cú `withAnimation` cũ, kể cả việc `curve`
    /// phải tới cả `settled` lẫn `expansion` — xem ghi chú ở `onEnded`.
    ///
    /// Nhánh giảm chuyển động **không phải một đường cong khác**. Đổi curve
    /// thôi thì thẻ vẫn phóng từ viên thuốc ra toàn màn hình, chỉ là phóng theo
    /// curve khác, và người say chuyển động vẫn thấy đúng thứ làm họ khó chịu.
    /// Cái phải biến mất là **quãng đường**, không phải hình dáng gia tốc của
    /// nó.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// BA DÒNG, VÀ VÌ SAO CHỈ CẦN BA DÒNG
    /// ─────────────────────────────────────────────────────────────────────
    /// Hình học nhảy thẳng tới đích trong một transaction `nil`, cùng lượt ấy
    /// độ mờ bị hạ về 0, rồi độ mờ được `withAnimation` đưa về 1. Người dùng
    /// **không bao giờ thấy cú nhảy**: khung duy nhất có hình học mới ở độ mờ
    /// 0 là khung không vẽ ra gì cả, và thứ hiện lên sau đó đã đứng yên sẵn ở
    /// đích. Không có khung nào có thẻ ở một hình học trung gian, nên không có
    /// cú phóng to nào để mà thấy.
    ///
    /// Ba dòng ấy dựa vào một hành vi của SwiftUI mà **suy luận đã đoán sai và
    /// phép đo bác bỏ**: hạ một giá trị xuống 0 rồi cho `withAnimation` đưa nó
    /// về 1 trong cùng một lượt cập nhật *vẫn chạy* cú hoà mờ, xuất phát từ 0
    /// — SwiftUI không gộp cặp ấy thành "1 tới 1". Bản nháp trước tin là nó có
    /// gộp, nên phải làm hai nửa nối bằng `completion`, kèm con dấu huỷ, kèm
    /// một quãng `cardOpacity` nằm ở 0 trong state — tức một `completion` rơi
    /// mất là một player vô hình vĩnh viễn. Xem
    /// `SwiftUIAnimationTransactionEvidenceTests`: cả ba hành vi ở đây đều có
    /// vết đo, và bản ba dòng này không có trạng thái nào chờ ai dọn.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// MỘT CÚ MORPH ĐÈ LÊN CÚ HOÀ MỜ ĐANG CHẠY
    /// ─────────────────────────────────────────────────────────────────────
    /// Có thật, không hiếm: `collapse()` chạy từ
    /// `onChange(of: playback.currentTrack?.id)` và có thể rơi vào giữa cú hoà
    /// mờ của `expand()`.
    ///
    /// Mối lo đúng chỗ: lúc ấy `cardOpacity` **trong state đã là 1**, nên hạ
    /// về 0 rồi đưa về 1 là một cặp không đổi gì trong lượt ấy. Nếu SwiftUI
    /// giữ nguyên animation đang chạy thì thẻ đang ở một độ mờ *lưng chừng*
    /// đúng lúc hình học nhảy — tức cú nhảy hiện ra trên màn hình, đúng thứ cả
    /// tính năng này tồn tại để giấu.
    ///
    /// Đã đo, và animation cũ **không** được giữ — nhưng lý do không giống cả
    /// hai dự đoán. Animation của SwiftUI **cộng dồn**: hạ state đi 1 trong lúc
    /// một animation đang bay làm giá trị đang vẽ tụt xuống đúng 1.0 chứ không
    /// bị bỏ qua. Đo ở hai thời điểm cắt ngang khác nhau, giá trị ngay sau cú
    /// đè bằng `giá trị trước đó − 1.0` tới ba chữ số thập phân. Mà cú hoà mờ
    /// đang chạy không bao giờ vẽ quá 1, nên hiệu ấy **luôn ≤ 0** — thẻ không
    /// bao giờ ở một độ mờ lưng chừng đúng khoảnh khắc hình học nhảy. Xem
    /// `SwiftUIAnimationTransactionEvidenceTests.testASecondFadeArrivingMidFadeIsNeverPartiallyVisible`.
    ///
    /// **Điều kiện của bất biến ấy, và nó nằm ở file khác.** "Không bao giờ vẽ
    /// quá 1" là tính chất của *đường cong*, không phải của cơ chế. Hàm này
    /// nhận bất kỳ `Animation` nào; một đường cong có vọt lố sẽ vẽ quá 1 giữa
    /// chừng, làm cú tụt cộng dồn rơi vào vùng **dương**, và cú nhảy hình học
    /// hiện ra — đúng cái hỏng mà cả tính năng tồn tại để tránh. Cái đang giữ
    /// điều kiện ấy là mọi chỗ gọi đều truyền `BottomBarStyle.expand` hoặc
    /// `settle(initialVelocity:)`, mà nhánh giảm chuyển động của cả hai là
    /// `easeInOut` — không vọt lố. **Nếu bạn định truyền một đường cong có nảy
    /// vào đây, dừng lại và đọc đoạn này trước.** Điều kiện được đo trực tiếp
    /// ở `testTheCurvesTheReducedMorphRunsOnNeverPresentAboveTheirTarget`, kèm
    /// một lò xo có nảy làm đối chứng để bộ đo không thể xanh vì mù.
    ///
    /// **Và "≤ 0 nghĩa là vô hình" cũng đã được đo, chứ không còn là suy
    /// luận.** Vòng sửa 1 chỉ đo tới chỗ giá trị đi âm rồi *cho rằng* âm là
    /// trong suốt; vòng 2 đo nốt bằng cách dựng ảnh và đọc pixel:
    /// `View.opacity` — đúng cái modifier chỗ áp `cardOpacity` dùng — kẹp số âm
    /// thành trong suốt hoàn toàn, ra đúng bằng nền.
    ///
    /// Cẩn thận một cái bẫy nằm ngay cạnh: `ShapeStyle.opacity`, tức
    /// `Color.blue.opacity(x)`, **không** kẹp — nó nhân thẳng vào alpha của màu
    /// và một alpha âm composite theo kiểu trừ mực, vẽ ra một bóng ma âm bản
    /// (đo được: nền `[255, 56, 60]`, mực xanh ở alpha −0,915 ra `[255, 0, 0]`).
    /// Hai thứ trùng tên. Chuỗi lập luận ở đây đứng được là nhờ chỗ áp
    /// `cardOpacity` dùng cái thứ nhất, nên **đừng đổi nó thành một `Color` có
    /// alpha**.
    ///
    /// Cái phải trả là một khoảng **trống dài hơn**, không phải một cú nhảy lộ
    /// ra: cú hồi phục xuất phát từ dưới 0 nên một cú morph bị cắt ngang nằm
    /// vô hình lâu hơn trước khi bắt đầu hiện. Chặn trên tính được: cú tụt là
    /// đúng −1.0 và giá trị trước đó ≥ 0, nên chỗ xuất phát tệ nhất là −1, và
    /// một `easeInOut` đi từ −1 tới 1 cắt qua 0 ở đúng giữa chặng. Tức **thêm
    /// tối đa nửa thời lượng của chính đường cong ấy: 0,185s khi chạm
    /// (`expand` 0,37s) và 0,145s khi thả tay (`settle` 0,29s)**. Tổng độ dài
    /// cú chuyển không đổi — chỉ phần đầu trống dài ra. Ghi lại chứ không chữa:
    /// chữa nó là quay về bản hai nửa có con dấu huỷ, tức đổi một khoảng trống
    /// dài hơn lấy một trạng thái mà một `completion` rơi mất sẽ để lại player
    /// vô hình vĩnh viễn.
    ///
    /// `curve` được dùng nguyên si cho cú hoà mờ, không đổi sang một hằng số
    /// riêng. Khi giảm chuyển động thì nó đã là nhánh phẳng của chính đường nó
    /// vốn chạy — 0.37s cho cú chạm, 0.29s cho cú đáp — và ghi chú của
    /// `BottomBarStyle.expand` đã kết luận sẵn rằng nếu quãng đường ấy thành
    /// một cú hoà mờ thì đây vẫn là độ dài đúng. Hai lối vào giữ nguyên nhịp
    /// khác nhau của chúng, đúng như khi còn là chuyển động.
    ///
    /// Cái mất, nói thẳng: trạng thái **cũ** bị cắt phụt chứ không tan dần.
    /// Đóng player thì thư viện hiện ra ngay trong một khung rồi viên thuốc mờ
    /// vào. Một cú hoà mờ chéo thật sự sẽ tránh được điều đó, và nó đòi hai bản
    /// thẻ cùng tồn tại ở hai `progress` khác nhau — tức phải luồn `progress`
    /// qua từng chỗ đọc nó trong 2.400 dòng của file này, đúng cái tái cấu trúc
    /// đang bị chặn. Xem b3-report. Một cú cắt không phải chuyển động, nên bản
    /// này đạt yêu cầu của HIG; nó chỉ chưa phải bản êm nhất có thể có.
    private func morph(to target: Double, curve: Animation) {
        guard BottomBarStyle.reduceMotion else {
            withAnimation(curve) {
                settled = target
                dragDelta = 0
                expansion.set(progress: target, animation: curve)
            }
            return
        }

        // Hỏi trước khi `settled` đổi: `progress` là chỗ xuất phát, và sau
        // dòng dưới thì nó đã là đích rồi.
        let needsFade = Self.morphNeedsFade(from: progress, to: target)

        // `Transaction(animation: nil)` viết rõ ràng chứ không phải gán trần.
        // Đây là chỗ duy nhất của cả tính năng, cú nhảy hình học phải là cú
        // nhảy thật, và `morph` được gọi từ nhiều nơi — một chỗ gọi nằm trong
        // `withAnimation` của ai đó là đủ để cú nhảy biến thành cú phóng to.
        //
        // `animation: nil` cho `expansion` vì cùng lẽ ấy: cú thu nhỏ nền không
        // được phép chạy một đồng hồ riêng ở đây. Khi giảm chuyển động thì
        // `BottomBarStyle.recedeScale` đã là 1 nên nó không vẽ ra gì — nhưng
        // truyền `nil` là nói đúng ý định thay vì dựa vào một hằng số ở file
        // khác tình cờ triệt tiêu biểu thức.
        withTransaction(Transaction(animation: nil)) {
            settled = target
            dragDelta = 0
            expansion.set(progress: target, animation: nil)
            if needsFade { cardOpacity = 0 }
        }

        if needsFade {
            withAnimation(curve) { cardOpacity = 1 }
        }
    }

    /// Bán kính hai góc **trên** của thẻ ở một `progress` cho trước.
    ///
    /// Thu gọn là một viên thuốc thật (32 = nửa chiều cao), mở hết là tấm thẻ
    /// Now Playing (38). Không bao giờ về 0 ở hai góc này.
    static func cardTopCornerRadius(progress: Double) -> CGFloat {
        collapsedCornerRadius
            + (expandedCornerRadius - collapsedCornerRadius) * progress
    }

    /// Bán kính hai góc **dưới**, cho những máy phải vẽ chúng cho đúng.
    ///
    /// Vuông dần về 0 khi mở, vì mép dưới của thẻ mở hết áp vào mép màn hình.
    static func cardBottomCornerRadius(progress: Double) -> CGFloat {
        collapsedCornerRadius * (1 - progress)
    }

    /// Thẻ có được phép cắt bằng **một** bán kính đều cho cả bốn góc không.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// VÌ SAO CÓ CÂU HỎI NÀY, VÀ NÓ ĐÁNG BAO NHIÊU
    /// ─────────────────────────────────────────────────────────────────────
    /// `UnevenRoundedRectangle` — bốn bán kính khác nhau — không có đường nào
    /// ánh xạ xuống `layer.cornerRadius` của Core Animation, vốn chỉ có **một**
    /// bán kính (`maskedCorners` chọn góc nào nhận nó, không cho mỗi góc một
    /// số). Nên SwiftUI phải dựng một mask layer, và mask là một lượt rasterize
    /// ngoài màn hình.
    ///
    /// **Đo được** (Color Offscreen-Rendered Yellow, Release, iPhone 12,
    /// 2026-08-18): với `UnevenRoundedRectangle`, **cả màn hình** bị tô vàng —
    /// nền danh sách, từng hàng, tiêu đề, thanh phân đoạn — ở **mọi** màn hình
    /// của app, kể cả khi player đóng, vì thẻ luôn nằm trong cây. Đổi sang một
    /// bán kính đều thì toàn bộ phần ấy sạch; chỉ còn `.thinMaterial` của viên
    /// thuốc và của thanh tab, mà Đợt A1 đã đo Material không kèm bóng ra
    /// 0,0 ms/giây. Người dùng xác nhận cú bung mượt hơn, thử tay trên Release.
    ///
    /// Đây là thứ mà bốn vòng đo `h1`–`k1` không thể thấy: bộ đo của chúng dừng
    /// ở `CATransaction.flush()`, tức chỉ đo pha commit, còn bảng A1 cho thấy
    /// 86% chi phí của lỗi cùng loại ở thanh tab nằm ở render và GPU.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// VÌ SAO KHÔNG PHẢI MÁY NÀO CŨNG ĐƯỢC
    /// ─────────────────────────────────────────────────────────────────────
    /// Một bán kính đều nghĩa là hai góc **dưới** cũng bo 38 khi mở hết, thay
    /// vì vuông về 0. Trên máy có màn hình bo góc thì không ai thấy: thiết bị
    /// tự cắt nhiều hơn thế (iPhone XS ~39pt, iPhone 12 ~47pt, 14 Pro ~55pt),
    /// nên góc bo 38 của thẻ nằm trọn trong phần đã bị cắt.
    ///
    /// Trên máy màn hình **góc vuông** — iPhone SE 2/3, iPad có nút Home — thì
    /// thấy rõ: hai lỗ tròn ở đáy player mở hết. Nên những máy ấy giữ hình cũ
    /// và giữ luôn cái giá cũ.
    ///
    /// **Phân biệt bằng safe-area inset dưới, không bằng model.** Đúng một lớp
    /// máy có màn hình bo góc: lớp có thanh Home ảo, và thanh ấy chính là thứ
    /// tạo ra inset dưới khác 0. Máy còn nút Home vật lý cho inset 0 và cũng là
    /// máy màn hình góc vuông. Không có API công khai đọc bán kính bo của màn
    /// hình, và cái private (`_displayCornerRadius`) thì không đáng đánh đổi
    /// với App Review khi đã có một dấu hiệu công khai nói đúng cùng chuyện.
    ///
    /// **Biên an toàn mỏng, và nó được ghim bằng test.** Máy có màn bo góc hẹp
    /// nhất mà iOS 18 còn chạy là iPhone XS / 11 Pro ở ~39pt, chỉ hơn
    /// `expandedCornerRadius` = 38 đúng 1pt. Nâng `expandedCornerRadius` lên 40
    /// là hở góc trên chính những máy này, và
    /// `testTheExpandedCornerStaysInsideTheNarrowestRoundedDisplay` đỏ ngay.
    static func cardCornerRadiiMayBeUniform(bottomSafeAreaInset: CGFloat) -> Bool {
        bottomSafeAreaInset > 0
    }

    /// Bán kính bo màn hình của máy hẹp nhất mà nhánh nhanh còn phải đúng —
    /// iPhone XS / 11 Pro. Xem `cardCornerRadiiMayBeUniform`.
    static let narrowestRoundedDisplayCorner: CGFloat = 39


    /// Quãng đổi có đáng giấu sau một cú hoà mờ không.
    ///
    /// **Cái này không phải chỉnh cho đẹp, nó chặn một lỗi thật.**
    /// `expand()` chạy từ `onChange(of: playback.explicitSelections)`, và
    /// `explicitSelections` tăng cả khi người dùng chạm một hàng trong
    /// `QueuePanel` — tức lúc thẻ *đang mở sẵn*. Ghi chú ở chỗ gọi ấy nói rõ
    /// đó là chuyện thường và vô hại: "animates 1 to 1, which is a no-op the
    /// spring resolves on its first frame". Với cú hoà mờ thì nó không còn vô
    /// hại: cả player sẽ chớp tắt rồi hiện lại mỗi lần chọn một bài trong hàng
    /// đợi. Cùng chuyện ấy với `collapse()` khi `currentTrack` về `nil` lúc thẻ
    /// đã đóng.
    ///
    /// 0.02 là **chọn, không phải đo** — và nó là quãng đường chứ không phải
    /// thời gian, nên nó không thuộc về `BottomBarStyle`. Trên một máy có
    /// `dragTravel` khoảng 800 điểm thì đó là 16 điểm: một cú nhảy cỡ một dòng
    /// chữ, thấy được nhưng không phải một cú morph, và giấu nó sau một cú chớp
    /// tắt tốn nhiều hơn nó che. Ngưỡng chỉ nói *quãng nào không đáng giấu*;
    /// quãng vẫn nhảy tức thì trong cả hai nhánh, nên nó không bao giờ để lọt
    /// một cú phóng to.
    ///
    /// Thuần và `static` vì cùng lý do `dragOffset` và `dragThreshold` là vậy:
    /// một cái rào mà sai thì không nhìn ra được, chỉ thấy player thỉnh thoảng
    /// chớp.
    static func morphNeedsFade(from current: Double, to target: Double) -> Bool {
        abs(target - current) > morphFadeMinimumTravel
    }

    /// Xem `morphNeedsFade(from:to:)`.
    static let morphFadeMinimumTravel: Double = 0.02

    /// - Parameter safeAreaSize / insets: the same geometry `card(size:insets:)`
    ///   lays out with, so the decode target matches what `artworkView` will
    ///   actually draw. See F2.
    private func loadArtwork() async {
        // Bail rather than clear: when the last track in the queue finishes,
        // `currentTrack` goes nil and this re-fires with a nil id while the
        // card is still mid collapse-and-fade. Clearing `artwork`/`tint` here
        // would flash a bare placeholder for that whole animation. Leaving
        // the last frame's artwork in place instead means it fades away with
        // the rest of the card. See F3.
        guard playback.currentTrack != nil else { return }

        let path = playback.currentTrack?.artworkRelativePath
        async let image = ArtworkStore.image(
            for: path,
            // **Hằng số dùng chung, không phải cỡ vẽ tính từ hình học.**
            //
            // Chỗ này từng là `artworkSide * displayScale` — cỡ vẽ thật, và đúng
            // hơn về nguyên tắc. Cái giá của "đúng hơn": nó cho 1026 trên iPhone
            // 12 trong khi màn khoá xin 1024, `cacheKey` băm theo
            // `Int(maxPixel)`, nên mỗi lần đổi bài app giải mã cùng một JPEG
            // **hai lần** — hai bitmap ~4MB cách nhau 2 pixel, song song ngay
            // lúc cú morph bắt đầu.
            //
            // Toàn bộ lý lẽ và đánh đổi ở doc của
            // `ArtworkStore.fullScreenCoverPixels`.
            maxPixel: ArtworkStore.fullScreenCoverPixels
        )
        async let colour = ArtworkStore.dominantColor(for: path)
        // Concurrently with the others, not after them: all read the same
        // cached decode chain, and the palette is the cheapest of them by a
        // wide margin — a 48px decode and a nine-pixel draw.
        let (loadedImage, loadedColour) = await (image, colour)

        guard playback.currentTrack?.artworkRelativePath == path else { return }
        artworkOwner = artworkIdentity
        artwork = loadedImage
        // Mốc thứ hai, và chỉ cho đúng nhánh này. Khi bản giải mã của chính thẻ
        // về nil thì `cachedCover` là thứ duy nhất còn vẽ được, mà cache có thể
        // đã có thêm ảnh cho đúng đường dẫn này kể từ lúc bài đổi. Có ít nhất
        // hai người ghi vào đó trong quãng ấy: một hàng danh sách vừa cuộn tới,
        // và `PlaybackService.loadArtworkIntoNowPlaying` — nó giải mã 1024px cho
        // màn khoá sau **mỗi** lần đổi bài, vô điều kiện, cho đúng đường dẫn
        // này. Khi `loadedImage` khác nil thì tra lại là thừa: `preferredCover`
        // cho bản đầy đủ thắng, và ảnh trong cache không được nhìn tới nữa.
        //
        // `path` ở đây là đường dẫn hiện tại — dòng `guard` ngay trên vừa đối
        // chiếu nó với bài đang phát — nên không có đường nào để một ảnh của
        // bài khác lọt vào.
        if loadedImage == nil {
            refreshCachedCover(for: path, owner: artworkIdentity)
        }
        tint = loadedColour
    }
}

/// Cắt thẻ theo hình của nó, bằng hình **rẻ nhất** mà máy này chấp nhận được.
///
/// Một `ViewModifier` chứ không phải một `.clipShape(AnyShape(...))`: `AnyShape`
/// xoá kiểu tĩnh của hình, và nhánh nhanh ở đây phụ thuộc đúng vào việc SwiftUI
/// **nhận ra** `RoundedRectangle` để hạ nó xuống `layer.cornerRadius`. Một cái
/// `if` trong `body` giữ nguyên kiểu ở cả hai nhánh.
///
/// Rẽ nhánh cấu trúc ở đây an toàn vì điều kiện là hằng số theo máy: safe-area
/// inset dưới không đổi giữa các khung, nên `_ConditionalContent` không bao giờ
/// lật và không có gì bị tháo ra gắn lại giữa cú morph. Xoay máy đổi *độ lớn*
/// của inset chứ không đổi việc nó khác 0.
///
/// Toàn bộ lý lẽ, số đo, và vì sao SE phải đi đường khác: xem
/// `PlayerCard.cardCornerRadiiMayBeUniform(bottomSafeAreaInset:)`.
private struct CardClip: ViewModifier {
    let progress: Double
    let insets: EdgeInsets

    func body(content: Content) -> some View {
        let top = PlayerCard.cardTopCornerRadius(progress: progress)
        if PlayerCard.cardCornerRadiiMayBeUniform(bottomSafeAreaInset: insets.bottom) {
            content.clipShape(RoundedRectangle(cornerRadius: top, style: .continuous))
        } else {
            content.clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: top,
                    bottomLeadingRadius: PlayerCard.cardBottomCornerRadius(progress: progress),
                    bottomTrailingRadius: PlayerCard.cardBottomCornerRadius(progress: progress),
                    topTrailingRadius: top
                )
            )
        }
    }
}

/// Lớp nền đục và lớp sương của tấm thẻ, cả hai đọc **giá trị đang được vẽ**.
///
/// ─────────────────────────────────────────────────────────────────────────
/// VÌ SAO PHẢI LÀ MỘT `Animatable` RIÊNG
/// ─────────────────────────────────────────────────────────────────────────
/// Hai lớp này từng nằm thẳng trong `background` và đọc `progress` — tức giá
/// trị trong `body`. Trên đường **kéo tay** điều đó đúng: `body` chạy lại mỗi
/// khung nên `progress` là chỗ tấm thẻ đang thật sự ở. Trên đường
/// **`withAnimation`** thì không: `settled` nhảy thẳng tới đích, nên `progress`
/// đọc trong `body` **đã là giá trị cuối ngay từ khung đầu**, và thứ SwiftUI
/// nội suy là bản thân các modifier sinh ra từ nó.
///
/// Hậu quả đo được, từ video người dùng quay cú thu nhỏ: ở khung có mép thẻ
/// 338pt — `progress` ≈ 0,52, chỗ mà lớp nền đáng ra đã đục hẳn — vẫn đọc được
/// tên các hàng danh sách xuyên qua tấm thẻ. Vì `.opacity` được tính ở
/// `progress` = 0 rồi nội suy từ 1 xuống 0 suốt cả cú lò xo, nên giữa đường nó
/// là ~0,5 bất kể tấm thẻ đang to bằng nào. Và lớp sương thì ngược lại: cái
/// `if` đúng ngay khung đầu nên nó được **chèn** vào ở cường độ đầy đủ, không
/// nội suy gì. Cộng lại: tấm thẻ trong mờ và bị làm mờ suốt cú thu, rồi trả về
/// nguyên trạng một phát khi xong — đúng thứ người dùng báo.
///
/// `Animatable` trên một view **lá** như thế này không phải cách mà `b8a94d6`
/// đã làm và `b14ad5d` đã hoàn nguyên: ở đó nó bắt cả `PlayerCard.body` chạy
/// lại mỗi khung. Ở đây chỉ thân của chính kiểu này chạy lại — cùng khuôn với
/// `PresentedOpacity` ngay dưới, với `Slot` trong `ReorderableStack`, và với
/// `PlaybackScrubber`.
///
/// ─────────────────────────────────────────────────────────────────────────
/// LỚP SƯƠNG HIỆN RA TỪ 0, KHÔNG BẬT RA Ở 0,9
/// ─────────────────────────────────────────────────────────────────────────
/// Cái `if` vẫn còn, và vẫn cố ý — một `.thinMaterial` là một cú làm mờ trực
/// tiếp, và nó tốn như nhau ở opacity 0,01 hay 1, nên giữ nó trong cây suốt cú
/// morph là trả tiền cho một thứ không ai thấy. Nhưng giờ nó gắn vào đúng lúc,
/// và **gắn ở opacity 0**: `1 - progress / materialCutoff` bằng 0 ngay tại mốc
/// gắn và bằng 1 ở trạng thái nghỉ. Bản cũ dùng `1 - progress`, tức gắn vào ở
/// 0,9 — một cú bật.
private struct CardSurface: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .opacity(min(1, progress * PlayerCard.opaqueBaseRamp))
            if progress < PlayerCard.materialCutoff {
                Rectangle()
                    .fill(.thinMaterial)
                    .opacity(max(0, 1 - progress / PlayerCard.materialCutoff))
            }
        }
    }
}

/// Áp một độ mờ **và** cho hit testing đi theo đúng giá trị đang được *vẽ*.
///
/// ─────────────────────────────────────────────────────────────────────────
/// VÌ SAO CẦN MỘT KIỂU RIÊNG, KHI `.allowsHitTesting` LÀ MỘT DÒNG
/// ─────────────────────────────────────────────────────────────────────────
/// Trong SwiftUI, khác với `alpha` của UIKit, một view ở `opacity` 0 **vẫn
/// nhận chạm**. Nhánh giảm chuyển động của `PlayerCard.morph(to:curve:)` nhảy
/// hình học tới toàn màn hình rồi hạ `cardOpacity` về 0 và hoà mờ về 1 trong
/// `expandFlat` = 0,37s, nên suốt quãng ấy có một tấm player tràn màn hình
/// không nhìn thấy nằm chắn trên thư viện. Chạm một hàng bài mình vẫn còn
/// trông thấy thì cú chạm rơi vào tấm player vô hình. Trước đợt này thẻ đục
/// suốt cú mở, nên **cái vẽ ra luôn khớp với cái chạm được**; đây là chỗ khôi
/// phục điều đó.
///
/// `.allowsHitTesting(cardOpacity > 0)` viết thẳng trong `body` **không chữa
/// được gì**, và lý do đáng ghi lại: `cardOpacity` trong `body` là giá trị
/// trong *state*, không phải giá trị đang vẽ. Nó nhảy về 1 ngay trong lượt
/// `withAnimation` ấy — chỉ có cái SwiftUI nội suy mới đi từ 0 lên. Muốn đọc
/// được giá trị đang vẽ thì phải là `animatableData`, và `animatableData` chỉ
/// tồn tại trên một `Animatable`.
///
/// ─────────────────────────────────────────────────────────────────────────
/// NGƯỠNG 0,5 LÀ **CHỌN**, KHÔNG PHẢI ĐO
/// ─────────────────────────────────────────────────────────────────────────
/// Cùng loại quyết định với `PlayerCard.morphFadeMinimumTravel`, và cùng nên
/// nói thẳng ra. Giữa chừng cú hoà mờ, cả hai lớp đều nhìn thấy được một
/// phần, nên không có câu trả lời đúng tuyệt đối — chỉ có hai kiểu lệch:
///
///   - Ngưỡng quá thấp: thẻ ăn chạm khi nó gần như vô hình. Đó đúng là lỗi
///     đang chữa, chỉ ngắn hơn.
///   - Ngưỡng quá cao: thẻ đã hiện rõ mà chạm vẫn xuyên qua xuống thư viện —
///     tệ theo chiều ngược lại, và tệ hơn, vì cú chạm ấy đổi bài đang phát.
///
/// Nửa đường chia đôi hai kiểu lệch ấy: lớp nào đang đục hơn thì lớp ấy nhận
/// chạm. Không có con số đo được nào tốt hơn nửa đường ở đây.
///
/// Với `cardOpacity` xuất phát từ số **âm** — xem `morph(to:curve:)`, cú morph
/// đè lên một cú hoà mờ đang chạy — ngưỡng này chỉ kéo dài thêm chính khoảng
/// trống mà ghi chú ấy đã ghi lại và chấp nhận. Không có trạng thái mới nào.
///
/// ─────────────────────────────────────────────────────────────────────────
/// GIẢM CHUYỂN ĐỘNG TẮT: KHÔNG ĐỔI MỘT DÒNG NÀO
/// ─────────────────────────────────────────────────────────────────────────
/// `cardOpacity` chỉ được ghi trong nhánh giảm chuyển động của `morph`. Khi
/// tắt, nó là hằng số 1 từ lúc dựng, `animatableData` không bao giờ nội suy,
/// nên `opacity >= 0.5` luôn đúng và modifier này là `.opacity(1)` cộng một
/// `.allowsHitTesting(true)` — đúng bằng dòng `.opacity(cardOpacity)` nó thay.
///
/// `content.opacity(_:)` là `View.opacity`, **không** phải `ShapeStyle.opacity`
/// — cả chuỗi lập luận về số âm ở `morph(to:curve:)` đứng trên chỗ ấy, nên
/// đừng đổi nó thành một `Color` có alpha.
private struct PresentedOpacity: ViewModifier, Animatable {
    var opacity: Double

    var animatableData: Double {
        get { opacity }
        set { opacity = newValue }
    }

    /// Xem ghi chú của kiểu này: chọn, không đo.
    static let hitTestThreshold: Double = 0.5

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .allowsHitTesting(opacity >= Self.hitTestThreshold)
    }
}
