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

    var body: some View {
        GeometryReader { geo in
            let travel = max(geo.size.height - Self.collapsedHeight, 1)
            let height = Self.collapsedHeight + travel * progress

            ZStack(alignment: .topLeading) {
                background
                miniChrome(width: geo.size.width)
                expandedContent(size: geo.size, topInset: geo.safeAreaInsets.top)
                artworkView(size: geo.size, topInset: geo.safeAreaInsets.top)
            }
            .frame(width: geo.size.width, height: height, alignment: .top)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: Self.expandedCornerRadius * progress,
                    topTrailingRadius: Self.expandedCornerRadius * progress
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(drag(travel: travel))
            .onTapGesture { if progress < 0.5 { expand() } }
        }
        .ignoresSafeArea()
        .opacity(playback.currentTrack == nil ? 0 : 1)
        .allowsHitTesting(playback.currentTrack != nil)
        .task(id: playback.currentTrack?.id) { await loadArtwork() }
        .onChange(of: playback.currentTrack?.id) { _, id in
            if id == nil { collapse() }
        }
    }

    // MARK: - Pieces

    private var background: some View {
        ZStack {
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
                    Image(systemName: "music.note")
                        .font(.system(size: side * 0.4))
                        .foregroundStyle(.secondary)
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
                var delta = -value.translation.height / travel
                let raw = settled + delta
                // Past the top, damp the excess so the card feels tethered
                // rather than rigid.
                if raw > 1 { delta -= (raw - 1) * 0.8 }
                dragDelta = delta
            }
            .onEnded { value in
                // Decide on the predicted end, not the current offset, so a
                // quick flick settles the card even though the finger barely
                // moved. Comparing raw distance is what makes hand-rolled
                // sheets feel heavy.
                let predicted = settled - value.predictedEndTranslation.height / travel
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
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
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
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
