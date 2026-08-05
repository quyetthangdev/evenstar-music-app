import XCTest
import SwiftData
@testable import Evenstar

@MainActor
final class PlayableQueueTests: XCTestCase {

    private func makeStack() throws -> (PlaybackService, MockAudioPlayer, LibraryService) {
        let player = MockAudioPlayer()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(
            player: player, nowPlaying: MockNowPlayingPublisher(), library: library
        )
        return (service, player, library)
    }

    private func localTrack(_ library: LibraryService) throws -> Track {
        let track = Track(
            title: "Local", artistName: "A", albumTitle: "B",
            durationSeconds: 100, relativePath: "Music/\(UUID().uuidString).mp3", format: "mp3"
        )
        try library.insert(track)
        return track
    }

    private func driveTrack(_ library: LibraryService) throws -> DriveTrack {
        let track = DriveTrack(fileID: UUID().uuidString, folderID: "F1", fileName: "remote.mp3")
        library.context.insert(track)
        try library.save()
        return track
    }

    /// The point of the protocol: one queue holding both kinds.
    func testAQueueCanHoldBothSources() throws {
        let (service, _, library) = try makeStack()
        let local = try localTrack(library)
        let remote = try driveTrack(library)

        service.play(local, in: [local, remote])
        XCTAssertEqual(service.currentTrack?.id, local.id)

        service.next()
        XCTAssertEqual(service.currentTrack?.id, remote.id)
        XCTAssertEqual(service.queue.count, 2)
    }

    /// A local track plays from a file URL and a Drive track from https. If
    /// this regresses, playback "works" in tests and fails on device.
    func testEachSourceReportsItsOwnKindOfURL() throws {
        let library = try InMemoryLibrary.make()
        let local = try localTrack(library)
        let remote = try driveTrack(library)

        XCTAssertTrue(local.playbackURL().isFileURL)
        XCTAssertEqual(remote.playbackURL().scheme, "https")
    }

    /// Session restore has to look in both stores. Resolving only local tracks
    /// would silently drop every Drive track from a restored queue.
    func testRestoreResolvesADriveTrackFromThePersistedQueue() async throws {
        let (service, _, library) = try makeStack()
        let remote = try driveTrack(library)
        service.play(remote, in: [remote])

        let relaunched = PlaybackService(
            player: MockAudioPlayer(), nowPlaying: MockNowPlayingPublisher(), library: library
        )
        await relaunched.restoreFromPersistedState()

        XCTAssertEqual(relaunched.queue.count, 1)
        XCTAssertEqual(relaunched.currentTrack?.id, remote.id)
    }

    /// The only coverage that play counting works for a queue member that is
    /// not a `Track`. Every other play-count test builds a local queue, so all
    /// of them would stay green if the count were only ever reachable for local
    /// tracks.
    ///
    /// Concretely, this fails if `tickPosition()` is ever rewritten to resolve
    /// the row it increments through `library.findTrack(byID:)` — a plausible
    /// change, since that is how `restoreFromPersistedState()` finds its rows —
    /// because that lookup only searches the `Track` table and would return nil
    /// for the Drive track, silently counting nothing.
    ///
    /// It does *not* test the `AnyObject` constraint: `tickPosition()` binds
    /// `let track = currentTrack`, so dropping `AnyObject` from `Playable` is a
    /// compile error rather than a test failure, and both conformers are
    /// classes anyway.
    func testPlayingADriveTrackCountsAgainstTheRowItself() throws {
        let (service, player, library) = try makeStack()
        let remote = try driveTrack(library)
        service.play(remote, in: [remote])

        player.currentTime = 30.5
        service.tickForTesting()

        XCTAssertEqual(remote.playCount, 1)
        XCTAssertNotNil(remote.lastPlayedAt)
    }

    /// Unknown tags become the same placeholder the local library shows, rather
    /// than an empty line in the player.
    ///
    /// Asserted against `MetadataPlaceholder`, not against string literals. A
    /// literal here would pass while `ImportService` used a different one,
    /// which is exactly the divergence this test is supposed to prevent —
    /// `ImportServiceTests` already pins the literal spelling from the other
    /// side, so between them the pair is held to one value.
    func testADriveTrackWithNoTagsStillHasAnArtistAndAlbumToShow() throws {
        let library = try InMemoryLibrary.make()
        let remote = try driveTrack(library)

        XCTAssertEqual(remote.artistName, MetadataPlaceholder.artist)
        XCTAssertEqual(remote.albumTitle, MetadataPlaceholder.album)
    }
}
