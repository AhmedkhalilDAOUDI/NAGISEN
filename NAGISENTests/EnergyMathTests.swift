import XCTest
@testable import NAGISEN

final class EnergyMathTests: XCTestCase {
    func testEachQuarterKiloAWeekIsAbout275Calories() {
        let maintain = EnergyMath.dailyCalories(weight: 90, height: 182, age: 30, equation: .male, activity: .veryActive, weeklyRate: 0)
        let lose = EnergyMath.dailyCalories(weight: 90, height: 182, age: 30, equation: .male, activity: .veryActive, weeklyRate: -0.25)
        XCTAssertEqual(Double(maintain - lose), 275, accuracy: 25)
    }

    func testGoalDateFollowsTheRateAndIgnoresTheWrongDirection() {
        let start = Date(timeIntervalSince1970: 0)
        let date = WeeklyRate.goalDate(weight: 80, target: 78, rate: -0.5, from: start)
        XCTAssertEqual(date.map { Calendar.current.dateComponents([.day], from: start, to: $0).day }, 28)
        XCTAssertNil(WeeklyRate.goalDate(weight: 80, target: 78, rate: 0.25, from: start))
        XCTAssertNil(WeeklyRate.goalDate(weight: 80, target: nil, rate: -0.5, from: start))
    }

    func testRateChoicesSwitchToGainingWhenTheTargetIsHigher() {
        XCTAssertEqual(WeeklyRate.options(weight: 70, target: 75), [0, 0.25, 0.5])
        XCTAssertEqual(WeeklyRate.options(weight: 80, target: 75).last, -1)
    }

    func testACustomBudgetPredictsTheDailyAndWeeklyChange() {
        let projection = WeightProjection(maintenance: 2800, calories: 2030, weight: 85, target: 80)
        XCTAssertEqual(projection.dailyChange, -0.1, accuracy: 0.0001)
        XCTAssertEqual(projection.weeklyChange, -0.7, accuracy: 0.0001)
        let week = projection.forecast(days: 7)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.last!.kilograms, 84.3, accuracy: 0.0001)
        XCTAssertNotNil(projection.goalDate)
        XCTAssertNil(WeightProjection(maintenance: 2000, calories: 2600, weight: 85, target: 80).goalDate,
                     "eating above maintenance never reaches a lower target")
    }
}
