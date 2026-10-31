import SwiftUI

/// Day-by-day proof that the streak is intact: every day from the start of the run to today,
/// with the number it carries and whether it is finished.
struct StreakAuditView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss

    @State private var audit: StreakAudit?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let audit {
                        summary(audit)
                        if audit.empty {
                            Text("No streak to check yet.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(18)
                                .nagisenGlass(in: RoundedRectangle(cornerRadius: 18))
                        } else {
                            days(audit)
                        }
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(40)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .background(NagisenBackdrop())
            .nagisenSheetBar("Streak audit", onClose: { dismiss() })
        }
        .task {
            guard audit == nil else { return }
            audit = StreakAuditor.build(
                completedDays: store.completedLoggingDays,
                legacy: store.legacyStreak,
                today: .now,
                calendar: .current,
                value: { store.streakSnapshot(asOf: $0).activeStreak })
        }
    }

    private func summary(_ audit: StreakAudit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(audit.countedDays.formatted(.number.grouping(.automatic))) days checked")
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.ink)

            HStack(spacing: 8) {
                Image(systemName: audit.isClean ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(audit.isClean ? Theme.accentText : .orange)
                Text(statusText(audit))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
            }

            if let first = audit.firstDayKey, let last = audit.lastDayKey {
                Text("\(first) → \(last)")
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.muted)
            }

            Text("Each day is checked against the number the diary shows on it.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .nagisenGlass(in: RoundedRectangle(cornerRadius: 20))
    }

    private func statusText(_ audit: StreakAudit) -> String {
        if audit.isClean { return "No gaps · the count is consistent every day" }
        var parts: [String] = []
        if !audit.gaps.isEmpty { parts.append("\(audit.gaps.count) unfinished day(s)") }
        if !audit.driftDays.isEmpty { parts.append("\(audit.driftDays.count) day(s) disagree with the diary") }
        return parts.joined(separator: " · ")
    }

    private func days(_ audit: StreakAudit) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(audit.rows.reversed())) { row in
                HStack(spacing: 12) {
                    Image(systemName: row.counted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(row.counted ? Theme.accentText : Theme.muted)
                        .font(.system(size: 15))

                    Text(row.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)

                    Spacer(minLength: 8)

                    if row.drift {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Text("Day \(row.dayNumber.formatted(.number.grouping(.automatic)))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(row.counted ? Theme.muted : Theme.muted.opacity(0.7))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if row.id != audit.rows.first?.id {
                    Rectangle()
                        .fill(Theme.line)
                        .frame(height: 1)
                        .padding(.leading, 44)
                }
            }
        }
        .nagisenGlass(in: RoundedRectangle(cornerRadius: 18))
    }
}
