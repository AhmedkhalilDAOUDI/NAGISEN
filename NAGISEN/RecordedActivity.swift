import CoreLocation
import Foundation

/// An outdoor activity recorded with GPS: the route, and everything worked out from it.
struct RecordedActivity: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case run, walk, ride, hike
        var id: String { rawValue }

        var name: String {
            switch self {
            case .run: String(localized: "Run")
            case .walk: String(localized: "Walk")
            case .ride: String(localized: "Ride")
            case .hike: String(localized: "Hike")
            }
        }

        var symbol: String {
            switch self {
            case .run: "figure.run"
            case .walk: "figure.walk"
            case .ride: "figure.outdoor.cycle"
            case .hike: "figure.hiking"
            }
        }

        /// Rides read as speed; everything on foot reads as pace.
        var showsSpeed: Bool { self == .ride }
        /// Anything faster is a GPS jump, not the person.
        var maxSpeed: Double { self == .ride ? 30 : 15 }
    }

    struct RoutePoint: Codable, Equatable {
        var latitude: Double
        var longitude: Double
        var altitude: Double
        var date: Date
        /// Increases after each pause, so the line and the moving time skip the paused stretch.
        var segment: Int

        var location: CLLocation {
            CLLocation(coordinate: .init(latitude: latitude, longitude: longitude), altitude: altitude,
                       horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: date)
        }
    }

    var id = UUID()
    var kind: Kind
    var start: Date
    var points: [RoutePoint] = []
    var workoutID: UUID? = nil
    var healthUUID: UUID? = nil
}

// MARK: - Measures

extension RecordedActivity {
    /// The point-to-point steps inside each segment: no distance is counted across a pause.
    private var steps: [(distance: Double, seconds: Double, climb: Double, end: RoutePoint)] {
        zip(points, points.dropFirst()).compactMap { a, b in
            guard a.segment == b.segment else { return nil }
            return (b.location.distance(from: a.location), b.date.timeIntervalSince(a.date), b.altitude - a.altitude, b)
        }
    }

    var distance: Double { steps.reduce(0) { $0 + $1.distance } }
    var movingSeconds: Double { steps.reduce(0) { $0 + $1.seconds } }
    var end: Date { points.last?.date ?? start }

    /// Seconds per km, nil until there is a real distance.
    var pace: Double? { distance > 50 ? movingSeconds / (distance / 1000) : nil }
    var speedKmh: Double? { movingSeconds > 0 ? distance / movingSeconds * 3.6 : nil }

    /// Climb summed after smoothing, so the phone's altitude jitter does not add up to fake hills.
    var elevationGain: Double {
        var gain = 0.0
        var anchor: Double?
        for point in points {
            guard let base = anchor else { anchor = point.altitude; continue }
            let change = point.altitude - base
            if change >= 2 { gain += change; anchor = point.altitude }
            else if change <= -2 { anchor = point.altitude }
        }
        return gain
    }

    /// Seconds for each whole km, then the leftover part (with its length) if there is one.
    var splits: [(km: Double, seconds: Double)] {
        var result: [(Double, Double)] = []
        var carried = 0.0, seconds = 0.0
        for step in steps where step.distance > 0 {
            var distance = step.distance
            var time = step.seconds
            while carried + distance >= 1000 {
                let needed = 1000 - carried
                let share = time * needed / distance
                result.append((1, seconds + share))
                distance -= needed; time -= share
                carried = 0; seconds = 0
            }
            carried += distance; seconds += time
        }
        if carried >= 50 { result.append((carried / 1000, seconds)) }
        return result
    }

    /// The fastest time to cover `meters` anywhere in the activity, or nil if it was shorter.
    func bestEffort(meters: Double) -> Double? {
        let moves = steps
        guard moves.reduce(0, { $0 + $1.distance }) >= meters else { return nil }
        var best = Double.infinity
        var startIndex = 0, windowDistance = 0.0, windowTime = 0.0
        for move in moves {
            windowDistance += move.distance; windowTime += move.seconds
            while startIndex < moves.count, windowDistance - moves[startIndex].distance >= meters {
                windowDistance -= moves[startIndex].distance; windowTime -= moves[startIndex].seconds
                startIndex += 1
            }
            if windowDistance >= meters {
                // Scale the window down to exactly `meters` at its average pace.
                best = min(best, windowTime * meters / windowDistance)
            }
        }
        return best.isFinite ? best : nil
    }

    /// Whether a new GPS fix should join the route: precise enough, and not a jump.
    static func accepts(_ location: CLLocation, after last: CLLocation?, kind: Kind) -> Bool {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 25 else { return false }
        guard let last else { return true }
        let seconds = location.timestamp.timeIntervalSince(last.timestamp)
        guard seconds > 0 else { return false }
        return location.distance(from: last) / seconds <= kind.maxSpeed
    }

    var summary: String {
        let km = (distance / 1000).formatted(.number.precision(.fractionLength(2)))
        if kind.showsSpeed, let speed = speedKmh {
            return "\(km) km · \(speed.formatted(.number.precision(.fractionLength(1)))) km/h"
        }
        return pace.map { "\(km) km · \(Self.paceText($0)) /km" } ?? "\(km) km"
    }

    static func paceText(_ secondsPerKm: Double) -> String {
        let total = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func durationText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Records and totals

enum ActivityRecords {
    static let efforts: [(name: String, meters: Double)] = [
        (String(localized: "1 km"), 1000), (String(localized: "5 km"), 5000),
        (String(localized: "10 km"), 10_000), (String(localized: "Half marathon"), 21_097.5),
    ]

    /// Fastest time for each standard distance across all runs, with the activity it came from.
    static func bestEfforts(_ activities: [RecordedActivity]) -> [(name: String, seconds: Double, activity: RecordedActivity)] {
        efforts.compactMap { effort in
            activities.filter { $0.kind == .run }
                .compactMap { activity in activity.bestEffort(meters: effort.meters).map { (activity, $0) } }
                .min { $0.1 < $1.1 }
                .map { (effort.name, $0.1, $0.0) }
        }
    }

    static func longest(_ activities: [RecordedActivity], kind: RecordedActivity.Kind) -> RecordedActivity? {
        activities.filter { $0.kind == kind }.max { $0.distance < $1.distance }
    }

    /// Kilometres in the calendar week (or month) containing `date`.
    static func kilometres(_ activities: [RecordedActivity], in component: Calendar.Component,
                           of date: Date, calendar: Calendar = .current) -> Double {
        activities.filter { calendar.isDate($0.start, equalTo: date, toGranularity: component) }
            .reduce(0) { $0 + $1.distance } / 1000
    }

    /// The last `weeks` weeks, oldest first, as (week start, km).
    static func weeklyKilometres(_ activities: [RecordedActivity], weeks: Int, until date: Date = .now,
                                 calendar: Calendar = .current) -> [(week: Date, km: Double)] {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { return [] }
        return (0..<weeks).reversed().compactMap { offset in
            calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek).map {
                ($0, kilometres(activities, in: .weekOfYear, of: $0, calendar: calendar))
            }
        }
    }
}
