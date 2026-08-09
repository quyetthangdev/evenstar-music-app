import XCTest
@testable import Evenstar

/// The handover between the preview player and the main one.
///
/// Everything here is about `suspendMainPlayback`/`resumeMainPlayback` being
/// called the right number of times: the audio session is shared, so a missing
/// suspend means two tracks sounding at once, and a stray resume means music
/// starting on its own after the user stopped it.
@MainActor
final class JamendoPreviewPlayerTests: XCTestCase {

    private func makeTrack(
        id: String = "1",
        audio: String = "https://api.jamendo.com/audio/1.mp3"
    ) -> JamendoCatalogueTrack {
        JamendoCatalogueTrack(
            id: id,
            title: "Title \(id)",
            artistName: "Artist",
            albumTitle: "Album",
            durationSeconds: 180,
            audioURL: URL(string: audio)!,
            coverURL: nil,
            licenceURL: nil,
            shareURL: nil
        )
    }

    /// Counts the two closures the view supplies, and lets a test say whether
    /// there was music playing to interrupt in the first place.
    @MainActor
    private final class Coordinator {
        var mainWasPlaying: Bool
        private(set) var suspendCount = 0
        private(set) var resumeCount = 0

        init(mainWasPlaying: Bool) { self.mainWasPlaying = mainWasPlaying }

        func attach(to preview: JamendoPreviewPlayer) {
            preview.suspendMainPlayback = { [unowned self] in
                suspendCount += 1
                return mainWasPlaying
            }
            preview.resumeMainPlayback = { [unowned self] in resumeCount += 1 }
        }
    }

    func testTogglingATrackLoadsAndPlaysIt() {
        let audio = MockAudioPlayer()
        let preview = JamendoPreviewPlayer(player: audio)
        let track = makeTrack()

        preview.toggle(track)

        XCTAssertEqual(preview.playingID, "1")
        XCTAssertEqual(audio.loadedURL, track.audioURL)
        XCTAssertEqual(audio.playCallCount, 1)
    }

    func testTogglingTheSameTrackAgainStopsIt() {
        let audio = MockAudioPlayer()
        let preview = JamendoPreviewPlayer(player: audio)
        let track = makeTrack()

        preview.toggle(track)
        preview.toggle(track)

        XCTAssertNil(preview.playingID)
        XCTAssertEqual(audio.pauseCallCount, 1)
    }

    func testAPreviewSuspendsPlayingMusicAndResumesItOnStop() {
        let coordinator = Coordinator(mainWasPlaying: true)
        let preview = JamendoPreviewPlayer(player: MockAudioPlayer())
        coordinator.attach(to: preview)

        preview.toggle(makeTrack())
        XCTAssertEqual(coordinator.suspendCount, 1)
        XCTAssertEqual(coordinator.resumeCount, 0, "resumed while still previewing")

        preview.stop()
        XCTAssertEqual(coordinator.resumeCount, 1)
    }

    /// The point of `suspendMainPlayback` returning a `Bool`. Previewing while
    /// the user has their music paused must not start it playing afterwards.
    func testAPreviewStartedInSilenceEndsInSilence() {
        let coordinator = Coordinator(mainWasPlaying: false)
        let preview = JamendoPreviewPlayer(player: MockAudioPlayer())
        coordinator.attach(to: preview)

        preview.toggle(makeTrack())
        preview.stop()

        XCTAssertEqual(coordinator.suspendCount, 1, "should still ask")
        XCTAssertEqual(coordinator.resumeCount, 0, "nothing was interrupted, so nothing resumes")
    }

    /// Switching rows is one previewing session, not two. Resuming the main
    /// player between them would blast a second of the interrupted track out
    /// between every two previews.
    func testSwitchingTracksDoesNotResumeInBetween() {
        let coordinator = Coordinator(mainWasPlaying: true)
        let preview = JamendoPreviewPlayer(player: MockAudioPlayer())
        coordinator.attach(to: preview)

        preview.toggle(makeTrack(id: "1"))
        preview.toggle(makeTrack(id: "2", audio: "https://api.jamendo.com/audio/2.mp3"))

        XCTAssertEqual(preview.playingID, "2")
        XCTAssertEqual(coordinator.suspendCount, 1, "suspended once for the session")
        XCTAssertEqual(coordinator.resumeCount, 0)

        preview.stop()
        XCTAssertEqual(coordinator.resumeCount, 1)
    }

    func testATrackEndingByItselfResumesTheMainPlayer() {
        let coordinator = Coordinator(mainWasPlaying: true)
        let audio = MockAudioPlayer()
        let preview = JamendoPreviewPlayer(player: audio)
        coordinator.attach(to: preview)

        preview.toggle(makeTrack())
        audio.simulateFinish()

        XCTAssertNil(preview.playingID)
        XCTAssertEqual(coordinator.resumeCount, 1)
    }

    func testAStreamThatFailsReportsAndHandsPlaybackBack() {
        let coordinator = Coordinator(mainWasPlaying: true)
        let audio = MockAudioPlayer()
        let preview = JamendoPreviewPlayer(player: audio)
        coordinator.attach(to: preview)

        preview.toggle(makeTrack())
        audio.simulateFailure(URLError(.notConnectedToInternet))

        XCTAssertNil(preview.playingID)
        XCTAssertNotNil(preview.failureMessage)
        XCTAssertEqual(coordinator.resumeCount, 1)
    }

    /// `AudioPlayerProtocol.didFailCallback` carries the URL precisely so a
    /// late failure for an abandoned load cannot stop the preview that replaced
    /// it. Without the identity check, tapping row 2 while row 1's stream is
    /// still failing silences row 2 and blames it for row 1's error.
    func testALateFailureForAnAbandonedTrackIsIgnored() {
        let coordinator = Coordinator(mainWasPlaying: true)
        let audio = MockAudioPlayer()
        let preview = JamendoPreviewPlayer(player: audio)
        coordinator.attach(to: preview)

        let abandoned = makeTrack(id: "1")
        preview.toggle(abandoned)
        preview.toggle(makeTrack(id: "2", audio: "https://api.jamendo.com/audio/2.mp3"))

        audio.simulateFailure(URLError(.timedOut), url: abandoned.audioURL)

        XCTAssertEqual(preview.playingID, "2", "the live preview was stopped by a stale failure")
        XCTAssertNil(preview.failureMessage)
        XCTAssertEqual(coordinator.resumeCount, 0)
    }

    /// The discovery screen calls `stop()` unconditionally in `onDisappear`.
    func testStoppingWhenNothingIsPlayingDoesNothing() {
        let coordinator = Coordinator(mainWasPlaying: true)
        let audio = MockAudioPlayer()
        let preview = JamendoPreviewPlayer(player: audio)
        coordinator.attach(to: preview)

        preview.stop()

        XCTAssertEqual(audio.pauseCallCount, 0)
        XCTAssertEqual(coordinator.resumeCount, 0, "resumed music nobody interrupted")
    }

    func testATrackThatWillNotLoadResumesTheMainPlayer() {
        let coordinator = Coordinator(mainWasPlaying: true)
        let audio = MockAudioPlayer()
        let track = makeTrack()
        audio.failingURLs = [track.audioURL]
        let preview = JamendoPreviewPlayer(player: audio)
        coordinator.attach(to: preview)

        preview.toggle(track)

        XCTAssertNil(preview.playingID)
        XCTAssertNotNil(preview.failureMessage)
        XCTAssertEqual(coordinator.resumeCount, 1)
    }
}
