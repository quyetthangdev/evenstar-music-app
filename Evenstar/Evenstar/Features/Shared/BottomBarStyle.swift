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
    /// `morph` alone is read from `RootView`, `FloatingTabBar`, `PlayerCard`
    /// and `ScrollMinimise`, and if any two of those disagreed within a frame,
    /// the two halves of one morph would run different curves — a worse bug
    /// than having no reduced mode at all. A single storage location makes that
    /// disagreement impossible to express rather than merely unlikely. This is
    /// the same argument `RootView.isMinimisedActive` makes: filter once, in
    /// one place, instead of asking every reader to remember.
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
    // and `morph` at 99.9356%, 0.0644% under. Six hundredths of a percent is
    // `morph`'s number, quoted against the constant it is ten times too small
    // for. The trough depth is a function of the damping ratio *alone* —
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
    //   expand               0.52 / 0.12  0.372    0.37
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
    ///
    /// Reduced: 0.20s `easeInOut`, the point at which the spring above is
    /// visually done. The shape-change itself stays — a pill becoming a circle
    /// is the surface telling the user what it now is, and removing it would
    /// leave two indistinguishable states rather than a calmer transition. What
    /// goes is the overshoot: the pill no longer arrives past its own edge and
    /// swings back.
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
    ///
    /// Reduced: unchanged, and see the shared note above. 0.09s of ease-out is
    /// not a curve anyone can perceive as motion; the thing that moves is
    /// `pressedScale`, and removing *that* is B4's decision at the call site.
    /// Whatever replaces it there still wants to answer the finger in 0.09s.
    @MainActor static var press: Animation { reduceMotion ? pressFlat : pressFull }
    private static let pressFull = Animation.easeOut(duration: 0.09)
    private static let pressFlat = pressFull

    /// What a pressed tab shrinks to. Shallower than the transport buttons'
    /// 0.92: those are 44pt circles the thumb lands on squarely, while a tab is
    /// a whole quarter of the bar, and the same ratio on something that wide
    /// reads as the bar itself flinching.
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
    /// more accessible one, so the three styles that lose a scale here —
    /// `TabPressStyle`, `QueueToggleStyle`, `TransportButtonStyle` — all pick
    /// this up in its place.
    ///
    /// **One number for all three, where `pressedScale` deliberately differs per
    /// control.** That difference exists because a percentage of a wide thing is
    /// many points of travel and a percentage of a small thing is barely any:
    /// 0.96 on a quarter-bar tab and 0.9 on a 44pt glyph are the same *apparent*
    /// movement. Opacity has no points in it. There is nothing for the size of
    /// the control to scale, so a second figure would be a distinction without
    /// a difference — and this file exists to stop the pieces down here drifting
    /// apart.
    ///
    /// **0.45, and why that is enough to see.** The bar already stakes a
    /// readability claim on a smaller gap than this one: `tint(isCurrent:)` in
    /// `FloatingTabBar` distinguishes the current destination from the other
    /// three by 1.0 against 0.6 and nothing else, and that difference is
    /// expected to be read at a glance, on a 15pt glyph, without moving. A press
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
    /// Reduced: 0.37s `easeInOut`, the longest flat curve here, for the same
    /// reason it is the longest spring — 750pt covered too fast arrives before
    /// the eye has followed it, and that is true of a flat curve too. The
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
    /// while the new one fades in. `PlayerCard.morph(to:curve:)` says what
    /// that costs and why the version without the cut is out of reach here.
    ///
    /// The full branch is untouched and still animates the whole travel.
    ///
    /// Note that `PlayerCard.morph(to:curve:)` fades on whatever curve its
    /// caller passes, not on this one specifically: a tap arrives here, a
    /// release after a drag arrives at `settle`'s 0.29s. The two keep their
    /// different tempos in the reduced mode exactly as they had them in the
    /// full one.
    @MainActor static var expand: Animation { reduceMotion ? expandFlat : expandFull }
    private static let expandFull = Animation.spring(duration: 0.52, bounce: 0.12)
    private static let expandFlat = Animation.easeInOut(duration: 0.37)

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
    @MainActor static var recedeScale: CGFloat { reduceMotion ? recedeScaleFlat : recedeScaleFull }
    private static let recedeScaleFull: CGFloat = 0.92
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
    @MainActor static var queueContentOut: Animation { reduceMotion ? queueContentOutFlat : queueContentOutFull }
    private static let queueContentOutFull = Animation.easeIn(duration: 0.10)
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
    ///
    /// Giảm chuyển động: **giữ nguyên**, xem ghi chú chung ở đầu phần này. Chỉ
    /// là lượng mực của một khối chữ đi về 0 — không dịch chuyển, không phóng
    /// to. Cả `delay(0.04)` cũng giữ: nó là dàn cảnh chứ không phải chuyển
    /// động, và lập luận về **mối nối** ở trên (`easeOut` về 0 với vận tốc gần
    /// 0 để khớp đạo hàm với cú hiện tiếp sau) vẫn đúng nguyên si khi cú hiện
    /// tiếp sau đổi từ lò xo sang curve — curve cũng khởi động từ vận tốc 0.
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
    ///
    /// That warning has since been measured, not just guessed at. On device
    /// (Instruments "Animation Hitches", Release, scrolling the Songs list)
    /// `FloatingTabBar`'s three call sites cost 87.6 ms/s of hitch — even
    /// constant, a shadow over `.regularMaterial` cannot be cached, because its
    /// shape has to be re-derived from the blurred content behind it every
    /// frame. Removing all three brought it to 0.0 ms/s, against Apple's
    /// 10 ms/s "bad" threshold, and `FloatingTabBar.swift` no longer calls
    /// `floatingBarShadow()` anywhere. `PlayerCard`'s call (~line 1176) is
    /// still standing and still **unmeasured** — its fate is a separate
    /// decision, not something to infer from the tab bar's number.
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
    /// The same trade `selectionWash(for:)` and the two `ButtonStyle`s made:
    /// answer with opacity, not with shape.
    ///
    /// **One mechanism, not seven branches.** Six production sites plus the
    /// demo reachable from Settings read this. Written per-site it would be
    /// seven chances to miss the eighth.
    ///
    /// The unreduced branch is exactly the call it replaces, so nothing changes
    /// for anyone with the setting off.
    @MainActor
    func symbolReplace() -> some View {
        contentTransition(BottomBarStyle.reduceMotion ? .opacity : .symbolEffect(.replace))
    }
}
