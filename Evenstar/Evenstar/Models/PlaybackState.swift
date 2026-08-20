import Foundation
import SwiftData

@Model
final class PlaybackState {
    var currentTrackID: UUID?
    var positionSeconds: Double = 0
    var queueTrackIDs: [UUID] = []
    var queueIndex: Int = 0
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

    /// Whether the stored `queueTrackIDs` are in shuffled order.
    ///
    /// A literal default, for exactly the reason `repeatModeRaw` above carries
    /// one: it is what lets SwiftData migrate rows written before this property
    /// existed without a migration plan. A property added without one is an app
    /// that will not launch for anyone who has used it before.
    var isShuffled: Bool = false

    /// The queue's order *before* shuffling, so the toggle can be undone after a
    /// relaunch. Empty when `isShuffled` is false.
    ///
    /// The shuffled order needs no field of its own — it is what
    /// `queueTrackIDs` already holds. This is the information that would
    /// otherwise be lost, because a shuffle cannot be inverted.
    var unshuffledQueueTrackIDs: [UUID] = []

    /// Hàng đợi hết bài thì có tự nối thêm từ thư viện không.
    ///
    /// Literal default, cùng lý do `repeatModeRaw` và `isShuffled` mang một
    /// cái: nó là thứ cho SwiftData đọc được những hàng đã ghi trước khi thuộc
    /// tính này tồn tại, không cần migration plan.
    var isAutoplay: Bool = false

    init(currentTrackID: UUID? = nil,
         positionSeconds: Double = 0,
         queueTrackIDs: [UUID] = [],
         queueIndex: Int = 0,
         repeatModeRaw: String = "off",
         isShuffled: Bool = false,
         unshuffledQueueTrackIDs: [UUID] = [],
         isAutoplay: Bool = false) {
        self.currentTrackID = currentTrackID
        self.positionSeconds = positionSeconds
        self.queueTrackIDs = queueTrackIDs
        self.queueIndex = queueIndex
        self.repeatModeRaw = repeatModeRaw
        self.isShuffled = isShuffled
        self.unshuffledQueueTrackIDs = unshuffledQueueTrackIDs
        self.isAutoplay = isAutoplay
    }
}
