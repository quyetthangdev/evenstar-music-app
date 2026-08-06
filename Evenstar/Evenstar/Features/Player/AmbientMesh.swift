import SwiftUI

/// The expanded player's background: the cover's colours as a mesh that drifts.
///
/// Replaces a still, blurred copy of the cover. The blur was already the
/// cover's colours in the cover's layout, and it read as a photograph someone
/// had knocked out of focus. A mesh made from the same nine cells reads as
/// light in the room instead — the same information, no longer pretending to be
/// a picture.
///
/// **The motion has to be slow enough to be missed.** This sits directly behind
/// the title and the transport controls, and anything the eye can track there is
/// competing with them. The frequencies below give periods of roughly twenty to
/// thirty seconds: look away and back and it has changed, watch it and almost
/// nothing happens.
struct AmbientMesh: View {
    /// Nine colours, top row first, from `ArtworkStore.meshPalette(for:)`.
    let colours: [Color]

    /// How far an edge point slides along its edge, and the centre in each
    /// direction. Large enough to see over time, small enough that no cell ever
    /// collapses — a mesh whose points cross produces a visible pinch.
    private static let edgeSwing: Float = 0.16
    private static let centreSwing: Float = 0.12

    /// 30, not the display's rate.
    ///
    /// The motion is slower than anything 60fps buys, so the extra frames are
    /// spent for nothing — and this is a full-screen redraw that runs for as
    /// long as the player is open. Halving it halves that cost with no visible
    /// difference at these frequencies.
    private static let frameInterval: Double = 1.0 / 30.0

    var body: some View {
        TimelineView(.animation(minimumInterval: Self.frameInterval)) { context in
            MeshGradient(
                width: 3,
                height: 3,
                points: Self.points(at: context.date.timeIntervalSinceReferenceDate),
                colors: colours
            )
        }
    }

    /// The nine control points at a moment in time.
    ///
    /// **The four corners never move.** A `MeshGradient` fills exactly the hull
    /// of its points, so a corner that drifts inward leaves an unpainted wedge
    /// at the edge of the screen. Edge midpoints slide only along their own
    /// edge, for the same reason. Only the centre is free in both directions.
    ///
    /// The five speeds are deliberately not multiples of one another. Related
    /// speeds resynchronise on a short cycle and the whole field starts to
    /// pulse in step, which is exactly the kind of regularity the eye locks
    /// onto.
    private static func points(at time: TimeInterval) -> [SIMD2<Float>] {
        func drift(_ centre: Float, _ swing: Float, speed: Double, phase: Double) -> Float {
            centre + swing * Float(sin(time * speed + phase))
        }
        return [
            SIMD2(0, 0),
            SIMD2(drift(0.5, Self.edgeSwing, speed: 0.31, phase: 0.0), 0),
            SIMD2(1, 0),

            SIMD2(0, drift(0.5, Self.edgeSwing, speed: 0.23, phase: 1.3)),
            SIMD2(
                drift(0.5, Self.centreSwing, speed: 0.19, phase: 0.7),
                drift(0.5, Self.centreSwing, speed: 0.27, phase: 2.1)
            ),
            SIMD2(1, drift(0.5, Self.edgeSwing, speed: 0.17, phase: 3.4)),

            SIMD2(0, 1),
            SIMD2(drift(0.5, Self.edgeSwing, speed: 0.13, phase: 4.6), 1),
            SIMD2(1, 1)
        ]
    }
}

#Preview {
    AmbientMesh(colours: [
        .init(red: 0.20, green: 0.35, blue: 0.75),
        .init(red: 0.45, green: 0.30, blue: 0.80),
        .init(red: 0.75, green: 0.35, blue: 0.55),
        .init(red: 0.15, green: 0.45, blue: 0.55),
        .init(red: 0.35, green: 0.55, blue: 0.45),
        .init(red: 0.80, green: 0.45, blue: 0.30),
        .init(red: 0.10, green: 0.30, blue: 0.25),
        .init(red: 0.25, green: 0.45, blue: 0.20),
        .init(red: 0.55, green: 0.50, blue: 0.20)
    ])
    .ignoresSafeArea()
}
