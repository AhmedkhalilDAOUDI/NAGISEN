import CoreLocation
import XCTest
@testable import NAGISEN

final class MoveProgressTests: XCTestCase {
    private let degreesPerMeter = 1 / 111_195.0

    /// A run north from the same start, `meters` per step and `seconds` per step.
    private func run(steps: Int, meters: Double = 50, seconds: Double, startOffset: Double = 0) -> RecordedActivity {
        let start = Date(timeIntervalSince1970: 1_790_000_000 + startOffset)
        let points = (0...steps).map { i in
            RecordedActivity.RoutePoint(latitude: 33.5 + Double(i) * meters * degreesPerMeter, longitude: -7.6, altitude: 0,
                                        date: start.addingTimeInterval(Double(i) * seconds), segment: 0)
        }
        return RecordedActivity(kind: .run, start: start, points: points)
    }

    func testASegmentFindsEveryPassAndRanksThem() throws {
        let marked = run(steps: 40, seconds: 15)                       // 5:00 /km
        let segment = try XCTUnwrap(PersonalSegment(name: "Seafront", activity: marked, from: 4, to: 24))   // 1 km
        XCTAssertEqual(segment.length, 1000, accuracy: 15)
        XCTAssertEqual(segment.time(in: marked) ?? 0, 300, accuracy: 20)
        let faster = run(steps: 40, seconds: 12, startOffset: 86_400)  // 4:00 /km
        let efforts = segment.efforts([marked, faster])
        XCTAssertEqual(efforts.count, 2)
        XCTAssertEqual(efforts.first?.activity.id, faster.id, "your fastest pass comes first")
    }

    func testARouteElsewhereNeverMatches() throws {
        let marked = run(steps: 40, seconds: 15)
        let segment = try XCTUnwrap(PersonalSegment(name: "Seafront", activity: marked, from: 4, to: 24))
        var elsewhere = run(steps: 40, seconds: 15)
        for i in elsewhere.points.indices { elsewhere.points[i].longitude += 0.01 }   // ~900 m east
        XCTAssertNil(segment.time(in: elsewhere))
    }

    func testTooShortStretchesAreNotSegments() {
        XCTAssertNil(PersonalSegment(name: "x", activity: run(steps: 40, seconds: 15), from: 0, to: 1))
    }

    func testGoalProgressCountsOnlyTheRightPeriodAndKind() {
        let week = run(steps: 100, seconds: 15)                         // 5 km
        var ride = run(steps: 100, seconds: 6); ride.kind = .ride
        let distance = ActivityGoal(measure: .kilometres, period: .week, target: 20, kind: .run)
        XCTAssertEqual(distance.progress([week, ride], on: week.start), 5, accuracy: 0.1)
        let count = ActivityGoal(measure: .activities, period: .week, target: 3, kind: nil)
        XCTAssertEqual(count.progress([week, ride], on: week.start), 2)
    }

    func testFitnessRisesSlowlyAndFatigueQuickly() {
        let today = Date(timeIntervalSince1970: 1_790_000_000)
        let workouts = (0..<7).map { WorkoutEntry(date: today.addingTimeInterval(-Double($0) * 86_400), activity: "Run", minutes: 60) }
        let days = TrainingLoad.history(workouts, days: 30, until: today)
        XCTAssertEqual(days.count, 30)
        let last = days.last!
        XCTAssertGreaterThan(last.fatigue, last.fitness, "a hard week shows as fatigue before fitness")
        XCTAssertTrue(TrainingLoad.formText(last).hasPrefix("Tired"))
        XCTAssertEqual(TrainingLoad.history([], days: 10, until: today).last?.fitness, 0)
    }

    func testTheWeightCardShowsTheChangeButNeverTheWeight() throws {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let entries = [WeightEntry(date: start, kilograms: 92.4), WeightEntry(date: start.addingTimeInterval(86_400 * 30), kilograms: 89.1)]
        let card = try XCTUnwrap(ShareCards.weight(entries))
        XCTAssertTrue(card.value.contains("3.3"))
        XCTAssertTrue(card.value.hasPrefix("−"))
        let text = [card.kicker, card.headline, card.value, card.caption].joined(separator: " ")
        XCTAssertFalse(text.contains("92") || text.contains("89"), "the card must not reveal the weight itself")
        XCTAssertNil(ShareCards.weight([entries[0]]), "one weigh-in has no change to share")
    }

    func testSavingARouteFromAnActivityThinsIt() {
        let route = SavedRoute(name: "Loop", activity: run(steps: 200, meters: 5, seconds: 2))
        XCTAssertLessThan(route.coordinates.count, 60)
        XCTAssertEqual(route.distance, 1000, accuracy: 40)
    }
}
