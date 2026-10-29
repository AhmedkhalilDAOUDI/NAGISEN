import Foundation

/// A streak achieved in another tracker and confirmed by the user.
///
/// NAGISEN never invents diary entries or completed days for history it did not observe.
/// A `LegacyStreak` is the explicit, auditable record of those days: `count` consecutive
/// days ending on `lastConfirmedDayKey`. The engine walks forward from that anchor, so the
/// number can only grow when the user actually logs a qualifying day in NAGISEN.
struct LegacyStreak: Codable, Equatable {
    /// Human readable origin, e.g. "Lose It!".
    var source: String
    /// Number of consecutive days ending on `lastConfirmedDayKey`.
    var count: Int
    /// Calendar day the achievement was last confirmed, formatted `yyyy-MM-dd`.
    var lastConfirmedDayKey: String
    /// The zone the confirmation was made in. Kept for provenance; day keys are already
    /// calendar-day strings, so no conversion happens at read time.
    var timeZoneIdentifier: String
    /// How the value was established. Only user confirmation is accepted today.
    var verification: String
    var migrationVersion: Int
    var recordedAt: Date

    static let currentMigrationVersion = 3
    /// Version whose achievement is written into the diary as real completed days.
    static let materializedVersion = 3
    static let userConfirmed = "user-confirmed"

    init(source: String, count: Int, lastConfirmedDayKey: String,
         timeZoneIdentifier: String = TimeZone.current.identifier,
         verification: String = LegacyStreak.userConfirmed,
         migrationVersion: Int = LegacyStreak.currentMigrationVersion,
         recordedAt: Date = .now) {
        self.source = source
        self.count = count
        self.lastConfirmedDayKey = lastConfirmedDayKey
        self.timeZoneIdentifier = timeZoneIdentifier
        self.verification = verification
        self.migrationVersion = migrationVersion
        self.recordedAt = recordedAt
    }

    private enum CodingKeys: String, CodingKey {
        case source, count, lastConfirmedDayKey, timeZoneIdentifier, verification,
             migrationVersion, recordedAt
    }

    /// Tolerant decoding: older or hand written migration files may omit the metadata.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "Lose It!"
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
        lastConfirmedDayKey = try container.decodeIfPresent(String.self, forKey: .lastConfirmedDayKey) ?? ""
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
            ?? TimeZone.current.identifier
        verification = try container.decodeIfPresent(String.self, forKey: .verification)
            ?? LegacyStreak.userConfirmed
        migrationVersion = try container.decodeIfPresent(Int.self, forKey: .migrationVersion)
            ?? LegacyStreak.currentMigrationVersion
        recordedAt = try container.decodeIfPresent(Date.self, forKey: .recordedAt)
            ?? Date(timeIntervalSince1970: 0)
    }

    var isWellFormed: Bool {
        count > 0 && StreakEngine.isValidDayKey(lastConfirmedDayKey) && count < 100_000
    }

    /// v1 stored the achievement ending on the very day it was confirmed, so that day was
    /// already spent: pressing "Done Logging" could not add anything. From v2 the count ends
    /// the day before, which makes the confirmation day earnable like any other.
    var migratedToCurrentVersion: LegacyStreak {
        guard migrationVersion < LegacyStreak.currentMigrationVersion else { return self }
        var record = self
        // Only v1 stored the achievement ending on its own confirmation day.
        if migrationVersion < 2,
           let anchor = StreakEngine.date(fromDayKey: lastConfirmedDayKey),
           let previous = Calendar.current.date(byAdding: .day, value: -1, to: anchor) {
            record.lastConfirmedDayKey = StreakEngine.dayKey(for: previous)
        }
        record.migrationVersion = LegacyStreak.currentMigrationVersion
        return record
    }

    /// Every calendar day the achievement covers, oldest first. From version 3 these are
    /// written into the diary as real completed days, so the streak is made of editable marks
    /// rather than a frozen number: unticking a day ends the run exactly where it should.
    func dayKeys(calendar: Calendar = .current) -> [String] {
        guard isWellFormed,
              let firstKey = firstDayKey(calendar: calendar),
              let first = StreakEngine.date(fromDayKey: firstKey, calendar: calendar) else { return [] }
        var keys: [String] = []
        keys.reserveCapacity(count)
        var day = first
        for _ in 0..<count {
            keys.append(StreakEngine.dayKey(for: day, calendar: calendar))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return keys
    }

    /// First day covered by the achievement (inclusive), derived from the end date and count.
    func firstDayKey(calendar: Calendar = .current) -> String? {
        guard isWellFormed,
              let end = StreakEngine.date(fromDayKey: lastConfirmedDayKey, calendar: calendar),
              let start = calendar.date(byAdding: .day, value: -(count - 1), to: end) else { return nil }
        return StreakEngine.dayKey(for: start, calendar: calendar)
    }
}

/// Everything the diary needs to describe a streak at one point in time.
struct StreakSnapshot: Equatable {
    var legacy: LegacyStreak?
    /// The streak the user sees for the day being viewed.
    var activeStreak: Int
    /// Longest run ever recorded, never below the legacy achievement.
    var longestStreak: Int
    /// Most recent day that counted toward a streak (real logging or the legacy anchor).
    var lastQualifyingDayKey: String?
    /// Days earned in NAGISEN after the legacy anchor.
    var continuationDays: Int
    /// True when `activeStreak` includes the legacy achievement.
    var continuesLegacy: Bool
    var isCompleteToday: Bool

    static let empty = StreakSnapshot(legacy: nil, activeStreak: 0, longestStreak: 0,
                                      lastQualifyingDayKey: nil, continuationDays: 0,
                                      continuesLegacy: false, isCompleteToday: false)
}

/// Pure streak arithmetic. No storage, no SwiftUI, no clock of its own: everything is
/// injected so the behaviour is deterministic under test.
enum StreakEngine {
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Strict `yyyy-MM-dd` check that also rejects impossible dates such as `2026-02-31`.
    static func isValidDayKey(_ key: String) -> Bool {
        guard key.count == 10 else { return false }
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return false }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        return back.year == year && back.month == month && back.day == day
    }

    static func date(fromDayKey key: String, calendar: Calendar = .current) -> Date? {
        guard isValidDayKey(key) else { return nil }
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// - Parameters:
    ///   - completedDays: `yyyy-MM-dd` keys of days the user marked as done logging.
    ///   - legacy: the migrated achievement, if any.
    ///   - viewedDay: the diary day on screen; may be in the past.
    ///   - today: the current instant (injected so tests can travel in time).
    ///   - recordedLongest: the highest streak NAGISEN has already observed.
    static func snapshot(completedDays: Set<String>,
                         legacy legacyInput: LegacyStreak?,
                         viewedDay: Date,
                         today: Date,
                         calendar: Calendar = .current,
                         recordedLongest: Int = 0) -> StreakSnapshot {
        // A malformed record must never influence arithmetic.
        let legacy = legacyInput?.isWellFormed == true ? legacyInput : nil
        let viewed = calendar.startOfDay(for: viewedDay)
        let todayStart = calendar.startOfDay(for: today)
        let todayKey = dayKey(for: todayStart, calendar: calendar)
        let validDays = completedDays.filter(isValidDayKey)
        // From v3 the achievement is written into `completedDays` as real marks, so the walk
        // below is the only arithmetic. Older records keep the anchor fallback until migrated.
        let materialized = (legacy?.migrationVersion ?? 0) >= LegacyStreak.materializedVersion
        let completeToday = validDays.contains(todayKey)
        let baseline = max(recordedLongest, legacy?.count ?? 0)

        var lastQualifying = validDays.filter { $0 <= todayKey }.max()
        if let legacy, legacy.isWellFormed, legacy.lastConfirmedDayKey <= todayKey,
           lastQualifying == nil || legacy.lastConfirmedDayKey > (lastQualifying ?? "") {
            lastQualifying = legacy.lastConfirmedDayKey
        }

        func result(_ active: Int, continues: Bool) -> StreakSnapshot {
            StreakSnapshot(legacy: legacy, activeStreak: active,
                           longestStreak: max(baseline, active),
                           lastQualifyingDayKey: lastQualifying,
                           continuationDays: continues ? max(0, active - (legacy?.count ?? 0)) : 0,
                           continuesLegacy: continues,
                           isCompleteToday: completeToday)
        }

        // Future days have no streak to report.
        guard viewed <= todayStart else { return result(0, continues: false) }

        // A legacy anchor is a fixed calendar day. Browsing earlier history is answered from
        // the achievement itself: on day N of a 1,563-day run the streak was N.
        if !materialized, let legacy, legacy.isWellFormed,
           let anchor = date(fromDayKey: legacy.lastConfirmedDayKey, calendar: calendar),
           viewed < calendar.startOfDay(for: anchor) {
            if let firstKey = legacy.firstDayKey(calendar: calendar),
               let first = date(fromDayKey: firstKey, calendar: calendar),
               viewed >= calendar.startOfDay(for: first) {
                let elapsed = calendar.dateComponents([.day], from: calendar.startOfDay(for: first),
                                                      to: viewed).day ?? 0
                return result(max(0, elapsed + 1), continues: true)
            }
            return result(0, continues: false)
        }

        // Keep an active streak visible during today before logging is finished.
        var day = viewed
        if day == todayStart && !completeToday,
           let yesterday = calendar.date(byAdding: .day, value: -1, to: day) {
            day = yesterday
        }

        // Migration day: the achievement already covers the anchor. When that anchor is today
        // and logging is not finished, the grace step lands before it — the streak must still
        // read 1,563 rather than fall out of the achievement.
        if !materialized, let legacy,
           let anchorDay = date(fromDayKey: legacy.lastConfirmedDayKey, calendar: calendar),
           day < calendar.startOfDay(for: anchorDay),
           viewed >= calendar.startOfDay(for: anchorDay) {
            return result(legacy.count, continues: true)
        }

        let anchorKey = legacy?.lastConfirmedDayKey
        var run = 0
        var reachedAnchor = false
        var iterations = 0
        while iterations < 40_000 {
            iterations += 1
            let key = dayKey(for: day, calendar: calendar)
            if !materialized, key == anchorKey {
                // The anchor is counted by `legacy.count`, never as an extra day.
                reachedAnchor = true
                break
            }
            guard validDays.contains(key) else { break }
            run += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }

        if reachedAnchor, let legacy {
            return result(legacy.count + run, continues: true)
        }
        if materialized {
            return result(run, continues: run > 0)
        }
        // Missed a day after the anchor: the active streak restarts honestly, while the
        // historical achievement stays intact in `baseline`/`legacy`.
        return result(run, continues: false)
    }

    /// Idempotent merge for repeated migrations. Never lowers a confirmed achievement and
    /// prefers the record that ends later.
    static func merge(_ existing: LegacyStreak?, with incoming: LegacyStreak) -> LegacyStreak? {
        guard incoming.isWellFormed else { return existing }
        guard let existing, existing.isWellFormed else { return incoming }
        if incoming.lastConfirmedDayKey > existing.lastConfirmedDayKey { return incoming }
        if incoming.lastConfirmedDayKey < existing.lastConfirmedDayKey { return existing }
        var merged = existing
        merged.count = max(existing.count, incoming.count)
        return merged
    }
}
