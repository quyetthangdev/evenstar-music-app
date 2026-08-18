import XCTest
import Foundation
import SwiftData
@testable import Evenstar

/// `RoutingAudioPlayer` is the piece that makes Drive playback reachable at all:
/// `PlaybackService` takes one player, `AVAudioPlayer` cannot open an https URL,
/// and `AVPlayer` is not worth using for a local file. None of that is visible
/// in a screenshot — a mis-routed track is silence — so the routing itself is
/// tested here.
final class RoutingAudioPlayerTests: XCTestCase {

    private func makeRouter() -> (RoutingAudioPlayer, MockAudioPlayer, MockAudioPlayer) {
        let local = MockAudioPlayer()
        let streaming = MockAudioPlayer()
        return (RoutingAudioPlayer(local: local, streaming: streaming), local, streaming)
    }

    private let fileURL = URL(fileURLWithPath: "/tmp/song.mp3")
    private let httpsURL = URL(string: "https://www.googleapis.com/drive/v3/files/abc?alt=media&key=k")!

    // MARK: - The routing decision

    func testAFileURLGoesToTheLocalEngineOnly() throws {
        let (router, local, streaming) = makeRouter()

        try router.load(url: fileURL)

        XCTAssertEqual(local.loadedURL, fileURL)
        XCTAssertNil(streaming.loadedURL, "a local file must never reach the streaming player")
        XCTAssertFalse(router.isStreamingActiveForTesting)
    }

    /// The bug this whole type exists to prevent: `AVAudioPlayer(contentsOf:)`
    /// rejects an https URL, so a Drive track handed to it fails to load and is
    /// silently skipped by `PlaybackService`'s queue loop.
    func testAnHTTPSURLGoesToTheStreamingEngineOnly() throws {
        let (router, local, streaming) = makeRouter()

        try router.load(url: httpsURL)

        XCTAssertEqual(streaming.loadedURL, httpsURL)
        XCTAssertNil(local.loadedURL, "a network URL must never reach AVAudioPlayer")
        XCTAssertTrue(router.isStreamingActiveForTesting)
    }

    /// The missing-API-key sentinel is an https URL with an unreachable host. It
    /// has to reach the streaming player, because that is the only place that
    /// recognises it and turns it into `DriveError.missingAPIKey`.
    func testTheMissingAPIKeySentinelIsRoutedToTheStreamingEngine() throws {
        let (router, _, streaming) = makeRouter()

        try router.load(url: DriveClient.missingAPIKeyURL)

        XCTAssertEqual(streaming.loadedURL, DriveClient.missingAPIKeyURL)
    }

    // MARK: - Switching engines stops the outgoing one

    /// `AVAudioPlayer` keeps playing across a switch that never touches it, so
    /// without this a queue stepping from a local track to a Drive track plays
    /// both at once.
    func testSwitchingFromLocalToStreamingStopsTheLocalEngine() throws {
        let (router, local, _) = makeRouter()
        try router.load(url: fileURL)
        router.play()
        XCTAssertTrue(local.isPlaying)

        try router.load(url: httpsURL)

        XCTAssertFalse(local.isPlaying, "the outgoing engine must be stopped, not left running")
        XCTAssertEqual(local.pauseCallCount, 1)
    }

    func testSwitchingFromStreamingToLocalStopsTheStreamingEngine() throws {
        let (router, _, streaming) = makeRouter()
        try router.load(url: httpsURL)
        router.play()

        try router.load(url: fileURL)

        XCTAssertFalse(streaming.isPlaying)
        XCTAssertEqual(streaming.pauseCallCount, 1)
    }

    /// Loading a second track on the *same* engine must not pause it first —
    /// that is the ordinary next-track path, and the engine's own `load` already
    /// replaces what it holds.
    func testStayingOnOneEngineDoesNotPauseIt() throws {
        let (router, local, _) = makeRouter()
        try router.load(url: fileURL)

        try router.load(url: URL(fileURLWithPath: "/tmp/other.mp3"))

        XCTAssertEqual(local.pauseCallCount, 0)
    }

    // MARK: - The inactive engine must not be able to speak

    /// An `AVAudioPlayer` left paused mid-file can still post its finish
    /// notification. Forwarded, it would skip the Drive track that is playing.
    func testAFinishFromTheInactiveEngineIsNotForwarded() throws {
        let (router, local, streaming) = makeRouter()
        var finishes = 0
        router.didFinishCallback = { finishes += 1 }
        try router.load(url: fileURL)
        try router.load(url: httpsURL)

        local.simulateFinish()

        XCTAssertEqual(finishes, 0, "a superseded engine must not advance the queue")

        streaming.simulateFinish()

        XCTAssertEqual(finishes, 1, "the live engine must still advance the queue")
    }

    /// `AVPlayer` can reach `.failed` seconds after a load was abandoned. By
    /// then the user may be listening to a local track that is playing fine, and
    /// `PlaybackService.handleFailure` would pause it and raise a banner.
    func testAFailureFromTheInactiveEngineIsNotForwarded() throws {
        let (router, local, streaming) = makeRouter()
        var reported: [URL] = []
        router.didFailCallback = { _, url in reported.append(url) }
        try router.load(url: httpsURL)
        try router.load(url: fileURL)

        streaming.simulateFailure(url: httpsURL)

        XCTAssertEqual(reported, [], "a failure from an abandoned engine must not reach the service")

        local.simulateFailure(url: fileURL)

        XCTAssertEqual(reported, [fileURL], "the live engine's failure must reach the service")
    }

    /// `StreamingAudioPlayer` reports the missing-API-key sentinel *from inside*
    /// `load(url:)`. If the router opened its gate only after `load` returned,
    /// that report would be dropped and a missing key would be silence.
    func testAFailureReportedFromInsideLoadIsForwarded() throws {
        let local = MockAudioPlayer()
        let streaming = FailsDuringLoadPlayer()
        let router = RoutingAudioPlayer(local: local, streaming: streaming)
        var reported: [URL] = []
        router.didFailCallback = { _, url in reported.append(url) }

        try router.load(url: httpsURL)

        XCTAssertEqual(reported, [httpsURL])
    }

    // MARK: - Live state reaches through to the live engine

    func testIsPlayingCurrentTimeAndDurationReadFromTheLiveEngine() throws {
        let (router, local, streaming) = makeRouter()
        local.duration = 100
        local.currentTime = 10
        streaming.duration = 300
        streaming.currentTime = 30

        try router.load(url: fileURL)
        local.currentTime = 10
        XCTAssertEqual(router.duration, 100, accuracy: 0.01)
        XCTAssertEqual(router.currentTime, 10, accuracy: 0.01)
        router.play()
        XCTAssertTrue(router.isPlaying)
        XCTAssertFalse(streaming.isPlaying)

        try router.load(url: httpsURL)
        streaming.currentTime = 30
        XCTAssertEqual(router.duration, 300, accuracy: 0.01)
        XCTAssertEqual(router.currentTime, 30, accuracy: 0.01)
        XCTAssertFalse(router.isPlaying, "the streaming engine has not been asked to play yet")
    }

    /// The setter is the half that is easy to forget, and losing it means every
    /// restored position and every scrub silently does nothing.
    func testTheCurrentTimeSetterWritesToTheLiveEngineOnly() throws {
        let (router, local, streaming) = makeRouter()
        try router.load(url: httpsURL)

        router.currentTime = 151

        XCTAssertEqual(streaming.currentTime, 151, accuracy: 0.01)
        XCTAssertEqual(local.currentTime, 0, accuracy: 0.01)
    }

    /// `PlaybackService.clampToDuration` declines to clamp while this is false.
    /// If the router answered for itself, every restored Drive position would be
    /// flattened to 0:00 again — the exact defect Task 6 fixed.
    func testIsDurationKnownReachesThroughToTheLiveEngine() throws {
        let (router, local, streaming) = makeRouter()
        local.isDurationKnown = true
        streaming.isDurationKnown = false

        try router.load(url: httpsURL)
        XCTAssertFalse(router.isDurationKnown)

        try router.load(url: fileURL)
        XCTAssertTrue(router.isDurationKnown)
    }

    /// Before anything is loaded the router must answer exactly as
    /// `AVAudioPlayerWrapper` did when it was wired in directly, so nothing
    /// about the local path changes.
    func testAnUnloadedRouterAnswersLikeTheLocalPlayerDidBeforeIt() {
        let (router, _, _) = makeRouter()

        XCTAssertFalse(router.isPlaying)
        XCTAssertEqual(router.currentTime, 0, accuracy: 0.01)
        XCTAssertEqual(router.duration, 0, accuracy: 0.01)
        XCTAssertTrue(router.isDurationKnown)
    }

    /// Play and pause must reach the live engine and nothing else.
    func testPlayAndPauseOnlyTouchTheLiveEngine() throws {
        let (router, local, streaming) = makeRouter()
        try router.load(url: httpsURL)

        router.play()
        router.pause()

        XCTAssertEqual(streaming.playCallCount, 1)
        XCTAssertEqual(streaming.pauseCallCount, 1)
        XCTAssertEqual(local.playCallCount, 0)
        XCTAssertEqual(local.pauseCallCount, 0)
    }

    // MARK: - End to end through PlaybackService

    /// The router is only useful if `PlaybackService` — untouched by this task —
    /// drives it correctly. A mixed queue is the case that exercises both
    /// engines and the switch between them.
    @MainActor
    func testAMixedQueueAdvancesFromALocalTrackToADriveTrack() throws {
        let local = MockAudioPlayer()
        let streaming = MockAudioPlayer()
        let router = RoutingAudioPlayer(local: local, streaming: streaming)
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(
            player: router, nowPlaying: MockNowPlayingPublisher(), library: library
        )
        let localTrack = Track(
            title: "Local", artistName: "A", albumTitle: "B",
            durationSeconds: 100, relativePath: "Music/a.mp3", format: "mp3"
        )
        try library.insert(localTrack)
        let driveTrack = DriveTrack(fileID: "f1", folderID: "folder", fileName: "Drive.mp3")
        library.context.insert(driveTrack)
        try library.save()

        service.play(localTrack, in: [localTrack, driveTrack])
        XCTAssertEqual(local.loadedURL, localTrack.playbackURL())
        XCTAssertNil(streaming.loadedURL)

        service.next()

        XCTAssertEqual(streaming.loadedURL, driveTrack.playbackURL())
        XCTAssertFalse(local.isPlaying, "the local file must stop when the Drive track starts")
        XCTAssertTrue(service.isPlaying)
    }

    // MARK: - Helpers

    /// Stands in for `StreamingAudioPlayer`'s missing-API-key branch, which
    /// reports through `didFailCallback` from inside `load(url:)` rather than
    /// throwing. `MockAudioPlayer` cannot express that — it fails loudly when
    /// asked to report with nothing loaded.
    private final class FailsDuringLoadPlayer: AudioPlayerProtocol {
        var isPlaying = false
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var didFinishCallback: (() -> Void)?
        var didFailCallback: ((Error, URL) -> Void)?

        func load(url: URL) throws {
            didFailCallback?(DriveError.missingAPIKey, url)
        }

        func play() {}
        func pause() {}
    }
}
