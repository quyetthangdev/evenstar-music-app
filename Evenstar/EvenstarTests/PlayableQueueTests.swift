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

    /// The reason `Playable` is `AnyObject`. `PlaybackService` bumps
    /// `playCount`/`lastPlayedAt` through the existential, expecting to mutate
    /// the SwiftData row itself; a value-type protocol would let that write
    /// land on a copy and vanish, and the local-only play-count tests would
    /// stay green while every Drive track's count sat at zero forever.
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
    func testADriveTrackWithNoTagsStillHasAnArtistAndAlbumToShow() throws {
        let library = try InMemoryLibrary.make()
        let remote = try driveTrack(library)

        XCTAssertEqual(remote.artistName, "Nghệ sĩ không rõ")
        XCTAssertEqual(remote.albumTitle, "Album không rõ")
    }
}
