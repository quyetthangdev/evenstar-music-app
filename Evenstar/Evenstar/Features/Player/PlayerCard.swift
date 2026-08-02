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

    /// Read by `LibraryView`'s safe-area inset as well, so the list scrolls
    /// clear of the collapsed card. Do not duplicate this as a literal.
    static let collapsedHeight: CGFloat = 64

    private static let collapsedArtwork: CGFloat = 40
    private static let expandedArtwork: CGFloat = 280
    private static let expandedCornerRadius: CGFloat = 38
    /// Gap between the top safe area and the expanded artwork.
    private static let expandedArtworkTopGap: CGFloat = 72

    /// Where the card rests: 0 collapsed, 1 expanded. Changed only on release.
    @State private var settled: Double = 0
    /// How far the in-flight drag has moved it. Zeroed when the drag settles.
    @State private var dragDelta: Double = 0

    @State private var artwork: UIImage?
    @State private var tint: Color?

    private var progress: Double { min(max(settled + dragDelta, 0), 1) }

    /// Spring shared by drag release and `collapse()`, including the fade
    /// that now accompanies `collapse()` when the queue ends (F7) so the
    /// card disappears on the same curve it moves on. `expand()` keeps its
    /// own slightly snappier spring.
    private static let settleSpring = Animation.spring(response: 0.42, dampingFraction: 0.86)

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
        }
        .opacity(playback.currentTrack == nil ? 0 : 1)
        .animation(Self.settleSpring, value: playback.currentTrack == nil)
        .allowsHitTesting(playback.currentTrack != nil)
        .task(id: playback.currentTrack?.id) { await loadArtwork() }
        .onChange(of: playback.currentTrack?.id) { _, id in
            if id == nil { collapse() }
        }
    }

    /// - Parameter size: the *safe-area* size of the reader (not the full
    ///   screen — see the note on `outer` above).
    /// - Parameter insets: the reader's real safe-area insets.
    private func card(size: CGSize, insets: EdgeInsets) -> some View {
        let fullHeight = size.height + insets.top + insets.bottom
        let travel = max(fullHeight - Self.collapsedHeight, 1)
        let height = Self.collapsedHeight + travel * progress

        return ZStack(alignment: .topLeading) {
            background
            miniChrome(width: size.width)
            expandedContent(size: size, topInset: insets.top)
            artworkView(size: size, topInset: insets.top)
            grabber(topInset: insets.top)
        }
        .frame(width: size.width, height: height, alignment: .top)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: Self.expandedCornerRadius * progress,
                topTrailingRadius: Self.expandedCornerRadius * progress
            )
        )
        // Hit-testing must bind to this card-sized view, not to the
        // full-screen frame below it — otherwise the collapsed card claims
        // the whole display or nothing behind it is reachable. See F1.
        .contentShape(Rectangle())
        .gesture(drag(travel: travel))
        .onTapGesture { if progress < 0.5 { expand() } }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // At progress 0 this holds the card's bottom at the real safe-area
        // inset, matching where LibraryView's spacer stops the list; at
        // progress 1 it goes to 0 so the expanded card reaches the physical
        // bottom edge. See F3.
        .padding(.bottom, insets.bottom * (1 - progress))
    }

    // MARK: - Pieces

    private var background: some View {
        ZStack {
            // Opaque base: the two layers above cross-fade via opacity, which
            // composites rather than sums, so without this the card is
            // translucent through the whole middle of the morph. See F4.
            Color(.systemGroupedBackground)
            Rectangle()
                .fill(.thinMaterial)
                .opacity(1 - progress)
            LinearGradient(
                colors: [tint ?? Color(.systemGroupedBackground), Color(.systemGroupedBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(progress)
        }
    }

    /// Hints that the expanded card can be dragged away, the way the
    /// `.sheet` this replaced showed `.presentationDragIndicator(.visible)`.
    /// Fades in with `progress` so it is invisible while collapsed. See F8.
    private func grabber(topInset: CGFloat) -> some View {
        Capsule()
            .fill(Color.secondary)
            .opacity(0.4)
            .frame(width: 36, height: 5)
            .padding(.top, topInset + 8)
            .frame(maxWidth: .infinity, alignment: .top)
            .opacity(progress)
            .allowsHitTesting(false)
    }

    private func miniChrome(width: CGFloat) -> some View {
        MiniPlayerChrome(playback: playback)
            .padding(.leading, Self.collapsedArtwork + 24)
            .padding(.trailing, 12)
            .frame(width: width, height: Self.collapsedHeight)
            .opacity(max(0, 1 - progress * 3))
            .allowsHitTesting(progress < 0.1)
    }

    private func expandedContent(size: CGSize, topInset: CGFloat) -> some View {
        NowPlayingContent(playback: playback)
            .padding(.horizontal, 24)
            .frame(width: size.width)
            .offset(y: topInset + Self.expandedArtworkTopGap + Self.expandedArtwork + 40)
            .opacity(max(0, (progress - 0.5) * 2))
            .allowsHitTesting(progress > 0.9)
    }

    private func artworkView(size: CGSize, topInset: CGFloat) -> some View {
        let side = Self.collapsedArtwork
            + (Self.expandedArtwork - Self.collapsedArtwork) * progress
        let collapsedCentre = CGPoint(
            x: 12 + Self.collapsedArtwork / 2,
            y: Self.collapsedHeight / 2
        )
        let expandedCentre = CGPoint(
            x: size.width / 2,
            y: topInset + Self.expandedArtworkTopGap + Self.expandedArtwork / 2
        )
        let centre = CGPoint(
            x: collapsedCentre.x + (expandedCentre.x - collapsedCentre.x) * progress,
            y: collapsedCentre.y + (expandedCentre.y - collapsedCentre.y) * progress
        )

        return Group {
            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(Color(.tertiarySystemFill))
                    // `.font(size:)` isn't animatable, so during the expand
                    // spring the glyph would otherwise jump to its final size
                    // immediately while the surrounding frame is still
                    // interpolating 40 -> 280. Render it at a fixed base size
                    // and use `.scaleEffect`, which does animate, to track
                    // `side` continuously. Ratio matches ArtworkThumbnail's
                    // placeholder (size * 0.5). See F6.
                    Image(systemName: "music.note")
                        .font(.system(size: Self.expandedArtwork * 0.5))
                        .foregroundStyle(.secondary)
                        .scaleEffect(side / Self.expandedArtwork)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.12))
        .shadow(radius: 10 * progress, y: 4 * progress)
        .position(centre)
    }

    // MARK: - Gesture

    private func drag(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                // No rubber-band past either end: `progress` (settled +
                // dragDelta, clamped) is rigid at 0 and 1. An earlier version
                // of this method shaved the excess off `delta` here to fake
                // give, but that landed after the clamp already applied, so
                // it had no visible effect at any input — the code and its
                // comment disagreed. See F5; overshoot geometry was judged
                // more risk than the interaction is worth for this pass.
                dragDelta = -value.translation.height / travel
            }
            .onEnded { value in
                // Decide on the predicted end, not the current offset, so a
                // quick flick settles the card even though the finger barely
                // moved. Comparing raw distance is what makes hand-rolled
                // sheets feel heavy.
                let predicted = settled - value.predictedEndTranslation.height / travel
                withAnimation(Self.settleSpring) {
                    settled = predicted > 0.5 ? 1 : 0
                    dragDelta = 0
                }
            }
    }

    private func expand() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            settled = 1
            dragDelta = 0
        }
    }

    private func collapse() {
        withAnimation(Self.settleSpring) {
            settled = 0
            dragDelta = 0
        }
    }

    private func loadArtwork() async {
        let path = playback.currentTrack?.artworkRelativePath
        async let image = ArtworkStore.image(
            for: path,
            maxPixel: Self.expandedArtwork * UIScreen.main.scale
        )
        async let colour = ArtworkStore.dominantColor(for: path)
        let (loadedImage, loadedColour) = await (image, colour)

        guard playback.currentTrack?.artworkRelativePath == path else { return }
        artwork = loadedImage
        tint = loadedColour
    }
}
