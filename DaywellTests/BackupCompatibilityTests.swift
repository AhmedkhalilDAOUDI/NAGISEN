import XCTest
@testable import Daywell

final class BackupCompatibilityTests: XCTestCase {
    private var store: NutritionStore!

    private static func minimalBackup(extra: String = "") -> Data {
        let json = """
        {
          "entries": [],
          "customFoods": [],
          "goals": {"calories": 2000, "protein": 120, "carbs": 250, "fat": 65}
          \(extra.isEmpty ? "" : "," + extra)
        }
        """
        return Data(json.utf8)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = NutritionStore()
        XCTAssertTrue(store.restoreJSON(Self.minimalBackup()), "baseline restore must succeed")
    }

    private func legacy(count: Int = 1563, end: String = "2026-10-29") -> LegacyStreak {
        LegacyStreak(source: "Lose It!", count: count, lastConfirmedDayKey: end,
                     timeZoneIdentifier: "Africa/Casablanca")
    }

    private func exportedObject() throws -> [String: Any] {
        let data = try XCTUnwrap(store.exportJSON())
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Export shape

    func testExportCarriesLegacyStreakAndSchemaVersion() throws {
        XCTAssertTrue(store.applyLegacyStreak(legacy()))
        let object = try exportedObject()
        let legacyObject = try XCTUnwrap(object["legacyStreak"] as? [String: Any])
        XCTAssertEqual(legacyObject["count"] as? Int, 1563)
        XCTAssertEqual(legacyObject["lastConfirmedDayKey"] as? String, "2026-10-29")
        XCTAssertEqual(legacyObject["source"] as? String, "Lose It!")
        XCTAssertEqual(legacyObject["verification"] as? String, "user-confirmed")
        XCTAssertEqual(object["schemaVersion"] as? Int, 2)
    }

    func testRepeatedApplicationDoesNotLowerTheAchievement() {
        XCTAssertTrue(store.applyLegacyStreak(legacy(count: 1563)))
        XCTAssertTrue(store.applyLegacyStreak(legacy(count: 3)))
        XCTAssertEqual(store.legacyStreak?.count, 1563)
    }

    func testLongestRecordedTracksTheAchievement() {
        XCTAssertTrue(store.applyLegacyStreak(legacy()))
        XCTAssertEqual(store.longestStreakRecorded, 1563)
        XCTAssertEqual(store.streakSnapshot(asOf: .now).longestStreak, 1563)
    }

    // MARK: - Restore compatibility

    func testBackupWithoutLegacyFieldsStillRestores() throws {
        // This is exactly what NAGISEN wrote before this change.
        XCTAssertTrue(store.restoreJSON(Self.minimalBackup()))
        XCTAssertNil(store.legacyStreak)
        XCTAssertNoThrow(try exportedObject())
    }

    func testStreakSurvivesExportAndRestore() throws {
        XCTAssertTrue(store.applyLegacyStreak(legacy()))
        let exported = try XCTUnwrap(store.exportJSON())

        // Wipe it, then restore the file.
        XCTAssertTrue(store.restoreJSON(Self.minimalBackup()))
        XCTAssertNil(store.legacyStreak)

        XCTAssertTrue(store.restoreJSON(exported))
        XCTAssertEqual(store.legacyStreak?.count, 1563)
        XCTAssertEqual(store.legacyStreak?.lastConfirmedDayKey, "2026-10-29")
        XCTAssertEqual(store.longestStreakRecorded, 1563)
    }

    func testUnknownFutureFieldsArePreserved() throws {
        let future = Self.minimalBackup(extra: """
        "futureField": {"nested": [1, 2, 3]}, "schemaVersion": 9
        """)
        XCTAssertTrue(store.restoreJSON(future))
        let object = try exportedObject()
        XCTAssertEqual(object["schemaVersion"] as? Int, 9, "a newer schema marker must not be downgraded")
        let futureField = try XCTUnwrap(object["futureField"] as? [String: Any])
        XCTAssertEqual(futureField["nested"] as? [Int], [1, 2, 3])
    }

    func testMalformedLegacyStreakRejectsTheWholeFile() {
        let broken = Self.minimalBackup(extra: """
        "legacyStreak": {"source": "Lose It!", "count": 0, "lastConfirmedDayKey": "2026-10-29"}
        """)
        XCTAssertFalse(store.restoreJSON(broken))
        XCTAssertNil(store.legacyStreak)
    }

    func testCorruptFileIsRejected() {
        XCTAssertFalse(store.restoreJSON(Data("{ not json".utf8)))
    }

    func testImplausibleGoalsAreRejected() {
        let bad = Data("""
        {"entries": [], "customFoods": [], "goals": {"calories": 10, "protein": 120, "carbs": 250, "fat": 65}}
        """.utf8)
        XCTAssertFalse(store.restoreJSON(bad))
    }

    // MARK: - Import commit

    func testImportKeepsExistingRecordsAndIsIdempotent() throws {
        store.add(Food(name: "Existing breakfast", serving: "1 bowl", calories: 300,
                       protein: 10, carbs: 40, fat: 8), to: .breakfast, servings: 1, on: .now)
        let before = store.entries.count
        XCTAssertEqual(before, 1)

        let csv = """
        Date,Meal,Food,Calories,Protein,Carbs,Fat
        2026-10-28,Dinner,Tagine,540,32,40,22
        2026-10-29,Lunch,Couscous,610,24,82,18
        """
        let plan = LoseItImporter.preview(files: [LoseItSourceFile(name: "food.csv", data: Data(csv.utf8))],
                                          existingEntryFingerprints: store.entryFingerprints,
                                          existingWeights: store.weights)

        let outcome = store.importLoseIt(plan)
        XCTAssertEqual(outcome, .imported(entries: 2, weights: 0, legacyApplied: false))
        XCTAssertEqual(store.entries.count, 3)
        XCTAssertTrue(store.entries.contains { $0.food.name == "Existing breakfast" })
        XCTAssertEqual(store.loseItImports.count, 1)

        // Re-import exactly the same data.
        let again = LoseItImporter.preview(files: [LoseItSourceFile(name: "food.csv", data: Data(csv.utf8))],
                                           existingEntryFingerprints: store.entryFingerprints,
                                           existingWeights: store.weights)
        XCTAssertEqual(store.importLoseIt(again), .nothingNew)
        XCTAssertEqual(store.entries.count, 3)
        XCTAssertEqual(store.loseItImports.count, 1)
    }

    func testImportAppliesTheLegacyStreakAlongsideHistory() throws {
        let json = """
        {
          "legacyStreak": {"source": "Lose It!", "count": 1563, "lastConfirmedDate": "2026-10-29",
                           "timeZone": "Africa/Casablanca", "verification": "user-confirmed"},
          "entries": [{"date": "2026-10-28", "meal": "Dinner", "food": "Tagine", "calories": 540}]
        }
        """
        let plan = LoseItImporter.preview(files: [LoseItSourceFile(name: "migration.json", data: Data(json.utf8))],
                                          existingEntryFingerprints: store.entryFingerprints,
                                          existingWeights: store.weights)
        let outcome = store.importLoseIt(plan)
        XCTAssertEqual(outcome, .imported(entries: 1, weights: 0, legacyApplied: true))
        XCTAssertEqual(store.legacyStreak?.count, 1563)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.loseItImports.first?.legacyCount, 1563)
    }

    func testImportDoesNotTouchGoalsOrProfile() {
        store.goals.calories = 1850
        store.profile = PersonalProfile(age: 33, heightCm: 180, targetWeightKg: 78)
        let csv = "Date,Food,Calories\n2026-10-29,Toast,120\n"
        let plan = LoseItImporter.preview(files: [LoseItSourceFile(name: "food.csv", data: Data(csv.utf8))],
                                          existingEntryFingerprints: store.entryFingerprints,
                                          existingWeights: store.weights)
        _ = store.importLoseIt(plan)
        XCTAssertEqual(store.goals.calories, 1850)
        XCTAssertEqual(store.profile.age, 33)
        XCTAssertEqual(store.profile.targetWeightKg, 78)
    }

    // MARK: - Restart persistence

    func testStreakSurvivesANewStoreInstance() {
        XCTAssertTrue(store.applyLegacyStreak(legacy()))
        let reopened = NutritionStore()
        XCTAssertEqual(reopened.legacyStreak?.count, 1563)
        XCTAssertEqual(reopened.legacyStreak?.lastConfirmedDayKey, "2026-10-29")
        XCTAssertEqual(reopened.longestStreakRecorded, 1563)
    }

    // MARK: - Finishing the day earns the next one

    private func todayKey() -> String {
        StreakEngine.dayKey(for: Date(), calendar: .current)
    }

    private func yesterdayKey() -> String {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        return StreakEngine.dayKey(for: yesterday, calendar: .current)
    }

    func testVersionOneRecordMovesItsAnchorBackADay() {
        let record = LegacyStreak(source: "Lose It!", count: 1563,
                                  lastConfirmedDayKey: "2026-10-29",
                                  timeZoneIdentifier: "Africa/Casablanca",
                                  migrationVersion: 1)
        let migrated = record.migratedToCurrentVersion
        XCTAssertEqual(migrated.lastConfirmedDayKey, "2026-10-28")
        XCTAssertEqual(migrated.count, 1563, "the achievement keeps every day it had")
        XCTAssertEqual(migrated.migrationVersion, 2)
        XCTAssertEqual(migrated.migratedToCurrentVersion, migrated, "migration is idempotent")
    }

    func testFinishingTheConfirmationDayAddsTheNextDay() {
        // A v1 record confirmed today: before finishing anything, the streak is 1,563.
        let record = LegacyStreak(source: "Lose It!", count: 1563,
                                  lastConfirmedDayKey: todayKey(),
                                  timeZoneIdentifier: "Africa/Casablanca",
                                  migrationVersion: 1)
        XCTAssertTrue(store.applyLegacyStreak(record))
        XCTAssertEqual(store.legacyStreak?.lastConfirmedDayKey, yesterdayKey())
        XCTAssertEqual(store.streakSnapshot(asOf: Date()).activeStreak, 1563)

        // Pressing Done Logging is what earns the next day.
        store.setLoggingComplete(true, on: Date())
        XCTAssertEqual(store.streakSnapshot(asOf: Date()).activeStreak, 1564)
    }

    func testUndoingTheDayTakesTheDayBackAway() {
        let record = LegacyStreak(source: "Lose It!", count: 1563,
                                  lastConfirmedDayKey: todayKey(),
                                  timeZoneIdentifier: "Africa/Casablanca",
                                  migrationVersion: 1)
        XCTAssertTrue(store.applyLegacyStreak(record))
        store.setLoggingComplete(true, on: Date())
        XCTAssertEqual(store.streakSnapshot(asOf: Date()).activeStreak, 1564)
        store.setLoggingComplete(false, on: Date())
        XCTAssertEqual(store.streakSnapshot(asOf: Date()).activeStreak, 1563)
    }

    func testMigrationHandsTheConfirmationDayBackToTheUser() {
        // v1 counted the confirmation day inside the achievement, so its flag did nothing.
        store.setLoggingComplete(true, on: Date())
        XCTAssertTrue(store.isLoggingComplete(on: Date()))

        let record = LegacyStreak(source: "Lose It!", count: 1563,
                                  lastConfirmedDayKey: todayKey(),
                                  timeZoneIdentifier: "Africa/Casablanca",
                                  migrationVersion: 1)
        XCTAssertTrue(store.applyLegacyStreak(record))
        XCTAssertEqual(store.legacyStreak?.lastConfirmedDayKey, yesterdayKey())
        // The day is offered again, so pressing Done Logging can earn it.
        XCTAssertEqual(store.streakSnapshot(asOf: Date()).activeStreak, 1563)

        store.setLoggingComplete(true, on: Date())
        XCTAssertEqual(store.streakSnapshot(asOf: Date()).activeStreak, 1564)
    }

    func testMigratedRecordSurvivesAReinstallRestore() {
        let record = LegacyStreak(source: "Lose It!", count: 1563,
                                  lastConfirmedDayKey: "2026-10-29",
                                  timeZoneIdentifier: "Africa/Casablanca",
                                  migrationVersion: 1)
        XCTAssertTrue(store.applyLegacyStreak(record))
        let exported = try! XCTUnwrap(store.exportJSON())
        let reopened = NutritionStore()
        XCTAssertTrue(reopened.restoreJSON(exported))
        XCTAssertEqual(reopened.legacyStreak?.lastConfirmedDayKey, "2026-10-28")
        XCTAssertEqual(reopened.legacyStreak?.migrationVersion, 2)
        XCTAssertEqual(reopened.legacyStreak?.count, 1563)
    }
}
