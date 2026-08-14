import SwiftUI

/// What plays next, with the controls that shape it.
///
/// Occupies the region the artwork otherwise fills — see `PlayerCard`. That is
/// the whole reason this exists as a panel rather than a sheet: the spec's
/// point is that Apple Music *replaces* the artwork rather than stacking a
/// queue below it, and stacking is what this screen has no room for.
struct QueuePanel: View {
    let playback: PlaybackService

    /// 0 closed, 1 open — the same animated value `PlayerCard` interpolates the
    /// artwork's shrink on.
    ///
    /// Passed in rather than derived from a `Bool` here, and that is the point:
    /// the list's rise and the cover's shrink are one gesture, and reading the
    /// same number is what makes them incapable of disagreeing. A local
    /// animation would be a second clock.
    let factor: Double
    /// Ba khối bên dưới **hiện** ra tới đâu, 0…1.
    let reveal: Double
    /// Ba khối bên dưới đã **về chỗ** tới đâu, 0…1.
    ///
    /// Hai giá trị chứ không một: Apple cho khối chữ đọc được trong ~0.13s rồi
    /// mới thong thả trượt về chỗ trong ~0.27s. Xem
    /// `BottomBarStyle.queueContentSlide`.
    let slide: Double
    /// Màu cho những mặt phẳng nhỏ trong panel — nền viên thuốc, nền hàng lúc
    /// nhấc, ô placeholder của hàng.
    ///
    /// **Đã là màu *mặt phẳng*, không phải màu trội thô** — `PlayerCard` nâng
    /// độ sáng của nó lên trên nền một bậc trước khi truyền xuống, xem
    /// `PlayerCard.queueSurface`. Nên ở đây không pha loãng nó về gần màu nền
    /// nữa; làm thế là xoá đúng cái bậc ấy đi.
    ///
    /// Không còn `nil`: bài không có bìa cũng nhận một màu xám trung tính theo
    /// cùng quy tắc, vì nền dưới panel giờ luôn tối bất kể chế độ sáng hay tối
    /// của hệ thống, và một `tertiarySystemFill` phân giải theo hệ thống thì
    /// không biết điều đó.
    let tint: Color
    /// Bật suốt một cú kéo trong danh sách. `PlayerCard` đọc nó để tắt cử chỉ
    /// vuốt-đóng của mình: một cú kéo hàng xuống dưới cũng là một cú vuốt
    /// xuống, và cả hai cùng nhận thì thẻ đóng lại giữa lúc đang sắp bài.
    @Binding var isReordering: Bool

    @State private var shuffleTaps = 0
    @State private var repeatTaps = 0
    @State private var autoplayTaps = 0
    /// Bề ngang panel, đo tại chỗ. Ba viên chia nhau một phần của nó — xem
    /// `pillRow` — nên chúng cần biết con số ấy; không có nguồn nào khác vì
    /// panel nhận bề ngang từ `PlayerCard` qua layout, không qua tham số.
    @State private var rowWidth: CGFloat = 0

    private var pillWidth: CGFloat {
        let usable = rowWidth * Self.pillRowShare - Self.pillSpacing * 2
        return max(usable / 3, Self.pillHeight)
    }

    /// Matches `SongRow`'s thumbnail, so a queue row and a library row are the
    /// same size object.
    private static let rowArtwork: CGFloat = 44

    /// Khoảng hở giữa hai hàng. Bằng đúng tổng lề dọc mà ô của collection view
    /// trước đây đặt (2 trên + 2 dưới), nên mật độ danh sách không đổi.
    private static let rowSpacing: CGFloat = 4

    /// Read by `PlayerCard`, which flies the real artwork down into this slot —
    /// so the two must agree on its size.
    ///
    /// **60, where every other artwork thumbnail in this app is 44** —
    /// `SongRow`, `QueueRow`, `JamendoResultRow`. Chosen deliberately for
    /// prominence at the top of the panel. Recorded here so a later reader
    /// finds a decision rather than an inconsistency.
    ///
    /// 54 trước đó đọc ra hơi nhỏ so với Apple Music: ở đó tấm bìa sau khi thu
    /// vẫn còn ra dáng một tấm bìa, không thành một cái icon.
    static let headerArtwork: CGFloat = 60

    /// Hai viên thuốc và danh sách trượt lên bao xa.
    ///
    /// 55 điểm. Đo bằng tâm khối chữ "There's no music in the queue" qua từng
    /// khung: y 373.5 → 318.5.
    ///
    /// Con số 32 trước đó tôi đọc bằng mắt trên một tấm ghép khung đã thu nhỏ,
    /// và nó thiếu gần một nửa.
    private static let riseDistance: CGFloat = 55

    /// Pill geometry, moved here with the pills.
    ///
    /// **36pt tall, and that is not negotiable.** `PlayerCard.contentBudget`
    /// allows about 20pt of slack across the whole stack and its doc comment
    /// records the same overrun shipping twice. The pills grow sideways; they
    /// never grow down.
    private static let pillHeight: CGFloat = 36

    /// Half of what a 36pt pill is short of HIG's 44pt hit region. Spent on the
    /// *hit shape* rather than the frame, by the padding → `contentShape` →
    /// negative-padding trick `NowPlayingContent.jamendoCredit` uses for the
    /// identical collision.
    private static let pillHitPad: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Không offset và không opacity ở **cả khối** header: đây là chỗ
            // tấm bìa đang bay tới, và một cái đích tự dịch chuyển thì hai bên
            // đuổi nhau — bản chuyển động của cú lệch 12pt mà file này đã tạo
            // ra một lần rồi.
            //
            // Cú hiện nằm ở riêng khối chữ bên trong, xem `header`.
            header
                .background {
                    // Đo bề ngang hàng một lần, ở khối đầu tiên trải hết chiều
                    // ngang. `GeometryReader` đặt ở `background` nên nó không
                    // đề xuất kích thước nào cho ai — nó chỉ đọc.
                    GeometryReader { geo in
                        Color.clear.onAppear { rowWidth = geo.size.width }
                            .onChange(of: geo.size.width) { _, new in rowWidth = new }
                    }
                }
            pillRow
                .offset(y: Self.riseDistance * (1 - slide))
                .opacity(reveal)
            upcomingList
                .offset(y: Self.riseDistance * (1 - slide))
                .opacity(reveal)
        }
    }

    /// Khối chữ header trượt lên bao xa: 8 điểm, đo từ Apple Music (y 124.5 →
    /// 117).
    ///
    /// Ngắn hơn 32 của hai khối kia, và ngắn hơn có chủ ý ở bản gốc: chữ header
    /// nằm cao nhất, gần chỗ tấm bìa vừa đáp xuống, nên một quãng dài ở đó đọc
    /// ra như nó rơi từ trên tấm bìa xuống.
    private static let headerTextRise: CGFloat = 8

    /// The artwork and title, one line tall.
    ///
    /// `NowPlayingContent` hides its own title block while this is on screen —
    /// see Task 3 — so these two strings appear once, not twice.
    private var header: some View {
        HStack(spacing: 12) {
            // Invisible, and that is the whole job. `PlayerCard` shrinks the
            // real artwork down onto exactly this rect, so drawing a second
            // copy here would double it for the length of the animation and
            // leave two thumbnails stacked at rest. What this still does is
            // reserve the space, so the title and artist do not slide sideways
            // when the queue opens.
            ArtworkThumbnail(
                relativePath: playback.currentTrack?.artworkRelativePath,
                size: Self.headerArtwork
            )
            .opacity(0)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(playback.currentTrack?.title ?? "—")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(playback.currentTrack?.artistName ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // Trượt từ dưới lên **rất ngắn** — 8 điểm, đo được — trong khi
            // hai khối dưới đi 55. Chữ header nằm cao nhất, ngay chỗ tấm bìa
            // vừa đáp xuống, nên một quãng dài ở đó đọc ra như nó rơi từ trên
            // tấm bìa xuống chứ không như nó trồi lên.
            //
            // **Không có đường cong đàn hồi ở đâu trong panel này.** Các bước
            // trượt đo được giảm dần đều, không khung nào vượt qua đích.
            //
            // Đặt riêng ở khối chữ, không ở cả `header`: ô ảnh bìa vô hình bên
            // trái là chỗ tấm bìa thật đang bay tới, và một cái đích tự dịch
            // chuyển thì hai bên đuổi nhau.
            .offset(y: (1 - slide) * Self.headerTextRise)
            .opacity(reveal)
            Spacer()
        }
    }

    private var pillRow: some View {
        // **Ba viên chia đều ba phần tư chiều rộng hàng.**
        //
        // Đo ở Apple Music: ba viên bằng nhau, chạy từ lề trái tới khoảng 3/4
        // bề ngang, phần còn lại để trống. Không phải "co theo nội dung" — cả
        // ba đều rộng như nhau bất kể glyph bên trong, nên hàng đọc ra là một
        // bộ điều khiển chứ không phải ba cái nút tình cờ đứng cạnh nhau.
        HStack(spacing: Self.pillSpacing) {
            pill(
                systemImage: "shuffle",
                isOn: playback.isShuffled,
                label: String(localized: "Phát ngẫu nhiên",
                              bundle: AppLanguage.resolvedBundle,
                              locale: AppLanguage.resolvedLocale),
                trigger: shuffleTaps
            ) {
                shuffleTaps += 1
                playback.toggleShuffle()
            }

            pill(
                systemImage: playback.repeatMode == .one ? "repeat.1" : "repeat",
                isOn: playback.repeatMode != .off,
                label: String(localized: "Lặp lại",
                              bundle: AppLanguage.resolvedBundle,
                              locale: AppLanguage.resolvedLocale),
                trigger: repeatTaps
            ) {
                repeatTaps += 1
                playback.cycleRepeatMode()
            }

            pill(
                systemImage: "infinity",
                isOn: playback.isAutoplay,
                label: String(localized: "Tự phát tiếp",
                              bundle: AppLanguage.resolvedBundle,
                              locale: AppLanguage.resolvedLocale),
                trigger: autoplayTaps
            ) {
                autoplayTaps += 1
                playback.toggleAutoplay()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Ba viên chiếm bao nhiêu phần bề ngang. Xem `pillRow`.
    private static let pillRowShare: CGFloat = 0.75
    private static let pillSpacing: CGFloat = 10

    @ViewBuilder
    private var upcomingList: some View {
        let upcoming = playback.upcoming
        if upcoming.isEmpty {
            Text("Không còn bài nào tiếp theo")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            Spacer(minLength: 0)
        } else {
            Text("Tiếp theo")
                .font(.headline)
            // Cả cử chỉ lẫn chuyển động là của `ReorderableStack` — xem file ấy
            // về lý do cú giữ chạy bằng recogniser UIKit và vì sao thứ tự chỉ
            // đổi sau khi hàng đã bay tới nơi.
            let byID = Dictionary(uniqueKeysWithValues: upcoming.map { ($0.id, $0) })
            ReorderableStack(
                ids: upcoming.map(\.id),
                rowHeight: Self.rowArtwork + 20,
                rowSpacing: Self.rowSpacing,
                isReordering: $isReordering,
                onTap: { id in playUpcoming(id) },
                onMove: { source, destination in
                    playback.moveUpcoming(from: IndexSet(integer: source), to: destination)
                }
            ) { id, lifted, pressed in
                if let track = byID[id] {
                    QueueRowContent(track: track, size: Self.rowArtwork, tint: tint)
                        // Cùng một màu cho cả hai trạng thái, khác ở độ đục:
                        // nền lúc đè không phải hiệu ứng riêng, nó là cùng cái
                        // thẻ ấy mờ hơn.
                        //
                        // Đục hẳn khi nhấc, chứ không phải 0.55 như trước.
                        // `tint` giờ là màu *mặt phẳng* — đã sáng hơn nền một
                        // bậc, xem `PlayerCard.queueSurface` — nên pha loãng nó
                        // là kéo nó ngược về đúng màu nền và cái thẻ biến mất.
                        .reorderCard(
                            lifted: lifted,
                            pressed: pressed,
                            fill: tint,
                            pressedOpacity: 0.45
                        )
                }
            }
        }
    }

    /// Nhảy tới một bài trong hàng đợi, tra vị trí của nó ngay lúc chạm.
    ///
    /// Tra tại chỗ chứ không mang sẵn theo hàng: mang theo thì `ForEach` phải
    /// duyệt trên một mảng tuple, và đó chính là thứ làm `List` diff cú đổi chỗ
    /// thành xoá + chèn. Tra lúc chạm cũng đúng hơn về mặt dữ liệu — vị trí tại
    /// khoảnh khắc ngón tay chạm mới là vị trí người dùng nhắm tới.
    private func playUpcoming(_ id: UUID) {
        guard let offset = playback.upcoming.firstIndex(where: { $0.id == id }) else { return }
        playback.playUpcoming(at: offset)
    }

    /// One capsule control.
    ///
    /// The **fill** says on or off, not the glyph's colour: `shuffle` and
    /// `repeat` render identically armed or not, so a tint alone would leave
    /// shuffle with no readable state. `JamendoDiscoveryView`'s genre chips
    /// shipped that mistake with a 0.12-opacity fill against
    /// `tertiarySystemFill` and it was invisible.
    @ViewBuilder
    private func pill(
        systemImage: String,
        isOn: Bool,
        label: String,
        trigger: Int,
        action: @escaping () -> Void
    ) -> some View {
        let enabled = playback.currentTrack != nil
        TouchDownButton(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                // Three branches, and set *inside* the label on purpose:
                // `TransportButtonStyle` dims a disabled label from outside,
                // but the innermost `foregroundStyle` wins, so its dimming
                // would never land.
                // Dark when on, because the capsule behind it is filled white
                // on the same condition — a white glyph there would be white
                // on white, which is `ProminentActionButton`'s failure moved
                // to a new control. Inverting is also what Apple Music does:
                // the armed pill is a white capsule with a dark glyph.
                .foregroundStyle(
                    !enabled ? AnyShapeStyle(.tertiary)
                             : isOn ? AnyShapeStyle(Color.black)
                                    : AnyShapeStyle(.secondary)
                )
                .contentTransition(.symbolEffect(.replace))
                .frame(width: pillWidth, height: Self.pillHeight)
                .background(
                    // Literal white, not the accent: this pill sits on the
                    // now-playing card, over artwork the darkening overlay
                    // already keeps dark, so white is legible there and only
                    // there — it is not a statement about what the accent
                    // colour should be. Matches the glyph above, which already
                    // goes `Color.white` on the same condition.
                    // Trạng thái tắt bám theo màu của tấm bìa đang phát chứ
                    // không dùng màu xám hệ thống: viên thuốc nằm trên nền là
                    // chính tấm bìa ấy, và một mảng xám hệ thống ở đó đọc ra
                    // như một miếng vá dán lên. Pha rất loãng — nó phải là nền
                    // cho glyph, không phải một khối màu tranh chỗ.
                    // 0.45 chứ không phải 0.32: con số cũ là một phần của màu
                    // trội *chưa* kéo tối, tức đã sáng sẵn. Trên trường tối bây
                    // giờ, cùng con số ấy ra một mảng gần như không thấy.
                    isOn && enabled
                        ? AnyShapeStyle(Color.white)
                        : AnyShapeStyle(tint.opacity(0.45)),
                    in: Capsule()
                )
                .padding(.vertical, Self.pillHitPad)
                .contentShape(Rectangle())
                .padding(.vertical, -Self.pillHitPad)
        }
        .buttonStyle(.transportPill(trigger: trigger))
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn && enabled ? [.isButton, .isSelected] : .isButton)
    }
}

/// One row of the queue.
///
/// Not `SongRow`: that one is greedy and carries its own vertical padding sized
/// for a full-width library list, and these rows sit in a panel that is fighting
/// for every point of height. Same 44pt thumbnail so the two read as the same
/// kind of object.
/// `Equatable` có chủ đích, và nó cắt bớt việc thật.
///
/// Mỗi lần `QueuePanel` dựng lại — đổi bài, đổi repeat/shuffle, panel mở hay
/// đóng — mọi hàng chạy lại `body`, và `ArtworkThumbnail.init` tra cache ảnh
/// **đồng bộ** ngay trong đó. Với hai chục hàng thì đó là hai chục lượt tra
/// cache cho một thay đổi không đụng tới hàng nào.
///
/// Trong lúc kéo thả, `List` tự lo phần chuyển động của hàng đang bị nhấc,
/// nhưng mọi lượt dựng lại xen vào giữa đều là công tranh chỗ với nó.
///
/// So bằng `track.id` chứ không phải `===`: `any Playable` là một tồn tại
/// (existential) và hai lượt fetch của SwiftData có thể trả về hai hộp khác
/// nhau cho cùng một hàng.
/// Nội dung một hàng. Không có nền, không có cử chỉ.
///
/// Cả hai thứ đó do `ReorderableStack` lo: nền là `.reorderCard(...)` mà chỗ
/// gọi khoác lên, và cú chạm tới từ recogniser chung của cả danh sách. Hàng chỉ
/// còn là nội dung, nên nó không biết gì về việc mình đang được nhấc hay không.
struct QueueRowContent: View {

    let track: any Playable
    let size: CGFloat
    /// Truyền xuống chứ không tự đọc: hàng nằm trong panel, và panel là chỗ
    /// duy nhất biết mình đang đặt trên tấm bìa nào.
    let tint: Color?

    var body: some View {
        row
            .frame(height: rowHeight)
            // `children: .ignore` cộng nhãn tự viết, không phải `.combine`:
            // `ArtworkThumbnail` là một `Image` trần không nhãn, nên gộp con sẽ
            // đọc thành "image, <tên bài>, <nghệ sĩ>" — nhiễu đặt trước đúng
            // hai thứ đáng nghe. Trait `.isButton` và việc kích hoạt do ô của
            // collection view lo, nên ở đây chỉ còn nhãn.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(track.title), \(track.artistName)"))
    }

    /// Chiều cao cố định, và nó là một quyết định về hiệu năng chứ không phải
    /// về bố cục.
    ///
    /// Layout dạng list của collection view **tự đo** mỗi ô, và đo một ô chứa
    /// view SwiftUI nghĩa là chạy cả một lượt layout của SwiftUI cho từng hàng
    /// — nhiều lần trong một cú kéo, khi các ô liên tục được sắp lại. Cố định
    /// chiều cao biến phép đo ấy thành một hằng số.
    ///
    /// Con số dẫn xuất từ cỡ ảnh bìa chứ không gõ tay, để đổi `rowArtwork` thì
    /// chiều cao tự đi theo.
    private var rowHeight: CGFloat { size + 20 }

    private var row: some View {
        HStack(spacing: 12) {
            ArtworkThumbnail(relativePath: track.artworkRelativePath, size: size, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(track.artistName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)

            // Tay cầm để kéo. Không phải một nút — cả hàng đều nhấc được, và
            // hàng đợi không có chế độ sửa để bật nó lên. Nó là **nhãn**: thứ
            // duy nhất trên màn hình nói rằng những hàng này sắp lại được.
            //
            // Không có nó thì cách duy nhất để biết là nhấn giữ thử một bài và
            // hy vọng — mà nhấn giữ một bài trong danh sách phát thì đoán ra là
            // "phát" trước khi đoán ra là "kéo".
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }
}
