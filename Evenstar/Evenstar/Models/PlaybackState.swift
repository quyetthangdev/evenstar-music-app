import Foundation
import SwiftData

@Model
final class PlaybackState {
    var currentTrackID: UUID?
    var positionSeconds: Double
    var queueTrackIDs: [UUID]
    var queueIndex: Int

    init(currentTrackID: UUID? = nil,
         positionSeconds: Double = 0,
         queueTrackIDs: [UUID] = [],
         queueIndex: Int = 0) {
        self.currentTrackID = currentTrackID
        self.positionSeconds = positionSeconds
        self.queueTrackIDs = queueTrackIDs
        self.queueIndex = queueIndex
    }
}
