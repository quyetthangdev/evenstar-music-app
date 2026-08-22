import SwiftUI

enum LibraryTab: String, Identifiable {
    case songs, albums, artists, account, search
    var id: String { rawValue }

    /// The four that share the pill. Search is deliberately absent: it lives
    /// in its own circular button beside the pill.
    ///
    /// `CaseIterable` is deliberately NOT adopted. With it, `allCases` reads
    /// as the obvious way to lay out "the tabs", and using it would draw
    /// search twice — once in the pill and once in its own button. Leaving the
    /// conformance off makes that mistake impossible rather than merely
    /// warned against. Adding a destination means adding it here.
    static let pillTabs: [LibraryTab] = [.songs, .albums, .artists, .account]

    /// **`String(localized:)`, not a bare literal.** A `String` handed to
    /// `Text` is displayed verbatim — only a string *literal* becomes a
    /// `LocalizedStringKey` and goes through the catalogue. So an enum that
    /// returns plain literals renders untranslated no matter how complete the
    /// catalogue is, and it does not even appear in it to be noticed as
    /// missing: the tab bar and the source chips stayed Vietnamese in an
    /// English build, with everything else around them translated.
    ///
    /// Localising here rather than at the call site keeps it a `String`, which
    /// one caller needs — the accessibility label interpolates it into a
    /// sentence, and `LocalizedStringKey` cannot be interpolated into one.
    var label: String {
        switch self {
        case .songs:   String(localized: "Bài hát", bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
        case .albums:  String(localized: "Album", bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
        case .artists: String(localized: "Nghệ sĩ", bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
        case .account: String(localized: "Tài khoản", bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
        case .search:  String(localized: "Tìm kiếm", bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
        }
    }

    var symbol: String {
        switch self {
        case .songs:   "music.note.list"
        case .albums:  "square.stack"
        case .artists: "music.mic"
        case .account: "person.crop.circle"
        case .search:  "magnifyingglass"
        }
    }
}

/// The floating tab bar beneath the collapsed Now Playing pill: a pill holding
/// four destinations, and a separate circular search button beside it.
///
/// Labels in the pill are never hidden behind a size class or Dynamic Type
/// check — four items have the room, and unlabelled symbols are worse for
/// someone opening the app for the first time. The search button is the one
/// exception, and it carries an explicit accessibility label to compensate.
struct FloatingTabBar: View {
    @Binding var selection: LibraryTab
    /// Drives the morph between the four-tab bar and the search field.
    @Binding var isSearching: Bool
    @Binding var query: String
    /// Mirrors the field's focus outward, so callers can react to the keyboard
    /// actually being up rather than guessing from `isSearching`. The two are
    /// not the same: search opens without the keyboard.
    @Binding var isEditing: Bool
    /// Drives the morph between the four-tab bar and the minimised circle,
    /// set by a caller watching scroll direction.
    ///
    /// `RootView` passes a masked view of its real flag here, not the flag
    /// itself: this reads `false` whenever `isSearching` is `true`, no matter
    /// what the real state underneath holds, so `isCollapsed` and
    /// `restoreButton` below can never see both flags true at once — see
    /// `isMinimisedActive` in `RootView`. `trailingButton`'s
    /// `isMinimised = false`, on the way into search, still clears the real
    /// state through this same binding, so the flag does not snap back
    /// minimised the instant search closes without a fresh scroll — but that
    /// write is belt-and-braces now, not the guarantee.
    @Binding var isMinimised: Bool

    /// Whether a track is loaded, which decides *which* minimised layout the
    /// bar collapses to. Not `isPlaying` — a paused track still owns the middle
    /// slot, because the collapsed player is still on screen there.
    let hasTrack: Bool

    /// Called when the trailing button opens search.
    let onOpenSearch: () -> Void
    /// Called when search closes. `nil` means "back where you came from";
    /// a tab means go there explicitly. The bar does not know the tab history —
    /// `RootView` owns it — so it says what it wants rather than deciding.
    let onCloseSearch: (LibraryTab?) -> Void
    /// Called when the minimised circle is tapped. Restores the full bar —
    /// it does not navigate, even though it is drawn with the current tab's
    /// icon. See the type-level doc for why.
    let onRestore: () -> Void

    @FocusState private var queryFocused: Bool

    /// Ties the selected tab's wash to one geometry across all four slots, so
    /// changing tabs moves a single capsule rather than swapping two.
    @Namespace private var selectionNamespace

    /// Ties the active tab's glyph to the minimised circle's glyph, so the two
    /// are one view travelling rather than one fading out while another fades
    /// in somewhere else.
    @Namespace private var glyphNamespace

    // No explicit init. The one that stood here defaulted `isMinimised` to
    // `.constant(false)` and `onRestore` to `{}` so `RootView` kept compiling
    // while it was out of scope; both are now supplied for real, and keeping
    // the defaults would mean the next view to build this bar — a new screen, a
    // second root, a preview — silently gets one that can never minimise, with
    // no compiler error and nothing on screen to notice. The synthesized
    // memberwise init has no defaults to give, so omitting either argument is a
    // build error instead.

    /// "The leading capsule is a circle." True for either morph that shrinks
    /// the four-tab pill down to one glyph. Everything that only cares about
    /// the capsule's *shape* reads this instead of `isSearching` directly, so
    /// minimising reuses the exact same collapse path rather than a second
    /// one. What still must stay keyed to `isSearching` alone — the search
    /// field's width, the trailing button's glyph/label, and the bar's
    /// height — does not go near this value.
    private var isCollapsed: Bool { isSearching || isMinimised }

    /// The bar collapses all the way to one small centred capsule holding the
    /// current tab and search, rather than to a circle at each edge.
    ///
    /// Only when minimised **with nothing playing**. With a track loaded the
    /// space between the two circles is not empty — the collapsed player sits
    /// exactly there — so merging would drop the bar on top of it.
    ///
    /// Searching never merges: that mode needs the full width for its field.
    private var isMerged: Bool { isMinimised && !hasTrack && !isSearching }

    private static let symbolSize: CGFloat = 15
    /// The selected item's backing. Drawn over the material rather than
    /// replacing it, so it reads as a slightly darker patch of the same
    /// surface. `.primary` rather than a fixed grey so it inverts with the
    /// colour scheme: a 10% black wash in light mode, 10% white in dark, both
    /// separating the selected item from the bar around it.
    private static let selectionWash = 0.10

    /// How far the selected item's capsule sits inside the pill, on every side.
    ///
    /// A uniform inset is what makes the two shapes **concentric**, which is
    /// how the real thing looks. The pill is `tabBarHeight` tall, so its caps
    /// have radius `tabBarHeight / 2` = 27 and its leading cap is centred at
    /// (27, 27). Inset the inner capsule by 5 on every side and it is 44 tall,
    /// radius 22, with its leading cap centred at (5 + 22, 5 + 22) — the same
    /// point. The two curves stay parallel instead of drifting apart.
    ///
    /// The inset survives a change in `tabBarHeight` for free: both radii shrink
    /// by the same amount, so the centres stay coincident whatever the height.
    ///
    /// This only holds if the selected item's backing fills its whole slot and
    /// is then inset. Sizing it to hug the icon and label instead — padding
    /// around the content — makes its width depend on how long each label is
    /// and pulls its leading edge away from the pill's curve, which is what
    /// this replaced.
    private static let selectionInset: CGFloat = 5

    /// The tint for a bar item, by whether it is the current destination.
    ///
    /// `Color.primary` at an opacity rather than the `.primary`/`.secondary`
    /// pair those two sites used to switch between. Those are *hierarchical*
    /// styles, and SwiftUI does not interpolate one into another — it resolves
    /// each to a colour and swaps. So the glyph and label snapped to their new
    /// tint in a single frame while the wash behind them slid across on a
    /// spring: the one part of a tab change that was not animating, in the
    /// middle of the part that was.
    ///
    /// An opacity does interpolate — but it must **not** interpolate on the
    /// wash's spring. Given `selectionSpring`'s 0.38s and its bounce, the
    /// destination tab spends the whole slide fading up, which reads as the tab
    /// being dragged along behind the wash rather than the wash arriving at a
    /// tab that is already lit. The call sites give it `BottomBarStyle.control`
    /// instead: quick, and no bounce, since a colour has nowhere to overshoot
    /// to.
    ///
    /// So the two are deliberately on different curves. The wash is the thing
    /// travelling; the tint just has to stop snapping.
    ///
    /// 0.6 is not arbitrary — `secondaryLabel`, which `.secondary` resolves to,
    /// is 60% in both light and dark. Nothing looks different at rest; only the
    /// transition between the two changed.
    private static func tint(isCurrent: Bool) -> Color {
        Color.primary.opacity(isCurrent ? 1 : 0.6)
    }

    /// Identifies the selected tab's wash across all four slots. A constant,
    /// because the whole point is that every slot claims the *same* geometry.
    ///
    /// Claimed **only on the travelling branch**. With Reduce Motion on the
    /// wash is built a different way and this id is never handed out at all —
    /// see `selectionWash(for:)`.
    private static let selectionGeometryID = "tab-selection-wash"

    /// Identifies a tab's glyph as it travels between its slot in the pill and
    /// the minimised circle.
    ///
    /// Exactly one view may claim a given id at a time, which is why both sites
    /// are behind an `if` on `isMinimised` rather than being present-but-hidden.
    /// Two live claimants make SwiftUI position one from the other's frame, and
    /// the glyph lands somewhere neither of them is.
    ///
    /// **Keyed per tab, not one shared id.** As a single constant it also
    /// matched across a plain tab change: the outgoing tab's glyph dropped the
    /// id and the incoming tab's picked it up, so SwiftUI read that as one view
    /// moving and flew the destination icon in from the previous tab's slot.
    /// The effect was never written for that — it exists only for the trip into
    /// the minimised circle — and a tab bar whose icons move is the specific
    /// thing that makes it unusable without looking: Apple moves the indicator
    /// and nothing else.
    ///
    /// Per tab, two different tabs simply hold two different ids and there is
    /// nothing to match. The minimise trip is unaffected, because
    /// `restoreButton` asks for the *selected* tab's id — still exactly one
    /// source and one destination.
    ///
    /// Claimed **only on the travelling branch**, exactly like
    /// `selectionGeometryID`. With Reduce Motion on neither site hands this out
    /// at all — see `tabSlotGlyph(for:)` and `restoreGlyph`.
    private static func activeGlyphID(for tab: LibraryTab) -> String {
        "active-tab-glyph-\(tab.rawValue)"
    }

    /// How far the field's growth trails the tab pill's collapse, and the
    /// reverse on the way back. Short enough that the bar still feels like one
    /// gesture — much more and the two halves read as separate events.
    ///
    /// It is a fraction of `BottomBarStyle.morph`'s duration, not an absolute
    /// time. Shortening that spring without shortening this leaves the delay
    /// occupying most of the animation, so the field straggles in after the
    /// movement it was meant to be part of.
    ///
    /// It doubles as the tab row's fade delay on the way back in, so the tabs
    /// do not start appearing before the capsule has begun to grow.
    ///
    /// The three springs this file used to define — the morph, the wash's
    /// slide, and the content's shrink — now live in `BottomBarStyle`, so the
    /// collapsed player and anything added down here later move on the same
    /// curves as this bar rather than on their own.
    private static let stagger = 0.07

    /// What the tabs shrink to as the pill closes, and grow from as it opens.
    ///
    /// **Only the distance travelled. The timing, the fade, the stagger and the
    /// clip are all unchanged** — moving this changes how far the glyphs go, not
    /// how they get there.
    ///
    /// It has been three values, and the middle one is the reason this doc is
    /// long. At **0.92** the shrink was invisible: it was paired with the fade
    /// across two curves with two delays, and a glyph fading out while barely
    /// changing size just reads as fading. **0.75** made it read, and that was
    /// the right call at the time.
    ///
    /// **0.86** now, because the fix that made 0.92 fail was fixed separately:
    /// the shrink and the fade were put on one animation, so the size change is
    /// carried by the same curve the eye is already following instead of
    /// competing with a second one. On one curve a quarter of travel is more
    /// than the motion needs — it reads as the glyphs being pulled away rather
    /// than tucked in.
    ///
    /// **Giảm chuyển động: 1** — không co một chút nào, cú mờ đi một mình.
    ///
    /// Đây là cú phóng nổ *thường xuyên* nhất trong app, và điều đó không hiện
    /// ra từ tên biến: `isCollapsed = isSearching || isMinimised`, mà
    /// `isMinimised` do cuộn danh sách thư viện lái. Tức nó không chỉ chạy khi
    /// người dùng mở ô tìm kiếm — nó chạy vài lần một phút trong lúc lướt danh
    /// sách bài hát, cả bốn khối glyph+nhãn cùng co 14%.
    ///
    /// Bỏ được vì đoạn văn trên đã tự nói ra: ở 0.92 cú co là **vô hình** và
    /// thứ người ta thật sự đọc được là cú mờ. Cú mờ ở lại nguyên vẹn
    /// (`.opacity(isCollapsed ? 0 : 1)` ngay dưới `.scaleEffect`), nên các tab
    /// vẫn hiện ra và vẫn biến đi đúng nhịp cũ, trên đúng đường cong cũ, với
    /// đúng cú `stagger` cũ. Chỉ có quãng đường là mất.
    /// Nội bộ chứ không `private`, cùng lý do `BottomBarStyle.recedeScale` là
    /// vậy: đây là con số duy nhất nói bốn khối tab còn co hay không.
    @MainActor static var tabRevealScale: CGFloat {
        BottomBarStyle.reduceMotion ? tabRevealScaleFlat : tabRevealScaleFull
    }
    private static let tabRevealScaleFull: CGFloat = 0.86
    private static let tabRevealScaleFlat: CGFloat = 1

    /// Mỗi tab rời đi **muộn hơn tab bên phải nó**, và quay lại theo chiều ngược.
    ///
    /// Trước đây cả bốn tab dùng chung một độ trễ, nên chúng mờ đi cùng lúc —
    /// bốn khối biến mất như một mảng. Apple cho chúng rụng lần lượt từ phải
    /// sang trái, và điều đó không phải trang trí: viên nang thu về phía **trái**,
    /// nên tab bên phải là tab bị mép clip chạm tới trước. Cho nó mờ trước là
    /// cho cú mờ đi cùng chiều với cú clip thay vì cắt ngang nó.
    ///
    /// Chiều bung đảo lại: tab trái hiện ra trước, vì mép clip mở ra từ đó.
    ///
    /// 0.03s mỗi bậc, bốn tab nên toàn dãy trải 0.09s — ngắn hơn `content`
    /// (0.34s) nhiều lần, nên nó đọc ra là một đợt sóng chứ không phải bốn cú
    /// riêng lẻ. Dài hơn thì tab cuối còn nằm đó khi viên nang đã đóng gần hết.
    ///
    /// Giảm chuyển động: **giữ nguyên**. Đây là dàn cảnh, không phải chuyển
    /// động — cùng lập luận với `BottomBarStyle.queueTitleOut`.
    static let tabCascadeStep: TimeInterval = 0.03

    /// Quãng mỗi tab trượt về trái khi rời đi.
    ///
    /// **Mọi tab đều trượt, và bản đầu thì không.** Công thức cũ tỉ lệ thẳng
    /// theo chỉ số — tab trái nhất nhận đúng 0. Sai ở chỗ tab trái nhất là tab
    /// **sống lâu nhất** trong cú thu: viên nang clip từ phải sang, nên ba tab
    /// kia bị che gần như ngay, còn tab đầu ở lại tới cuối. Thứ người ta nhìn
    /// được lâu nhất lại là thứ duy nhất đứng yên, nên cú trượt gần như không
    /// tồn tại trên màn hình.
    ///
    /// Giờ mọi tab trượt ít nhất `baseFraction` của quãng, và tab càng bên phải
    /// càng đi xa hơn. Giữ được cả hai: hàng vẫn **hội tụ** về phía viên tròn
    /// sắp thành hình, mà không tab nào bị bỏ lại đứng im.
    ///
    /// Giảm chuyển động: **0**. Đây là quãng đường thật, đúng thứ cài đặt ấy
    /// tồn tại để bỏ — cùng quyết định với `tabRevealScaleFlat`.
    @MainActor static var tabCascadeShift: CGFloat {
        BottomBarStyle.reduceMotion ? 0 : tabCascadeShiftFull
    }
    /// 14 → 18 → **40**, và hai bước đầu đều quá ngắn vì cùng một lý do.
    ///
    /// Mỗi tab chỉ hiện trong một phần của cú thu trước khi mép clip che nó —
    /// khe thời gian ấy ngắn, nên quãng đường phải **dài** thì cú trượt mới đọc
    /// ra được. Một quãng vừa phải chia cho một khe hẹp thì thành đứng yên.
    ///
    /// 40pt là khoảng nửa bề rộng một ô tab (~75pt trên màn 402pt). Đủ để đọc
    /// ra là các tab đang bị **thu về** phía viên tròn, chứ không phải rung nhẹ
    /// tại chỗ. Chúng chồng lên nhau ở cuối hành trình, và điều đó không sao:
    /// tới lúc ấy chúng đã mờ gần hết, và cú chồng đọc ra như xếp lại chứ không
    /// như va nhau.
    private static let tabCascadeShiftFull: CGFloat = 40

    /// Phần quãng mà **mọi** tab đi, kể cả tab trái nhất.
    ///
    /// 0.55 nên tab đầu đi 55% quãng và tab cuối đi 100% — đủ chênh để hàng đọc
    /// ra là hội tụ, đủ nền để không tab nào đứng yên.
    static let tabCascadeBaseFraction: CGFloat = 0.55

    /// Độ trễ và quãng trượt của một tab, theo vị trí của nó trong hàng.
    ///
    /// Chỉ số 0 là tab trái nhất. Khi thu, đảo lại để tab phải nhất chạy trước.
    private func cascade(index: Int) -> (delay: TimeInterval, shift: CGFloat) {
        let count = LibraryTab.pillTabs.count
        let fromRight = count - 1 - index
        let spread = CGFloat(index) / CGFloat(max(count - 1, 1))
        let fraction = Self.tabCascadeBaseFraction
            + (1 - Self.tabCascadeBaseFraction) * spread
        return (
            delay: Double(isCollapsed ? fromRight : index) * Self.tabCascadeStep,
            shift: -Self.tabCascadeShift * fraction
        )
    }

    /// Shorter while searching: one text field needs less room than an icon
    /// stacked over a label.
    private var barHeight: CGFloat {
        isSearching ? BottomBarMetrics.searchBarHeight : BottomBarMetrics.tabBarHeight
    }

    /// Three slots whose widths carry the whole morph.
    ///
    /// Closed: the leading capsule takes all the room as the four-tab pill,
    /// the search capsule is zero-wide, and the trailing circle is the search
    /// button. Open: the leading capsule shrinks to a circle holding the way
    /// home, the search capsule grows into the gap it leaves, and the trailing
    /// circle becomes the close button.
    ///
    /// The two are **staggered**, which is what makes it read as one thing
    /// becoming another rather than everything sliding at once: opening, the
    /// tab pill collapses first and the field grows into the space afterwards;
    /// closing runs it backwards, the field folding away before the tabs
    /// return. Hence `.animation` per slot with a delay keyed on the direction,
    /// rather than one `withAnimation` at the call site — a single wrapper
    /// cannot give two subviews different timing.
    var body: some View {
        // Measured so the tabs can be laid out at the width the pill will
        // *end* at, rather than at whatever width it happens to be mid-morph.
        // See `leadingCapsule(expandedWidth:)` for why that matters.
        //
        // The outer fixed height keeps the reader from growing to fill the
        // screen, and the inner `alignment: .bottom` keeps the bar's bottom
        // edge still while its height changes — it is anchored to the bottom
        // of the screen, so shrinking should move its top, not lift it.
        GeometryReader { geo in
            content(availableWidth: geo.size.width)
                .frame(
                    width: geo.size.width,
                    height: BottomBarMetrics.tabBarHeight,
                    alignment: .bottom
                )
        }
        .frame(height: BottomBarMetrics.tabBarHeight)
        .padding(.horizontal, BottomBarMetrics.sideMargin)
        // Opening search deliberately does NOT raise the keyboard: the user
        // sees the field and taps it when they want to type. Closing does have
        // to drop focus explicitly, or the keyboard outlives the field that
        // owns it — the field stays in the hierarchy at opacity 0 rather than
        // being torn down, so it never loses focus on its own.
        .onChange(of: isSearching) { _, searching in
            if !searching { queryFocused = false }
        }
        .onChange(of: queryFocused) { _, focused in
            isEditing = focused
        }
    }

    private func content(availableWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            leadingCapsule(
                expandedWidth: availableWidth
                    - BottomBarMetrics.tabBarSearchGap
                    - BottomBarMetrics.tabBarHeight
            )
            // Co về **mép trái của chính nó**, không về tâm thanh bar.
            //
            // Bản đầu đặt một `scaleEffect` lên cả thanh bar. Nó co về tâm, nên
            // viên tròn trái dịch sang phải và nút tìm dịch sang trái — cả hai
            // lấn vào chỗ viên pill đang đứng, và ba khối dính vào nhau. Viên
            // pill không co theo được vì nó nằm trong `PlayerCard`, một hệ toạ
            // độ khác.
            //
            // Neo ở mép ngoài thì mỗi khối co vào trong chính nó: mép trái của
            // viên tròn và mép phải của nút tìm đứng yên, còn hai khe hở hai
            // bên viên pill **rộng ra** thay vì hẹp lại.
            //
            // Hai lớp `.animation`, và thứ tự là load-bearing: lớp **trong**
            // nhận cú hẹp bề ngang trên `morph`, lớp **ngoài** nhận cú co trên
            // `chromeSettle` nảy hơn. Gộp một lớp thì cú nảy lan sang bề ngang,
            // và viên nang sẽ vượt quá kích thước cuối rồi lùi lại — xem
            // `BottomBarStyle.chromeSettle` về vì sao đó là hai chuyện khác nhau.
            .animation(
                BottomBarStyle.morph.delay(isCollapsed ? 0 : Self.stagger),
                value: isCollapsed
            )
            .scaleEffect(isCollapsed ? BottomBarStyle.collapsedChromeScale : 1,
                         anchor: .leading)
            .animation(BottomBarStyle.chromeSettle, value: isCollapsed)

            // Fixed, so the gap between the leading capsule and whatever
            // follows never collapses. The search capsule's own trailing gap
            // is conditional instead — at zero width it must contribute
            // nothing, or the closed bar would carry a phantom 8pt.
            //
            // The height is not decoration. `Color` is greedy in any axis left
            // unconstrained, so a width-only frame here stretches the whole
            // `HStack` to the height of its container and the bar ends up
            // centred in the middle of the screen instead of sitting at the
            // bottom.
            Color.clear.frame(
                width: isMerged ? 0 : BottomBarMetrics.tabBarSearchGap,
                height: barHeight
            )

            // The row's one flexible element while collapsed by either mode.
            // With `leadingCapsule` clamped to `barHeight` and `trailingButton`
            // fixed, *something* between them has to be greedy or the HStack
            // shrinks to its intrinsic width and the outer `.frame(width:
            // geo.size.width, alignment: .bottom)` — `.bottom` only pins the
            // vertical axis — centres that short row instead of pinning the
            // two circles to the leading and trailing edges. `searchCapsule`
            // already played this role for search; keying its width on
            // `isCollapsed` instead of `isSearching` lets minimising reuse it
            // rather than adding a second flexible element that would have to
            // be kept in lockstep with this one.
            //
            // The width this resolves to is not incidental: with `leadingCapsule`
            // at `tabBarHeight` (50) and this gap at `tabBarSearchGap` (8) on
            // each side, this capsule spans exactly
            // `[58, W − 58]` in the bar's own (post-`sideMargin`) coordinate
            // space — the same span Task 2 slots the collapsed player pill
            // into via `BottomBarMetrics.minimisedPlayerInset`. Landing on a
            // different span here would leave the player visibly out of line
            // with the two circles, with nothing in a build or a test to
            // catch it.
            searchCapsule
                .padding(.trailing, (isCollapsed && !isMerged) ? BottomBarMetrics.tabBarSearchGap : 0)
                .animation(
                    BottomBarStyle.morph.delay(isCollapsed ? Self.stagger : 0),
                    value: isCollapsed
                )

            // Zero-width and invisible when merged: its glyph has moved inside
            // the merged capsule, and leaving a 56pt button here would both
            // duplicate search and push the centred row off centre. `.clipped()`
            // still earns its keep without a shadow beside it — `trailingButton`
            // is a fixed `barHeight`-square view, and without the clip it would
            // overflow the zero-width frame above instead of disappearing into
            // it.
            //
            // No shadow modifier here any more — see the comment on the main
            // pill's `.clipShape(Capsule())` in `leadingCapsule(expandedWidth:)`
            // for the mechanism and the measured numbers (87.6 → 0.0 ms/s).
            //
            // **What used to stand here, and why it is back.** The rule was
            // `.clipped()` before the shadow, never after: a shadow is drawn
            // *outside* the shape that casts it, so clipping over one cuts its
            // soft edge off at the frame's rectangle — which is exactly the
            // square halo that appeared around this circular button once the
            // clip was added for the merged layout. When the shadow went, that
            // paragraph went with it as no longer applying here, and that was
            // one step too far: `floatingBarShadow()` still exists, and
            // `PlayerCard` still calls it on a view that is itself clipped. The
            // bug is one `.floatingBarShadow()` away from being reintroduced in
            // this file too, and a bug that has been paid for once should not
            // have to be found twice. Anyone putting a shadow back on a clipped
            // view here: it goes after the clip, not before.
            trailingButton
                // Neo mép phải, đối xứng với viên tròn trái — xem ghi chú ở đó.
                .scaleEffect(isCollapsed ? BottomBarStyle.collapsedChromeScale : 1,
                             anchor: .trailing)
                .animation(BottomBarStyle.chromeSettle, value: isCollapsed)
                .frame(width: isMerged ? 0 : barHeight)
                .clipped()
                .opacity(isMerged ? 0 : 1)
                .animation(BottomBarStyle.morph, value: isSearching)
        }
    }

    /// The four-tab pill, collapsing to a circular way home.
    ///
    /// Both rows exist at all times and cross-fade, with the capsule's frame
    /// animating underneath them. Swapping them with `if`/`else` would tear one
    /// subtree down and build the other, and SwiftUI cannot animate a frame
    /// across that — the capsule would jump between its two widths instead of
    /// collapsing.
    ///
    /// The hidden row leaves hit-testing and accessibility too. Opacity alone
    /// keeps it tappable and readable by VoiceOver, so the tabs would still
    /// respond from behind the collapsed circle.
    /// - Parameter expandedWidth: the width this capsule reaches when the bar
    ///   is closed. The tabs are laid out at **that** width at all times, not
    ///   at the capsule's current one, and the capsule clips them.
    ///
    ///   Laying them out in the live width is what made them slide: collapsed,
    ///   four tabs sharing a 48pt circle are 12pt each and bunched at the left,
    ///   and every one of their centres travels rightwards as the capsule
    ///   grows. Pinned to the final width instead, each tab simply sits where
    ///   it belongs and the expanding clip uncovers it, so it can scale up in
    ///   place with nothing to slide.
    private func leadingCapsule(expandedWidth: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            // No opacity here: each tab fades and scales on its own schedule,
            // inside `tabsRow`. Hit-testing and accessibility stay at row
            // level, since those flip for the whole row at once.
            tabsRow
                .frame(width: expandedWidth, alignment: .leading)
                .allowsHitTesting(!isCollapsed)
                .accessibilityHidden(isCollapsed)

            // Two circles occupy the same spot and cross-fade, exactly like
            // `tabsRow`/`homeButton` above. The two conditions below are
            // genuinely mutually exclusive, not merely unreached: `isMinimised`
            // is a binding `RootView` constructs from `isMinimisedActive`,
            // which reads `false` whenever `isSearching` is `true` regardless
            // of what the real state holds — see the doc comment on
            // `isMinimised` above. At most one of these two is ever opaque
            // because of that, not because of anything local to this view; do
            // not "simplify" this back to a plain, unmasked `isMinimised`.
            homeButton
                .opacity(isSearching ? 1 : 0)
                .allowsHitTesting(isSearching)
                .accessibilityHidden(!isSearching)

            // No `.opacity` here any more. The glyph's presence is conditional
            // now, so there is nothing to hide when expanded — and fading it
            // would fade the travelling glyph itself, which is meant to stay
            // solid the whole way across.
            restoreButton
                .allowsHitTesting(isMinimised)
                .accessibilityHidden(!isMinimised)
        }
        // `maxWidth` rather than `width`: closed it takes everything the HStack
        // will give, open (searching or minimised) it is exactly as wide as it
        // is tall, which is what makes the capsule resolve to a circle.
        //
        // `alignment: .leading` is required, not tidy-up. `.frame(maxWidth:)`
        // centres its content, and this content is deliberately wider than the
        // frame while collapsed — centred, it overhangs equally on both sides
        // and the home glyph, which sits at the content's leading edge, ends up
        // outside the clip entirely. The circle renders empty.
        .frame(
            maxWidth: isMerged ? barHeight * 2 : (isCollapsed ? barHeight : .infinity),
            alignment: .leading
        )
        .frame(height: barHeight)
        .background(.regularMaterial, in: Capsule())
        // Load-bearing, not cosmetic: `tabsRow` is deliberately wider than this
        // capsule while it is collapsed, and without the clip those tabs draw
        // straight across the search field beside it.
        .clipShape(Capsule())
        // No shadow modifier here any more. A shadow over `.regularMaterial`
        // cannot be cached: its shape has to be re-derived from the blurred
        // content behind it every frame, which forces an offscreen
        // rasterisation pass on a view that is already animating. Measured on
        // device (Instruments "Animation Hitches", Release, scrolling the
        // Songs list): 87.6 ms/s of hitch with the shadow on this bar, 0.0 ms/s
        // with it removed — against Apple's 10 ms/s "bad" threshold. A
        // solid-colour backing with the same shadow still measured 6.9 ms/s, so
        // the material alone was not the cost; dropping the shadow is what
        // actually cleared it. The other two sites in this file that used to
        // carry the same shadow modifier point back to this comment rather
        // than repeating the numbers.
        //
        // `BottomBarStyle`'s shadow helper stays — `PlayerCard` still calls
        // it, and that call is unmeasured, a separate decision from this one.
    }

    /// Sized to the collapsed circle rather than filling. In a leading-aligned
    /// `ZStack` whose other child is deliberately over-wide, `maxWidth:
    /// .infinity` would stretch this across that whole width and put the glyph
    /// somewhere off in the middle of the search field.
    private var homeButton: some View {
        Button {
            onCloseSearch(.songs)
        } label: {
            Image(systemName: LibraryTab.songs.symbol)
                .font(.system(size: Self.symbolSize))
                .foregroundStyle(.secondary)
                .frame(width: barHeight, height: barHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Về \(LibraryTab.songs.label)")
    }

    /// The minimised circle. Shows the **currently selected tab's** icon
    /// rather than a fixed glyph — it says where you are, which a fixed icon
    /// cannot — but tapping it does not navigate there. It restores the full
    /// bar. Nothing else on screen offers a way back other than scrolling up,
    /// and a circle that looks tappable and only navigates would be a trap.
    ///
    /// The accessibility label says what the tap *does*, not where the icon
    /// points: read on its own, a bare tab glyph announces a destination, and
    /// this button does not go there.
    /// The glyph a tab draws. Factored out so the active tab and
    /// `restoreButton` render the identical view, which is what makes the
    /// shared geometry read as one thing moving rather than two things
    /// swapping.
    private func glyph(for tab: LibraryTab) -> some View {
        Image(systemName: tab.symbol)
            .font(.system(size: Self.symbolSize))
    }

    /// The glyph in a tab's own slot, in the three states it can be in.
    ///
    /// **The same forced shape as `selectionWash(for:)`, for the same reason.**
    /// `matchedGeometryEffect` cannot be switched off: two views claiming one id
    /// in one namespace stay matched whatever is passed to the modifier, so "the
    /// glyph does not fly to the circle" is not something a flag on it can
    /// express. The only way to stop the travel is for the id never to be
    /// claimed, which means two structures rather than one with a parameter.
    ///
    /// **Travelling (the default).** The selected tab's glyph claims the id, and
    /// while the bar is minimised it steps aside for `restoreGlyph`, which
    /// claims the same one — leaving a hidden copy behind so the label below it
    /// does not lurch upward mid-collapse. Exactly one site holds the id at a
    /// time, which is what the `hidden()` branch is for.
    ///
    /// **Reduced.** Every slot draws a plain glyph, always, and nothing here
    /// ever claims an id. There is no hidden branch either: with nothing to
    /// travel, the placeholder would be a gap where an icon belongs. The row is
    /// already at `opacity(0)` by the time the bar is minimised, so the glyph it
    /// draws in that state is not visible — it fades out where it sits while
    /// `restoreGlyph` fades in where *it* sits, and nothing crosses the bar.
    ///
    /// The glyph stays, exactly as the wash stays: what Reduce Motion removes
    /// here is the journey, not the mark. A tab bar whose icons travel across it
    /// is the specific thing the note on `activeGlyphID(for:)` calls unusable
    /// without looking, and this is the same objection raised by an
    /// accessibility setting rather than by a bug.
    @ViewBuilder
    private func tabSlotGlyph(for tab: LibraryTab) -> some View {
        if BottomBarStyle.reduceMotion || selection != tab {
            glyph(for: tab)
        } else if isMinimised {
            glyph(for: tab).hidden()
        } else {
            glyph(for: tab).matchedGeometryEffect(
                id: Self.activeGlyphID(for: tab),
                in: glyphNamespace
            )
        }
    }

    /// The other end of that trip: the glyph inside the minimised circle.
    ///
    /// Reduced, it is the same image with no id on it, so it simply appears in
    /// the circle when `restoreButton`'s `if isMinimised` inserts it and goes
    /// when that is removed. Both branches draw the identical view — see
    /// `washInk` for why one description of the ink is the surest way to make
    /// the two modes indistinguishable at rest.
    @ViewBuilder
    private var restoreGlyph: some View {
        if BottomBarStyle.reduceMotion {
            glyph(for: selection)
        } else {
            glyph(for: selection).matchedGeometryEffect(
                id: Self.activeGlyphID(for: selection),
                in: glyphNamespace
            )
        }
    }

    /// Holds the active tab's glyph while the bar is minimised. The glyph is
    /// the *same* one the pill had — shared geometry travels it here as the
    /// capsule closes, and back to its slot as the capsule opens, so it slides
    /// rather than cross-fading between two positions.
    private var restoreButton: some View {
        HStack(spacing: 0) {
            Button {
                onRestore()
            } label: {
                Group {
                    if isMinimised {
                        restoreGlyph
                    }
                }
                .foregroundStyle(Self.tint(isCurrent: false))
                .frame(width: barHeight, height: barHeight)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hiện thanh điều hướng")

            // Search joins the capsule only in the merged layout. Everywhere
            // else it is the standalone trailing circle, and drawing it in both
            // places at once would put two search buttons on screen.
            //
            // Its own opacity rather than the row's: the capsule is growing
            // from 56 to 112 underneath it, and a glyph that appears at full
            // strength on frame one sits outside the capsule that has not
            // reached it yet.
            Button {
                onOpenSearch()
            } label: {
                glyph(for: .search)
                    .foregroundStyle(Self.tint(isCurrent: false))
                    .frame(width: barHeight, height: barHeight)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LibraryTab.search.label)
            .opacity(isMerged ? 1 : 0)
            .allowsHitTesting(isMerged)
            .accessibilityHidden(!isMerged)
        }
    }

    /// Zero-wide when closed, so it takes up no room and contributes no gap;
    /// flexible whenever the row is collapsed — by search **or** by
    /// minimising, so this stays the row's one flexible slot in either mode
    /// rather than a second one being added. `.clipShape` matters at zero
    /// width — without it the field and its icon spill out of a capsule that
    /// has no room for them.
    ///
    /// Content, visibility, hit-testing and accessibility all stay keyed to
    /// `isSearching` alone: while minimised this is reserved, invisible
    /// space — there is no field to show or interact with, only room held
    /// open for the collapsed player (Task 2) to occupy from outside this
    /// view.
    private var searchCapsule: some View {
        searchRow
            // Not flexible when merged. With nothing greedy in the row, the
            // HStack shrinks to its intrinsic width and the outer
            // `.frame(width: geo.size.width, alignment: .bottom)` centres it —
            // which is precisely the behaviour that shipped as a Critical
            // defect in Task 1, and precisely what the merged layout wants.
            .frame(maxWidth: (isCollapsed && !isMerged) ? .infinity : 0)
            .frame(height: barHeight)
            .background(.regularMaterial, in: Capsule())
            .clipShape(Capsule())
            // No shadow modifier here any more — see the comment on the main
            // pill's `.clipShape(Capsule())` in `leadingCapsule(expandedWidth:)`
            // for the mechanism and the measured numbers (87.6 → 0.0 ms/s).
            .opacity(isSearching ? 1 : 0)
            .allowsHitTesting(isSearching)
            .accessibilityHidden(!isSearching)
    }

    /// Each tab scales up in place as the pill's edge reaches it, rather than
    /// the row cross-fading as one — which put all four on screen while the
    /// pill was still a circle, in space it had not grown into yet.
    private var tabsRow: some View {
        tabsRowContent
            // The bar has a fixed height, so its content cannot be allowed to
            // grow without limit: `.caption2` scales with the user's text size,
            // and at the larger settings the icon-over-label stack outgrows the
            // 40pt selection wash and then the 50pt capsule itself.
            //
            // A clamp is the lesser evil here. The alternative usually reached
            // for — dropping the labels above some size — makes the bar less
            // usable for exactly the people who raised the text size. This lets
            // the labels grow as far as the bar can hold and stops there.
            //
            // Only the tabs are clamped. The search field's text scales
            // normally, because that one is content the user is reading and
            // editing rather than a fixed-size control.
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    /// Switches tabs, at most once per touch.
    ///
    /// Idempotent on purpose: the touch-down gesture reports continuously while
    /// the finger is down, and the `Button` fires again on lift. Both call
    /// this, and only the first one that finds a different tab does anything —
    /// which is also what stops a second animation from restarting the spring
    /// half way through the first.
    private func select(_ tab: LibraryTab) {
        guard selection != tab else { return }
        withAnimation(BottomBarStyle.selection) { selection = tab }
    }

    /// The wash itself. One expression, so the two structures below can only
    /// ever differ in *how they are identified*, never in what they look like:
    /// at rest the two modes have to be pixel-identical, and the surest way to
    /// get that is for there to be one description of the ink.
    private var washInk: some View {
        Capsule()
            .fill(Color.primary.opacity(Self.selectionWash))
            .padding(Self.selectionInset)
    }

    /// The selected tab's backing, in the slot belonging to `tab`.
    ///
    /// **Two structures, not one structure with a parameter**, and that is
    /// forced rather than chosen. `matchedGeometryEffect` cannot be switched
    /// off: two views claiming one id in one namespace stay geometrically
    /// matched whatever is passed to it, so "the wash does not travel" is not
    /// something a flag on that modifier can express. The only way to stop the
    /// travel is for there to be nothing to match.
    ///
    /// **Travelling (the default).** One capsule, handed from tab to tab.
    ///
    /// Each tab used to draw its own, so changing tabs removed one view and
    /// inserted another — nothing moved, because nothing was the same view
    /// twice. `matchedGeometryEffect` makes it one view as far as SwiftUI is
    /// concerned, so it interpolates the frame between the old slot and the new
    /// one and the wash slides across.
    ///
    /// This is the case that effect is actually for, and it is not the case
    /// `PlayerCard`'s doc comment rejects it for: both slots are in one view
    /// tree in one layout pass, and this is a discrete state change rather than
    /// something tracking a finger.
    ///
    /// **Reduced.** A wash in *every* slot, at all times, and only its opacity
    /// changes. Nothing is inserted and nothing is removed as the selection
    /// moves, so there is no pair of views for SwiftUI to match and no frame to
    /// interpolate: the old slot's wash fades out where it is and the new
    /// slot's fades in where it is. Nothing crosses the bar.
    ///
    /// The wash stays, rather than going the way `recedeScale` went. It is not
    /// decoration — it is the only thing on the bar that says which of the four
    /// destinations you are in, and the tint at `tint(isCurrent:)` is a 0.6-to-1
    /// difference on a 15pt glyph, not a replacement for it. What Reduce Motion
    /// removes here is the journey, not the mark.
    ///
    /// Both branches animate on whatever transaction changed `selection`, which
    /// is `select(_:)`'s `withAnimation(BottomBarStyle.selection)` — 0.18s of
    /// `easeInOut` with the setting on. The `.animation(BottomBarStyle.control,
    /// value: selection)` further up the chain is applied to the label before
    /// `.background`, so it does not reach this and the fade does not land on
    /// the tint's shorter curve.
    @ViewBuilder
    private func selectionWash(for tab: LibraryTab) -> some View {
        if BottomBarStyle.reduceMotion {
            washInk.opacity(selection == tab ? 1 : 0)
        } else if selection == tab {
            washInk.matchedGeometryEffect(
                id: Self.selectionGeometryID,
                in: selectionNamespace
            )
        }
    }

    private var tabsRowContent: some View {
        HStack(spacing: 0) {
            ForEach(Array(LibraryTab.pillTabs.enumerated()), id: \.element.id) { index, tab in
                Button {
                    // Touch-up, and by now `select` has almost always already
                    // run from the gesture below. It stays for the paths that
                    // have no touch-down phase at all — VoiceOver activation,
                    // Full Keyboard Access — and `select` is idempotent, so
                    // arriving here second costs nothing.
                    select(tab)
                } label: {
                    VStack(spacing: 2) {
                        // The active tab's glyph is the one that survives the
                        // collapse, so it is not drawn here while minimised —
                        // `restoreButton` draws it instead, and the shared
                        // geometry carries it there. Only one site may hold the
                        // id at a time, hence the `if` rather than hiding it.
                        //
                        // The placeholder keeps the `VStack`'s height while it
                        // is away, so the label beneath does not lurch upward
                        // mid-collapse.
                        //
                        // All three of those states, and the fourth the reduced
                        // mode adds, now live in `tabSlotGlyph(for:)` — the
                        // branch has to be structural, so it cannot be a
                        // modifier applied here.
                        tabSlotGlyph(for: tab)

                        Text(tab.label)
                            .font(.caption2)
                    }
                    .foregroundStyle(Self.tint(isCurrent: selection == tab))
                    // Scoped to `selection` so the tint lands on its own quick
                    // curve instead of riding the wash's long bouncy one. See
                    // `tint(isCurrent:)`.
                    .animation(BottomBarStyle.control, value: selection)
                    // Fill the slot first, then inset the backing — see
                    // `selectionInset`. Doing it the other way round (padding
                    // the content and letting the capsule hug it) sizes the
                    // backing to the label's length and breaks the concentric
                    // curve at the pill's leading edge.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { selectionWash(for: tab) }
                    // The whole slot takes the tap, not just the ink.
                    //
                    // `.frame(maxWidth:.infinity, maxHeight:.infinity)` above
                    // makes each tab *occupy* its quarter of the pill, but a
                    // frame is layout — it draws nothing, so it hit-tests
                    // nothing. Under `.buttonStyle(.plain)` the tappable area
                    // was therefore the glyph and the label themselves, and the
                    // wash behind them only exists for the selected tab. On a
                    // 402pt screen that is a 74×55pt slot with roughly 32×32pt
                    // of it live: the outer ring of every tab did nothing, which
                    // is why tapping one sometimes appeared to be ignored.
                    //
                    // The HIG's rule, on Buttons: "a button needs a hit region
                    // of at least 44x44 pt". A `Rectangle` here is exactly the
                    // slot the frame already claims, so no tab reaches into its
                    // neighbour — it only stops the gaps from being dead.
                    .contentShape(Rectangle())
                }
                .buttonStyle(TabPressStyle())
                // **Selection happens on touch-down, not on touch-up.**
                //
                // A `Button` runs its action when the finger lifts, so nothing
                // could begin moving until then — the wash, the glyph tint, the
                // screen behind. Shortening the animation does not touch that
                // gap because the gap is before the animation. Press feedback
                // filled it visually and the delay was still reported, which is
                // the evidence that made this worth its cost.
                //
                // **The cost, stated plainly: a mistaken tap can no longer be
                // taken back.** Everywhere else on iOS, touching a control and
                // sliding off before lifting cancels it; four tab slots along
                // the bottom edge of a phone is exactly where that matters
                // most. Apple's own tab bar selects on touch-up for this
                // reason. This is a deliberate departure, made because the
                // response was judged slow on a real device after the cheaper
                // fix had already been tried.
                //
                // `minimumDistance: 0` is what makes a `DragGesture` report the
                // touch itself rather than waiting for movement, and
                // `.simultaneousGesture` leaves the `Button` intact underneath —
                // so `isPressed`, the accessibility traits and the VoiceOver
                // action all keep working.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0).onChanged { _ in select(tab) }
                )
                // `.isButton` is restated alongside `.isSelected` only so
                // both branches of the ternary share one type — `Button`
                // already carries `.isButton` on its own, and
                // `accessibilityAddTraits` is additive, so this never removes
                // it. `.isSelected` is what makes VoiceOver announce which
                // tab is current.
                .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
                // Scaled about its own centre, so it grows where it belongs
                // instead of sliding in from anywhere. Keyed on `isCollapsed`,
                // not `isSearching` alone — this is the tab reveal, and it
                // must run identically whichever mode collapsed the pill.
                //
                // Shrink and fade on **one** animation, so a tab gets smaller
                // and dimmer at the same time rather than doing one and then
                // the other. An earlier pass split them across two curves with
                // two delays; it read as fussy, and the near-1 scale it used
                // was invisible next to the fade anyway.
                //
                // Still no per-tab stagger. The capsule is pinned to its
                // expanded width and clipped, so its edge already uncovers the
                // tabs in order as it sweeps — the ordering comes free from the
                // clip, and delaying each tab on top of that double-counts the
                // same effect.
                // Co, mờ và trượt trái — ba thứ trên **một** đường cong.
                //
                // Doc của `tabRevealScale` ghi lại vì sao: tách chúng ra hai
                // curve hai delay từng làm cú co thành vô hình, vì mắt đang bám
                // theo cú mờ. Quãng trượt mới thêm vào đây đi cùng hai thứ kia,
                // không mang lịch riêng.
                .scaleEffect(isCollapsed ? Self.tabRevealScale : 1)
                .offset(x: isCollapsed ? cascade(index: index).shift : 0)
                .opacity(isCollapsed ? 0 : 1)
                .animation(
                    BottomBarStyle.content
                        .delay(cascade(index: index).delay
                               + (isCollapsed ? 0 : Self.stagger)),
                    value: isCollapsed
                )
            }
        }
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: LibraryTab.search.symbol)
                .font(.system(size: Self.symbolSize))
                .foregroundStyle(.secondary)

            TextField("Bài hát, nghệ sĩ, album", text: $query)
                .textFieldStyle(.plain)
                .focused($queryFocused)
                .submitLabel(.search)
                // A library search is over titles and names the user already
                // has; autocorrecting "Biển" into a dictionary word, or
                // capitalising a lowercase artist name, only fights them.
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.leading, Self.selectionInset)
        .padding(.trailing, 16)
    }

    /// Opens search, then becomes the way out of it. Square frame at the bar's
    /// own height clipped to a circle, so it stays circular at either height
    /// and always matches the pill beside it.
    private var trailingButton: some View {
        Button {
            if isSearching {
                onCloseSearch(nil)
            } else {
                // Mutual exclusion enforced here, not hoped for from the
                // caller: minimised and searching both drive the leading
                // capsule, so opening search restores the bar first. This
                // binding write happens before `onOpenSearch()` sets
                // `isSearching`, in the same action, so the two flags are
                // never both true in any render this view produces.
                isMinimised = false
                onOpenSearch()
            }
        } label: {
            Image(systemName: isSearching ? "xmark" : LibraryTab.search.symbol)
                .font(.system(size: Self.symbolSize))
                // The one glyph that changes meaning mid-animation, so it
                // swaps on the same curve as the bar rather than popping.
                //
                // `symbolReplace()`, not `.contentTransition` directly: the
                // replace effect scales the glyph, and no `Animation` this bar
                // passes it can take that out. See the helper.
                .symbolReplace()
                .foregroundStyle(Self.tint(isCurrent: selection == .search))
                .animation(BottomBarStyle.control, value: selection)
                .frame(width: barHeight, height: barHeight)
                .background {
                    ZStack {
                        Circle().fill(.regularMaterial)
                        if selection == .search {
                            Circle().fill(Color.primary.opacity(Self.selectionWash))
                        }
                    }
                }
        }
        .buttonStyle(.plain)
        // Never carries visible text, and its meaning flips, so the label has
        // to flip with it. Without one, VoiceOver reads the symbol's own
        // description — "magnifying glass", or "xmark" — instead of what the
        // button does.
        .accessibilityLabel(
            isSearching
            ? String(localized: "Đóng tìm kiếm", bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
            : LibraryTab.search.label
        )
        .accessibilityAddTraits(selection == .search ? [.isButton, .isSelected] : .isButton)
    }
}

/// `.regularMaterial` needs content behind it to read as translucent rather
/// than flat grey — a gradient stands in for the library content that sits
/// behind the real bar. A wrapper view (rather than `@Previewable @State`)
/// so the binding has somewhere to live.
private struct FloatingTabBarPreview: View {
    @State private var selection: LibraryTab = .albums
    @State private var isSearching = false
    @State private var query = ""
    @State private var isEditing = false
    @State private var isMinimised = false

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [.blue, .purple, .orange],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Stands in for the real trigger — `RootView`'s scroll detection,
            // Task 3 — so the minimised mode can be seen in the canvas.
            // Wrapped in the same spring the bar itself uses, matching how
            // `RootView` will drive `isMinimised` in Task 4: unlike
            // `isSearching`, nothing inside `FloatingTabBar` owns this
            // transition's timing on the caller's behalf.
            VStack {
                // `verbatim`, so this preview-only scaffold does not put two
                // untranslatable English strings into the String Catalog.
                Button {
                    withAnimation(BottomBarStyle.morph) {
                        isMinimised.toggle()
                    }
                } label: {
                    Text(verbatim: isMinimised ? "Restore" : "Minimise")
                }
                .buttonStyle(.prominentAction)
                Spacer()
            }
            .padding(.top, 60)

            FloatingTabBar(
                selection: $selection,
                isSearching: $isSearching,
                query: $query,
                isEditing: $isEditing,
                isMinimised: $isMinimised,
                // `false`, so the preview's Minimise toggle shows the merged
                // layout — the one with nothing playing, which is the harder
                // of the two to reach in the running app.
                hasTrack: false,
                // Unwrapped, matching `RootView` — the bar owns its own timing,
                // and a `withAnimation` here would flatten the stagger.
                onOpenSearch: {
                    selection = .search
                    isSearching = true
                },
                onCloseSearch: { destination in
                    selection = destination ?? .albums
                    isSearching = false
                    query = ""
                },
                onRestore: {
                    withAnimation(BottomBarStyle.morph) {
                        isMinimised = false
                    }
                }
            )
            // Matches `RootView`, greedy frame and all — see the note there for
            // why that frame is what makes `ignoresSafeArea` do anything. Kept
            // in step so the canvas does not quietly demonstrate a placement
            // the app does not use.
            .padding(.bottom, BottomBarMetrics.screenBottomInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }
}

#Preview {
    FloatingTabBarPreview()
}

/// Press feedback for a tab, which `.buttonStyle(.plain)` gives none of.
///
/// The bar's own animations all begin on touch-up: the wash cannot start
/// sliding until it knows where it is going. That left the whole touch-down
/// half of a tap unanswered, and a control that does nothing while the finger
/// is on it reads as slow no matter how quick everything after it is.
///
/// Deliberately only a scale. A tint change would fight
/// `tint(isCurrent:)`, which is already animating on its own curve, and a
/// highlight behind the glyph would collide with the selection wash arriving
/// in the same place a moment later.
///
/// With Reduce Motion on it is deliberately only an *opacity*, for the mirror
/// of that reason: `BottomBarStyle.pressedScale` goes to 1 and
/// `pressedOpacity` to 0.45, so the tab answers the finger without changing
/// size. Both are applied unconditionally and it is the constants that branch —
/// in the mode that is not reduced, one of the two is the identity and costs
/// nothing, which keeps the whole decision in `BottomBarStyle` rather than half
/// here.
///
/// A dim is not the tint change ruled out above: that one changes the
/// *foreground* of the glyph and the label, on `control`'s own curve, and would
/// have collided with a colour already in flight. This is the whole slot, on
/// `press`, and it does not touch the tint at all.
private struct TabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? BottomBarStyle.pressedScale : 1)
            .opacity(configuration.isPressed ? BottomBarStyle.pressedOpacity : 1)
            .animation(BottomBarStyle.press, value: configuration.isPressed)
    }
}
