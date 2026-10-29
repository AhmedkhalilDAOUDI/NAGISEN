import XCTest
@testable import Daywell

final class StreakLedgerTests: XCTestCase {
    private var casablanca: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Africa/Casablanca")!
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int,
                     calendar: Calendar? = nil) -> Date {
        let calendar = calendar ?? casablanca
        return calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    /// A pre-v3 record: the achievement lives in the anchor, not in the diary.
    private func legacy(count: Int = 1563, end: String = "2026-10-29",
                        version: Int = 2) -> LegacyStreak {
        LegacyStreak(source: "Lose It!", count: count, lastConfirmedDayKey: end,
                     timeZoneIdentifier: "Africa/Casablanca", migrationVersion: version)
    }

    /// A v3 record: every day of the achievement is a real completed day in the diary.
    private func marks(count: Int = 1563, end: String = "2026-10-28") -> [String] {
        legacy(count: count, end: end, version: 3).dayKeys(calendar: casablanca)
    }

    private func snapshot(completed: [String],
                          legacy: LegacyStreak?,
                          viewed: Date,
                          today: Date,
                          calendar: Calendar? = nil,
                          longest: Int = 0) -> StreakSnapshot {
        StreakEngine.snapshot(completedDays: Set(completed), legacy: legacy,
                              viewedDay: viewed, today: today,
                              calendar: calendar ?? casablanca, recordedLongest: longest)
    }

    // MARK: - Materialised achievement (v3)

    func testEveryAchievementDayIsARealMark() {
        let markList = marks()
        XCTAssertEqual(markList.count, 1563)
        XCTAssertEqual(markList.last, "2026-10-28")
        XCTAssertEqual(markList.first, StreakEngine.dayKey(
            for: casablanca.date(byAdding: .day, value: -1562, to: day(2026, 10, 28))!,
            calendar: casablanca))
    }

    func testMaterialisedRunReadsTheFullAchievement() {
        let today = day(2026, 10, 29)
        let result = snapshot(completed: marks(), legacy: legacy(end: "2026-10-28", version: 3),
                              viewed: today, today: today)
        XCTAssertEqual(result.activeStreak, 1563)
        XCTAssertEqual(result.longestStreak, 1563)
    }

    func testFinishingTodayAddsADayToTheMaterialisedRun() {
        let today = day(2026, 10, 29)
        let result = snapshot(completed: marks() + ["2026-10-29"],
                              legacy: legacy(end: "2026-10-28", version: 3),
                              viewed: today, today: today)
        XCTAssertEqual(result.activeStreak, 1564)
    }

    func testUntickingYesterdayEndsTheRunAtToday() {
        let today = day(2026, 10, 29)
        let completed = marks().filter { $0 != "2026-10-28" } + ["2026-10-29"]
        let result = snapshot(completed: completed, legacy: legacy(end: "2026-10-28", version: 3),
                              viewed: today, today: today)
        XCTAssertEqual(result.activeStreak, 1, "the run broke yesterday, so only today counts")
        XCTAssertEqual(result.longestStreak, 1563, "the historical best is untouched")
    }

    func testUntickingInsideTheRunEndsAtTheGap() {
        let today = day(2026, 10, 29)
        let completed = marks().filter { $0 != "2026-10-27" } + ["2026-10-28", "2026-10-29"]
        let result = snapshot(completed: completed, legacy: legacy(end: "2026-10-28", version: 3),
                              viewed: today, today: today)
        XCTAssertEqual(result.activeStreak, 2, "27 Oct broke it; 28 and 29 remain")
    }

    func testMaterialisedHistoryMatchesTheRun() {
        let end = day(2026, 10, 28)
        let oct27 = day(2026, 10, 27)
        let hundredBack = casablanca.date(byAdding: .day, value: -100, to: end)!
        let inside = snapshot(completed: marks(), legacy: legacy(end: "2026-10-28", version: 3),
                              viewed: oct27, today: end)
        XCTAssertEqual(inside.activeStreak, 1562)
        let back = snapshot(completed: marks(), legacy: legacy(end: "2026-10-28", version: 3),
                            viewed: hundredBack, today: end)
        XCTAssertEqual(back.activeStreak, 1463)
    }

    // MARK: - Initialization

    func testLegacyInitializationReportsConfirmedCount() {
        let today = day(2026, 10, 29)
        let result = snapshot(completed: ["2026-10-27", "2026-10-28", "2026-10-29"],
                              legacy: legacy(), viewed: today, today: today)
        XCTAssertEqual(result.activeStreak, 1563)
        XCTAssertTrue(result.continuesLegacy)
        XCTAssertEqual(result.continuationDays, 0)
        XCTAssertEqual(result.longestStreak, 1563)
        XCTAssertEqual(result.lastQualifyingDayKey, "2026-10-29")
    }

    func testAnchorIsCountedOnceEvenWhenAlsoInCompletedDays() {
        // NAGISEN's own 3-day run overlaps the achievement; it must not add three days.
        let today = day(2026, 10, 29)
        let result = snapshot(completed: ["2026-10-27", "2026-10-28", "2026-10-29"],
                              legacy: legacy(), viewed: today, today: today)
        XCTAssertEqual(result.activeStreak, 1563)
    }

    // MARK: - Continuation

    func testQualifyingDaysContinueTheStreak() {
        let oct29 = day(2026, 10, 29)
        let oct30 = day(2026, 10, 30)
        let oct31 = day(2026, 10, 31)

        var completed = ["2026-10-29"]
        let onOct29 = snapshot(completed: completed, legacy: legacy(), viewed: oct29, today: oct29)
        XCTAssertEqual(onOct29.activeStreak, 1563)

        completed.append("2026-10-30")
        let onOct30 = snapshot(completed: completed, legacy: legacy(), viewed: oct30, today: oct30)
        XCTAssertEqual(onOct30.activeStreak, 1564)
        XCTAssertEqual(onOct30.continuationDays, 1)

        completed.append("2026-10-31")
        let onOct31 = snapshot(completed: completed, legacy: legacy(), viewed: oct31, today: oct31)
        XCTAssertEqual(onOct31.activeStreak, 1565)
        XCTAssertEqual(onOct31.continuationDays, 2)
    }

    func testMigrationDayBeforeLoggingShowsTheAchievement() {
        // Fresh install on the confirmation day: nothing logged yet, still 1,563.
        let today = day(2026, 10, 29)
        let result = snapshot(completed: [], legacy: legacy(), viewed: today, today: today)
        XCTAssertEqual(result.activeStreak, 1563)
        XCTAssertTrue(result.continuesLegacy)
        XCTAssertFalse(result.isCompleteToday)
    }

    func testTodayWithoutLoggingYetKeepsYesterdayValueVisible() {
        let today = day(2026, 10, 30)
        let result = snapshot(completed: ["2026-10-29"], legacy: legacy(), viewed: today, today: today)
        XCTAssertEqual(result.activeStreak, 1563)
        XCTAssertFalse(result.isCompleteToday)
    }

    func testCalendarRolloverAloneNeverIncrements() {
        let base = ["2026-10-29"]
        let onOct30 = snapshot(completed: base, legacy: legacy(),
                               viewed: day(2026, 10, 30), today: day(2026, 10, 30))
        XCTAssertEqual(onOct30.activeStreak, 1563)
        let onOct31 = snapshot(completed: base, legacy: legacy(),
                               viewed: day(2026, 10, 31), today: day(2026, 10, 31))
        XCTAssertEqual(onOct31.activeStreak, 0, "A missed day ends the active run; the achievement is untouched")
        XCTAssertEqual(onOct31.longestStreak, 1563)
        XCTAssertEqual(onOct31.legacy?.count, 1563)
    }

    // MARK: - Missed days and longest streak

    func testMissedDayRestartsActiveStreakButKeepsAchievement() {
        let oct31 = day(2026, 10, 31)
        let result = snapshot(completed: ["2026-10-31"], legacy: legacy(), viewed: oct31, today: oct31)
        XCTAssertEqual(result.activeStreak, 1)
        XCTAssertFalse(result.continuesLegacy)
        XCTAssertEqual(result.continuationDays, 0)
        XCTAssertEqual(result.legacy?.count, 1563)
        XCTAssertEqual(result.longestStreak, 1563)
    }

    func testLongestStreakSurvivesLaterReset() {
        let november = day(2026, 11, 15)
        let result = snapshot(completed: [], legacy: legacy(), viewed: november, today: november,
                              longest: 1565)
        XCTAssertEqual(result.activeStreak, 0)
        XCTAssertEqual(result.longestStreak, 1565)
    }

    func testFutureDayHasNoStreak() {
        let result = snapshot(completed: ["2026-10-30"], legacy: legacy(),
                              viewed: day(2026, 10, 31), today: day(2026, 10, 30))
        XCTAssertEqual(result.activeStreak, 0)
    }

    // MARK: - Historical browsing

    func testBrowsingBeforeTheAnchorUsesTheAchievementWindow() {
        let oct28 = day(2026, 10, 28)
        let result = snapshot(completed: [], legacy: legacy(), viewed: oct28, today: day(2026, 10, 29))
        XCTAssertEqual(result.activeStreak, 1562)
        XCTAssertTrue(result.continuesLegacy)
    }

    func testBrowsingBeforeTheAchievementWindowIsZero() {
        let first = StreakEngine.date(fromDayKey: legacy().firstDayKey(calendar: casablanca)!,
                                      calendar: casablanca)!
        let before = casablanca.date(byAdding: .day, value: -1, to: first)!
        let result = snapshot(completed: [], legacy: legacy(), viewed: before, today: day(2026, 10, 29))
        XCTAssertEqual(result.activeStreak, 0)
    }

    func testAchievementWindowStartsWhereTheCountSaysItDoes() {
        let firstKey = legacy().firstDayKey(calendar: casablanca)
        XCTAssertEqual(firstKey, "2022-07-20")
    }

    // MARK: - Time zones

    func testDayKeyFollowsTheCalendarTimeZone() {
        // 00:30 in Paris (UTC+1) is still the previous day in UTC.
        var paris = Calendar(identifier: .gregorian)
        paris.timeZone = TimeZone(identifier: "Europe/Paris")!
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let instant = paris.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 0, minute: 30))!
        XCTAssertEqual(StreakEngine.dayKey(for: instant, calendar: paris), "2026-10-29")
        XCTAssertEqual(StreakEngine.dayKey(for: instant, calendar: utc), "2026-10-28")
    }

    func testMidnightRolloverInCasablanca() {
        // Built from the calendar itself, so the assertion holds for whatever offset
        // Africa/Casablanca uses in this tzdata revision.
        let late = casablanca.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 23, minute: 59))!
        let justAfter = casablanca.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 0, minute: 1))!
        XCTAssertEqual(StreakEngine.dayKey(for: late, calendar: casablanca), "2026-10-29")
        XCTAssertEqual(StreakEngine.dayKey(for: justAfter, calendar: casablanca), "2026-10-30")

        let result = snapshot(completed: ["2026-10-29", "2026-10-30"], legacy: legacy(),
                              viewed: justAfter, today: justAfter)
        XCTAssertEqual(result.activeStreak, 1564)
    }

    func testDaylightSavingTransitionKeepsConsecutiveDays() {
        var paris = Calendar(identifier: .gregorian)
        paris.timeZone = TimeZone(identifier: "Europe/Paris")!
        let march30 = day(2026, 3, 30, calendar: paris)
        let completed = ["2026-03-28", "2026-03-29", "2026-03-30"]
        let result = StreakEngine.snapshot(completedDays: Set(completed), legacy: nil,
                                           viewedDay: march30, today: march30, calendar: paris)
        XCTAssertEqual(result.activeStreak, 3, "DST start on 2026-03-29 must not break the run")
    }

    func testTimeZoneChangeDoesNotCorruptTheAnchor() {
        // Day keys are calendar-day strings, so reading the same data in another zone keeps
        // the achievement addressable; only "which day is today" shifts.
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let result = StreakEngine.snapshot(completedDays: ["2026-10-29"], legacy: legacy(),
                                           viewedDay: day(2026, 10, 29), today: day(2026, 10, 29),
                                           calendar: tokyo)
        XCTAssertEqual(result.activeStreak, 1563)
        XCTAssertEqual(result.legacy?.lastConfirmedDayKey, "2026-10-29")
    }

    // MARK: - Migration idempotency

    func testDuplicateMigrationDoesNotDoubleCount() {
        let first = StreakEngine.merge(nil, with: legacy())
        let second = StreakEngine.merge(first, with: legacy())
        XCTAssertEqual(first, second)
        let today = day(2026, 10, 29)
        let result = snapshot(completed: ["2026-10-29"], legacy: second, viewed: today, today: today)
        XCTAssertEqual(result.activeStreak, 1563)
    }

    func testMergeNeverLowersAConfirmedCount() {
        let confirmed = legacy(count: 1563)
        let downgraded = legacy(count: 3)
        let merged = StreakEngine.merge(confirmed, with: downgraded)
        XCTAssertEqual(merged?.count, 1563)
        XCTAssertEqual(merged?.lastConfirmedDayKey, "2026-10-29")
    }

    func testMergeAcceptsALaterConfirmation() {
        let older = legacy(count: 1563, end: "2026-10-29")
        let newer = legacy(count: 1566, end: "2026-11-01")
        XCTAssertEqual(StreakEngine.merge(older, with: newer)?.count, 1566)
        XCTAssertEqual(StreakEngine.merge(older, with: newer)?.lastConfirmedDayKey, "2026-11-01")
    }

    func testMalformedAchievementIsRejected() {
        XCTAssertFalse(LegacyStreak(source: "Lose It!", count: 0, lastConfirmedDayKey: "2026-10-29").isWellFormed)
        XCTAssertFalse(LegacyStreak(source: "Lose It!", count: 10, lastConfirmedDayKey: "2026-02-31").isWellFormed)
        XCTAssertNil(StreakEngine.merge(nil, with: LegacyStreak(source: "Lose It!", count: 0,
                                                               lastConfirmedDayKey: "2026-10-29")))
    }

    func testMalformedAchievementIsIgnoredByTheEngine() {
        let invalid = LegacyStreak(source: "Lose It!", count: 0, lastConfirmedDayKey: "2026-10-29")
        let today = day(2026, 10, 29)
        let result = snapshot(completed: ["2026-10-29"], legacy: invalid, viewed: today, today: today)
        XCTAssertEqual(result.activeStreak, 1)
    }

    // MARK: - Persistence shape

    func testLegacyRoundTripsThroughCodable() throws {
        let original = LegacyStreak(source: "Lose It!", count: 1563, lastConfirmedDayKey: "2026-10-29",
                                    timeZoneIdentifier: "Africa/Casablanca",
                                    recordedAt: Date(timeIntervalSince1970: 1_790_000_000))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LegacyStreak.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testLegacyDecodesWithMissingOptionalMetadata() throws {
        // Hand-written migration files may carry only the essentials.
        let json = #"{"count":1563,"lastConfirmedDayKey":"2026-10-29"}"#
        let decoded = try JSONDecoder().decode(LegacyStreak.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.count, 1563)
        XCTAssertEqual(decoded.lastConfirmedDayKey, "2026-10-29")
        XCTAssertEqual(decoded.source, "Lose It!")
        XCTAssertEqual(decoded.verification, LegacyStreak.userConfirmed)
        XCTAssertTrue(decoded.isWellFormed)
    }
}
