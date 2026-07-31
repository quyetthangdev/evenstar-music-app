import Foundation
import MediaPlayer

final class RemoteCommandsBridge {
    private let playback: PlaybackService

    init(playback: PlaybackService) {
        self.playback = playback
    }

    func install() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)

        center.playCommand.addTarget { [weak self] _ in
            guard let playback = self?.playback else { return .success }
            Task { @MainActor in playback.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let playback = self?.playback else { return .success }
            Task { @MainActor in playback.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let playback = self?.playback else { return .success }
            Task { @MainActor in playback.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let playback = self?.playback else { return .success }
            Task { @MainActor in playback.next() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            guard let playback = self?.playback else { return .success }
            let target = positionEvent.positionTime
            Task { @MainActor in playback.seek(to: target) }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = true
    }
}
