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
}
