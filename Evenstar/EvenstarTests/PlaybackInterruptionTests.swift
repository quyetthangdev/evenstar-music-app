import XCTest
import AVFoundation
@testable import Evenstar

/// What happens to playback when something outside the app takes the audio
/// away: a phone call, an alarm, Siri, or headphones being pulled out.
///
/// A `.playback`-category app is expected to handle both notifications itself —
/// iOS pauses the audio hardware but does not update the app, and it does not
/// resume for you. Without this the app's own state drifts from reality: the
/// pause glyph, the lock screen and `isPlaying` all still claim playback is
/// live while nothing is coming out, and the session the OS tore down is never
/// reactivated.
///
/// The notification centre is injected so each test posts into its own, rather
/// than into `NotificationCenter.default` where every other live service — and
/// the real `AVAudioSession` — would hear it too.
@MainActor
final class PlaybackInterruptionTests: XCTestCase {

    private func makeStack() throws
        -> (PlaybackService, MockAudioPlayer, NotificationCenter, Track) {
        let player = MockAudioPlayer()
        let centre = NotificationCenter()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(
            player: player,
            nowPlaying: MockNowPlayingPublisher(),
            library: library,
            notificationCentre: centre
        )
        let track = InMemoryLibrary.makeTrack(title: "Sample")
        try library.insert(track)
        return (service, player, centre, track)
    }

    private func postInterruption(
        _ centre: NotificationCenter,
        _ type: AVAudioSession.InterruptionType,
        options: AVAudioSession.InterruptionOptions = []
    ) async {
        centre.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: type.rawValue,
                AVAudioSessionInterruptionOptionKey: options.rawValue,
            ]
        )
        // The observer hops to the main actor rather than trusting the posting
        // thread, exactly as the player's own callbacks do. One yield is enough:
        // the hop is enqueued during `post`, so it is ahead of this suspension.
        await Task.yield()
    }

    private func postRouteChange(
        _ centre: NotificationCenter,
        _ reason: AVAudioSession.RouteChangeReason
    ) async {
        centre.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: reason.rawValue]
        )
        await Task.yield()
    }

    // MARK: - Interruptions

    func testAPhoneCallPausesPlayback() async throws {
        let (service, player, centre, track) = try makeStack()
        service.play(track, in: [track])

        await postInterruption(centre, .began)

        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(player.pauseCallCount, 1)
    }

    func testTheEndOfAPhoneCallResumesPlaybackWhenTheSystemSaysItShould() async throws {
        let (service, player, centre, track) = try makeStack()
        service.play(track, in: [track])
        await postInterruption(centre, .began)

        await postInterruption(centre, .ended, options: .shouldResume)

        XCTAssertTrue(service.isPlaying)
        XCTAssertEqual(player.playCallCount, 2)
    }

    /// `.shouldResume` absent means the interrupting app is still holding the
    /// session — Siri left something playing, or the user started another audio
    /// app. Resuming anyway would fight it.
    func testTheEndOfAnInterruptionWithoutShouldResumeLeavesPlaybackPaused() async throws {
        let (service, player, centre, track) = try makeStack()
        service.play(track, in: [track])
        await postInterruption(centre, .began)

        await postInterruption(centre, .ended)

        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(player.playCallCount, 1)
    }

    /// An interruption that arrives while the user has the app paused must not
    /// turn into playback when it ends. `.shouldResume` says the *session* may
    /// resume, not that this app was playing.
    func testAnInterruptionOfPausedPlaybackDoesNotStartIt() async throws {
        let (service, player, centre, track) = try makeStack()
        service.play(track, in: [track])
        service.togglePlayPause()
        XCTAssertFalse(service.isPlaying)

        await postInterruption(centre, .began)
        await postInterruption(centre, .ended, options: .shouldResume)

        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(player.playCallCount, 1)
    }

    // MARK: - Route changes

    /// Headphones or a Bluetooth speaker going away. Without this the track
    /// keeps playing out loud through the built-in speaker — in a pocket, in a
    /// meeting — until the user notices and reaches for the phone.
    func testUnpluggingHeadphonesPausesPlayback() async throws {
        let (service, player, centre, track) = try makeStack()
        service.play(track, in: [track])

        await postRouteChange(centre, .oldDeviceUnavailable)

        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(player.pauseCallCount, 1)
    }

    /// *Plugging headphones in* is the same notification with a different
    /// reason, and it must not stop the music.
    func testPluggingHeadphonesInLeavesPlaybackRunning() async throws {
        let (service, player, centre, track) = try makeStack()
        service.play(track, in: [track])

        await postRouteChange(centre, .newDeviceAvailable)

        XCTAssertTrue(service.isPlaying)
        XCTAssertEqual(player.pauseCallCount, 0)
    }

    /// A route change is not an interruption: nothing is coming back, so the
    /// next `.ended` — from an unrelated interruption later — must not treat the
    /// unplug as something to resume from.
    func testUnpluggingHeadphonesIsNotResumedByALaterInterruptionEnding() async throws {
        let (service, player, centre, track) = try makeStack()
        service.play(track, in: [track])
        await postRouteChange(centre, .oldDeviceUnavailable)

        await postInterruption(centre, .ended, options: .shouldResume)

        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(player.playCallCount, 1)
    }
}
