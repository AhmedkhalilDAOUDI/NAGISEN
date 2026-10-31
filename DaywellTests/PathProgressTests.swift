import XCTest
@testable import Daywell

final class PathProgressTests: XCTestCase {

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_790_000_000 + Double(offset) * 86_400)
    }

    private func lift(_ exercise: String, _ kilograms: Double, _ reps: Int, day offset: Int) -> StrengthRecord {
        StrengthRecord(exercise: exercise, kilograms: kilograms, reps: reps, date: day(offset))
    }

    private func plan(_ questIDs: [String], shuffled: Bool = false) -> ChallengePlan {
        ChallengePlan(title: "Pack", blocks: [], estimatedMinutes: 30, symbol: "bolt",
                      quests: questIDs.map {
                          ChallengeQuest(id: $0, category: "move", title: $0, detail: "", estimatedMinutes: 10, symbol: "bolt")
                      },
                      wasShuffled: shuffled)
    }

    private func quest(_ id: String, on key: String, minutes: Int = 10) -> WorkoutEntry {
        WorkoutEntry(activity: id, minutes: minutes, challengeDayKey: key, challengeID: id)
    }

    // MARK: - Borders

    func testBordersStartAtTheirThresholds() {
        XCTAssertEqual(BorderTier.forPoints(0), .none)
        XCTAssertEqual(BorderTier.forPoints(4), .none)
        XCTAssertEqual(BorderTier.forPoints(5), .washi)
        XCTAssertEqual(BorderTier.forPoints(15), .copper)
        XCTAssertEqual(BorderTier.forPoints(34), .copper)
        XCTAssertEqual(BorderTier.forPoints(35), .silver)
        XCTAssertEqual(BorderTier.forPoints(70), .gold)
        XCTAssertEqual(BorderTier.forPoints(120), .jade)
        XCTAssertEqual(BorderTier.forPoints(5000), .jade)
    }

    func testPointsWeighMilestonesDouble() {
        let progress = PathProgress(finishedPacks: 3, personalRecords: 2, milestones: 4)
        XCTAssertEqual(progress.points, 3 + 2 + 8)
        XCTAssertEqual(progress.tier, .washi)
        XCTAssertEqual(progress.pointsToNext, 2)
    }

    func testProgressToTheNextBorder() {
        XCTAssertEqual(PathProgress(finishedPacks: 10, personalRecords: 0, milestones: 0).fractionToNext, 0.5)
        let top = PathProgress(finishedPacks: 200, personalRecords: 0, milestones: 0)
        XCTAssertEqual(top.tier, .jade)
        XCTAssertNil(top.pointsToNext)
        XCTAssertEqual(top.fractionToNext, 1)
    }

    // MARK: - Personal records

    func testTheFirstLiftIsABaselineNotARecord() {
        XCTAssertEqual(PathProgress.recordCount([lift("Squat", 100, 5, day: 0)]), 0)
    }

    func testHeavierOrMoreRepsAtTheSameWeightCount() {
        let lifts = [lift("Squat", 100, 5, day: 0),
                     lift("Squat", 100, 6, day: 1),   // same weight, more reps
                     lift("Squat", 95, 10, day: 2),   // lighter: not a record
                     lift("Squat", 105, 3, day: 3)]   // heavier
        XCTAssertEqual(PathProgress.recordCount(lifts), 2)
    }

    func testRecordsAreCountedInDateOrderPerExercise() {
        let lifts = [lift("bench", 80, 5, day: 2),
                     lift("Bench", 70, 5, day: 0),     // same exercise, different case
                     lift("Deadlift", 140, 3, day: 1)]
        XCTAssertEqual(PathProgress.recordCount(lifts), 1)
    }

    func testRepeatingABestIsNotARecord() {
        XCTAssertEqual(PathProgress.recordCount([lift("Row", 60, 8, day: 0), lift("Row", 60, 8, day: 1)]), 0)
    }

    // MARK: - Packs and milestones

    func testAPackCountsOnlyWhenEveryQuestIsLogged() {
        let plans = ["2026-10-30": plan(["a", "b"]), "2026-10-31": plan(["c", "d"])]
        let workouts = [quest("a", on: "2026-10-30"), quest("b", on: "2026-10-30"), quest("c", on: "2026-10-31")]
        XCTAssertEqual(Milestones.finishedPackDays(workouts: workouts, plans: plans), ["2026-10-30"])
    }

    func testMilestonesMatchTheWorkoutTrophies() {
        let plans = ["2026-10-30": plan(["a", "b", "c"], shuffled: true)]
        let workouts = ["a", "b", "c"].map { quest($0, on: "2026-10-30", minutes: 40) }
        let milestones = Milestones(workouts: workouts, plans: plans)
        XCTAssertTrue(milestones.firstWorkout)
        XCTAssertTrue(milestones.hundredMinutes)
        XCTAssertTrue(milestones.threeQuests)
        XCTAssertTrue(milestones.shuffledPack)
        XCTAssertFalse(milestones.sevenWorkouts)
        XCTAssertFalse(milestones.fiveHundredMinutes)
        XCTAssertEqual(milestones.earnedCount, 4)
    }

    func testProgressAddsPacksRecordsAndMilestones() {
        let plans = ["2026-10-30": plan(["a"])]
        let workouts = [quest("a", on: "2026-10-30", minutes: 20)]
        let lifts = [lift("Squat", 100, 5, day: 0), lift("Squat", 110, 5, day: 1)]
        let progress = PathProgress(workouts: workouts, plans: plans, lifts: lifts)
        XCTAssertEqual(progress.finishedPacks, 1)
        XCTAssertEqual(progress.personalRecords, 1)
        XCTAssertEqual(progress.milestones, 1)     // first workout only
        XCTAssertEqual(progress.points, 1 + 1 + 2)
    }

    func testNothingLoggedMeansNoBorder() {
        let progress = PathProgress(workouts: [], plans: [:], lifts: [])
        XCTAssertEqual(progress.points, 0)
        XCTAssertEqual(progress.tier, .none)
    }
}
