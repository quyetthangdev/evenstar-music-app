import XCTest
@testable import Evenstar

/// `explicitSelections` is what makes tapping a row open the full-screen
/// player. Its whole value is in what it does **not** count: if any automatic
/// path ever starts incrementing it, the player will fling itself open while
/// the phone is in a pocket, and nothing about that failure is visible in a
/// build or in the rest of the suite. These tests are that guard rail.
@MainActor
final class ExplicitSelectionTests: XCTestCase {

    private func makeStack() throws -> (PlaybackService, MockAudioPlayer, LibraryService) {
        let player = MockAudioPlayer()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(
            player: player,
            nowPlaying: MockNowPlayingPublisher(),
            library: library
        )
        return (service, player, library)
    }

    private func tracks(_ count: Int, library: LibraryService) throws -> [Track] {
        var out: [Track] = []
        for index in 0..<count {
            let track = Track(
                title: "Track \(index)",
                artistName: "Artist",
                albumTitle: "Album",
                durationSeconds: 100,
                relativePath: "Music/\(UUID().uuidString).mp3",
                format: "mp3"
            )
            try library.insert(track)
            out.append(track)
        }
        return out
    }

    func testStartsAtZero() throws {
        let (service, _, _) = try makeStack()
        XCTAssertEqual(service.explicitSelections, 0)
    }

    func testTappingARowCounts() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(3, library: library)

        service.play(list[0], in: list)

        XCTAssertEqual(service.explicitSelections, 1)
    }

    /// Two taps on the *same* row are two separate requests to open the player.
    /// A `Bool` would collapse them into one and the second tap would do
    /// nothing, which is why this is a count.
    func testTappingTheSameRowTwiceCountsTwice() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(3, library: library)

        service.play(list[0], in: list)
        service.play(list[0], in: list)

        XCTAssertEqual(service.explicitSelections, 2)
    }

    // The three "does not count" tests below compare against the count taken
    // immediately BEFORE the action, never against a literal.
    //
    // They were written against the literal `1` first, and a mutation run —
    // moving the increment out of `play(_:in:)` and into `advance(to:)` — left
    // all three green: `play` then contributed 0 and the skip contributed 1, so
    // the total still read 1 and the assertions could not tell the difference.
    // A test for "this action changes nothing" has to measure the change.

    func testNextDoesNotCount() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)
        let before = service.explicitSelections

        service.next()

        XCTAssertEqual(service.queueIndex, 1, "precondition: next() actually moved")
        XCTAssertEqual(service.explicitSelections, before)
    }

    func testPreviousDoesNotCount() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[2], in: list)
        let before = service.explicitSelections

        service.previous()

        XCTAssertEqual(service.queueIndex, 1, "precondition: previous() actually moved")
        XCTAssertEqual(service.explicitSelections, before)
    }

    /// The one that matters most: a track ending on its own is the case where
    /// an accidental open would happen unattended.
    ///
    /// Async and yielding for the same reason `PlaybackServiceQueueTests`
    /// documents — `didFinishCallback` hops through `Task { @MainActor in }`,
    /// so a synchronous assertion would run before `handleFinish()` did and
    /// would pass whether or not the counter moved.
    func testAutoAdvanceOnFinishDoesNotCount() async throws {
        let (service, player, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)
        let before = service.explicitSelections

        player.simulateFinish()
        await Task.yield()

        XCTAssertEqual(service.queueIndex, 1, "precondition: the finish advanced the queue")
        XCTAssertEqual(service.explicitSelections, before)
    }

    func testPauseAndResumeDoNotCount() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(2, library: library)
        service.play(list[0], in: list)
        let before = service.explicitSelections

        service.pause()
        service.resume()
        service.togglePlayPause()

        XCTAssertEqual(service.explicitSelections, before)
    }
}
