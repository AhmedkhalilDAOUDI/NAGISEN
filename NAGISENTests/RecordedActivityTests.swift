import CoreLocation
import XCTest
@testable import NAGISEN

final class RecordedActivityTests: XCTestCase {
    /// A straight line north: `meters` apart, `seconds` apart, starting at a fixed time.
    private func track(count: Int, meters: Double, seconds: Double, segment: (Int) -> Int = { _ in 0 },
                       altitude: (Int) -> Double = { _ in 0 }) -> RecordedActivity {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let degreesPerMeter = 1 / 111_195.0
        let points = (0..<count).map { i in
            RecordedActivity.RoutePoint(latitude: 33.5 + Double(i) * meters * degreesPerMeter, longitude: -7.6,
                                        altitude: altitude(i), date: start.addingTimeInterval(Double(i) * seconds),
                                        segment: segment(i))
        }
        return RecordedActivity(kind: .run, start: start, points: points)
    }

    func testDistanceAndPaceOfAKnownTrack() {
        let run = track(count: 101, meters: 50, seconds: 15)   // 5 km at 5:00 /km
        XCTAssertEqual(run.distance, 5000, accuracy: 25)
        XCTAssertEqual(run.movingSeconds, 1500)
        XCTAssertEqual(run.pace ?? 0, 300, accuracy: 3)
        XCTAssertEqual(RecordedActivity.paceText(300), "5:00")
    }

    func testSplitsCoverEveryKilometreAndTheRest() {
        let run = track(count: 51, meters: 50, seconds: 15)    // 2.5 km
        let splits = run.splits
        XCTAssertEqual(splits.count, 3)
        XCTAssertEqual(splits[0].seconds, 300, accuracy: 3)
        XCTAssertEqual(splits[2].km, 0.5, accuracy: 0.01)
    }

    func testPausedStretchesAreNeitherDistanceNorTime() {
        // Points 0-10 in segment 0, then a 10-minute pause, then points 11-20 in segment 1.
        var run = track(count: 21, meters: 50, seconds: 15, segment: { $0 > 10 ? 1 : 0 })
        for i in 11..<21 { run.points[i].date.addTimeInterval(600) }
        // 19 steps of 50 m with one skipped across the pause: 950 m in 285 s.
        XCTAssertEqual(run.distance, 950, accuracy: 10, "the 50 m across the pause is not counted")
        XCTAssertEqual(run.movingSeconds, 285)
    }

    func testBestOneKilometreFindsTheFastestStretch() {
        // Slow first km (6:00), then 1.5 km fast (4:00 /km).
        let start = Date(timeIntervalSince1970: 0)
        let degreesPerMeter = 1 / 111_195.0
        var points: [RecordedActivity.RoutePoint] = []
        var time = 0.0
        for i in 0...50 {
            points.append(.init(latitude: Double(i) * 50 * degreesPerMeter, longitude: 0, altitude: 0,
                                date: start.addingTimeInterval(time), segment: 0))
            time += i < 20 ? 18 : 12
        }
        let run = RecordedActivity(kind: .run, start: start, points: points)
        XCTAssertEqual(run.bestEffort(meters: 1000) ?? 0, 240, accuracy: 6)
        XCTAssertNil(run.bestEffort(meters: 5000))
    }

    func testAltitudeJitterIsNotClimb() {
        let jitter = track(count: 100, meters: 10, seconds: 4, altitude: { $0 % 2 == 0 ? 100 : 101.5 })
        XCTAssertEqual(jitter.elevationGain, 0)
        let hill = track(count: 11, meters: 10, seconds: 4, altitude: { Double($0) * 3 })
        XCTAssertEqual(hill.elevationGain, 30, accuracy: 0.01)
    }

    func testBadGPSFixesAreDropped() {
        let base = CLLocation(coordinate: .init(latitude: 33.5, longitude: -7.6), altitude: 0,
                              horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date(timeIntervalSince1970: 0))
        let vague = CLLocation(coordinate: base.coordinate, altitude: 0, horizontalAccuracy: 80, verticalAccuracy: 5,
                               timestamp: Date(timeIntervalSince1970: 5))
        let jump = CLLocation(coordinate: .init(latitude: 33.51, longitude: -7.6), altitude: 0, horizontalAccuracy: 5,
                              verticalAccuracy: 5, timestamp: Date(timeIntervalSince1970: 5))   // ~1.1 km in 5 s
        let step = CLLocation(coordinate: .init(latitude: 33.50005, longitude: -7.6), altitude: 0, horizontalAccuracy: 5,
                              verticalAccuracy: 5, timestamp: Date(timeIntervalSince1970: 5))
        XCTAssertFalse(RecordedActivity.accepts(vague, after: base, kind: .run))
        XCTAssertFalse(RecordedActivity.accepts(jump, after: base, kind: .run))
        XCTAssertTrue(RecordedActivity.accepts(step, after: base, kind: .run))
    }

    func testWeeklyTotalsRespectTheWeekBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 9))!
        var thisWeek = track(count: 101, meters: 50, seconds: 15); thisWeek.start = monday
        var lastWeek = track(count: 41, meters: 50, seconds: 15)
        lastWeek.start = calendar.date(byAdding: .day, value: -1, to: monday)!
        let weeks = ActivityRecords.weeklyKilometres([thisWeek, lastWeek], weeks: 2, until: monday, calendar: calendar)
        XCTAssertEqual(weeks.count, 2)
        XCTAssertEqual(weeks[0].km, 2, accuracy: 0.05)
        XCTAssertEqual(weeks[1].km, 5, accuracy: 0.05)
    }
}
