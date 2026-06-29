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
            self?.playback.play()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.playback.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.playback.togglePlayPause()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.playback.seek(to: positionEvent.positionTime)
            return .success
        }

        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = true
    }
}
