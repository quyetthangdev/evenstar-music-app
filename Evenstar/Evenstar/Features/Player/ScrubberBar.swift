import SwiftUI

/// The playback scrubber: a capsule track with the played portion filled and
/// no thumb, which swells while a finger is on it.
///
/// SwiftUI's `Slider` always draws a circular knob, which is the single most
/// obvious difference from Apple Music on this screen — hence a custom view.
/// Owning the gesture also lets the priority against `PlayerCard`'s drag be
/// declared with `.highPriorityGesture` rather than left to SwiftUI's implicit
/// child-over-parent rule.
struct ScrubberBar: View {
    let position: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    /// Where the finger currently is. Nil when nobody is dragging, in which
    /// case the bar follows `position` from the player.
    @State private var draggingPosition: TimeInterval?

    private static let restingHeight: CGFloat = 7
    private static let activeHeight: CGFloat = 12
    /// The bar is thin; the touch target is not. This is the full height the
    /// row reserves, so the swell does not shift anything below it.
    private static let touchHeight: CGFloat = 28

    private var displayedPosition: TimeInterval { draggingPosition ?? position }
    private var isDragging: Bool { draggingPosition != nil }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.25))
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: geo.size.width * Self.fillFraction(
                            position: displayedPosition,
                            duration: duration
                        ))
                }
                .frame(height: isDragging ? Self.activeHeight : Self.restingHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .highPriorityGesture(drag(width: geo.size.width))
                .animation(.easeOut(duration: 0.15), value: isDragging)
            }
            .frame(height: Self.touchHeight)

            labels
        }
    }

    private var labels: some View {
        HStack {
            Text(Self.formatTime(displayedPosition))
            Spacer()
            Text("-" + Self.formatTime(max(0, duration - displayedPosition)))
        }
        .font(.caption)
        .foregroundStyle(isDragging ? Color.primary : Color.secondary)
        .monospacedDigit()
        .animation(.easeOut(duration: 0.15), value: isDragging)
    }

    /// `minimumDistance: 0` so a tap seeks, as Apple Music does. Combined with
    /// `.highPriorityGesture` this means any touch starting on the bar belongs
    /// to the scrubber and never to the card behind it — which is the point.
    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                draggingPosition = Self.time(
                    forX: value.location.x, width: width, duration: duration
                )
            }
            .onEnded { value in
                // Seek once, on release. Seeking every frame would thrash
                // AVAudioPlayer.
                onSeek(Self.time(forX: value.location.x, width: width, duration: duration))
                draggingPosition = nil
            }
    }

    // MARK: - Arithmetic (pure, and unit-tested)

    /// How much of the track is filled, 0...1. Returns 0 for any duration or
    /// position that cannot produce a meaningful fraction.
    static func fillFraction(position: TimeInterval, duration: TimeInterval) -> Double {
        guard duration.isFinite, duration > 0, position.isFinite else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    /// The time a touch at `x` across a bar of `width` corresponds to, clamped
    /// to `0...duration`.
    static func time(forX x: CGFloat, width: CGFloat, duration: TimeInterval) -> TimeInterval {
        guard width > 0, duration.isFinite, duration > 0 else { return 0 }
        let fraction = min(max(Double(x / width), 0), 1)
        return fraction * duration
    }

    static func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let total = Int(time.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
