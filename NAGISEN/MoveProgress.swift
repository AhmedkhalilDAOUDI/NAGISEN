import CoreLocation
import Foundation

/// A coordinate that can be stored and backed up.
struct RouteCoordinate: Codable, Equatable, Hashable {
    var latitude: Double
    var longitude: Double

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

/// A way to follow: drawn on the map, or kept from a past activity.
struct SavedRoute: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var coordinates: [RouteCoordinate]
    var created = Date.now

    var distance: Double {
        zip(coordinates, coordinates.dropFirst()).reduce(0) { $0 + $1.1.location.distance(from: $1.0.location) }
    }

    init(name: String, coordinates: [RouteCoordinate]) {
        self.name = name
        self.coordinates = coordinates
    }

    /// Keeps a past activity's way, thinned to one point every ~20 m so it stays light.
    init(name: String, activity: RecordedActivity) {
        var kept: [RouteCoordinate] = []
        for point in activity.points {
            let next = RouteCoordinate(latitude: point.latitude, longitude: point.longitude)
            if let last = kept.last, last.location.distance(from: next.location) < 20 { continue }
            kept.append(next)
        }
        self.init(name: name, coordinates: kept)
    }
}

/// A stretch you mark yourself. Every time an activity passes through it, its time is kept,
/// and you only ever race your own times.
struct PersonalSegment: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var start: RouteCoordinate
    var end: RouteCoordinate
    /// The length along the way it was marked on.
    var length: Double

    /// How close a route must come to the start and end marks to count as passing through.
    static let tolerance: Double = 30

    /// Seconds for the fastest pass through this segment in an activity, or nil if it never passed.
    /// A pass starts near the start mark, ends near the end mark, and covers about the same length.
    func time(in activity: RecordedActivity) -> Double? {
        let points = activity.points
        var best: Double?
        var index = 0
        while index < points.count {
            guard points[index].location.distance(from: start.location) <= Self.tolerance else { index += 1; continue }
            var covered = 0.0
            var j = index + 1
            while j < points.count, points[j].segment == points[j - 1].segment, covered <= length * 1.4 {
                covered += points[j].location.distance(from: points[j - 1].location)
                if points[j].location.distance(from: end.location) <= Self.tolerance, covered >= length * 0.7 {
                    let seconds = points[j].date.timeIntervalSince(points[index].date)
                    best = min(best ?? .infinity, seconds)
                    break
                }
                j += 1
            }
            index += 1
        }
        return best
    }

    /// Every pass across all activities, fastest first.
    func efforts(_ activities: [RecordedActivity]) -> [(activity: RecordedActivity, seconds: Double)] {
        activities.compactMap { activity in time(in: activity).map { (activity, $0) } }.sorted { $0.seconds < $1.seconds }
    }

    /// Marks the stretch of an activity between two route points.
    init?(name: String, activity: RecordedActivity, from first: Int, to last: Int) {
        let points = activity.points
        guard first >= 0, last < points.count, last > first else { return nil }
        let length = zip(points[first...last], points[first...last].dropFirst())
            .reduce(0) { $0 + $1.1.location.distance(from: $1.0.location) }
        guard length >= 100 else { return nil }
        self.name = name
        self.start = RouteCoordinate(latitude: points[first].latitude, longitude: points[first].longitude)
        self.end = RouteCoordinate(latitude: points[last].latitude, longitude: points[last].longitude)
        self.length = length
    }
}

/// A target for a week or a month: a distance, or a number of activities.
struct ActivityGoal: Codable, Identifiable, Equatable {
    enum Measure: String, Codable, CaseIterable { case kilometres, activities }
    enum Period: String, Codable, CaseIterable { case week, month }

    var id = UUID()
    var measure: Measure
    var period: Period
    var target: Double
    /// Nil counts every kind.
    var kind: RecordedActivity.Kind?

    func progress(_ activities: [RecordedActivity], on date: Date = .now, calendar: Calendar = .current) -> Double {
        let component: Calendar.Component = period == .week ? .weekOfYear : .month
        let inPeriod = activities.filter {
            calendar.isDate($0.start, equalTo: date, toGranularity: component) && (kind == nil || $0.kind == kind)
        }
        return measure == .kilometres ? inPeriod.reduce(0) { $0 + $1.distance } / 1000 : Double(inPeriod.count)
    }

    var title: String {
        let what = kind?.name.lowercased() ?? String(localized: "activity")
        let amount = target.formatted(.number.precision(.fractionLength(0...1)))
        let span = period == .week ? String(localized: "a week") : String(localized: "a month")
        return measure == .kilometres ? String(localized: "\(amount) km of \(what) \(span)")
            : String(localized: "\(amount) × \(what) \(span)")
    }
}

/// Training load from every logged workout: effort per day, then a long average (fitness),
/// a short average (fatigue) and the gap between them (form).
enum TrainingLoad {
    /// Effort points for one workout: minutes times how hard that kind of work usually is.
    /// With an average heart rate, intensity comes from it instead.
    static func load(minutes: Int, activity: String, averageHeartRate: Int? = nil, age: Int? = nil) -> Double {
        if let averageHeartRate, let age, age > 0 {
            let reserve = Double(averageHeartRate) / Double(220 - age)
            return Double(minutes) * max(0.3, min(reserve, 1.1)) * 1.2
        }
        let name = activity.lowercased()
        let intensity: Double =
            name.contains("walk") ? 0.45 :
            name.contains("hike") ? 0.65 :
            name.contains("ride") || name.contains("cycl") ? 0.7 :
            name.contains("run") || name.contains("cardio") ? 0.85 :
            name.contains("box") ? 0.85 :
            name.contains("strength") || name.contains("body") || name.contains("calisth") ? 0.7 : 0.6
        return Double(minutes) * intensity
    }

    struct Day: Equatable { var date: Date; var load: Double; var fitness: Double; var fatigue: Double }

    /// One entry per day for the last `days` days, warmed up on the 42 days before so the curve starts settled.
    static func history(_ workouts: [WorkoutEntry], days: Int, until end: Date = .now,
                        calendar: Calendar = .current) -> [Day] {
        let today = calendar.startOfDay(for: end)
        guard let first = calendar.date(byAdding: .day, value: -(days + 41), to: today) else { return [] }
        var perDay: [Date: Double] = [:]
        for workout in workouts where workout.date >= first {
            perDay[calendar.startOfDay(for: workout.date), default: 0] += load(minutes: workout.minutes, activity: workout.activity)
        }
        var fitness = 0.0, fatigue = 0.0
        var result: [Day] = []
        var day = first
        while day <= today {
            let value = perDay[day] ?? 0
            fitness += (value - fitness) / 42
            fatigue += (value - fatigue) / 7
            result.append(Day(date: day, load: value, fitness: fitness, fatigue: fatigue))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return Array(result.suffix(days))
    }

    /// Plain words for fitness minus fatigue.
    static func formText(_ day: Day) -> String {
        let form = day.fitness - day.fatigue
        if day.fitness < 1 && day.fatigue < 1 { return String(localized: "Log a few workouts to see your trend.") }
        if form < -10 { return String(localized: "Tired: you've done more than usual lately. A lighter day helps.") }
        if form > 5 { return String(localized: "Fresh: rested and ready for a hard day.") }
        return String(localized: "Building: a steady load you can keep.")
    }
}
