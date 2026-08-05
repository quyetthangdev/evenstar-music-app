import Foundation
import SwiftData

@Model
final class PlaybackState {
    var currentTrackID: UUID?
    var positionSeconds: Double
    var queueTrackIDs: [UUID]
    var queueIndex: Int
    /// `RepeatMode.rawValue`.
    ///
    /// A raw `String` with a literal default rather than the enum itself: the
    /// default is what lets SwiftData migrate rows written before this property
    /// existed without a migration plan, and a raw value read back as something
    /// unrecognised degrades to `.off` instead of failing to decode.
    ///
    /// The literal is pinned to the enum by
    /// `PlaybackServiceRepeatTests.testFreshPlaybackStateDefaultsToOff`.
    var repeatModeRaw: String = "off"

    init(currentTrackID: UUID? = nil,
         positionSeconds: Double = 0,
         queueTrackIDs: [UUID] = [],
         queueIndex: Int = 0,
         repeatModeRaw: String = "off") {
        self.currentTrackID = currentTrackID
        self.positionSeconds = positionSeconds
        self.queueTrackIDs = queueTrackIDs
        self.queueIndex = queueIndex
        self.repeatModeRaw = repeatModeRaw
    }
}
