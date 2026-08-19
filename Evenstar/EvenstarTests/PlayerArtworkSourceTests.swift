import XCTest
@testable import Evenstar

/// Which of the three things the expanded player's artwork slot draws.
///
/// Written from a bug report, and each case below is one line of it: covers are
/// fine; a track with no cover animates wrongly; the first cover opened after
/// one of those is wrong too; the next cover is fine again. That pattern is the
/// signature of state arriving a beat late, and the rule under test is what
/// stops the *structure* of the slot depending on it.
///
/// `hasArtwork` is read from the track — synchronously, on the first frame.
/// `loaded` is `@State` written by a `.task`, so it always describes the
/// previous track until the load finishes. Everything here is about not letting
/// the second one decide anything.
/// `@MainActor` like every other test class here. The helpers under test are
/// statics on a `View`, which `InferIsolatedConformances` makes main-actor
/// isolated, so a nonisolated test cannot call them under Swift 6. Nothing
/// about how these run changes — `XCTestCase` already runs them on the main
/// thread; the annotation only writes that down.
@MainActor
final class PlayerArtworkSourceTests: XCTestCase {

    private func source(hasArtwork: Bool, loaded: Bool) -> PlayerCard.ArtworkSource {
        PlayerCard.source(hasArtwork: hasArtwork, loaded: loaded)
    }

    // MARK: - The reported cases

    /// **"Bài không có bìa, animation sai."**
    ///
    /// The state still holds the *previous* track's cover when this track opens.
    /// Branching on it drew that cover — a picture belonging to a different
    /// song — and then snapped to the placeholder part-way through the expand.
    /// The track has no cover, so nothing but the placeholder is ever right,
    /// from the first frame.
    func testATrackWithNoCoverShowsThePlaceholderEvenWhileStaleArtworkIsStillLoaded() {
        XCTAssertEqual(source(hasArtwork: false, loaded: true), .placeholder)
    }

    /// **"Sau khi mở bài không bìa, mở lại bài có bìa lần đầu sai."**
    ///
    /// The previous track cleared the state, so this one opens with `loaded`
    /// false. The old rule showed the "no artwork" glyph and then snapped to the
    /// image. A track that *has* a cover must never draw that glyph.
    func testATrackWithACoverNeverShowsThePlaceholderWhileItsCoverIsStillDecoding() {
        XCTAssertEqual(source(hasArtwork: true, loaded: false), .pending)
        XCTAssertNotEqual(source(hasArtwork: true, loaded: false), .placeholder)
    }

    /// **"Bài có bìa thì oke."** The case that always worked, and must keep
    /// working: nothing structural changes when one cover replaces another.
    func testATrackWithACoverAndACoverInHandDrawsIt() {
        XCTAssertEqual(source(hasArtwork: true, loaded: true), .image)
    }

    /// The remaining corner: no cover, and no stale image either — the first
    /// track played after launch.
    func testNoCoverAndNothingLoadedIsStillThePlaceholder() {
        XCTAssertEqual(source(hasArtwork: false, loaded: false), .placeholder)
    }

    // MARK: - The rule itself

    /// The property the fix rests on, stated directly: what the slot draws is
    /// decided by the model alone. `loaded` may pick *which* picture, never
    /// whether there is one.
    func testTheLoadedFlagNeverChangesWhetherThereIsACover() {
        for loaded in [true, false] {
            XCTAssertEqual(
                source(hasArtwork: false, loaded: loaded), .placeholder,
                "a coverless track must not depend on what happens to be decoded"
            )
            XCTAssertNotEqual(
                source(hasArtwork: true, loaded: loaded), .placeholder,
                "a track with a cover must never fall back to the glyph"
            )
        }
    }

    /// `.pending` and `.placeholder` must stay distinct. Collapsing them —
    /// which is what "just use the placeholder until it loads" would do — is the
    /// second half of the same bug, and it would still compile and still look
    /// fine for any cover already in the cache.
    func testPendingIsNotTheSameThingAsHavingNoCover() {
        XCTAssertNotEqual(PlayerCard.ArtworkSource.pending, .placeholder)
    }

    // MARK: - The background

    // **Two tests were deleted here, and this note is why.**
    //
    // They pinned `PlayerCard.usesMesh(hasArtwork:)` — that the expanded
    // background used the cover's drifting colour mesh for a track with a cover
    // and a flat gradient otherwise, and that this agreed with the artwork
    // slot. The rule was real and the tests were right.
    //
    // The mesh is gone. Two Instruments recordings on the device attributed
    // most of the app's stalling to it — 189 ms of hitch per second of use with
    // it, 35 ms without — so the background is now one flat gradient in every
    // case, and there is no longer a choice to make or to test. What survives
    // is the artwork slot's own rule, above and below.

    // MARK: - Which cover, and whether there is one in time

    private func cover(_ has: Bool, loaded: String?, cached: String?) -> String? {
        PlayerCard.preferredCover(
            hasArtwork: has, loadedForThisTrack: loaded, cachedForThisPath: cached
        )
    }

    /// **The half the first fix missed.** Opening a cover track straight after a
    /// coverless one, the frame grew correctly but the picture appeared
    /// part-way instead of growing with it — because `artwork` was nil at that
    /// moment and the decode lands well into a 400ms spring. The row the user
    /// just tapped has already decoded the same picture at its own size, so
    /// there is something to draw from the first frame.
    func testACoverDecodedAtAnotherSizeIsUsedWhenTheFullOneIsNotReady() {
        XCTAssertEqual(cover(true, loaded: nil, cached: "row-thumbnail"), "row-thumbnail")
    }

    /// The full-size decode wins once it belongs to this track.
    func testTheFullDecodeWinsOnceItIsForThisTrack() {
        XCTAssertEqual(cover(true, loaded: "full", cached: "row-thumbnail"), "full")
    }

    /// A *stale* full decode is passed in as nil by the caller, precisely so it
    /// cannot outrank a correct smaller one. This pins that a correct small
    /// cover beats nothing at all.
    func testACorrectSmallCoverBeatsHavingNothing() {
        XCTAssertEqual(cover(true, loaded: nil, cached: "row-thumbnail"), "row-thumbnail")
        XCTAssertNil(cover(true, loaded: nil, cached: nil))
    }

    /// A coverless track draws no cover, whatever happens to be in the cache —
    /// including a decode left by the track before it.
    func testACoverlessTrackDrawsNothingEvenWithSomethingCached() {
        XCTAssertNil(cover(false, loaded: "previous", cached: "previous"))
    }
}
