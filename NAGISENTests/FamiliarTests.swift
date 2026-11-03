import XCTest
import simd
@testable import NAGISEN

final class FamiliarTests: XCTestCase {
    private let week = ["2026-11-03", "2026-11-02", "2026-11-01", "2026-10-31", "2026-10-30", "2026-10-29", "2026-10-28"]

    func testItGrowsWithEveryActiveDayAndNeverLosesAStage() {
        XCTAssertEqual(Familiar.state(activeDays: [], longestStreak: 0, lastWeek: week).stage, .kitten)
        XCTAssertEqual(Familiar.state(activeDays: Set(week), longestStreak: 0, lastWeek: week).stage, .young)
        XCTAssertEqual(Familiar.state(activeDays: [], longestStreak: 30, lastWeek: week).stage, .grown,
                       "a long streak counts, even with today quiet")
        let elder = Familiar.state(activeDays: [], longestStreak: 1568, lastWeek: week)
        XCTAssertEqual(elder.stage, .elder)
        XCTAssertNil(elder.nextStageAt)
        XCTAssertEqual(Familiar.state(activeDays: ["2026-10-01"], longestStreak: 0, lastWeek: week).nextStageAt, 7)
    }

    func testTheLastWeekSetsTheMood() {
        XCTAssertEqual(Familiar.state(activeDays: Set(week.prefix(4)), longestStreak: 0, lastWeek: week).mood, .bright)
        XCTAssertEqual(Familiar.state(activeDays: Set(week.prefix(2)), longestStreak: 0, lastWeek: week).mood, .calm)
        XCTAssertEqual(Familiar.state(activeDays: ["2026-11-03"], longestStreak: 400, lastWeek: week).mood, .resting,
                       "an old streak doesn't keep it awake")
        XCTAssertEqual(Familiar.state(activeDays: ["2026-10-01", "2026-10-02"], longestStreak: 0, lastWeek: week).lastWeek, 0)
    }

    private func walked(_ path: [SIMD2<Float>], from start: SIMD2<Float>, through check: (SIMD2<Float>) -> Bool) -> Bool {
        var last = start
        for point in path {
            for step in 1...40 where check(last + (point - last) * Float(step) / 40) { return true }
            last = point
        }
        return false
    }

    func testKuroWalksAroundTheVerandaNotUnderIt() {
        let map = GardenMap.hideout
        let start = SIMD2<Float>(-1.7, 0.2), goal = SIMD2<Float>(1.7, 0.2)
        let path = map.path(from: start, to: goal)
        XCTAssertEqual(path.last, goal)
        XCTAssertFalse(walked(path, from: start) { abs($0.x) < 1.3 && abs($0.y) < 1.0 }, "never under the boards")
    }

    func testATargetUnderTheVerandaMovesOutToOpenGround() {
        let map = GardenMap.hideout
        let path = map.path(from: SIMD2(-1.7, 1.4), to: SIMD2(0, 0))
        XCTAssertFalse(map.underVeranda(try! XCTUnwrap(path.last)))
    }

    func testKuroGoesAroundThePondAndReachesTheWarmStone() {
        let map = GardenMap.hideout
        let start = SIMD2<Float>(-3.8, -2.4), goal = SIMD2<Float>(-0.05, -2.4)
        let around = map.path(from: start, to: goal)
        let pond = map.pond
        XCTAssertFalse(walked(around, from: start) { simd_length_squared(($0 - pond.centre) / pond.radii) < 1 }, "not through the water")
        XCTAssertEqual(map.path(from: SIMD2(1.7, 1.4), to: SIMD2(2.05, 0.55)).last, SIMD2(2.05, 0.55), "the sun stone itself")
    }
}
