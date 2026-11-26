import Foundation
import ActivityKit

/// The Lock Screen and Dynamic Island timer for a nap or a nursing session.
/// Compiled into the app and the widgets extension.
struct TimerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var start: Date
        /// "Left" or "Right" while nursing.
        var detail: String
    }

    /// The log entry's ID, so the app can find and end it.
    var entryID: String
    var kidName: String
    var emoji: String
    /// "asleep" or "nursing".
    var activity: String
    /// The kid's color as 0xRRGGBB.
    var color: Int
}
