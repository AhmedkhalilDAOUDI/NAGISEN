import XCTest
@testable import Daywell

final class LoseItImporterTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Africa/Casablanca")!
        return calendar
    }

    private let foodCSV = """
    Date,Meal,Food,Quantity,Unit,Calories,Protein,Carbs,Fat,Fiber,Sodium
    2026-10-27,Breakfast,Oatmeal with milk,1,serving,320,12,48,8,6,120
    2026-10-27,Lunch,"Chicken salad, large",1,serving,410,38,14,21,5,640
    2026-10-28,Dinner,Salmon and rice,1,serving,620,40,58,24,4,520
    2026-10-29,Snacks,Greek yogurt,1,serving,120,17,7,2,0,60
    """

    private let weightCSV = """
    Date,Weight (lbs)
    2026-10-27,172.4
    2026-10-28,171.9
    """

    private let summaryCSV = """
    Date,Total Calories,Protein,Carbs,Fat
    2026-10-27,1850,120,200,60
    2026-10-28,1920,130,210,64
    """

    /// A real deflate-compressed archive containing three CSVs, generated once.
    private let zipFixtureBase64 = "UEsDBBQAAAAIABSnXV2Sn29C1wAAAEQBAAAaAAAATG9zZUl0IEV4cG9ydC9mb29kX2xvZy5jc3ZNzk1qwzAQhuF9TqEDfAFJkX+6bYO7aWlL6AEm9jQeLEsgyS25fZ2ddsPA9/KcqTDemTyGGCd8bRSKlDu+gxS8kI9JOOMzxcIS9ke6ZgxUMMiVEy5xkm09WG3bo9FH2+E5MS0/lAs+qKx7V/1JmdUqfoFB5vQr4YaT1TAWrkePdr90nXjbwjjjNYn3PKlxlnHhoDJ5mqqEMxqnHsbBGjRoXdXocZYQHj7yawyKwqSSjFzN213gNJoe1sGhqQlPuAQal7wbmBd1j7ctlWprHvoOHSw0Wn34B1BLAwQUAAAACAAUp11dfd+NRywAAAA0AAAAHAAAAExvc2VJdCBFeHBvcnQvd2VpZ2h0X2xvZy5jc3ZzSSxJ1QlPzUzPKFHQyEkq1uQyMjAy0zU00DUy1zE0N9IzQQhYAAUM9Sy5AFBLAwQUAAAACAAUp11d4idXlVIAAABcAAAAHwAAAExvc2VJdCBFeHBvcnQvZGFpbHlfc3VtbWFyeS5jc3ZzSSxJ1QnJL0nMUXBOzMkvykwt1gkoyi9JzczTcU4sSirWcUss4TIyMDLTNTTQNTLXMbQwNdAxNDLQMTIw0DEzQEhZ6BhaAoUNjYFShkApEy4AUEsBAhQDFAAAAAgAFKddXZKfb0LXAAAARAEAABoAAAAAAAAAAAAAAIABAAAAAExvc2VJdCBFeHBvcnQvZm9vZF9sb2cuY3N2UEsBAhQDFAAAAAgAFKddXX3fjUcsAAAANAAAABwAAAAAAAAAAAAAAIABDwEAAExvc2VJdCBFeHBvcnQvd2VpZ2h0X2xvZy5jc3ZQSwECFAMUAAAACAAUp11d4idXlVIAAABcAAAAHwAAAAAAAAAAAAAAgAF1AQAATG9zZUl0IEV4cG9ydC9kYWlseV9zdW1tYXJ5LmNzdlBLBQYAAAAAAwADAN8AAAAEAgAAAAA="

    private func preview(_ files: [LoseItSourceFile],
                         existing: Set<String> = [],
                         weights: [WeightEntry] = []) -> LoseItImportPreview {
        LoseItImporter.preview(files: files, existingEntryFingerprints: existing,
                               existingWeights: weights, calendar: calendar)
    }

    private func file(_ name: String, _ text: String) -> LoseItSourceFile {
        LoseItSourceFile(name: name, data: Data(text.utf8))
    }

    // MARK: - CSV mapping

    func testCSVEntriesAreMappedWithoutFabrication() {
        let result = preview([file("food_log.csv", foodCSV)])
        XCTAssertEqual(result.entries.count, 4)
        XCTAssertTrue(result.weights.isEmpty)
        XCTAssertTrue(result.dailySummaries.isEmpty)

        let first = result.entries[0]
        XCTAssertEqual(first.food.name, "Oatmeal with milk")
        XCTAssertEqual(first.food.calories, 320)
        XCTAssertEqual(first.food.protein, 12)
        XCTAssertEqual(first.food.carbs, 48)
        XCTAssertEqual(first.food.fat, 8)
        XCTAssertEqual(first.food.fiber, 6)
        XCTAssertEqual(first.food.sodium, 120)
        XCTAssertEqual(first.food.source, "Lose It!")
        XCTAssertEqual(first.meal, .breakfast)
        XCTAssertEqual(first.loggedQuantity, 1)
        XCTAssertEqual(first.loggedUnit, "serving")
        XCTAssertEqual(StreakEngine.dayKey(for: first.date, calendar: calendar), "2026-10-27")
        XCTAssertNotNil(first.importFingerprint)
    }

    func testQuotedFieldsWithCommasSurvive() {
        let result = preview([file("food.csv", foodCSV)])
        XCTAssertTrue(result.entries.contains { $0.food.name == "Chicken salad, large" })
    }

    func testMealNamesMapToNAGISENMeals() {
        XCTAssertEqual(LoseItImporter.meal(from: "Breakfast", default: .snacks), .breakfast)
        XCTAssertEqual(LoseItImporter.meal(from: "LUNCH", default: .snacks), .lunch)
        XCTAssertEqual(LoseItImporter.meal(from: "Dinner", default: .snacks), .dinner)
        XCTAssertEqual(LoseItImporter.meal(from: "Afternoon snack", default: .lunch), .snacks)
        XCTAssertEqual(LoseItImporter.meal(from: nil, default: .lunch), .lunch)
    }

    func testDailySummariesAreKeptButNeverTurnedIntoFoodEntries() {
        let result = preview([file("daily_summary.csv", summaryCSV)])
        XCTAssertTrue(result.entries.isEmpty, "Calorie totals must not become fabricated food entries")
        XCTAssertEqual(result.dailySummaries.count, 2)
        XCTAssertEqual(result.dailySummaries.first?.calories, 1850)
        XCTAssertTrue(result.skipped.contains { $0.category == "Daily summaries" && $0.rowCount == 2 })
    }

    func testWeightsConvertPoundsToKilograms() {
        let result = preview([file("weight_log.csv", weightCSV)])
        XCTAssertEqual(result.weights.count, 2)
        XCTAssertEqual(result.weights[0].kilograms, 78.2, accuracy: 0.15)
        XCTAssertEqual(result.weights[1].kilograms, 77.97, accuracy: 0.15)
    }

    // MARK: - Archive

    func testZipArchiveIsExpandedAndParsed() throws {
        let data = try XCTUnwrap(Data(base64Encoded: zipFixtureBase64))
        let result = preview([LoseItSourceFile(name: "LoseIt_Export.zip", data: data)])
        XCTAssertEqual(result.entries.count, 4)
        XCTAssertEqual(result.weights.count, 2)
        XCTAssertEqual(result.dailySummaries.count, 2)
        XCTAssertEqual(result.sourceFiles.count, 3)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testCorruptArchiveIsReportedNotGuessed() {
        let result = preview([LoseItSourceFile(name: "broken.zip", data: Data(repeating: 0x50, count: 64))])
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(result.warnings.contains { $0.contains("Could not open archive") })
    }

    // MARK: - Idempotency

    func testRepeatedImportYieldsNoNewEntries() {
        let first = preview([file("food_log.csv", foodCSV)])
        XCTAssertEqual(first.entries.count, 4)

        let fingerprints = Set(first.entries.compactMap(\.importFingerprint))
        let second = preview([file("food_log.csv", foodCSV)], existing: fingerprints)
        XCTAssertTrue(second.entries.isEmpty)
        XCTAssertEqual(second.duplicateEntries, 4)
    }

    func testRepeatedRowsInsideOneFileAreDeduplicated() {
        let duplicated = foodCSV + "\n2026-10-27,Breakfast,Oatmeal with milk,1,serving,320,12,48,8,6,120"
        let result = preview([file("food_log.csv", duplicated)])
        XCTAssertEqual(result.entries.count, 4)
        XCTAssertEqual(result.duplicateEntries, 1)
    }

    func testFingerprintIsStableAcrossParsingRuns() {
        let a = preview([file("food_log.csv", foodCSV)])
        let b = preview([file("food_log.csv", foodCSV)])
        XCTAssertEqual(a.entries.compactMap(\.importFingerprint),
                       b.entries.compactMap(\.importFingerprint))
    }

    // MARK: - Legacy streak in the migration file

    func testLegacyStreakFromJSONMigrationFile() throws {
        let json = """
        {
          "legacyStreak": {
            "source": "Lose It!",
            "count": 1563,
            "lastConfirmedDate": "2026-10-29",
            "timeZone": "Africa/Casablanca",
            "verification": "user-confirmed",
            "migrationVersion": 1
          },
          "entries": []
        }
        """
        let result = preview([file("NAGISEN_LoseIt_Import.json", json)])
        let legacy = try XCTUnwrap(result.legacy)
        XCTAssertEqual(legacy.count, 1563)
        XCTAssertEqual(legacy.lastConfirmedDayKey, "2026-10-29")
        XCTAssertEqual(legacy.timeZoneIdentifier, "Africa/Casablanca")
        XCTAssertEqual(legacy.verification, "user-confirmed")
        XCTAssertEqual(legacy.migrationVersion, 1)
        XCTAssertFalse(result.isEmpty)
    }

    func testLegacyStreakWithMalformedValuesIsSkipped() {
        let json = #"{"legacyStreak":{"count":0,"lastConfirmedDate":"2026-10-29"}}"#
        let result = preview([file("import.json", json)])
        XCTAssertNil(result.legacy)
        XCTAssertTrue(result.skipped.contains { $0.category == "Legacy streak" })
    }

    func testEntriesAndWeightsAndLegacyTogether() throws {
        let json = """
        {
          "legacyStreak": {"count": 1563, "lastConfirmedDate": "2026-10-29"},
          "entries": [
            {"date": "2026-10-28", "meal": "Dinner", "food": "Tagine", "calories": 540,
             "protein": 32, "carbs": 40, "fat": 22}
          ],
          "weights": [
            {"date": "2026-10-28", "weight": 79.4}
          ]
        }
        """
        let result = preview([file("migration.json", json)])
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.weights.count, 1)
        XCTAssertEqual(result.legacy?.count, 1563)
        XCTAssertEqual(result.entries[0].food.name, "Tagine")
    }

    // MARK: - Defensive parsing

    func testCorruptJSONIsReported() {
        let result = preview([file("bad.json", "{\"entries\": [")])
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(result.skipped.contains { $0.category == "Unreadable files" })
    }

    func testHeaderOnlyCSVProducesNothing() {
        let result = preview([file("empty.csv", "Date,Food,Calories\n")])
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(result.skipped.contains { $0.category == "Unreadable files" })
    }

    func testCompletelyEmptyInputProducesNothing() {
        let result = preview([])
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(result.skipped.isEmpty)
    }

    func testUnparseableDatesAreSkippedNotGuessed() {
        let csv = """
        Date,Food,Calories
        not-a-date,Toast,120
        2026-10-29,Toast,120
        """
        let result = preview([file("food.csv", csv)])
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertTrue(result.skipped.contains { $0.category == "Rows with an unreadable date" })
    }

    func testDateFormatsAllResolveToTheSameDay() {
        let formats = ["2026-10-29", "10/29/2026", "Oct 29, 2026", "2026/10/29", "20261029"]
        for raw in formats {
            let parsed = LoseItDateParser.parse(raw, calendar: calendar)
            XCTAssertNotNil(parsed, "failed: \(raw)")
            XCTAssertEqual(parsed.map { StreakEngine.dayKey(for: $0, calendar: calendar) }, "2026-10-29",
                           "wrong day for: \(raw)")
        }
    }

    func testSemicolonDelimitedFilesAreSupported() {
        let csv = """
        Date;Food;Calories;Protein;Carbs;Fat
        2026-10-29;Mjaddara;480;18;70;14
        """
        let result = preview([file("food.csv", csv)])
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries[0].food.name, "Mjaddara")
        XCTAssertEqual(result.entries[0].food.calories, 480)
    }

    func testEnergyInKilojoulesIsConverted() {
        let csv = """
        Date,Food,Energy (kJ)
        2026-10-29,Energy bar,920
        """
        let result = preview([file("food.csv", csv)])
        XCTAssertEqual(result.entries.first?.food.calories, 220)
    }

    func testRowsWithoutAnyUsableFieldAreReported() {
        let csv = """
        Date,Notes
        2026-10-29,Felt good
        """
        let result = preview([file("notes.csv", csv)])
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertTrue(result.skipped.contains { $0.category == "Unrecognized rows" })
    }
}
