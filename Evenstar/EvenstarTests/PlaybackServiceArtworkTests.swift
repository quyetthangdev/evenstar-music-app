import XCTest
import UIKit
@testable import Evenstar

/// Covers the artwork half of the Now Playing push — the half no test could
/// see until `MockNowPlayingPublisher.Update` started recording it.
///
/// `PlaybackService` publishes a track in two pushes: title/artist/album
/// synchronously on the tap, then the cover once `ArtworkStore` has read and
/// downsampled it off the main actor. Every test here is about that second
/// push: that it happens at all on the restore path, that it is genuinely
/// second rather than folded into the first, and that a stale one cannot
/// overtake a newer track.
@MainActor
final class PlaybackServiceArtworkTests: XCTestCase {

    /// Restoring on launch must put the cover on the lock screen.
    ///
    /// `restoreFromPersistedState()` deliberately does not call
    /// `loadCurrentAndPlay()` (it must not start playback), so it builds and
    /// pushes its own metadata — and `metadata(from:)` returns `artwork: nil`
    /// by design. When the artwork request was added to `loadCurrentAndPlay()`
    /// only, this path was left pushing nil forever: `NowPlayingService` drops
    /// the artwork key when it is nil, and every later push on the same track
    /// (`resume()`, `pause()`, `seek()`, the tick reconcile) re-reads the same
    /// nil-artwork `currentMetadata`. Cold launch, tap play, lock the phone —
    /// blank cover for the whole track, on the most common launch path there
    /// is.
    func testRestoredTrackEventuallyPushesItsArtwork() async throws {
        let (service, _, nowPlaying, library) = try makeStack()
        let path = try makeArtworkFile(side: 180, color: .red)
        defer { removeArtworkFile(path) }
        let track = InMemoryLibrary.makeTrack(title: "Restored", artworkRelativePath: path)
        try library.insert(track)
        let state = library.playbackState
        state.queueTrackIDs = [track.id]
        state.queueIndex = 0
        state.positionSeconds = 12
        try library.save()

        await service.restoreFromPersistedState()
        let arrived = await yieldUntil { nowPlaying.updates.contains(where: \.hasArtwork) }

        XCTAssertTrue(arrived, "Restore pushed the track but never followed up with its artwork")
        XCTAssertEqual(nowPlaying.updates.last?.title, "Restored")
        XCTAssertTrue(try XCTUnwrap(nowPlaying.updates.last).hasArtwork)
    }

    /// The two-push contract, stated for the first time: the text lands inside
    /// the tap and the cover does not.
    ///
    /// This is the trade the whole design rests on — the text is what tells the
    /// user the track changed, so it must not wait behind a file read and an
    /// ImageIO decode. If someone ever moves the decode back in front of the
    /// first push, the `XCTAssertFalse` below is what says so; if they drop the
    /// second push, the `XCTAssertTrue` is.
    func testPlayPushesTextFirstAndArtworkOnALaterTurn() async throws {
        let (service, _, nowPlaying, library) = try makeStack()
        let path = try makeArtworkFile(side: 180, color: .green)
        defer { removeArtworkFile(path) }
        let track = InMemoryLibrary.makeTrack(title: "Two Pushes", artworkRelativePath: path)
        try library.insert(track)

        service.play(track, in: [track])

        let firstPush = try XCTUnwrap(nowPlaying.updates.last)
        XCTAssertEqual(firstPush.title, "Two Pushes")
        XCTAssertFalse(
            firstPush.hasArtwork,
            "The tap's own push must not carry artwork — that is the decode this design moved off the tap"
        )

        let arrived = await yieldUntil { nowPlaying.updates.contains(where: \.hasArtwork) }

        XCTAssertTrue(arrived, "The artwork never arrived on a later turn")
        XCTAssertEqual(nowPlaying.updates.last?.title, "Two Pushes")
        XCTAssertTrue(try XCTUnwrap(nowPlaying.updates.last).hasArtwork)
    }

    /// The id guard in `loadArtworkIntoNowPlaying`. A user holding Next changes
    /// track faster than a decode finishes, and a late decode landing without
    /// the guard would put the previous track's cover under the current track's
    /// title — the one visibly wrong state this feature can produce.
    ///
    /// The two covers are told apart by pixel size (240 vs 120, both under the
    /// 1024 the lock screen asks for, so neither is downsampled and the sizes
    /// survive intact) rather than by colour, which would mean holding a
    /// non-`Sendable` `UIImage` in `Update`.
    func testArtworkForASupersededTrackIsNeverPushed() async throws {
        let (service, _, nowPlaying, library) = try makeStack()
        let pathA = try makeArtworkFile(side: 240, color: .red)
        let pathB = try makeArtworkFile(side: 120, color: .blue)
        defer { removeArtworkFile(pathA); removeArtworkFile(pathB) }
        let trackA = InMemoryLibrary.makeTrack(title: "A", artworkRelativePath: pathA)
        let trackB = InMemoryLibrary.makeTrack(title: "B", artworkRelativePath: pathB)
        try library.insert(trackA)
        try library.insert(trackB)

        service.play(trackA, in: [trackA, trackB])
        service.next()
        let arrived = await yieldUntil { nowPlaying.updates.last?.hasArtwork == true }

        XCTAssertTrue(arrived, "B's artwork never arrived")
        let last = try XCTUnwrap(nowPlaying.updates.last)
        XCTAssertEqual(last.title, "B")
        XCTAssertEqual(last.artworkSize, CGSize(width: 120, height: 120))

        // Nothing from the moment the title became B's may carry A's cover.
        let firstBPush = try XCTUnwrap(nowPlaying.updates.firstIndex { $0.title == "B" })
        for update in nowPlaying.updates[firstBPush...] {
            XCTAssertNotEqual(
                update.artworkSize,
                CGSize(width: 240, height: 240),
                "A superseded decode put A's cover under B's title"
            )
        }
    }

    // MARK: - Fixtures

    private func makeStack() throws -> (PlaybackService, MockAudioPlayer, MockNowPlayingPublisher, LibraryService) {
        let player = MockAudioPlayer()
        let nowPlaying = MockNowPlayingPublisher()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(player: player, nowPlaying: nowPlaying, library: library)
        return (service, player, nowPlaying, library)
    }

    /// Yields the main actor until `condition` holds, and reports whether it
    /// did. Returns as soon as it does, so the passing case costs nothing.
    ///
    /// `Task.yield()` is this suite's idiom for draining a main-actor hop — see
    /// `testFinishAdvancesToNextTrack` — but a *fixed* number of yields does
    /// not work here, and it is worth saying why. `handleFinish` is one
    /// enqueued main-actor job, so one yield drains it. The artwork is not:
    /// `loadArtworkIntoNowPlaying` enqueues a main-actor `Task` whose body
    /// awaits `ArtworkStore.image`, which is `@concurrent` and so genuinely
    /// leaves the main actor to open, decode and downsample a file before
    /// hopping back. The test is therefore waiting on real work on another
    /// thread, not on a known number of queued jobs.
    ///
    /// Measured on the iPhone 17 Pro simulator, over 40 runs: with the decode
    /// already in `ArtworkStore`'s cache it took 2 yields, occasionally 3 —
    /// which is the "two hops" a fixed count would be written for. With a cold
    /// cache, which is what these tests actually have, it took 9 to 29, and 458
    /// on the first decode of the run. So `await Task.yield(); await
    /// Task.yield()` would pass locally and fail perhaps nine times in ten in
    /// CI. Hence a loop, bounded by a deadline so a genuine regression fails
    /// the assertion instead of hanging the suite.
    private func yieldUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = Date.now.addingTimeInterval(5)
        while !condition(), Date.now < deadline {
            await Task.yield()
        }
        return condition()
    }

    /// Writes a solid-colour JPEG of the given pixel size into
    /// `Documents/Artwork` and returns its Documents-relative path — the same
    /// fixture `ArtworkStoreTests` uses, because `PlaybackService` resolves
    /// artwork through `FileLocation` and the file has to live where it would
    /// in real use.
    ///
    /// The renderer is pinned to scale 1, unlike `ArtworkStoreTests`' copy,
    /// which takes the screen's. Those tests only assert an upper bound on the
    /// decoded size; `testArtworkForASupersededTrackIsNeverPushed` identifies a
    /// cover *by* its size, so `side` has to mean pixels rather than points
    /// times whatever the simulator's scale happens to be.
    private func makeArtworkFile(side: CGFloat, color: UIColor) throws -> String {
        let folder = FileLocation.artworkFolderURL()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "playback-\(UUID().uuidString).jpg"
        let url = folder.appendingPathComponent(name)
        let size = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 1))
        try data.write(to: url)
        return "Artwork/\(name)"
    }

    private func removeArtworkFile(_ relativePath: String) {
        try? FileManager.default.removeItem(at: FileLocation.absoluteURL(forRelative: relativePath))
    }
}
