import Foundation

/// One day of the streak, as the audit sees it.
struct StreakAuditRow: Identifiable {
    var id: String { dayKey }
    let dayKey: String
    let date: Date
    /// The number the streak shows on this day.
    let dayNumber: Int
    /// Whether the day is finished, so it adds a day to the run.
    let counted: Bool
    /// True when the diary's own number disagreed with this pass.
    let drift: Bool
}

/// A full pass over every day the streak covers.
struct StreakAudit {
    let rows: [StreakAuditRow]
    let countedDays: Int
    let gaps: [String]
    let driftDays: [String]
    let longest: Int

    var isClean: Bool { gaps.isEmpty && driftDays.isEmpty }
    var firstDayKey: String? { rows.first?.dayKey }
    var lastDayKey: String? { rows.last?.dayKey }
    var empty: Bool { rows.isEmpty }
}

/// Checks the streak day by day instead of making someone scroll the diary.
///
/// The pass walks from the first day the achievement covers to today, counting finished days.
/// Each day's expected number is that running count, which is exactly what the diary shows for a
/// finished day and what it freezes at for an unfinished one. The diary's own calculation is
/// queried for the first day, every unfinished day and a spread through the run, so a disagreement
/// between the two surfaces as drift rather than being averaged away.
enum StreakAuditor {
    static func build(completedDays: Set<String>,
                      legacy: LegacyStreak?,
                      today: Date,
                      calendar: Calendar = .current,
                      value: (Date) -> Int) -> StreakAudit {
        let todayStart = calendar.startOfDay(for: today)

        let start: Date? = {
            if let key = legacy?.firstDayKey(calendar: calendar),
               let day = StreakEngine.date(fromDayKey: key, calendar: calendar) {
                return calendar.startOfDay(for: day)
            }
            return completedDays
                .compactMap { StreakEngine.date(fromDayKey: $0, calendar: calendar) }
                .min()
                .map { calendar.startOfDay(for: $0) }
        }()

        guard let first = start, first <= todayStart else {
            return StreakAudit(rows: [], countedDays: 0, gaps: [], driftDays: [],
                               longest: legacy?.count ?? 0)
        }

        var rows: [StreakAuditRow] = []
        var counted = 0
        var gaps: [String] = []
        var driftDays: [String] = []
        var day = first
        var index = 0

        while day <= todayStart {
            let key = StreakEngine.dayKey(for: day, calendar: calendar)
            let finished = completedDays.contains(key)
            if finished {
                counted += 1
            } else if day < todayStart {
                gaps.append(key)
            }

            var disagreed = false
            let sampled = index % 97 == 0 || index == 1 || !finished
            if sampled, value(day) != counted {
                disagreed = true
                driftDays.append(key)
            }

            rows.append(StreakAuditRow(dayKey: key, date: day, dayNumber: counted,
                                       counted: finished, drift: disagreed))
            index += 1
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return StreakAudit(rows: rows, countedDays: counted, gaps: gaps, driftDays: driftDays,
                           longest: max(legacy?.count ?? 0, counted))
    }
}
