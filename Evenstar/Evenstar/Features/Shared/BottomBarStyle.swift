import SwiftUI

/// How the player and the controls around it move.
///
/// The name is older than the current layout: this file used to style a
/// hand-drawn floating tab bar as well. The tab bar and its accessory are the
/// system's now (iOS 26), and what is left here is motion — the player card's
/// springs, the press feedback, the queue's choreography.
///
/// It exists because the pieces are separate views that must read as one
/// system: two morphs on different springs read as two unrelated things
/// happening at once. Anything new should take its motion from this type, not
/// from whichever view happens to define it.
enum BottomBarStyle {

    // MARK: - Motion

    /// Whether the system's **Reduce Motion** setting is on.
    ///
    /// Every `Animation` below branches on this, so one switch in
    /// Settings → Accessibility changes the whole bottom bar's motion
    /// vocabulary at once.
    ///
    /// **Written from exactly one place: `RootView`.** It holds the app's only
    /// `@Environment(\.accessibilityReduceMotion)` and pushes the value here
    /// from an `.onChange(of:initial:true)` action. `initial: true` is what
    /// makes the flag right on the first frame rather than only after the user
    /// toggles the setting mid-session. The write is in an action closure and
    /// never inside a `body`: mutating global state while SwiftUI is evaluating
    /// a view is undefined behaviour.
    ///
    /// A static rather than an environment value, for two reasons. The weaker
    /// one is reach — `BottomBarStyle` has no instances, and
    /// `TransportButtonStyle`, `QueueToggleStyle` and `TapHalo` are
    /// `ButtonStyle`s and `ViewModifier`s that cannot read the environment
    /// where the constant is actually needed. The stronger one is agreement:
    /// the player's morph is run by `PlayerCard` and, on the same curve, by
    /// the recede behind it (`RecedeBehindPlayer`), and if those two disagreed
    /// within a frame the two halves of one morph would run different curves —
    /// a worse bug than having no reduced mode at all. A single storage
    /// location makes that disagreement impossible to express rather than
    /// merely unlikely: filter once, in one place, instead of asking every
    /// reader to remember.
    ///
    /// **When a change takes effect.** `withAnimation(BottomBarStyle.x)` reads
    /// the constant at the moment of the write, so those sites are always
    /// current. `.animation(BottomBarStyle.x, value: v)` captures its curve
    /// when the enclosing `body` runs, which sounds like a stale-curve trap and
    /// is not one: that modifier only fires when `v` differs from the previous
    /// evaluation, and `v` is produced by the same `body`, so any evaluation
    /// that can change `v` has re-read the constant on the way. There is no
    /// reachable state in which a flag flipped after a `body` ran lets that
    /// body's stale spring play. What *is* accepted deliberately: an animation
    /// already in flight when the user flips the setting finishes on the curve
    /// it started with — retargeting mid-flight would be a visible seam, and
    /// the next one is already correct.
    ///
    /// **Neither of those two is how this feature mostly reads the flag, and
    /// this paragraph used to stop before saying so.** The dominant mechanism
    /// is a **structural branch**: a `body` that asks `reduceMotion` and returns
    /// a *different view* — `TapHalo.body`, `symbolReplace()`, and until the
    /// tab bar became the system's, three of the hand-drawn bar's own views.
    /// That case is not
    /// covered by the argument above, because there is no `v` and no
    /// `withAnimation` to re-read anything: it depends on SwiftUI re-evaluating
    /// the `body` at all after the flag changes, which is a different claim.
    ///
    /// It holds, and it is measured rather than assumed — the flag is written
    /// from `RootView`, which re-renders the tree, so the first render that can
    /// see the new value is also the one that picks the new structure. (The
    /// test that pinned this changed tab on the hand-drawn bar and went with
    /// it; the structural readers left are `TapHalo` and `symbolReplace()`.)
    @MainActor static var reduceMotion = false

    // Where the `…Flat` durations below come from — none of them is invented.
    //
    // Each is the time its own spring **first crosses 98%** of the target,
    // found by sampling `Spring(duration:bounce:)` with `value(target:time:)`
    // at 1ms and rounding to the hundredth this file is written in.
    //
    // Crossing 98% on the way *up*, and nothing more than that. An earlier
    // draft of this comment said "reaches 98% and stays there", which is
    // arithmetically true — none of the seven dips back under 98% afterwards,
    // the second undershoot being four *tenths* of a percent even for the
    // bounciest — but it reads as "and then it has arrived", and two of them
    // have not. `morph` carries on to 102.5% and `selection` to 106.3% past
    // the times in the table, and each spends a further third of a second
    // coming back down.
    //
    // That figure read "four hundredths" until B3, and it was wrong by a
    // factor of ten for the one case it names. Sampled the same way as the
    // table: `selection`, the bounciest, troughs at 99.5994% — 0.4006% under —
    // and `morph` at 99.9356%, 0.0644% under. So the old "four hundredths" was
    // roughly `morph`'s number wearing `selection`'s name, and against
    // `selection`'s real 0.4006% it is the factor of ten above.
    //
    // **`morph` and `selection` are 6.2 times apart, not ten.** 0.4006 / 0.0644
    // = 6.22, and that ratio — not ten — is what
    // `ReduceMotionTests.testTheSecondUndershootIsFourTenthsOfAPercentForTheBounciest`
    // executes. The ten belongs only to the *quoted* figure against the
    // constant it was quoted for; the two constants themselves were never ten
    // apart, and a block written to fix a factor-of-ten error should not leave a
    // second one behind it. The trough depth is a function of the damping ratio *alone* —
    // `e^(−2πζ/√(1−ζ²))` with `ζ = 1 − bounce` — which is why it ranks by
    // bounce, why `selection` is the worst case, and why no duration from the
    // table appears in it. `queue` and `queueContentSlide`, at bounce 0, have
    // no second undershoot at all.
    //
    // The conclusion is untouched, and that is the point of correcting the
    // number rather than deleting the clause: 0.4006% is nowhere near the two
    // whole points it would take to re-cross 98% from above.
    //
    // Timing against the crossing rather than against the settled state is the
    // point, not a shortcut around it: the overshoot is exactly what Reduce
    // Motion exists to remove, so measuring the flat variant against the tail
    // of a bounce would make it *slower* than the motion it replaces. That is
    // the opposite of the same tempo.
    //
    // 98% rather than 100% because the last two percent of a spring is not
    // motion anyone reads — `queue`'s own note below measures Apple Music
    // standing still around 350ms while the analytic spring is still creeping,
    // and `queueContentIn`'s note records SwiftUI cutting a spring off inside
    // that same tail.
    //
    //   constant             spring       t(98%)   flat
    //   morph                0.36 / 0.24  0.199    0.20
    //   selection            0.38 / 0.34  0.177    0.18
    //   content              0.34 / 0.20  0.204    0.20
    //   settle               0.42 / 0.14  0.287    0.29
    //   expand               0.36 / 0.12  0.258    0.26
    //   queue                0.31 / 0     0.288    0.29
    //   queueContentSlide    0.20 / 0     0.186    0.19
    //
    // The harness is checkable against this file: sampling `queue` at 30fps
    // gives 0.147, 0.391, 0.601, 0.851, 0.912 where the frame-by-frame Apple
    // Music numbers in its doc comment are 0.14, 0.40, 0.61, 0.86, 0.92.
    //
    // Two consequences worth naming rather than discovering later. `morph` and
    // `content` land on the same flat duration: what separated them was bounce
    // (0.24 against 0.20) and reducing motion is precisely the removal of that.
    // And `selection`, the bounciest of the set, comes out *shortest* — a
    // bouncier spring is stiffer for the same duration, so it arrives sooner
    // and spends the difference overshooting. Both are honest results of
    // dropping the overshoot, not rounding accidents.
    //
    // Six constants below — `press`, `control`, `queueContentIn`,
    // `queueContentOut`, `queueTitleOut`, `queueTitleIn` — are already duration
    // curves driving a fade or a 5pt swell, with no displacement to take out,
    // so their flat branch is the full one spelled `xFlat = xFull`. They are
    // still written through the branch rather than left as plain `let`s, so
    // that every motion constant in this type answers `reduceMotion` and a
    // future edit to one of them has somewhere obvious to put a second answer.
    // What actually disappears for those six is the scale and the offset at
    // their call sites, which is B3/B4's job, not this file's.

    /// A surface changing shape. Written for the hand-drawn tab bar, which the
    /// system's has replaced; nothing in the app reads it now, and the suite
    /// still pins its values.
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
    ///
    /// Reduced: 0.20s `easeInOut`, the point at which the spring above is
    /// visually done. The shape-change itself stays — a surface changing shape
    /// is the surface telling the user what it now is, and removing it would
    /// leave two indistinguishable states rather than a calmer transition. What
    /// goes is the overshoot: the surface no longer arrives past its own edge
    /// and swings back.
    @MainActor static var morph: Animation { reduceMotion ? morphFlat : morphFull }
    private static let morphFull = Animation.spring(duration: 0.36, bounce: 0.24)
    private static let morphFlat = Animation.easeInOut(duration: 0.20)

    /// The selected tab's wash travelling to the tab just tapped.
    ///
    /// Deliberately bouncier than `morph`. That one is scenery rearranging
    /// itself and should get out of the way; this is direct feedback for a tap
    /// the user just made, and can afford to be more alive. The extra bounce is
    /// what makes it read as liquid — arriving past the new tab and settling
    /// back — where a calmer curve reads as merely sliding.
    ///
    /// Reduced: 0.18s `easeInOut`. This is the constant that loses the most,
    /// and losing it is the point — "arriving past the new tab and settling
    /// back" is a description of exactly what makes someone motion-sensitive
    /// look away. The wash still travels, because it is what says which tab is
    /// selected; it simply stops being liquid. Note it comes out marginally
    /// shorter than `morph` rather than longer: see the table above.
    @MainActor static var selection: Animation { reduceMotion ? selectionFlat : selectionFull }
    private static let selectionFull = Animation.spring(duration: 0.38, bounce: 0.34)
    private static let selectionFlat = Animation.easeInOut(duration: 0.18)

    /// How a control answers the finger, before anything has moved.
    ///
    /// 0.09s ease-out, the same figure `TransportButtonStyle.kickDuration` now
    /// carries, and for the same reason: it is the part that has to be
    /// immediate. (That style once had a matching `squeeze` constant named
    /// here; it was removed when its buttons moved to touch-down, because a
    /// held-press squeeze cancelled out the kick that replaced it.) It was
    /// written for the hand-drawn tab bar, whose tabs had carried no press
    /// feedback at all — `.buttonStyle(.plain)` draws none — so the first
    /// thing that happened after a tap happened on touch-*up*. Everything
    /// before that was the app appearing not to have noticed.
    ///
    /// Reduced: unchanged, and see the shared note above. 0.09s of ease-out is
    /// not a curve anyone can perceive as motion; the thing that moves is
    /// `pressedScale`, and removing *that* is B4's decision at the call site.
    /// Whatever replaces it there still wants to answer the finger in 0.09s.
    @MainActor static var press: Animation { reduceMotion ? pressFlat : pressFull }
    private static let pressFull = Animation.easeOut(duration: 0.09)
    private static let pressFlat = pressFull

    /// What a pressed tab of the hand-drawn bar shrank to; nothing in the app
    /// reads it since the bar became the system's. Shallower than the transport
    /// buttons' 0.92: those are 44pt circles the thumb lands on squarely, while
    /// a tab was a whole quarter of the bar, and the same ratio on something
    /// that wide read as the bar itself flinching.
    ///
    /// Reduced: **1**, no shrink at all. The second constant here that is a
    /// distance rather than a curve, and it goes the way `recedeScale` went for
    /// the same reason — `press` above can flatten nothing, because what moves
    /// is this. `pressedOpacity` below is what answers the finger instead.
    @MainActor static var pressedScale: CGFloat { reduceMotion ? pressedScaleFlat : pressedScaleFull }
    private static let pressedScaleFull: CGFloat = 0.96
    private static let pressedScaleFlat: CGFloat = 1

    /// What a pressed control dims to when the scale has been taken out of it.
    ///
    /// **The whole point of this constant is that pressing must still show.** A
    /// control that answers a finger with nothing is a broken control, not a
    /// more accessible one, so the styles that lose a scale here —
    /// `QueueToggleStyle` and `TransportButtonStyle`, and the hand-drawn tab
    /// bar's press style before it was deleted — all pick this up in its place.
    ///
    /// **One number for all of them, where `pressedScale` deliberately differs per
    /// control.** That difference exists because a percentage of a wide thing is
    /// many points of travel and a percentage of a small thing is barely any:
    /// 0.96 on a quarter-bar tab and 0.9 on a 44pt glyph are the same *apparent*
    /// movement. Opacity has no points in it. There is nothing for the size of
    /// the control to scale, so a second figure would be a distinction without
    /// a difference — and this file exists to stop the pieces down here drifting
    /// apart.
    ///
    /// **0.45, and why that is enough to see.** The hand-drawn tab bar this was
    /// written for staked a readability claim on a smaller gap than this one:
    /// it distinguished the current destination from the other three by 1.0
    /// against 0.6 and nothing else, and that difference was expected to be
    /// read at a glance, on a 15pt glyph, without moving. A press
    /// dim has to clear that bar, because it is momentary where the tint is
    /// permanent — 0.45 is more than twice the distance from 1. It stops short
    /// of the 0.3 or so that reads as *disabled*: the control is being pressed,
    /// not switched off, and `isEnabled` already owns that appearance in
    /// `TransportButtonStyle`.
    ///
    /// Full: **1**, which is no dim at all. The full mode keeps answering with
    /// the scale it always did, and stacking a dim on top of it would change how
    /// the app looks for everyone — the setting off must be untouched.
    @MainActor static var pressedOpacity: Double { reduceMotion ? pressedOpacityFlat : pressedOpacityFull }
    private static let pressedOpacityFull: Double = 1
    private static let pressedOpacityFlat: Double = 0.45

    /// Content inside a surface as that surface changes shape: icons and labels
    /// shrinking and fading as the pill closes over them.
    ///
    /// Quicker and calmer than `morph` on purpose. The surface closing around
    /// them is the gesture; the glyphs should feel carried by it rather than
    /// staging a second performance inside it.
    ///
    /// Reduced: 0.20s `easeInOut`, the same figure `morph` lands on. That
    /// collision is correct rather than sloppy — "quicker and calmer" above was
    /// a statement about bounce, and with the bounce gone the two are the same
    /// pace. Being carried by the surface is if anything more true flat than it
    /// was sprung.
    @MainActor static var content: Animation { reduceMotion ? contentFlat : contentFull }
    private static let contentFull = Animation.spring(duration: 0.34, bounce: 0.20)
    private static let contentFlat = Animation.easeInOut(duration: 0.20)

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
    ///
    /// Reduced: 0.29s `easeInOut`. The overshoot this one already tried hardest
    /// to avoid is now gone entirely, so the only thing lost is the last of the
    /// give at the end of a gesture. See `settle(initialVelocity:)` below for
    /// the part of this that is a real trade rather than a free one.
    @MainActor static var settle: Animation { reduceMotion ? settleFlat : settleFull }
    private static let settleFull = Animation.spring(duration: 0.42, bounce: 0.14)
    private static let settleFlat = Animation.easeInOut(duration: settleFlatDuration)

    private static let settleDuration: Double = 0.42
    private static let settleBounce: Double = 0.14
    private static let settleFlatDuration: Double = 0.29

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
    ///
    /// Reduced: the velocity is dropped on the floor and this returns the flat
    /// `settle` — the same 0.29s curve for every release, gentle or violent.
    ///
    /// That is deliberate and it is the one place in this file where reducing
    /// motion costs something real. Everything the paragraphs above praise —
    /// no discontinuity in speed at release, a flick that reads as a flick —
    /// is *carried by* the initial velocity, and a hand-off of momentum is
    /// exactly the sensation vestibular symptoms are triggered by. Keeping the
    /// velocity and only flattening the curve would keep the thing worth
    /// removing and remove the thing that was harmless. The card still ends
    /// where the flick aimed it, because the target is chosen from the
    /// predicted end translation at the call site and that decision is
    /// untouched; only the manner of arrival is.
    @MainActor
    static func settle(initialVelocity: Double) -> Animation {
        if reduceMotion { return settleFlat }
        return .interpolatingSpring(
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
    ///
    /// **0.52 → 0.40 → 0.36, và đoạn trên đã bị chỉnh chứ không bị bỏ.** Người dùng
    /// yêu cầu cú bung nhanh hơn mà giữ nguyên kiểu, nên `bounce` không đổi —
    /// chỉ `duration`. Cái mất là chính thứ đoạn trên bảo vệ: 750pt giờ đi
    /// trong ~0,26s thay vì ~0,37s (`duration` của lò xo là thời gian *lắng*,
    /// không phải thời gian tới nơi; `h1` đo thẻ tới đích ở ~70% con số ấy).
    /// Nó vẫn là đường cong dài nhất trong file *trừ* `settle`, và tương quan
    /// với `settle` bị lật: cú chạm giờ nhanh hơn cú thả tay sau khi kéo, 0.36
    /// so với 0.42. Đó là lựa chọn có ý thức — `settle` được giữ nguyên đích
    /// danh, vì ngón tay đã đi phần lớn quãng đường trước khi nó bắt đầu, nên
    /// hai con số gần bằng nhau không có nghĩa hai cú đi cùng tốc độ.
    ///
    /// Reduced: 0.29s `easeInOut` — **không phải một con số chọn tay.** Bảng ở
    /// đầu file dẫn mọi thời lượng phẳng từ `t(98%)` của chính lò xo nó thay
    /// thế, và `SpringSettlingEvidenceTests` chạy lại phép dẫn ấy bằng
    /// `Spring.value(target:time:)` chứ không tin bảng. Lò xo 0.36/0.12 cắt
    /// 98% ở 0,258s, nên số phẳng là 0,26. Hai mốc trước: 0.40 cắt ở 0,286
    /// (phẳng 0,29), và 0.52 cắt ở 0,372 (phẳng 0,37). Ai đổi `duration` mà quên số này sẽ bị test bắt.
    ///
    /// Lý lẽ cũ cho con số phẳng vẫn giữ nguyên giá trị và được chép lại
    /// nguyên văn dưới đây, vì nó nói vì sao curve này dài hơn hàng xóm chứ
    /// không nói vì sao nó dài **đúng** ngần ấy — 750pt covered too fast
    /// arrives before the eye has followed it, and that is true of a flat
    /// curve too. The
    /// "little overshoot that keeps a large move from feeling mechanical" is
    /// the deliberate loss. B3 decides whether the 750pt travel survives at all
    /// or becomes a cross-fade; if it becomes a cross-fade, this duration is
    /// still the right length for it.
    ///
    /// **B3 took the second branch, and this constant did not have to change
    /// for it.** The card no longer travels 750pt when the setting is on: its
    /// geometry jumps to the destination inside a `nil` transaction and the
    /// card fades in at it, and *this is the curve that fade runs on*. The
    /// same 0.37s, timing the same transition, with the displacement taken
    /// out of it — which is what the paragraph above had already worked out
    /// would be the right thing to do.
    ///
    /// Not literally a cross-fade, and the difference is worth the word: the
    /// two states never overlap, so the old one cuts rather than dissolving
    /// while the new one fades in. `PlayerCard.morph(to:curves:)` says what
    /// that costs and why the version without the cut is out of reach here.
    ///
    /// The full branch is untouched and still animates the whole travel.
    ///
    /// Note that `PlayerCard.morph(to:curves:)` fades on whatever curve its
    /// caller passes, not on this one specifically: a tap arrives here, a
    /// release after a drag arrives at `settle`'s 0.29s. The two keep their
    /// different tempos in the reduced mode exactly as they had them in the
    /// full one.
    @MainActor static var expand: Animation { reduceMotion ? expandFlat : expandFull }
    private static let expandFull = Animation.spring(duration: expandDuration, bounce: expandBounce)
    private static let expandFlat = Animation.easeInOut(duration: 0.26)
    private static let expandDuration: Double = 0.36
    private static let expandBounce: Double = 0.12

    // MARK: - Cú thu về accessory

    /// Hai đường cong của **một** cú morph: một cho hình học của thẻ, một cho
    /// `PlayerCard.landing` — cú lún quá chỗ ở cuối cú thu.
    ///
    /// Ở chiều mở, và ở mọi nhánh giảm chuyển động, hai đường là một — xem
    /// `init(_:)`. Chỉ cú thu tách chúng ra; xem `collapse(initialVelocity:afterDrag:)`.
    struct MorphCurves {
        let geometry: Animation
        let landing: Animation
        /// Hình học, viết lại thành một lò xo thả từ đứng yên với vận tốc ban
        /// đầu này — khi nó đúng là thế (`expandCurves`, `settleCurves`). Một
        /// cú thu tới sau dùng nó để biết trước phần dư cú này còn để lại; xem
        /// `CollapseSpring.Residual`. `nil` cho mọi thứ khác.
        let geometrySpring: Spring?
        let initialVelocity: Double
        /// Lò xo của cú thu có lún, để `flooring(span:residuals:)` dựng lại hình
        /// học kèm sàn. `nil` khi đây không phải cú thu ấy.
        let collapseSpring: Spring?

        init(_ both: Animation, spring: Spring? = nil, initialVelocity: Double = 0) {
            geometry = both
            landing = both
            geometrySpring = spring
            self.initialVelocity = initialVelocity
            collapseSpring = nil
        }

        init(collapse spring: Spring, initialVelocity: Double) {
            geometry = Animation(CollapseSpring(spring: spring, initialVelocity: initialVelocity,
                                                stopsAtTarget: true))
            landing = Animation(CollapseSpring(spring: spring, initialVelocity: initialVelocity,
                                               stopsAtTarget: false))
            geometrySpring = nil
            self.initialVelocity = initialVelocity
            collapseSpring = spring
        }

        private init(geometry: Animation, keeping other: MorphCurves) {
            self.geometry = geometry
            landing = other.landing
            geometrySpring = other.geometrySpring
            initialVelocity = other.initialVelocity
            collapseSpring = other.collapseSpring
        }

        /// Cú thu có lún, dựng lại hình học để nó không bao giờ đưa thẻ dưới
        /// viên kính **dù có những cú morph trước còn đang chạy** — xem
        /// `CollapseSpring.residuals`. Không có phần dư nào (trường hợp thường)
        /// thì trả nguyên si, nên đường đi thường không đổi một bit.
        func flooring(span: Double, residuals: [CollapseSpring.Residual]) -> MorphCurves {
            guard let collapseSpring, !residuals.isEmpty else { return self }
            return MorphCurves(
                geometry: Animation(CollapseSpring(spring: collapseSpring, initialVelocity: initialVelocity,
                                                   stopsAtTarget: true, span: span, residuals: residuals)),
                keeping: self
            )
        }
    }

    /// `expand`, kèm lò xo của nó cho `MorphCurves.geometrySpring`.
    @MainActor static var expandCurves: MorphCurves {
        reduceMotion ? MorphCurves(expandFlat)
                     : MorphCurves(expandFull, spring: Spring(duration: expandDuration, bounce: expandBounce))
    }

    /// `settle(initialVelocity:)`, kèm lò xo của nó cho `MorphCurves.geometrySpring`.
    @MainActor static func settleCurves(initialVelocity: Double) -> MorphCurves {
        reduceMotion ? MorphCurves(settleFlat)
                     : MorphCurves(settle(initialVelocity: initialVelocity),
                                   spring: Spring(duration: settleDuration, bounce: settleBounce),
                                   initialVelocity: initialVelocity)
    }

    /// Thẻ thu về viên kính accessory, **phồng quá chỗ ~10pt rồi nảy lại**, theo
    /// nhịp Apple Music (video 2026-10-06, từng khung 33ms: chạm đáy ~132ms, lún
    /// tới ~200ms, nảy về tới ~500ms). Sửa 2026-10-06 sau QA trên máy: bản trước
    /// đáp khít viên kính rồi đứng chết — người dùng gọi là "cứng". Apple Music
    /// dời cả viên kính xuống; ta **phồng** thẻ đối xứng — mép trên lên, mép
    /// dưới xuống, hai bên nở — vì viên kính của hệ thống đứng yên: một tấm thẻ
    /// dời xuống để lộ nó thành viền thứ hai (QA IMG_2559), một tấm thẻ ghim mép
    /// trên thì "mép trên không đàn hồi, nhìn như gãy". Xem `CollapseGlass`.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// VÌ SAO KHÔNG CHỈ LÀ MỘT LÒ XO NẢY HƠN
    /// ─────────────────────────────────────────────────────────────────────
    /// Hình học của thẻ được tính trong `PlayerCard.body` **một lần**, ở đích,
    /// rồi SwiftUI nội suy khung và padding dọc đường cong. Lò xo vọt qua đích
    /// thì phép nội suy ấy **ngoại suy**: chiều cao thẻ đi dưới 48 và mép dưới
    /// nhích **lên** — thẻ bẹp lại tại chỗ chứ không lún xuống. Đúng cái spec cấm.
    ///
    /// Nên cùng **một** lò xo chạy hai lần, cùng lúc bắt đầu, cùng vận tốc ban
    /// đầu, khác đúng một điều — xem `CollapseSpring.stopsAtTarget`:
    ///
    ///   - `geometry` **dừng ở lần đầu chạm đích**. Khung thẻ không bao giờ
    ///     ngoại suy, nên không bao giờ nhỏ hơn viên kính.
    ///   - `landing` chạy hết: vọt qua 0, nảy về. `PlayerCard.landing` đi theo
    ///     nó, và phần **âm** của nó thành cú phồng của lớp kính (`CollapseGlass`
    ///     trong `PlayerCard.swift`) — mọi mép chỉ đi ra; không đụng bố cục.
    ///
    /// Không có thời lượng nào phải đoán: cú phồng bắt đầu **đúng** khung hình
    /// học chạm đích, vì đó là cùng một phép tính `Spring.value` trên cùng
    /// một đồng hồ. Đà của cú thu đi vào cú phồng: ngay trước khi chạm, mép
    /// trên thẻ đi `dragTravel × dp/dt`; ngay sau, chiều cao thẻ lớn lên đúng
    /// tốc độ ấy (độ dốc của `PlayerCard.landingGrowth` ở 0 là 1), chia đôi cho
    /// hai mép. Một cú búng mạnh phồng hơn — vận tốc ngón tay đi vào cả hai —
    /// và `landingGrowth` chặn trần nó.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// THỜI LƯỢNG VÀ ĐỘ NẢY
    /// ─────────────────────────────────────────────────────────────────────
    /// Thời lượng giữ nguyên nhịp cũ của từng lối vào: chạm là `expand` (0.36),
    /// thả tay sau khi kéo là `settle` (0.42). Chỉ `bounce` đổi, sang
    /// `landingBounce` — xem ghi chú ở đó về vì sao 0.25.
    ///
    /// Reduced: nhánh phẳng của chính lối vào ấy (`expandFlat`/`settleFlat`),
    /// không vận tốc, không lún — `PlayerCard.morph(to:curves:)` dùng nó cho
    /// cú hoà mờ và về nghỉ ngay, như trước.
    @MainActor
    static func collapse(initialVelocity: Double = 0, afterDrag: Bool) -> MorphCurves {
        if reduceMotion { return MorphCurves(afterDrag ? settleFlat : expandFlat) }
        return MorphCurves(collapse: collapseSpring(afterDrag: afterDrag), initialVelocity: initialVelocity)
    }

    /// Lò xo của cú thu, trước khi tách đôi. Tách riêng để test dựng lại đúng
    /// đường cong `collapse(initialVelocity:afterDrag:)` chạy.
    static func collapseSpring(afterDrag: Bool) -> Spring {
        Spring(duration: afterDrag ? settleDuration : expandDuration, bounce: landingBounce)
    }

    /// Độ nảy của lò xo thu — **chọn, có tính**, cho cú lún ~10pt.
    ///
    /// Lò xo thả từ đứng yên vọt qua đích một phần `e^(−πζ/√(1−ζ²))` quãng
    /// đường, `ζ = 1 − bounce`. Cú lún tính bằng điểm là phần ấy nhân quãng
    /// đường còn lại (`progress` lúc thả × `dragTravel`, ~710pt trên iPhone
    /// 12), rồi qua trần mềm của `PlayerCard.landingGrowth` — tổng hai mép:
    ///
    ///     bounce   vọt qua   thu trọn quãng   kéo tới 0.9, búng 1900pt/s
    ///     0.14     0.5%       3,5pt            3,2pt    (`settle` cũ)
    ///     0.20     1.5%       9,4pt            8,8pt
    ///     0.22     2.0%       11,3pt           10,7pt   (vòng sửa 1–3)
    ///     0.25     2.8%       13,6pt           13,1pt
    ///
    /// **0.25, nâng từ 0.22 ở vòng sửa 4**: người dùng thấy cú phồng "có mà
    /// thiếu đàn hồi". Phán quyết: phồng tổng ~12–14pt, tức ~6–7pt mỗi mép, vẫn
    /// dưới trần 16pt — 0.25 cho 13,1pt với cú thu thường ngày, 13,6pt với cú
    /// chạm. 0.28 đã là 14,6/15,0pt, sát trần đến mức trần mềm `tanh` nuốt mất
    /// khác biệt giữa búng nhẹ và búng mạnh. `CollapseHandoffTests` tính lại
    /// bảng này bằng chính `CollapseSpring`, không tin con số ở đây.
    ///
    /// Không ảnh hưởng gì khác: hình học dừng ở đích, nên độ nảy chỉ còn quyết
    /// thẻ tới nơi nhanh cỡ nào và lún sâu cỡ nào.
    static let landingBounce: Double = 0.25

    /// Hệ số cho **nhịp nảy ngược** của cú đáp — nửa chu kỳ thứ hai, khi lò xo
    /// vọt về phía bên kia đích — trong `PlayerCard.landingGrowth`.
    ///
    /// Nhịp ấy nhỏ hơn nhịp đầu đúng một lần hệ số vọt qua (~2,8%): với cú thu
    /// thường ngày nó là ~0,5pt — có trong đường cong mà mắt không thấy, nên
    /// cú phồng đọc ra như một nhịp rồi đứng. Phán quyết vòng sửa 4: "phồng
    /// lớn → lắng → phồng nhỏ → nghỉ". ×4 cho nhịp thứ hai ~2pt tổng (~1pt mỗi
    /// mép), vẫn rõ ràng là nhỏ hơn nhịp đầu ~13pt. ×5 thì ~2,6pt, và cú trao
    /// chỗ đẩy quá ~0,9s (xem `CollapseSpring.landingHandoffEpsilon`).
    static let landingReboundGain: CGFloat = 4

    /// Thẻ trao chỗ cho accessory, **sau** cú nảy: thẻ mờ đi trong khi hàng mini
    /// của accessory đã nằm sẵn dưới nó, đúng chỗ ấy — xem
    /// `PlayerCard.morph(to:curves:)`.
    ///
    /// Ngắn vì hai hàng trùng khít và hai lớp kính là cùng một chất liệu: thứ
    /// duy nhất thật sự hoà vào nhau là ô bìa của bài không bìa (thẻ tô theo
    /// màu bài, accessory tô xám hệ thống) — đúng cú "ô bìa tối nhảy sang sáng"
    /// đo được ở QA lần trước.
    ///
    /// **Hằng số duy nhất trong kiểu này không trả lời `reduceMotion`, và đó là
    /// chủ ý.** Nhánh giảm chuyển động của `morph(to:curves:)` về nghỉ ngay,
    /// không qua cú mờ này — nên một nhánh "phẳng" ở đây sẽ là một nhánh không
    /// ai gọi, trông như đã được nghĩ tới mà thật ra chưa từng chạy.
    static let collapseHandoff = Animation.easeOut(duration: 0.15)

    /// How the content behind the player recedes as it opens, the way a sheet
    /// pushes its presenting screen back.
    ///
    /// The scale is small on purpose. iOS's own card presentation moves the
    /// screen behind it by only a few percent; more than that stops reading as
    /// depth and starts reading as the app shrinking.
    ///
    /// Reduced: **1**, which is no recede at all.
    ///
    /// The only constant outside the `Animation` group that has to branch, and
    /// it has to because it is not a curve — it is a *distance*.
    /// `RecedeBehindPlayer` applies
    /// `scaleEffect(1 - (1 - recedeScale) * progress)`, so setting this to 1
    /// takes the `(1 - recedeScale)` coefficient to 0 and the whole expression
    /// to a constant 1 at every `progress`. Not a recede that runs flatter or
    /// faster: the screen behind the player holds perfectly still for the
    /// entire opening, including while a finger is dragging it.
    ///
    /// **Including the drag path, and that is the right exception.** B3 leaves
    /// the drag path alone for the card itself — a card that follows the finger
    /// is feedback, not an animation, and taking it away would leave the user
    /// unable to close the player. The *background's* shrink is not feedback:
    /// it is a depth effect drawn on top, nobody is holding it, and nothing
    /// about the interaction is lost when it stops. The HIG asks for scaling to
    /// go, and a whole screen scaling is exactly that.
    ///
    /// The route stays what it was — `PlayerExpansion.animation` into
    /// `.animation(_:value:)` — rather than being switched off: with the
    /// coefficient at 0 that modifier interpolates a value that never changes,
    /// which costs nothing and needs no second branch in
    /// `RecedeBehindPlayer`.
    /// ─────────────────────────────────────────────────────────────────────
    /// CẢ HAI NHÁNH GIỜ LÀ 1 — CÚ THU NHỎ NỀN ĐÃ BỊ BỎ, VÀ ĐÂY LÀ SỐ ĐO
    /// ─────────────────────────────────────────────────────────────────────
    /// Nhánh thường từng là 0,92. Bỏ vì nó cắt cụt đáy danh sách trong lúc
    /// morph rồi trả lại chiều cao đầy trong **một khung**.
    ///
    /// Đo trên video người dùng quay, một cú vuốt thu nhỏ chậm, dải màn hình
    /// y≈812–828 — ngay dưới thanh tab:
    ///
    ///     suốt 4 giây kéo tay   4,6 → 7,3    đứng gần như im
    ///     khung 398             7,27
    ///     khung 399            38,72         ← gấp 5 lần, đúng lúc thả tay
    ///
    /// Nhìn khung hình thì thấy thẳng: dưới thanh tab đen kịt suốt cú kéo, rồi
    /// một hàng danh sách hiện ra ở khung cuối. `scaleEffect` nhỏ hơn 1 thu cả
    /// lớp nội dung lại, nên phần mép **không còn được vẽ** — và cú trả về 1
    /// làm nó hiện lại một phát.
    ///
    /// Ghi chú ở `PlayerExpansion` đã đo đúng lỗi này từ trước ("mép dưới nội
    /// dung đứng ở y 797 suốt chín khung rồi nhảy xuống 828 trong một khung")
    /// và định vá bằng cách cho đường cong đi qua `PlayerExpansion.animation`.
    /// Bản vá ấy **không đủ**: đo lại trên máy thật, cú nhảy vẫn còn nguyên.
    ///
    /// Xác nhận bằng phép thử một biến: gỡ `recedesBehindPlayer` khỏi
    /// `RootView`, quay lại cùng thao tác — cú nhảy biến mất.
    ///
    /// Cái mất là chiều sâu kiểu "tấm sheet đẩy màn hình phía sau lùi lại".
    /// Cái được là thứ người dùng đòi và mô tả bằng chính lời họ: viên thuốc và
    /// thanh tab nổi trên nội dung, và **vẻ ấy giữ nguyên suốt cú thu nhỏ** chứ
    /// không biến mất rồi bật lại ở khung cuối.
    ///
    /// Đường đi được giữ nguyên chứ không tháo: với hệ số `(1 - recedeScale)`
    /// bằng 0, `RecedeBehindPlayer` nội suy một giá trị không bao giờ đổi —
    /// không tốn gì, và còn nguyên chỗ nếu sau này ai muốn dựng lại chiều sâu
    /// ấy bằng một cách không cắt cụt nội dung.
    @MainActor static var recedeScale: CGFloat { reduceMotion ? recedeScaleFlat : recedeScaleFull }
    private static let recedeScaleFull: CGFloat = 1
    private static let recedeScaleFlat: CGFloat = 1
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
    ///
    /// Reduced: unchanged, and see the shared note above. The sentence directly
    /// above already made the reduced-motion argument for its own reasons — a
    /// 5pt swell on a curve is not a mass arriving anywhere, and there is no
    /// overshoot here to take away.
    @MainActor static var control: Animation { reduceMotion ? controlFlat : controlFull }
    private static let controlFull = Animation.easeOut(duration: 0.15)
    private static let controlFlat = controlFull

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
    ///
    /// Giảm chuyển động: `easeInOut` 0.29s. Lò xo này vốn đã tắt dần tới hạn —
    /// không có khung nào vọt lố ở cả hai chiều — nên cái mất đi chỉ là hình
    /// dáng gia tốc, không phải một cú nảy. Đây cũng là hằng số dùng để kiểm
    /// bộ đo ở ghi chú trên đầu file: lấy mẫu chính lò xo này ở 30fps ra đúng
    /// dãy Apple Music chép ở trên, nên 0.29 không phải một con số đoán.
    ///
    /// Cả ba thứ nó lái vẫn phải chung một đồng hồ ở chế độ phẳng, vì lý do
    /// không đổi: hai nửa của cùng một cử chỉ chạy hai curve là lỗi tệ hơn.
    @MainActor static var queue: Animation { reduceMotion ? queueFlat : queueFull }
    private static let queueFull = Animation.spring(Spring(duration: 0.31, bounce: 0))
    private static let queueFlat = Animation.easeInOut(duration: 0.29)

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
    ///
    /// Giảm chuyển động: **giữ nguyên**, xem ghi chú chung ở đầu phần này. Đây
    /// là cú *hiện ra*, tức một phép hoà mờ, và HIG cho phép hoà mờ. Cái phải
    /// bỏ là cú trượt kèm theo, và cú trượt ấy là `queueContentSlide` bên dưới
    /// cùng chỗ áp nó ở B3/B4 — không phải hằng số này. Đổi 0.13 ở đây chỉ làm
    /// lệch pha với `queueTitleOut` mà chẳng bỏ được chuyển động nào.
    @MainActor static var queueContentIn: Animation { reduceMotion ? queueContentInFlat : queueContentInFull }
    private static let queueContentInFull = Animation.easeOut(duration: 0.13)
    private static let queueContentInFlat = queueContentInFull

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
    ///
    /// Giảm chuyển động: `easeInOut` 0.19s. Đây là hằng số **duy nhất** trong
    /// nhóm `queue*` mô tả một cú dịch chuyển thật, nên nó là chỗ duy nhất
    /// trong nhóm đáng đổi curve. Việc tách "đọc được nhanh rồi mới thong thả
    /// về chỗ" ở trên vẫn còn nguyên giá trị ở chế độ phẳng: hai thứ vẫn phải
    /// rời nhau, chỉ là quãng đường sẽ do B3/B4 quyết có còn hay không.
    @MainActor static var queueContentSlide: Animation { reduceMotion ? queueContentSlideFlat : queueContentSlideFull }
    private static let queueContentSlideFull = Animation.spring(Spring(duration: 0.20, bounce: 0))
    private static let queueContentSlideFlat = Animation.easeInOut(duration: 0.19)

    /// Chiều ngược lại **không trễ, và nhanh hơn**.
    ///
    /// Cũng đo được: đóng hàng đợi thì ba khối biến mất trong hai tới ba khung,
    /// ngay từ đầu. Đối xứng ở đây là sai — thứ đang đi khỏi màn hình không có
    /// lý do gì để chờ, và giữ nó lại là giữ một tấm bảng chắn trước tấm bìa
    /// đang lớn dần.
    ///
    /// Giảm chuyển động: **giữ nguyên**, xem ghi chú chung ở đầu phần này. Cú
    /// tan trong hai tới ba khung là một phép hoà mờ, và kéo dài nó ra ở chế độ
    /// giảm chuyển động là đi ngược mục đích — thứ ở lại lâu hơn trên đường đi
    /// của tấm bìa mới là thứ gây khó chịu.
    ///
    /// **0.10 → 0.05: hằng số cũ không khớp với phép đo ngay phía trên nó.**
    /// Đoạn văn kia nói "hai tới ba khung", và ở 60fps hai tới ba khung là
    /// 0.033–0.05 giây. 0.10 giây là **sáu** khung — gấp đôi thứ đã đo, và cách
    /// duy nhất nó lọt qua là không ai nhân 3 với 16.7ms. Người dùng nhìn thấy
    /// ba viên thuốc nán lại và báo trước khi tôi đọc ra chỗ vênh.
    ///
    /// **0.05 → 0.033 sau khi nhìn thật.** Ba khung vẫn còn đọc ra là ba viên
    /// thuốc *nán lại*, và chúng nằm đúng trên đường tấm bìa đang lớn dần —
    /// nên bất kỳ khoảnh khắc nào chúng còn ở đó cũng là một tấm bảng chắn.
    ///
    /// 0.033 là **hai khung**, đầu nhanh của khoảng đã đo. Đây là sàn: dưới nữa
    /// thì không còn là hoà mờ mà là cú cắt, và một khung biến mất trong một
    /// khung sẽ đọc ra như khung hình bị rớt chứ không như một chuyển động.
    @MainActor static var queueContentOut: Animation { reduceMotion ? queueContentOutFlat : queueContentOutFull }
    private static let queueContentOutFull = Animation.easeIn(duration: 0.033)
    private static let queueContentOutFlat = queueContentOutFull

    /// Khối chữ lớn của `NowPlayingContent` tan đi khi hàng đợi mở.
    ///
    /// Trễ 0.07s và dài 0.07s, đo bằng lượng mực của khối chữ qua từng khung:
    /// 963 → 957 → 925 → 872 → 633 → 0. Tức nó đứng gần như nguyên vẹn hai
    /// khung đầu, mất một phần ba ở khung thứ tư, và hết ở khung thứ năm.
    ///
    /// Mốc cũ 0.10 → 0.17 là ước lượng đọc bằng mắt trên một tấm ghép khung, và
    /// nó muộn hơn thật một khung rưỡi.
    ///
    /// `easeIn` chứ không `easeOut`, và **chính con số đo ở trên đã nói ra
    /// điều đó**: 963 → 957 → 925 → 872 → 633 → 0 là hai khung gần như phẳng
    /// rồi một cú sập — bước cuối lớn hơn bước đầu cả trăm lần. Đó là hình dáng
    /// của `easeIn`. Một `easeOut` sẽ cho dãy ngược lại: mất nhiều nhất ở khung
    /// đầu rồi bò dần về 0.
    ///
    /// **Ở đây từng có một đoạn lập luận ngược hẳn, và nó sai theo một kiểu
    /// đáng ghi lại.** Đoạn ấy nói phải là `easeOut` chứ không `easeIn`, vì
    /// `easeIn` kết thúc ở vận tốc lớn nhất còn cú hiện tiếp sau — một lò xo —
    /// khởi động từ vận tốc 0, nên nối một cái đang lao vào một cái đang đứng
    /// yên là một chỗ gãy. Lập luận nghe xuôi, và nó đã sống sót qua nhiều lượt
    /// đọc, nhưng nó tả một dòng mã **không tồn tại**: dòng ngay dưới vẫn luôn
    /// là `easeIn`, và `ReduceMotionTests` vẫn luôn ghim nó là `easeIn`.
    ///
    /// Cái làm nó vô hại là điều mà chính nó bỏ sót: hai cú này **không nối
    /// nhau**. `queueTitleIn` có `delay(0.13)` và chạy ở 0.23 → 0.33, còn cú
    /// tan này xong ở 0.10. Giữa hai đầu là 0.13s không có gì cả, nên không có
    /// mối nối nào để mà khớp đạo hàm — vấn đề mà đoạn văn ấy giải chưa bao giờ
    /// có mặt. Xem ghi chú của `queueTitleIn`: khe ấy tồn tại để hai khối chữ
    /// không bao giờ cùng đọc được, và đó mới là ràng buộc thật ở đây.
    ///
    /// **Viết thành thời gian chứ không phải cửa sổ trên `queueFactor`, và đó
    /// là điều bắt buộc.** Một cửa sổ trên `factor` chạy ngược khi đóng, nên nó
    /// đặt cú hiện lại của khối chữ vào quãng 0.032s – 0.102s — nằm gọn bên
    /// trong quãng `queueContentOut` đang tan. Hai khối chữ lấn nhau, và không
    /// có cặp số nào trên một trục duy nhất tách được chúng ở cả hai chiều.
    ///
    /// Giảm chuyển động: **giữ nguyên**, xem ghi chú chung ở đầu phần này. Chỉ
    /// là lượng mực của một khối chữ đi về 0 — không dịch chuyển, không phóng
    /// to. Cả `delay(0.04)` cũng giữ: nó là dàn cảnh chứ không phải chuyển
    /// động, và cái nó dàn ra — khe 0.13s trước khi khối chữ kia quay lại —
    /// không phụ thuộc vào việc cú hiện tiếp sau là lò xo hay curve. Thứ tự vẫn
    /// là thứ tự.
    ///
    /// (Chỗ này trước đây viết rằng "lập luận về mối nối ở trên (`easeOut` về 0
    /// với vận tốc gần 0…) vẫn đúng nguyên si". Nó tái khẳng định đúng cái lập
    /// luận sai vừa nói ở trên, và đợt này thêm nó vào — một câu mới dựng trên
    /// một tiền đề sai. Cái đúng cần giữ ở đây chỉ là: nhánh giảm chuyển động
    /// không đổi gì, và không có gì trong đợt này làm nó phải đổi.)
    @MainActor static var queueTitleOut: Animation { reduceMotion ? queueTitleOutFlat : queueTitleOutFull }
    private static let queueTitleOutFull = Animation.easeIn(duration: 0.06).delay(0.04)
    private static let queueTitleOutFlat = queueTitleOutFull

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
    ///
    /// Giảm chuyển động: **giữ nguyên**, xem ghi chú chung ở đầu phần này.
    /// Cũng là hoà mờ, và `delay(0.13)` càng phải giữ: nó tồn tại để hai khối
    /// chữ không bao giờ cùng đọc được, mà điều đó lại càng đúng hơn khi tấm
    /// bìa phía sau đổi sang một curve khác — thứ tự vẫn phải là nghịch đảo
    /// đúng của chiều mở.
    @MainActor static var queueTitleIn: Animation { reduceMotion ? queueTitleInFlat : queueTitleInFull }
    private static let queueTitleInFull = Animation.easeOut(duration: 0.10).delay(0.13)
    private static let queueTitleInFlat = queueTitleInFull
}

extension View {
    /// One glyph replacing another in place — **without the scale, when motion
    /// is reduced.**
    ///
    /// Use this instead of `.contentTransition(.symbolEffect(.replace))`
    /// anywhere an `Image(systemName:)` changes its symbol. Every site in the
    /// app does; `grep contentTransition` should find no bare call but this one.
    ///
    /// **What it is fixing.** The replace effect scales the outgoing glyph down
    /// to about half its height and scales the incoming one back up — measured
    /// at 15 → 7 → 15 rows over roughly 0.21s, centred in the control. That ran
    /// with Reduce Motion on, on play/pause among others, which is a scale
    /// animation on the app's most-tapped control under the setting whose whole
    /// purpose is removing scale animations.
    ///
    /// **Why a branch here rather than a curve anywhere else.** The effect is
    /// timed by SF Symbols and ignores the animation of the transaction it
    /// happens in — `SymbolReplaceTransactionEvidenceTests` measures a 1.2s
    /// `withAnimation` and a 1.2s ancestor `.transaction` leaving it exactly as
    /// it was. So no `Animation` constant in this file can reach it and none of
    /// the thirteen above was ever going to. Only two things do: replacing the
    /// transition, which is this, or `disablesAnimations` on an ancestor, which
    /// would also silence everything else in the subtree.
    ///
    /// **The swap still happens, and that is the requirement.** `.opacity`
    /// rather than `.identity`: where the caller has an animation in flight the
    /// glyph cross-fades, and where it does not it cuts. Either way the glyph
    /// changes — a play button that still reads "play" after being tapped is a
    /// worse outcome than a scale — and neither way does anything change size.
    /// The same trade the two `ButtonStyle`s made:
    /// answer with opacity, not with shape.
    ///
    /// **One mechanism, not four branches.** Four production sites, one each in
    /// four files, read this. Written per-site it would be four chances to miss
    /// the fifth.
    ///
    /// (The count has moved more than once — "six production sites plus the
    /// demo", then five plus the demo, then the demo was deleted. It is written
    /// out in full here so the next reader can check it against
    /// `grep -rn symbolReplace\(\)` in one pass rather than recounting from a
    /// summary. `SymbolReplaceCoverageTests` holds the executable half.)
    ///
    /// The unreduced branch is exactly the call it replaces, so nothing changes
    /// for anyone with the setting off.
    @MainActor
    func symbolReplace() -> some View {
        contentTransition(BottomBarStyle.reduceMotion ? .opacity : .symbolEffect(.replace))
    }
}

/// Lò xo của cú thu, ở một trong hai dạng chạy cùng một đồng hồ — xem
/// `BottomBarStyle.collapse(initialVelocity:afterDrag:)`.
///
/// Một `CustomAnimation` chứ không phải `.interpolatingSpring` vì đúng một
/// việc: dạng `stopsAtTarget` phải **dừng** ở lần đầu chạm đích, và không đường
/// cong dựng sẵn nào làm thế. Phần còn lại là `Spring.value`, tức chính phép
/// tính `.interpolatingSpring(duration:bounce:initialVelocity:)` chạy — vận tốc
/// ban đầu tính theo **quãng còn lại** mỗi giây, như ở
/// `BottomBarStyle.settle(initialVelocity:)`.
///
/// Thuần và tách được khỏi SwiftUI qua `fraction(at:)`, để test hỏi thẳng đường
/// cong mà không phải chạy animation.
struct CollapseSpring: CustomAnimation {
    let spring: Spring
    let initialVelocity: Double
    /// `true` cho hình học: kết thúc ngay khi chạm đích lần đầu. `false` cho
    /// cú đáp: chạy hết cú vọt qua và cú nảy về, tới khi lắng.
    let stopsAtTarget: Bool
    /// Quãng `progress` cú thu này đi, từ chỗ thẻ đang đứng (trong mô hình)
    /// về 0. Chỉ dùng cho sàn — xem `residuals`.
    let span: Double
    /// Phần dư của những cú morph **trước** còn đang chạy, chỉ cho hình học.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// VÌ SAO CẦN — "DỪNG Ở ĐÍCH" KHÔNG ĐỦ KHI CÓ CÚ KHÁC ĐANG BAY
    /// ─────────────────────────────────────────────────────────────────────
    /// Animation của SwiftUI cộng dồn: một cú thu cắt ngang một cú bung còn
    /// sớm không thay cú bung, mà cộng thêm vào. Thứ vẽ ra là
    /// `(1 − k)·span + R(t)`, với `R` là phần cú bung còn thiếu tới đích của nó
    /// — âm, nhỏ dần về 0 theo lò xo `expand`. Dạng hình học dừng ở lần đầu
    /// `k` chạm 1, lúc ấy `R` có thể vẫn âm vài phần trăm: thử cú chạm thu
    /// ngay sau cú chạm mở, `R` ≈ −0,046 lúc hình học dừng — thẻ cao ~12pt.
    ///
    /// `CustomAnimation` trộn vào được cú trước (`shouldMerge`) chỉ khi cùng
    /// kiểu, và đo được: trả `true` thì giá trị nhảy thẳng tới đích. Nên thay
    /// vì trộn, cú thu **biết trước** `R(t)` — cú bung là một lò xo đã biết
    /// tham số, giờ bắt đầu và quãng đi — và giữ `k ≤ 1 + R(t)/span`: thẻ không
    /// bao giờ nhỏ hơn viên kính, rồi kết thúc khi đã chạm đích **và** `R` đã
    /// về 0. Phần thẻ "lẽ ra" còn đi tiếp xuống thì `landing` vẫn mang — không
    /// có sàn — nên nó thành cú lún, như mọi cú lún khác.
    ///
    /// Chỉ ghi những cú có `MorphCurves.geometrySpring` (bung và thả tay để
    /// mở). Phần dư của một cú thu trước luôn ≥ 0 (`k ≤ 1`), không bao giờ kéo
    /// thẻ xuống dưới viên kính, nên bỏ qua nó chỉ làm sàn chặt hơn.
    let residuals: [Residual]
    /// Lúc đường cong kết thúc hẳn — xem `settleEpsilon` (hình học) và
    /// `landingRemovalEpsilon` (cú đáp). Tính một lần ở đây, không mỗi khung.
    /// Với hình học có phần dư, là lúc muộn nhất trong số ấy.
    let settlingTime: TimeInterval
    /// Lúc đường cong báo **xong về mặt logic** (`AnimationContext.isLogicallyComplete`)
    /// — tức lúc `completion` mặc định của `withAnimation` nổ và thẻ trao chỗ.
    /// Với hình học, trùng `settlingTime`. Với cú đáp, sớm hơn: xem
    /// `landingHandoffEpsilon`.
    let logicalCompletionTime: TimeInterval

    /// Một cú morph trước, đang chạy: lò xo thả từ đứng yên, đi `delta`, đã
    /// chạy được `elapsed` lúc cú thu bắt đầu.
    struct Residual: Hashable, Sendable {
        let spring: Spring
        let initialVelocity: Double
        let delta: Double
        let elapsed: TimeInterval
        let settlingTime: TimeInterval

        init(spring: Spring, initialVelocity: Double, delta: Double, elapsed: TimeInterval) {
            self.spring = spring
            self.initialVelocity = initialVelocity
            self.delta = delta
            self.elapsed = elapsed
            self.settlingTime = CollapseSpring.lastExcursion(of: spring, initialVelocity: initialVelocity)
        }

        /// Phần cú ấy còn đóng góp vào giá trị đang vẽ, `time` giây sau khi cú
        /// thu bắt đầu: `delta × (f − 1)`.
        func value(after time: TimeInterval) -> Double {
            let t = elapsed + time
            guard t < settlingTime else { return 0 }
            return delta * (spring.value(target: 1.0, initialVelocity: initialVelocity, time: t) - 1)
        }

        var isRunning: Bool { elapsed < settlingTime }
    }

    init(spring: Spring, initialVelocity: Double, stopsAtTarget: Bool,
         span: Double = 1, residuals: [Residual] = []) {
        self.spring = spring
        self.initialVelocity = initialVelocity
        self.stopsAtTarget = stopsAtTarget
        self.span = span
        self.residuals = stopsAtTarget ? residuals.filter(\.isRunning) : []
        if stopsAtTarget {
            let own = Self.lastExcursion(of: spring, initialVelocity: initialVelocity)
            self.settlingTime = self.residuals.reduce(own) { max($0, $1.settlingTime - $1.elapsed) }
            self.logicalCompletionTime = settlingTime
        } else {
            self.settlingTime = Self.lastExcursion(of: spring, initialVelocity: initialVelocity,
                                                   epsilon: Self.landingRemovalEpsilon)
            self.logicalCompletionTime = min(settlingTime,
                                             Self.lastExcursion(of: spring, initialVelocity: initialVelocity,
                                                                epsilon: Self.landingHandoffEpsilon))
        }
    }

    /// Tổng phần dư của các cú trước, `time` giây sau khi cú thu bắt đầu.
    func residual(at time: TimeInterval) -> Double {
        residuals.reduce(0) { $0 + $1.value(after: time) }
    }

    /// Lần cuối đường cong còn lệch đích từ `settleEpsilon` trở lên, cộng một
    /// bước — tức từ đó trở đi nó nằm yên trong biên.
    ///
    /// Không dùng thẳng `Spring.settlingDuration(target:initialVelocity:epsilon:)`:
    /// đo ra nó dè dặt hơn hẳn đường cong — 0,87s cho lò xo thả tay, trong khi
    /// lần cuối đường cong còn lệch 0,05% là quanh 0,6s. Thẻ về nghỉ ở mốc ấy,
    /// nên một phần ba giây dư là một phần ba giây thẻ đã đứng yên mà chưa trao
    /// chỗ. Dùng nó làm cận trên rồi dò ngược từng mili giây bằng chính
    /// `Spring.value` — vài trăm phép tính, một lần mỗi cú thu.
    fileprivate static func lastExcursion(of spring: Spring, initialVelocity: Double,
                                          epsilon: Double = settleEpsilon) -> TimeInterval {
        let bound = spring.settlingDuration(target: 1.0, initialVelocity: initialVelocity,
                                            epsilon: epsilon)
        let step = 0.001
        var time = bound
        while time > 0,
              abs(spring.value(target: 1.0, initialVelocity: initialVelocity, time: time) - 1) < epsilon {
            time -= step
        }
        return min(bound, time + step)
    }

    /// Phần quãng đường đã đi ở thời điểm `time`: 0 lúc bắt đầu, 1 ở đích, quá
    /// 1 khi vọt qua. `nil` khi đường cong đã xong.
    func fraction(at time: TimeInterval) -> Double? {
        guard time < settlingTime else { return nil }
        let fraction = spring.value(target: 1.0, initialVelocity: initialVelocity, time: time)
        guard stopsAtTarget else { return fraction }
        let residual = residual(at: time)
        if fraction >= 1, residual >= -Self.residualTolerance { return nil }
        guard !residuals.isEmpty, span > 0 else { return fraction }
        return min(fraction, 1 + residual / span)
    }

    /// Phần dư âm nhỏ tới mức này (~0,07pt trên 710pt) coi như đã về 0.
    static let residualTolerance: Double = 0.0001

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval,
                                      context: inout AnimationContext<V>) -> V? {
        guard let fraction = fraction(at: time) else { return nil }
        if time >= logicalCompletionTime { context.isLogicallyComplete = true }
        return value.scaled(by: fraction)
    }

    func velocity<V: VectorArithmetic>(value: V, time: TimeInterval,
                                       context: AnimationContext<V>) -> V? {
        guard fraction(at: time) != nil else { return nil }
        return value.scaled(by: spring.velocity(target: 1.0, initialVelocity: initialVelocity,
                                                time: time))
    }

    /// Lắng là khi phần còn lệch dưới 0,05% quãng đường: trên trọn quãng
    /// ~710pt của iPhone 12 là ~0,35pt — dưới một điểm ảnh @2x. Đây là lúc cú
    /// đáp coi như xong và thẻ trao chỗ cho accessory; lệch to hơn thì cú trao
    /// tay lộ ra thành một cú nhích.
    static let settleEpsilon: Double = 0.0005

    /// Cú đáp **báo xong** — và thẻ bắt đầu mờ đi trao chỗ — khi phần còn lại
    /// của cú nảy vẽ ra dưới ~1pt, kể cả qua hệ số `landingReboundGain` của
    /// nhịp nảy ngược, trên trọn quãng ~710pt. Nó **vẫn chạy** sau mốc ấy, dưới
    /// cú mờ, tới `landingRemovalEpsilon`: chút phồng còn lại tan cùng tấm thẻ
    /// chứ không bị cắt phụt ở đầu cú mờ.
    ///
    /// Vì sao không đợi lắng hẳn rồi mới mờ: nhịp nảy ngược kéo dài tới ~0,86s
    /// với cú thả tay; đợi nó tắt hẳn (0,35pt) là ~0,79s + 0,15s mờ = ~0,94s,
    /// quá mức ~0,9s của phán quyết vòng sửa 4. Ở 1pt: cú thả tay thường ngày
    /// ~0,72s + 0,15s; tệ nhất — thả không vận tốc từ thẻ mở hẳn — ~0,75s + 0,15s.
    static var landingHandoffEpsilon: Double {
        1 / (Double(BottomBarStyle.landingReboundGain) * referenceTravel)
    }

    /// Cú đáp thôi chạy hẳn khi phần còn lại vẽ ra dưới ~0,35pt — cùng mức mà
    /// `settleEpsilon` từng chọn — kể cả qua `landingReboundGain`.
    static var landingRemovalEpsilon: Double {
        0.35 / (Double(BottomBarStyle.landingReboundGain) * referenceTravel)
    }

    /// Quãng kéo của iPhone 12, để đổi các mức tính bằng điểm ở trên ra phần
    /// quãng đường. Thẻ ngắn hơn thì phần còn lại vẽ ra còn nhỏ hơn.
    static let referenceTravel: Double = 710
}
