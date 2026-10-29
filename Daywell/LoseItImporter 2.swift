import Foundation
import CryptoKit

/// One file handed to the importer, already read into memory.
struct LoseItSourceFile {
    let name: String
    let data: Data
}

struct LoseItSkippedCategory: Codable, Equatable, Identifiable {
    var category: String
    var reason: String
    var rowCount: Int
    var id: String { "\(category)|\(reason)" }
}

struct LoseItDailySummary: Codable, Equatable {
    var date: Date
    var calories: Int
    var protein: Double?
    var carbs: Double?
    var fat: Double?

    var dayKey: String { StreakEngine.dayKey(for: date) }
}

/// Everything the importer found, before anything is written.
struct LoseItImportPreview {
    var entries: [DiaryEntry] = []
    var weights: [WeightEntry] = []
    var dailySummaries: [LoseItDailySummary] = []
    var skipped: [LoseItSkippedCategory] = []
    var warnings: [String] = []
    var sourceFiles: [String] = []
    var duplicateEntries = 0
    var duplicateWeights = 0
    var legacy: LegacyStreak?
    var earliestDate: Date?
    var latestDate: Date?

    var isEmpty: Bool { entries.isEmpty && weights.isEmpty && legacy == nil }

    var dateRangeText: String? {
        guard let earliestDate, let latestDate else { return nil }
        let format = Date.FormatStyle.dateTime.year().month(.abbreviated).day()
        if StreakEngine.dayKey(for: earliestDate) == StreakEngine.dayKey(for: latestDate) {
            return earliestDate.formatted(format)
        }
        return "\(earliestDate.formatted(format)) – \(latestDate.formatted(format))"
    }
}

/// Audit trail of a committed import. Repeated imports append a record, never duplicate data.
struct LoseItImportRecord: Codable, Equatable, Identifiable {
    var id = UUID()
    var importedAt: Date = .now
    var sourceFiles: [String] = []
    var entryCount = 0
    var weightCount = 0
    var skippedCategories: [String] = []
    var legacyCount: Int?
    var migrationVersion = 1
}

enum LoseItImporter {
    static let sourceLabel = "Lose It!"

    /// Reads every file (expanding `.zip` archives), maps rows to NAGISEN models and removes
    /// anything already present. Nothing is written here: the caller shows this preview first.
    static func preview(files: [LoseItSourceFile],
                        existingEntryFingerprints: Set<String> = [],
                        existingWeights: [WeightEntry] = [],
                        defaultMeal: Meal = .snacks,
                        calendar: Calendar = .current) -> LoseItImportPreview {
        var builder = Builder(existingFingerprints: existingEntryFingerprints,
                              existingWeights: existingWeights,
                              defaultMeal: defaultMeal,
                              calendar: calendar)
        let expanded = expand(files)
        builder.unreadableFiles = expanded.unreadable
        for file in expanded.files {
            builder.consume(file)
        }
        return builder.finish()
    }

    // MARK: - Container expansion

    static func expand(_ files: [LoseItSourceFile]) -> (files: [LoseItSourceFile], unreadable: [String]) {
        var result: [LoseItSourceFile] = []
        var unreadableArchives: [String] = []
        var queue = files
        var guardCount = 0
        while let file = queue.first {
            queue.removeFirst()
            guardCount += 1
            if guardCount > 500 { break }

            let looksZipped = file.name.lowercased().hasSuffix(".zip") || ZipArchiveReader.isArchive(file.data)
            if looksZipped {
                do {
                    let entries = try ZipArchiveReader.entries(in: file.data)
                    queue.append(contentsOf: entries.map { LoseItSourceFile(name: $0.name, data: $0.data) })
                    continue
                } catch {
                    unreadableArchives.append(file.name)
                }
            }
            result.append(file)
        }
        return (result, unreadableArchives)
    }

    // MARK: - Row model

    struct RawRecord {
        var values: [String: String]
        var headers: [String: String]

        func text(_ aliases: [String]) -> String? {
            for alias in aliases {
                if let value = values[alias], !value.trimmingCharacters(in: .whitespaces).isEmpty {
                    return value.trimmingCharacters(in: .whitespaces)
                }
            }
            return nil
        }

        func header(_ aliases: [String]) -> String? {
            for alias in aliases { if let header = headers[alias] { return header.lowercased() } }
            return nil
        }

        func number(_ aliases: [String]) -> Double? {
            guard let raw = text(aliases) else { return nil }
            var cleaned = raw
                .replacingOccurrences(of: "\u{00A0}", with: "")
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "<", with: "")
                .replacingOccurrences(of: "≈", with: "")
                .replacingOccurrences(of: ">", with: "")
            // Keep only the leading numeric run so units such as "640 mg" still parse.
            let allowed = CharacterSet(charactersIn: "0123456789.,-")
            cleaned = String(cleaned.unicodeScalars.prefix { allowed.contains($0) })
            if cleaned.contains(",") && cleaned.contains(".") {
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
            }
            return Double(cleaned)
        }

        func has(_ aliases: [String]) -> Bool { text(aliases) != nil }
    }

    // MARK: - Builder

    private struct Builder {
        let existingFingerprints: Set<String>
        let existingWeights: [WeightEntry]
        let defaultMeal: Meal
        let calendar: Calendar

        var preview = LoseItImportPreview()
        var seen = Set<String>()
        var skippedRows: [String: (reason: String, count: Int)] = [:]
        var unreadableFiles: [String] = []

        init(existingFingerprints: Set<String>, existingWeights: [WeightEntry],
             defaultMeal: Meal, calendar: Calendar) {
            self.existingFingerprints = existingFingerprints
            self.existingWeights = existingWeights
            self.defaultMeal = defaultMeal
            self.calendar = calendar
        }

        mutating func skip(_ category: String, _ reason: String, count: Int = 1) {
            let key = "\(category)|\(reason)"
            let current = skippedRows[key] ?? (reason, 0)
            skippedRows[key] = (reason, current.count + count)
        }

        mutating func consume(_ file: LoseItSourceFile) {
            let lower = file.name.lowercased()
            guard let text = decodeText(file.data) else {
                // Binary files that are not archives are simply not data we understand.
                if !lower.hasSuffix(".zip") {
                    skip("Unsupported files", "Not readable as text", count: 1)
                }
                return
            }
            preview.sourceFiles.append(file.name)

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                consumeJSON(Data(trimmed.utf8), name: file.name)
            } else {
                consumeDelimited(text, name: file.name)
                }
        }

        private mutating func consumeJSON(_ data: Data, name: String) {
            guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                skip("Unreadable files", "JSON could not be parsed", count: 1)
                return
            }
            if let array = object as? [[String: Any]] {
                for row in array { consumeDictionary(row) }
                return
            }
            guard let root = object as? [String: Any] else {
                skip("Unreadable files", "JSON root is not an object", count: 1)
                return
            }
            if let legacy = root["legacyStreak"] as? [String: Any] {
                applyLegacy(legacy)
            } else if let legacy = root["legacyStreak"] as? String,
                      let legacyObject = try? JSONSerialization.jsonObject(with: Data(legacy.utf8)) as? [String: Any] {
                applyLegacy(legacyObject)
            }

            let entryKeys = ["entries", "food", "foods", "foodLog", "foodlog", "diary", "meals", "mealEntries"]
            for key in entryKeys {
                if let rows = root[key] as? [[String: Any]] {
                    for row in rows { consumeDictionary(row) }
                }
            }
            let weightKeys = ["weights", "weight", "weightLog", "weightlog", "weighIns"]
            for key in weightKeys {
                if let rows = root[key] as? [[String: Any]] {
                    for row in rows { consumeDictionary(row, forcedKind: .weight) }
                }
            }
            if let rows = root["dailySummaries"] as? [[String: Any]] ?? root["summaries"] as? [[String: Any]] {
                for row in rows { consumeDictionary(row, forcedKind: .dailySummary) }
            }
            if root["entries"] == nil && root["food"] == nil && root["weights"] == nil && root["legacyStreak"] == nil {
                // Single flat record.
                consumeDictionary(root)
            }
        }

        private mutating func applyLegacy(_ dictionary: [String: Any]) {
            func string(_ keys: [String]) -> String? {
                for key in keys {
                    if let value = dictionary[key] as? String, !value.isEmpty { return value }
                }
                return nil
            }
            func int(_ keys: [String]) -> Int? {
                for key in keys {
                    if let value = dictionary[key] as? Int { return value }
                    if let value = dictionary[key] as? Double { return Int(value) }
                    if let value = dictionary[key] as? String, let parsed = Int(value) { return parsed }
                }
                return nil
            }

            guard let count = int(["count", "days", "streak"]), count > 0,
                  let rawEnd = string(["lastConfirmedDate", "lastConfirmedDayKey", "lastConfirmed", "endDate"]) else {
                skip("Legacy streak", "Missing count or last confirmed date", count: 1)
                return
            }
            let endDate = LoseItDateParser.parse(rawEnd, calendar: calendar) ?? StreakEngine.date(fromDayKey: rawEnd, calendar: calendar)
            guard let endDate else {
                skip("Legacy streak", "Last confirmed date could not be read", count: 1)
                return
            }
            let legacy = LegacyStreak(
                source: string(["source"]) ?? LoseItImporter.sourceLabel,
                count: count,
                lastConfirmedDayKey: StreakEngine.dayKey(for: endDate, calendar: calendar),
                timeZoneIdentifier: string(["timeZone", "timeZoneIdentifier", "tz"]) ?? TimeZone.current.identifier,
                verification: string(["verification"]) ?? LegacyStreak.userConfirmed,
                migrationVersion: int(["migrationVersion"]) ?? LegacyStreak.currentMigrationVersion,
                recordedAt: LoseItDateParser.parse(string(["recordedAt"]) ?? "", calendar: calendar) ?? .now)
            guard legacy.isWellFormed else {
                skip("Legacy streak", "Values are outside a plausible range", count: 1)
                return
            }
            preview.legacy = StreakEngine.merge(preview.legacy, with: legacy) ?? legacy
        }

        private enum ForcedKind { case weight, dailySummary }

        private mutating func consumeDictionary(_ dictionary: [String: Any], forcedKind: ForcedKind? = nil) {
            var flat: [String: String] = [:]
            for (key, value) in dictionary {
                if let nested = value as? [String: Any] {
                    for (nestedKey, nestedValue) in nested {
                        flat[LoseItImporter.normalize(nestedKey)] = LoseItImporter.stringValue(nestedValue)
                    }
                } else {
                    flat[LoseItImporter.normalize(key)] = LoseItImporter.stringValue(value)
                }
            }
            let record = RawRecord(values: flat, headers: Dictionary(uniqueKeysWithValues: flat.keys.map { ($0, $0) }))
            switch forcedKind {
            case .weight:
                guard let date = rowDate(record) else {
                    skip("Rows without a date", "Weight row had no readable date", count: 1)
                    return
                }
                makeWeight(record, date: date)
            case .dailySummary:
                guard let date = rowDate(record) else {
                    skip("Rows without a date", "Summary row had no readable date", count: 1)
                    return
                }
                makeSummary(record, date: date)
            case nil:
                consume(record)
            }
        }

        private func rowDate(_ record: RawRecord) -> Date? {
            guard let text = record.text(LoseItImporter.Alias.date) else { return nil }
            return LoseItDateParser.parse(text, calendar: calendar)
        }

        private mutating func consumeDelimited(_ text: String, name: String) {
            let rows = CSVReader.rows(from: text)
            guard rows.count > 1 else {
                skip("Unreadable files", "No data rows", count: 1)
                return
            }
            let header = rows[0]
            let keys = header.map(LoseItImporter.normalize)
            var headerMap: [String: String] = [:]
            for (index, key) in keys.enumerated() where !key.isEmpty {
                headerMap[key] = header[index]
            }
            for row in rows.dropFirst() {
                guard row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { continue }
                var values: [String: String] = [:]
                for (index, key) in keys.enumerated() where !key.isEmpty && index < row.count {
                    values[key] = row[index]
                }
                consume(RawRecord(values: values, headers: headerMap))
            }
        }

        private mutating func consume(_ record: RawRecord) {
            let dateText = record.text(LoseItImporter.Alias.date)
            guard let dateText else {
                skip("Rows without a date", "No date column found on the row", count: 1)
                return
            }
            guard let date = LoseItDateParser.parse(dateText, calendar: calendar) else {
                skip("Rows with an unreadable date", "Could not parse \(dateText)", count: 1)
                return
            }
            let hasName = record.has(LoseItImporter.Alias.name)
            let hasWeight = record.has(LoseItImporter.Alias.weight)
            let hasCalories = record.has(LoseItImporter.Alias.calories)

            if hasName {
                makeEntry(record, date: date)
            } else if hasWeight {
                makeWeight(record, date: date)
            } else if hasCalories {
                makeSummary(record, date: date)
            } else {
                skip("Unrecognized rows", "No food name, weight or calories", count: 1)
            }
        }

        private mutating func makeEntry(_ record: RawRecord, date: Date) {
            guard let name = record.text(LoseItImporter.Alias.name), !name.isEmpty else { return }

            let caloriesRaw = record.number(LoseItImporter.Alias.calories) ?? 0
            let energyHeader = record.header(LoseItImporter.Alias.calories) ?? ""
            let calories = Int((energyHeader.contains("kj") ? caloriesRaw / 4.184 : caloriesRaw).rounded())
            guard (0...20_000).contains(calories) else {
                skip("Food entries", "Calories outside a plausible range", count: 1)
                return
            }

            var servings = record.number(LoseItImporter.Alias.servings) ?? 1
            var loggedQuantity: Double?
            var loggedUnit: String?
            if let quantity = record.number(LoseItImporter.Alias.quantity), quantity > 0, record.number(LoseItImporter.Alias.servings) == nil {
                let unit = record.text(LoseItImporter.Alias.unit)
                if let unit, !unit.isEmpty {
                    loggedQuantity = quantity
                    loggedUnit = unit
                } else {
                    servings = quantity
                }
            }
            guard servings.isFinite, servings > 0, servings <= 100 else {
                skip("Food entries", "Serving count outside a plausible range", count: 1)
                return
            }

            let brand = record.text(LoseItImporter.Alias.brand) ?? ""
            let serving = record.text(LoseItImporter.Alias.serving) ?? "1 serving"
            let meal = LoseItImporter.meal(from: record.text(LoseItImporter.Alias.meal),
                                            default: defaultMeal)
            let food = Food(name: name, brand: brand, serving: serving,
                            calories: calories,
                            protein: max(0, record.number(LoseItImporter.Alias.protein) ?? 0),
                            carbs: max(0, record.number(LoseItImporter.Alias.carbs) ?? 0),
                            fat: max(0, record.number(LoseItImporter.Alias.fat) ?? 0),
                            fiber: record.number(LoseItImporter.Alias.fiber).map { max(0, $0) },
                            sodium: record.number(LoseItImporter.Alias.sodium).map { max(0, $0) },
                            source: LoseItImporter.sourceLabel)

            let fingerprint = LoseItImporter.fingerprint(dayKey: StreakEngine.dayKey(for: date, calendar: calendar),
                                                         meal: meal, name: name, brand: brand,
                                                         servings: servings, calories: calories)
            if existingFingerprints.contains(fingerprint) {
                preview.duplicateEntries += 1
                return
            }
            if !seen.insert(fingerprint).inserted {
                preview.duplicateEntries += 1
                return
            }
            var entry = DiaryEntry(food: food, meal: meal, servings: servings, date: date)
            entry.loggedQuantity = loggedQuantity
            entry.loggedUnit = loggedUnit
            entry.importFingerprint = fingerprint
            preview.entries.append(entry)
            note(date: date)
        }

        private mutating func makeWeight(_ record: RawRecord, date: Date) {
            guard var kilograms = record.number(LoseItImporter.Alias.weight) else { return }
            let header = record.header(LoseItImporter.Alias.weight) ?? ""
            if header.contains("lb") || header.contains("pound") {
                kilograms *= 0.453_592_37
            }
            guard (20...500).contains(kilograms) else {
                skip("Weight records", "Outside 20–500 kg after unit conversion", count: 1)
                return
            }
            let duplicate = existingWeights.contains {
                abs($0.kilograms - kilograms) < 0.05 &&
                abs($0.date.timeIntervalSince(date)) < 12 * 3600
            } || preview.weights.contains {
                abs($0.kilograms - kilograms) < 0.05 &&
                abs($0.date.timeIntervalSince(date)) < 12 * 3600
            }
            if duplicate {
                preview.duplicateWeights += 1
                return
            }
            preview.weights.append(WeightEntry(date: date, kilograms: kilograms))
            note(date: date)
        }

        private mutating func makeSummary(_ record: RawRecord, date: Date) {
            let calories = Int((record.number(LoseItImporter.Alias.calories) ?? 0).rounded())
            guard calories > 0 else { return }
            preview.dailySummaries.append(LoseItDailySummary(
                date: date, calories: calories,
                protein: record.number(LoseItImporter.Alias.protein),
                carbs: record.number(LoseItImporter.Alias.carbs),
                fat: record.number(LoseItImporter.Alias.fat)))
            note(date: date)
        }

        private mutating func note(date: Date) {
            if preview.earliestDate == nil || date < preview.earliestDate! { preview.earliestDate = date }
            if preview.latestDate == nil || date > preview.latestDate! { preview.latestDate = date }
        }

        mutating func finish() -> LoseItImportPreview {
            if !unreadableFiles.isEmpty {
                preview.warnings.append("Could not open archive: \(unreadableFiles.joined(separator: ", ")). Unzip it and choose the CSV files instead.")
            }
            if !preview.dailySummaries.isEmpty {
                skip("Daily summaries", "Stored as summaries only — NAGISEN never invents food entries from calorie totals",
                     count: preview.dailySummaries.count)
            }
            preview.skipped = skippedRows
                .sorted { $0.key < $1.key }
                .map { LoseItSkippedCategory(category: $0.value.reason.isEmpty ? "Rows" : $0.key.components(separatedBy: "|")[0],
                                             reason: $0.value.reason,
                                             rowCount: $0.value.count) }
            return preview
        }
    }

    // MARK: - Field aliases

    enum Alias {
        static let date = ["date", "day", "loggeddate", "entrydate", "diarydate", "timestamp", "datetime", "createdat", "consumedat"]
        static let meal = ["meal", "mealname", "mealtype", "mealcategory", "category", "timeofday"]
        static let name = ["food", "foodname", "name", "item", "itemname", "description", "fooddescription", "title"]
        static let brand = ["brand", "brandname", "manufacturer", "restaurant", "store"]
        static let servings = ["servings", "servingcount", "numberofservings", "nservings", "servingqty"]
        static let quantity = ["quantity", "qty", "amount", "count"]
        static let unit = ["unit", "units", "servingunit", "measureunit"]
        static let serving = ["serving", "servingsize", "portion", "portiondescription", "servingdescription", "measure", "servingsizeunit"]
        static let calories = ["calories", "kcal", "energy", "energykcal", "energykj", "calorieskcal",
                               "totalcalories", "caloriesper", "caloriesperserving"]
        static let protein = ["protein", "proteing", "protein_g", "proteins"]
        static let carbs = ["carbs", "carbohydrates", "carbsg", "totalcarbohydrate", "totalcarbohydrates", "carbohydrate"]
        static let fat = ["fat", "fatg", "totalfat", "fattyacids"]
        static let fiber = ["fiber", "fibreg", "dietaryfiber", "fibre"]
        static let sodium = ["sodium", "sodiummg", "sodiumg", "salt"]
        static let weight = ["weight", "weightkg", "weightlbs", "weightpounds", "kilograms", "pounds", "lbs", "kg", "weightvalue"]
    }

    // MARK: - Helpers

    static func normalize(_ key: String) -> String {
        key.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    static func stringValue(_ value: Any) -> String {
        switch value {
        case let string as String: return string
        case let number as NSNumber: return number.stringValue
        case is NSNull: return ""
        default: return ""
        }
    }

    static func meal(from raw: String?, default fallback: Meal) -> Meal {
        guard let raw else { return fallback }
        let value = raw.lowercased()
        if value.contains("breakfast") || value.contains("morning") { return .breakfast }
        if value.contains("lunch") || value.contains("midday") { return .lunch }
        if value.contains("dinner") || value.contains("supper") || value.contains("evening") { return .dinner }
        if value.contains("snack") || value.contains("dessert") || value.contains("drink") { return .snacks }
        return fallback
    }

    static func fingerprint(dayKey: String, meal: Meal, name: String, brand: String,
                            servings: Double, calories: Int) -> String {
        let payload = [sourceLabel, dayKey, meal.rawValue, name.lowercased(), brand.lowercased(),
                       String(format: "%.3f", servings), String(calories)].joined(separator: "|")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return "loseit:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    static func decodeText(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .windowsCP1252) { return text }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        return nil
    }
}

// MARK: - CSV

enum CSVReader {
    /// RFC 4180 style parser with delimiter sniffing. Handles quoted fields, escaped quotes,
    /// CRLF and embedded newlines.
    static func rows(from text: String) -> [[String]] {
        let stripped = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let delimiter = sniffDelimiter(in: stripped)
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var index = stripped.startIndex

        while index < stripped.endIndex {
            let character = stripped[index]
            if inQuotes {
                if character == "\"" {
                    let next = stripped.index(after: index)
                    if next < stripped.endIndex, stripped[next] == "\"" {
                        field.append("\"")
                        index = stripped.index(after: next)
                        continue
                    }
                    inQuotes = false
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    inQuotes = true
                case delimiter:
                    row.append(field)
                    field = ""
                case "\n":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                case "\r":
                    break
                default:
                    field.append(character)
                }
            }
            index = stripped.index(after: index)
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows.filter { line in line.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
    }

    private static func sniffDelimiter(in text: String) -> Character {
        let sample = text.split(separator: "\n", maxSplits: 5, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let candidates: [Character] = [",", ";", "\t"]
        var best: Character = ","
        var bestCount = -1
        for candidate in candidates {
            let count = sample.filter { $0 == candidate }.count
            if count > bestCount { best = candidate; bestCount = count }
        }
        return bestCount <= 0 ? "," : best
    }
}

// MARK: - Dates

enum LoseItDateParser {
    private struct Format {
        let pattern: String
        let hasTime: Bool
    }

    /// Ordered by confidence: ISO and year-first read unambiguously, month-first matches
    /// Lose It!'s US formats, day-first is the last resort.
    private static let formats: [Format] = [
        Format(pattern: "yyyy-MM-dd'T'HH:mm:ss.SSS", hasTime: true),
        Format(pattern: "yyyy-MM-dd'T'HH:mm:ss", hasTime: true),
        Format(pattern: "yyyy-MM-dd HH:mm:ss", hasTime: true),
        Format(pattern: "yyyy-MM-dd HH:mm", hasTime: true),
        Format(pattern: "yyyy-MM-dd", hasTime: false),
        Format(pattern: "yyyy/MM/dd", hasTime: false),
        Format(pattern: "MM/dd/yyyy HH:mm", hasTime: true),
        Format(pattern: "MM/dd/yyyy", hasTime: false),
        Format(pattern: "M/d/yyyy", hasTime: false),
        Format(pattern: "MM/dd/yy", hasTime: false),
        Format(pattern: "M/d/yy", hasTime: false),
        Format(pattern: "MMM d, yyyy", hasTime: false),
        Format(pattern: "MMMM d, yyyy", hasTime: false),
        Format(pattern: "d MMM yyyy", hasTime: false),
        Format(pattern: "dd MMM yyyy", hasTime: false),
        Format(pattern: "yyyyMMdd", hasTime: false)
    ]

    static func parse(_ raw: String, calendar: Calendar = .current) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let iso = isoFormatter.date(from: trimmed) { return iso }
        if let iso = isoFormatterWithFraction.date(from: trimmed) { return iso }

        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = format.pattern
            formatter.isLenient = false
            guard let date = formatter.date(from: trimmed) else { continue }
            if format.hasTime { return date }
            return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        }
        if let dayKey = Optional(trimmed), StreakEngine.isValidDayKey(dayKey) {
            return StreakEngine.date(fromDayKey: dayKey, calendar: calendar)
        }
        return nil
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoFormatterWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
