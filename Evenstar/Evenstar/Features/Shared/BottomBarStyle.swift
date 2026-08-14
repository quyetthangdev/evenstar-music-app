import SwiftUI

/// How the floating bottom surfaces look and move.
///
/// The counterpart to `BottomBarMetrics`, which owns *where* they are. Between
/// them: Metrics answers "how big and how far in", Style answers "what it looks
/// like and how it gets there".
///
/// It exists because the pieces down there are separate views that must read as
/// one system. The collapsed player and the tab bar sit on the same screen and,
/// while minimised, on the same row — a shadow on one and none on the other is
/// visible immediately, and two morphs on different springs read as two
/// unrelated things happening at once.
///
/// It also fixes a dependency that pointed the wrong way. The springs used to
/// live on `FloatingTabBar`, so `ScrollMinimise` and `RootView` reached into a
/// *view* to find out how fast to animate. Anything new down here should take
/// its motion from this type, not from whichever view happens to define it.
enum BottomBarStyle {

    // MARK: - Motion

    /// A surface changing shape: the tab pill collapsing to a circle, the
    /// search field growing, the collapsed player sliding into the row.
    ///
    /// Written as `duration`/`bounce` rather than `response`/`dampingFraction`.
    /// The two describe the same family of springs, but this pair names what it
    /// does — `bounce` 0 stops on arrival, higher springs past and returns —
    /// where the older pair inverts that axis, since higher damping means less
    /// bounce.
    ///
    /// The two are not independent: `bounce` is a *proportion* of the duration,
    /// so shortening the spring flattens the same bounce value. Past about 0.4
    /// it wobbles rather than settles, and well before that it starts arriving
    /// hard — a high bounce over a short duration snaps back from its overshoot
    /// instead of easing into place.
    static let morph = Animation.spring(duration: 0.36, bounce: 0.24)

    /// The selected tab's wash travelling to the tab just tapped.
    ///
    /// Deliberately bouncier than `morph`. That one is scenery rearranging
    /// itself and should get out of the way; this is direct feedback for a tap
    /// the user just made, and can afford to be more alive. The extra bounce is
    /// what makes it read as liquid — arriving past the new tab and settling
    /// back — where a calmer curve reads as merely sliding.
    static let selection = Animation.spring(duration: 0.38, bounce: 0.34)

    /// How a tab answers the finger, before anything has moved.
    ///
    /// 0.09s ease-out, the same figure `TransportButtonStyle.kickDuration` now
    /// carries, and for the same reason: it is the part that has to be
    /// immediate. (That style once had a matching `squeeze` constant named
    /// here; it was removed when its buttons moved to touch-down, because a
    /// held-press squeeze cancelled out the kick that replaced it.) A tab
    /// carried no press feedback at all — `.buttonStyle(.plain)` draws none —
    /// so the first thing that happened after a tap happened on touch-*up*,
    /// once the wash began to slide. Everything before that was the app
    /// appearing not to have noticed.
    static let press = Animation.easeOut(duration: 0.09)

    /// What a pressed tab shrinks to. Shallower than the transport buttons'
    /// 0.92: those are 44pt circles the thumb lands on squarely, while a tab is
    /// a whole quarter of the bar, and the same ratio on something that wide
    /// reads as the bar itself flinching.
    static let pressedScale: CGFloat = 0.96

    /// Content inside a surface as that surface changes shape: icons and labels
    /// shrinking and fading as the pill closes over them.
    ///
    /// Quicker and calmer than `morph` on purpose. The surface closing around
    /// them is the gesture; the glyphs should feel carried by it rather than
    /// staging a second performance inside it.
    static let content = Animation.spring(duration: 0.34, bounce: 0.20)

    /// A surface settling after the user let go of it, or moving to an end
    /// state they asked for: the player card released mid-drag, collapsing when
    /// the queue empties, expanding on a tap.
    ///
    /// Longer and much calmer than `morph`. That one is a surface rearranging
    /// itself while the user watches; this one finishes a gesture the user was
    /// steering, and overshoot there fights the hand that just let go rather
    /// than decorating it.
    ///
    /// This replaced two springs that claimed to be different and were not:
    /// `response: 0.42, dampingFraction: 0.86` for the settle and
    /// `response: 0.45, dampingFraction: 0.85` for the expand — 0.42/0.14 and
    /// 0.45/0.15 in these units, a difference of three hundredths of a second
    /// and one hundredth of bounce. A comment described the second as
    /// "snappier"; it was in fact the slower of the two.
    static let settle = Animation.spring(duration: 0.42, bounce: 0.14)

    private static let settleDuration: Double = 0.42
    private static let settleBounce: Double = 0.14

    /// `settle`, but starting at the speed the finger was already moving.
    ///
    /// **This is the difference between a surface that was let go of and one
    /// that was told where to be.** A plain spring always starts from rest, so a
    /// violent flick and a gentle release produce animations identical to the
    /// pixel — they differ in where they end up, never in how they get there,
    /// and the moment of release has a visible discontinuity in speed. Handing
    /// the gesture's own velocity to the spring removes that seam, and it is
    /// what every system sheet does.
    ///
    /// `interpolatingSpring` rather than `spring`: only that family accepts an
    /// initial velocity, and it is also velocity-preserving if it is retargeted
    /// mid-flight, which is the right behaviour for a surface the user may grab
    /// again before it has settled.
    ///
    /// - Parameter initialVelocity: in units of the *remaining* distance per
    ///   second — 1 means "would arrive in one second at this speed". The caller
    ///   converts, because only it knows the travel and how far is left.
    static func settle(initialVelocity: Double) -> Animation {
        .interpolatingSpring(
            duration: settleDuration,
            bounce: settleBounce,
            initialVelocity: initialVelocity
        )
    }

    /// The largest initial velocity worth handing to `settle(initialVelocity:)`.
    ///
    /// A hard flick released a few points from its destination divides a large
    /// speed by a nearly-zero remaining distance, and the result is a spring
    /// that shoots far past its target and swings back. The clamp is not a
    /// fudge for that arithmetic — it is the same limit a real sheet has, which
    /// is that past a certain speed the surface simply arrives.
    static let maxSettleVelocity: Double = 18

    /// The collapsed player opening to full screen, and closing again.
    ///
    /// Separate from `settle`, and this distinction is real where the one it
    /// replaced was not. `settle` finishes a drag the user was steering: it
    /// covers whatever is left of the travel, often a fraction of the screen.
    /// This one covers the whole height in a single move — around 750pt on a
    /// phone — and a spring tuned for the short case reads as abrupt over that
    /// distance, arriving before the eye has followed it.
    ///
    /// Longer and calmer accordingly. Not bounce-free: a little overshoot is
    /// what keeps a large move from feeling mechanical, but far less than a
    /// short one can carry.
    static let expand = Animation.spring(duration: 0.52, bounce: 0.12)

    /// How the content behind the player recedes as it opens, the way a sheet
    /// pushes its presenting screen back.
    ///
    /// The scale is small on purpose. iOS's own card presentation moves the
    /// screen behind it by only a few percent; more than that stops reading as
    /// depth and starts reading as the app shrinking.
    static let recedeScale: CGFloat = 0.92
    // A `recedeCornerRadius` stood here, rounding the receding content the way
    // a sheet's backdrop is rounded. It was removed rather than tuned: applying
    // it meant clipping the whole screen to a shape on every frame of a drag,
    // which is a mask and an offscreen pass, and the recede was visibly rough
    // because of it. `recedeScale` above is a transform and costs nothing by
    // comparison.
    //
    // If the corners are wanted back, round a static backdrop behind the
    // content instead of masking the content itself.

    /// A control inside one of these surfaces reacting to touch — the
    /// scrubber swelling under a finger.
    ///
    /// A curve, not a spring: it is a state change on a small element, not a
    /// mass arriving somewhere, and a bounce on a 5pt height change is noise.
    static let control = Animation.easeOut(duration: 0.15)

    /// The queue panel opening and closing.
    ///
    /// Given as mass/stiffness/damping rather than duration/bounce because
    /// those are the terms it was specified in. Damping ratio is
    /// `22 / (2 * sqrt(180))` ≈ 0.82 and it settles in roughly 0.36s — firm,
    /// with barely any overshoot.
    ///
    /// **It drives three things and only three:** the capsule's fade-and-grow,
    /// the list's rise, and `queueFactor` — which is the artwork's shrink,
    /// since that is the value the shrink interpolates on. Those are parts of
    /// one gesture and must share a clock or they will visibly disagree.
    ///
    /// It is deliberately *not* `settle`. A drag-collapse begun while the queue
    /// is open already runs two clocks — `progress` tracks the finger while
    /// `queueFactor` runs a spring — and a third timing character makes that
    /// harder to read. If a slow collapse-drag with the queue open ever looks
    /// like two objects moving separately rather than one thing folding away,
    /// the answer is to point this at `settle` and let both share it.
    /// Đo từ Apple Music, không phải chọn.
    ///
    /// Ảnh quay 30fps cú mở và cú đóng hàng đợi, lấy cạnh tấm bìa theo từng
    /// khung rồi chuẩn hoá về 0…1: 0.14 ở 33ms, 0.40 ở 67ms, 0.61 ở 100ms,
    /// 0.86 ở 167ms, 0.92 ở 200ms, đứng yên quanh 350ms. Dãy ấy khớp
    /// `1 − (1 + ωt)·e^(−ωt)` với ω ≈ 20 rad/s trong hai phần trăm — tức một lò
    /// xo **tắt dần tới hạn**, và `response = 2π/ω = 0.31`.
    ///
    /// Không vọt lố ở bất kỳ khung nào, cả hai chiều. Bản trước là
    /// `Spring(stiffness: 180, damping: 22)`: ω 13.4 và hệ số tắt dần 0.82 —
    /// chậm hơn một phần ba, và có nảy.
    ///
    /// `bounce: 0` chính là hệ số tắt dần 1.0; `duration` ở dạng khởi tạo này
    /// là `response`, không phải thời gian chạy.
    static let queue = Animation.spring(Spring(duration: 0.31, bounce: 0))

    /// Ba khối trong `QueuePanel` — chữ header, hai viên thuốc, danh sách —
    /// hiện ra và trượt lên theo **nhịp riêng**, không theo `queueFactor`.
    ///
    /// Đo từ Apple Music: cú hiện bắt đầu ở khung thứ 6 của cú morph (~190ms)
    /// và xong ở khung thứ 11 (~360ms). Quy ra `queueFactor` thì đó là quãng
    /// 0.92 → 1.0 — tức **cái đuôi** của lò xo.
    ///
    /// **0.17 giây, không phải 0.26.** Con số cũ tôi tự đặt; 0.17 là đo được —
    /// năm khung. Chênh lệch ấy là cả một lỗi về pha: với 0.26 thì panel trượt
    /// xong ở 0.41 giây, trong khi tấm bìa đã đứng yên từ khoảng 0.30
    /// (`p = 0.99` ở `t = 0.28`). Panel về đích *sau khi* cú morph đã hết, và
    /// hai sự kiện rời nhau đúng ở chỗ chúng phải liền.
    ///
    /// `delay(0.02)` chồng lên `completion` của `queueTitleOut`, vốn kết thúc ở
    /// 0.17 — nên cú hiện chạy 0.19 → 0.36, khớp số đo. Ăn khớp về pha không có
    /// nghĩa là dán sát: hai phần trăm giây ở đây là chỗ Apple để trống, và mắt
    /// không đọc nó ra là trống vì tấm bìa vẫn đang đi (`p` 0.90 → 0.99).
    ///
    /// Và cái đuôi ấy là chỗ không diễn đạt được bằng một phép ánh xạ trên
    /// `queueFactor`: SwiftUI cắt lò xo khi sai số đủ nhỏ, đúng vào giữa quãng
    /// đó, nên thứ còn lại là một cú nảy ra chứ không phải một cú hiện dần.
    /// Nới cửa sổ cho thấy được thì lại đi xa Apple. Một nhịp riêng có `delay`
    /// nói đúng điều Apple làm, và nói được.
    ///
    /// `bounce: 0`: các bước đo được giảm dần đều — 15, 8, 4, 4, 1 điểm mỗi
    /// khung — không có khung nào vượt qua đích. Đây không phải chỗ đàn hồi.
    static let queueContentIn = Animation.easeOut(duration: 0.13)

    /// Cùng ba khối ấy **trượt** về chỗ, và nó dài hơn cú hiện ở trên.
    ///
    /// Đây là chỗ tôi gộp sai suốt mấy vòng vừa rồi. Đo lượng mực của khối chữ
    /// "There's no music in the queue" qua từng khung: 52% → 74% → 90% → 98%
    /// trong bốn khung (~0.13s). Còn *vị trí* của chính khối ấy thì đi tiếp tới
    /// khung thứ chín (~0.27s). Apple cho khối chữ **đọc được nhanh rồi mới
    /// thong thả về chỗ**.
    ///
    /// Buộc hai thứ vào một giá trị thì khối chữ còn nửa trong suốt khi còn
    /// cách đích khá xa — mắt thấy một vật vừa mờ vừa trôi, và đó là cái không
    /// ăn khớp.
    ///
    /// `response = 0.20` khớp dãy tiến độ đo được (0, .373, .655, .791, .882,
    /// .927, .964, .982, .991, 1) với sai số trung bình 2.8%.
    static let queueContentSlide = Animation.spring(Spring(duration: 0.20, bounce: 0))

    /// Chiều ngược lại **không trễ, và nhanh hơn**.
    ///
    /// Cũng đo được: đóng hàng đợi thì ba khối biến mất trong hai tới ba khung,
    /// ngay từ đầu. Đối xứng ở đây là sai — thứ đang đi khỏi màn hình không có
    /// lý do gì để chờ, và giữ nó lại là giữ một tấm bảng chắn trước tấm bìa
    /// đang lớn dần.
    static let queueContentOut = Animation.easeIn(duration: 0.10)

    /// Khối chữ lớn của `NowPlayingContent` tan đi khi hàng đợi mở.
    ///
    /// Trễ 0.07s và dài 0.07s, đo bằng lượng mực của khối chữ qua từng khung:
    /// 963 → 957 → 925 → 872 → 633 → 0. Tức nó đứng gần như nguyên vẹn hai
    /// khung đầu, mất một phần ba ở khung thứ tư, và hết ở khung thứ năm.
    ///
    /// Mốc cũ 0.10 → 0.17 là ước lượng đọc bằng mắt trên một tấm ghép khung, và
    /// nó muộn hơn thật một khung rưỡi.
    ///
    /// `easeOut` chứ không `easeIn`, và đó là chuyện của **mối nối**. `easeIn`
    /// kết thúc ở vận tốc lớn nhất: chữ đứng gần như đủ sáng rồi tắt phụt. Cú
    /// hiện tiếp sau là một lò xo, khởi động từ vận tốc 0. Nối một cái đang lao
    /// vào một cái đang đứng yên là một chỗ gãy. `easeOut` về 0 với vận tốc
    /// cũng gần 0, nên hai đầu khớp nhau về đạo hàm chứ không chỉ về thời điểm.
    ///
    /// **Viết thành thời gian chứ không phải cửa sổ trên `queueFactor`, và đó
    /// là điều bắt buộc.** Một cửa sổ trên `factor` chạy ngược khi đóng, nên nó
    /// đặt cú hiện lại của khối chữ vào quãng 0.032s – 0.102s — nằm gọn bên
    /// trong quãng `queueContentOut` đang tan. Hai khối chữ lấn nhau, và không
    /// có cặp số nào trên một trục duy nhất tách được chúng ở cả hai chiều.
    static let queueTitleOut = Animation.easeIn(duration: 0.06).delay(0.04)

    /// Chiều ngược lại, và nó **đợi `queueContentOut` xong hẳn**.
    ///
    /// `delay(0.13)` chồng lên `completion` của `queueContentOut` (kết thúc ở
    /// 0.10), nên cú hiện chạy 0.23 → 0.33 — số đo của Apple ở chiều đóng.
    ///
    /// Khe ở đây rộng hơn hẳn chiều mở, và có lý do: lúc ấy tấm bìa đang lớn
    /// dần từ `p` 0.10 xuống 0.05 theo cách đọc ngược — vẫn là phần *thấy rõ*
    /// nhất của cú morph. Nhét khối chữ vào giữa đó là hai thứ tranh nhau. Thứ tự khi đóng vì thế là
    /// nghịch đảo đúng của thứ tự khi mở: ba khối panel đi trước, khối chữ lớn
    /// quay lại sau, không lúc nào cả hai cùng đọc được.
    static let queueTitleIn = Animation.easeOut(duration: 0.10).delay(0.13)

    // MARK: - Surface

    /// What lifts a floating surface off the content behind it.
    ///
    /// Constant — never interpolated with any progress value. A shadow forces
    /// an offscreen pass, and one whose radius changes per frame forces a fresh
    /// one every frame on a view that is already moving. **If the bar or the
    /// player ever drops frames while animating, this is the first thing to
    /// remove**; nothing else down here draws offscreen.
    ///
    /// The expanded player needs no exception: at full screen it covers
    /// everything, so its shadow is occluded rather than wasted.
    private static let shadowColor = Color.black.opacity(0.15)
    private static let shadowRadius: CGFloat = 10
    private static let shadowOffsetY: CGFloat = 4

    /// Applies the shared shadow. Use this rather than restating the numbers,
    /// so a surface added later cannot land with a slightly different lift.
    static func floatingShadow<V: View>(_ view: V) -> some View {
        view.shadow(color: shadowColor, radius: shadowRadius, y: shadowOffsetY)
    }
}

extension View {
    /// The shadow every floating bottom surface shares. See
    /// `BottomBarStyle.floatingShadow`.
    func floatingBarShadow() -> some View {
        BottomBarStyle.floatingShadow(self)
    }
}
