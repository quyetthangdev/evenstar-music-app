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

    @State private var shuffleTaps = 0
    @State private var repeatTaps = 0

    /// Matches `SongRow`'s thumbnail, so a queue row and a library row are the
    /// same size object.
    private static let rowArtwork: CGFloat = 44

    /// Read by `PlayerCard`, which flies the real artwork down into this slot —
    /// so the two must agree on its size.
    ///
    /// **54, where every other artwork thumbnail in this app is 44** —
    /// `SongRow`, `QueueRow`, `JamendoResultRow`. Chosen deliberately for
    /// prominence at the top of the panel. Recorded here so a later reader
    /// finds a decision rather than an inconsistency.
    static let headerArtwork: CGFloat = 54

    /// How far the list starts below its resting place.
    private static let riseDistance: CGFloat = 50

    /// Pill geometry, moved here with the pills.
    ///
    /// **36pt tall, and that is not negotiable.** `PlayerCard.contentBudget`
    /// allows about 20pt of slack across the whole stack and its doc comment
    /// records the same overrun shipping twice. The pills grow sideways; they
    /// never grow down.
    private static let pillHeight: CGFloat = 36
    private static let pillHorizontalPadding: CGFloat = 22

    /// Half of what a 36pt pill is short of HIG's 44pt hit region. Spent on the
    /// *hit shape* rather than the frame, by the padding → `contentShape` →
    /// negative-padding trick `NowPlayingContent.jamendoCredit` uses for the
    /// identical collision.
    private static let pillHitPad: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // No offset on the header. It is where the artwork is flying to,
            // and a destination that moves while something is travelling toward
            // it makes the two chase each other — the motion version of the
            // 12pt landing mismatch this file has already produced once.
            header
            pillRow
                .offset(y: Self.riseDistance * (1 - factor))
                .opacity(factor)
            upcomingList
                .offset(y: Self.riseDistance * (1 - factor))
                .opacity(factor)
        }
    }

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
            Spacer()
        }
    }

    private var pillRow: some View {
        HStack(spacing: 12) {
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
        }
    }

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
            // `.active` edit mode is what puts the drag handles on screen and
            // makes the rows draggable at all: a `List` outside edit mode
            // ignores `.onMove` entirely. There is no `.onDelete` here, so the
            // red delete affordance edit mode would otherwise add never
            // appears — removing a track from the queue is out of scope, and
            // deliberately so: it would have to touch `unshuffledQueue` too,
            // which is exactly what this design avoids.
            List {
                ForEach(Array(upcoming.enumerated()), id: \.element.id) { offset, track in
                    QueueRow(track: track, size: Self.rowArtwork)
                        // Clear, so the card's own gradient and the artwork
                        // behind it show through the queue.
                        //
                        // `.scrollContentBackground(.hidden)` below already
                        // hides the `List`'s own backing, and was not enough:
                        // each *row* carries a separate system background, and
                        // that is what made the panel read as a solid slab
                        // laid over the player rather than as part of it.
                        //
                        // It also removes a measurement problem. Two attempts
                        // to judge whether the artwork's dissolve mask animates
                        // smoothly were defeated by this exact background —
                        // the panel's opaque rows sat over the same pixels the
                        // mask was being judged on, so neither could be told
                        // apart from the other by eye.
                        .listRowBackground(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { playback.playUpcoming(at: offset) }
                        // `TouchDownButton`'s doc comment names this exact
                        // failure two lines up the file from here: "VoiceOver's
                        // activation never produces a touch sequence, so the
                        // gesture below cannot serve it." A bare
                        // `.onTapGesture` is that gesture with nothing else
                        // added — this is the only way to jump to a specific
                        // upcoming track, and without an accessibility action
                        // it would be inert to anyone using VoiceOver.
                        //
                        // `.accessibilityElement(children: .ignore)` plus an
                        // explicit label, not `.combine`: `QueueRow`'s
                        // `ArtworkThumbnail` is a bare `Image` with no label of
                        // its own, so combining children would read as
                        // "image, <title>, <artist>" — noise in front of the
                        // two things that matter. Ignoring the children and
                        // stating the label directly is also what makes this
                        // one stop for VoiceOver rather than three, which
                        // `.isButton` alone would not fix: without it the row
                        // would still swipe as separate, uninteractive text
                        // and image elements.
                        // `Text(verbatim:)`, not a bare string-interpolation
                        // literal: that overload resolves to
                        // `LocalizedStringKey` and Xcode's build-time String
                        // Catalog extraction then treats the interpolated
                        // "%@, %@" as a *new* translatable string — for two
                        // fields of track metadata, not a phrase anyone
                        // should be asked to translate. Localization is its
                        // own separate work item; this keeps this label out
                        // of it, matching what `verbatim` is for.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: "\(track.title), \(track.artistName)"))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { playback.playUpcoming(at: offset) }
                }
                .onMove { source, destination in
                    playback.moveUpcoming(from: source, to: destination)
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
        }
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
                .frame(height: Self.pillHeight)
                .padding(.horizontal, Self.pillHorizontalPadding)
                .background(
                    // Literal white, not the accent: this pill sits on the
                    // now-playing card, over artwork the darkening overlay
                    // already keeps dark, so white is legible there and only
                    // there — it is not a statement about what the accent
                    // colour should be. Matches the glyph above, which already
                    // goes `Color.white` on the same condition.
                    isOn && enabled ? AnyShapeStyle(Color.white)
                                    : AnyShapeStyle(Color(.tertiarySystemFill)),
                    in: Capsule()
                )
                .padding(.vertical, Self.pillHitPad)
                .contentShape(Rectangle())
                .padding(.vertical, -Self.pillHitPad)
        }
        .buttonStyle(.transportToggle(trigger: trigger))
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
private struct QueueRow: View {
    let track: any Playable
    let size: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            ArtworkThumbnail(relativePath: track.artworkRelativePath, size: size)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(track.artistName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }
}
