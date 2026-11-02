import ActivityKit
import Foundation

/// What the Lock Screen and Dynamic Island show while an activity is recording.
/// Shared by the app (which starts and updates it) and the widget extension (which draws it).
struct RecordingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Moving time is drawn as a live timer counting from this moment while recording.
        var timerStart: Date
        /// Frozen moving time while paused.
        var pausedSeconds: Double?
        var kilometres: Double
        /// "5:12 /km" or "24.3 km/h", already formatted for the kind of activity.
        var pace: String
        /// Advances with every update; the mark drifts up or down with each one.
        var frame: Int = 0
    }

    var kindName: String
    var symbol: String
}
