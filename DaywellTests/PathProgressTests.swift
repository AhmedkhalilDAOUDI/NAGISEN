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
        XCTAssertEqual(BorderTier.forPoints(9), .none)
        XCTAssertEqual(BorderTier.forPoints(10), .washi)
        XCTAssertEqual(BorderTier.forPoints(30), .hinoki)
        XCTAssertEqual(BorderTier.forPoints(99), .copper)
        XCTAssertEqual(BorderTier.forPoints(100), .bronze)
        XCTAssertEqual(BorderTier.forPoints(250), .gold)
        XCTAssertEqual(BorderTier.forPoints(680), .jade)
        XCTAssertEqual(BorderTier.forPoints(1200), .kintsugi)
        XCTAssertEqual(BorderTier.forPoints(50_000), .kintsugi)
    }

    func testThresholdsRiseWithEveryBorder() {
        let thresholds = BorderTier.allCases.map(\.threshold)
        XCTAssertEqual(thresholds, thresholds.sorted())
        XCTAssertEqual(Set(thresholds).count, thresholds.count)
    }

    func testOnlyTheTopBordersShimmer() {
        XCTAssertFalse(BorderTier.gold.shimmers)
        XCTAssertTrue(BorderTier.jade.shimmers)
        XCTAssertTrue(BorderTier.kintsugi.shimmers)
    }

    func testEverySourceAddsItsPoints() {
        let progress = PathProgress(checkedDays: 30, goalDays: 20, weekStreaks: 4, monthStreaks: 1,
                                    finishedPacks: 3, personalRecords: 2, milestones: 4)
        XCTAssertEqual(progress.points, 30 + 20 + 4 * 5 + 1 * 20 + 3 + 2 + 4 * 2)
        XCTAssertEqual(progress.tier, .bronze)
        XCTAssertEqual(progress.pointsToNext, 160 - 103)
    }

    func testProgressToTheNextBorder() {
        XCTAssertEqual(PathProgress(checkedDays: 20).fractionToNext, 0.5)
        let top = PathProgress(checkedDays: 2000)
        XCTAssertEqual(top.tier, .kintsugi)
        XCTAssertNil(top.pointsToNext)
        XCTAssertEqual(top.fractionToNext, 1)
    }

    // MARK: - Streaks

    func testRunsOfConsecutiveDays() {
        let keys: Set<String> = ["2026-10-01", "2026-10-02", "2026-10-03", "2026-10-05", "2026-10-31", "2026-11-01"]
        XCTAssertEqual(PathProgress.streakRuns(keys).sorted(), [1, 2, 3])
    }

    func testEverySevenDaysInARowIsAWeekStreak() {
        let thirty = (1...30).map { String(format: "2026-09-%02d", $0) }
        let progress = PathProgress(workouts: [], plans: [:], lifts: [], checkedDayKeys: Set(thirty))
        XCTAssertEqual(progress.checkedDays, 30)
        XCTAssertEqual(progress.weekStreaks, 4)
        XCTAssertEqual(progress.monthStreaks, 1)
    }

    func testABrokenStreakStartsCountingAgain() {
        let first = (1...6).map { String(format: "2026-09-%02d", $0) }
        let second = (8...14).map { String(format: "2026-09-%02d", $0) }
        let progress = PathProgress(workouts: [], plans: [:], lifts: [], checkedDayKeys: Set(first + second))
        XCTAssertEqual(progress.weekStreaks, 1)
        XCTAssertEqual(progress.monthStreaks, 0)
    }

    // MARK: - Calorie goal

    private func entry(_ calories: Int, on offset: Int, imported: Bool = false) -> DiaryEntry {
        DiaryEntry(food: Food(name: "Meal", brand: "", serving: "1 plate", calories: calories, protein: 0, carbs: 0, fat: 0),
                   meal: .lunch, servings: 1, date: day(offset),
                   importFingerprint: imported ? "loseit-\(offset)" : nil)
    }

    func testAGoalDayLandsWithinTenPercent() {
        let entries = [entry(1000, on: 0), entry(950, on: 0),   // 1950 of 2000: hit
                       entry(2300, on: 1),                      // 15% over: missed
                       entry(1700, on: 2),                      // 15% under: missed
                       entry(2200, on: 3)]                      // exactly 10% over: hit
        XCTAssertEqual(PathProgress.goalDayCount(entries: entries, goal: { _ in 2000 }), 2)
    }

    func testImportedFoodDoesNotEarnGoalDays() {
        let entries = [entry(2000, on: 0, imported: true), entry(2000, on: 1)]
        XCTAssertEqual(PathProgress.goalDayCount(entries: entries, goal: { _ in 2000 }), 1)
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

    func testProgressAddsPacksRecordsAndMilestonesFromTheStoreData() {
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

    // MARK: - Reminders

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Africa/Casablanca")!
        return calendar
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: hour, minute: minute))!
    }

    func testAnUncheckedDayGetsTonightsReminderAndTheNextTwo() {
        let dates = Reminders.streakReminderDates(now: at(15), todayChecked: false, hour: 20, minute: 30,
                                                  calendar: calendar)
        XCTAssertEqual(dates.count, 3)
        XCTAssertEqual(dates.first, at(20, 30))
    }

    func testACheckedDaySkipsTonight() {
        let dates = Reminders.streakReminderDates(now: at(15), todayChecked: true, hour: 20, minute: 30,
                                                  calendar: calendar)
        XCTAssertEqual(dates.count, 2)
        XCTAssertGreaterThan(dates[0], at(23, 59))
    }

    func testTonightIsSkippedOnceTheTimeHasPassed() {
        let dates = Reminders.streakReminderDates(now: at(21), todayChecked: false, hour: 20, minute: 30,
                                                  calendar: calendar)
        XCTAssertEqual(dates.count, 2)
    }

    func testANudgeComesWhenCloseToTheNextBorder() {
        XCTAssertEqual(Reminders.borderToNudge(PathProgress(checkedDays: 26), lastNudged: nil), .hinoki)
        XCTAssertNil(Reminders.borderToNudge(PathProgress(checkedDays: 20), lastNudged: nil), "10 points away")
    }

    func testEachBorderIsNudgedOnlyOnce() {
        XCTAssertNil(Reminders.borderToNudge(PathProgress(checkedDays: 26),
                                             lastNudged: BorderTier.hinoki.rawValue))
    }

    func testNoNudgeAfterTheLastBorder() {
        XCTAssertNil(Reminders.borderToNudge(PathProgress(checkedDays: 5000), lastNudged: nil))
    }

    // MARK: - Workout split labels

    func testLongSplitDaysAreShortenedAndPhrasesKept() {
        XCTAssertEqual(WorkoutMusicView.shortFocus("Conditioning"), "Cond.")
        XCTAssertEqual(WorkoutMusicView.shortFocus("Full Body"), "Full Body")
        XCTAssertEqual(WorkoutMusicView.shortFocus("Boxing"), "Boxing")
        XCTAssertEqual(WorkoutMusicView.shortFocus("Upper Body Strength"), "Upper Body Strength")
    }

    // MARK: - Coach replies

    func testCoachRepliesRenderMarkdownAndKeepLineBreaks() {
        let text = DeepSeekChatView.rendered("Go with **eggs**.\n\nThen *rest*.")
        XCTAssertEqual(String(text.characters), "Go with eggs.\n\nThen rest.")
        let bold = text.runs.first { String(text[$0.range].characters) == "eggs" }
        XCTAssertEqual(bold?.inlinePresentationIntent, .stronglyEmphasized)
    }

    func testBrokenMarkdownFallsBackToPlainText() {
        XCTAssertEqual(String(DeepSeekChatView.rendered("5 * 3 = **15").characters).isEmpty, false)
    }

    // MARK: - Usual foods

    private func logged(_ name: String, day offset: Int) -> DiaryEntry {
        DiaryEntry(food: Food(name: name, brand: "", serving: "1 serving", calories: 100, protein: 0, carbs: 0, fat: 0),
                   meal: .lunch, servings: 1, date: day(offset))
    }

    func testUsualFoodsAreTheMostLoggedFirst() {
        let entries = [logged("Oats", day: 0), logged("Oats", day: 1), logged("Oats", day: 2),
                       logged("Eggs", day: 0), logged("Eggs", day: 3),
                       logged("Tea", day: 5)]
        XCTAssertEqual(NutritionStore.frequentFoods(in: entries, limit: 10).map(\.name), ["Oats", "Eggs", "Tea"])
    }

    func testTiesGoToTheMostRecentlyLogged() {
        let entries = [logged("Rice", day: 1), logged("Dates", day: 4)]
        XCTAssertEqual(NutritionStore.frequentFoods(in: entries, limit: 10).map(\.name), ["Dates", "Rice"])
    }

    func testTheSameFoodInDifferentCaseCountsOnce() {
        let entries = [logged("Skyr", day: 0), logged("skyr", day: 1), logged("Kefir", day: 2)]
        let usual = NutritionStore.frequentFoods(in: entries, limit: 10)
        XCTAssertEqual(usual.count, 2)
        XCTAssertEqual(usual.first?.name.lowercased(), "skyr")
    }

    func testRemovedQuickPicksStayHiddenAndTheLimitHolds() {
        let entries = [logged("Oats", day: 0), logged("Oats", day: 1), logged("Eggs", day: 2), logged("Tea", day: 3)]
        let hidden: Set<String> = [NutritionStore.foodKey(entries[0].food)]
        XCTAssertEqual(NutritionStore.frequentFoods(in: entries, limit: 1, excluding: hidden).map(\.name), ["Tea"])
    }

    func testNoLogsMeansNoUsualFoods() {
        XCTAssertTrue(NutritionStore.frequentFoods(in: [], limit: 10).isEmpty)
    }
}
