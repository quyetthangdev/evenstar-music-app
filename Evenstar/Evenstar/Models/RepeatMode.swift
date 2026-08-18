import Foundation

/// What happens when playback reaches the end of something.
enum RepeatMode: String {
    /// Stop when the queue runs out.
    case off
    /// Wrap round to the start of the queue.
    case all
    /// Replay the current track when it ends by itself. Deliberately not when
    /// the user presses Next — see `PlaybackService.handleFinish()`.
    case one

    /// The mode the repeat button selects next.
    ///
    /// An explicit `switch`, and the enum is deliberately not `CaseIterable`.
    /// The cycle order is behaviour; deriving it from `allCases` would tie it
    /// to the order the cases happen to be declared, so reordering them for
    /// readability would silently reorder what the button does.
    var cycled: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}
