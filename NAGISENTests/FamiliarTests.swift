import XCTest
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
}
