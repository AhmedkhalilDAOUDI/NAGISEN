import SwiftUI

/// The numbers behind the celebration, kept apart from the view so they can be tested.
enum StreakCelebration {
    /// Monday to Sunday of the week containing `date`.
    static func week(containing date: Date, calendar base: Calendar = .current) -> [Date] {
        var calendar = base
        calendar.firstWeekday = 2
        guard let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// Average of (goal − eaten) over days with food logged in the 28 days up to `date`;
    /// positive means under the goal. Nil when nothing was logged.
    static func averageUnderGoal(entries: [DiaryEntry], goal: (Date) -> Int, upTo date: Date,
                                 calendar: Calendar = .current) -> Int? {
        let end = calendar.startOfDay(for: date)
        guard let start = calendar.date(byAdding: .day, value: -27, to: end) else { return nil }
        let days = Dictionary(grouping: entries.filter {
            let day = calendar.startOfDay(for: $0.date)
            return day >= start && day <= end
        }) { calendar.startOfDay(for: $0.date) }
        guard !days.isEmpty else { return nil }
        var total = 0
        for (day, dayEntries) in days {
            let eaten = dayEntries.reduce(0) { $0 + $1.calories }
            total += goal(day) - eaten
        }
        return Int((Double(total) / Double(days.count)).rounded())
    }
}

/// The moment after checking off a day: the streak climbs, the week fills in.
struct StreakCelebrationView: View {
    let streak: Int
    let date: Date
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0.0

    private var week: [Date] { StreakCelebration.week(containing: date) }
    private var average: Int? {
        StreakCelebration.averageUnderGoal(entries: store.entries, goal: { store.goals(on: $0).calories }, upTo: date)
    }

    var body: some View {
        VStack(spacing: 26) {
            VStack(spacing: 6) {
                CountingNumber(value: shown)
                    .font(.system(size: 92, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.accentText)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("day streak")
                    .font(.system(.title2, design: .serif))
                    .foregroundStyle(Theme.ink)
            }
            .padding(.top, 34)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(streak)-day streak")

            VStack(spacing: 16) {
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { day in dayMark(day) }
                }
                if let average {
                    Divider().overlay(Theme.line)
                    Text(average >= 0
                         ? "Over the past 28 days, you've averaged \(average.formatted()) calories under your goal on the days you logged."
                         : "Over the past 28 days, you've averaged \((-average).formatted()) calories over your goal on the days you logged.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .nagisenGlass(in: RoundedRectangle(cornerRadius: 20), tint: Theme.surface.opacity(0.25))

            NagisenPrimaryButton("Keep going") { dismiss() }
        }
        .padding(22)
        .background { DriftingCircles() }
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 30))
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .padding(.horizontal, 16)
        .task {
            if reduceMotion { shown = Double(streak); return }
            shown = Double(max(0, streak - min(streak, 60)))
            withAnimation(.easeOut(duration: 1.3)) { shown = Double(streak) }
        }
        .sensoryFeedback(.success, trigger: shown == Double(streak))
    }

    private func dayMark(_ day: Date) -> some View {
        let calendar = Calendar.current
        let done = store.isLoggingComplete(on: day)
        let isToday = calendar.isDate(day, inSameDayAs: date)
        let future = calendar.startOfDay(for: day) > calendar.startOfDay(for: date)
        let isSunday = calendar.component(.weekday, from: day) == 1
        return VStack(spacing: 7) {
            ZStack {
                if done {
                    Circle().fill(Theme.accent)
                    Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(.white)
                } else if future && isSunday {
                    Circle().strokeBorder(Theme.line, lineWidth: 1)
                    Image(systemName: "trophy").font(.footnote).foregroundStyle(Theme.muted)
                } else {
                    Circle().strokeBorder(Theme.line, lineWidth: 1)
                }
            }
            .frame(width: 34, height: 34)
            .scaleEffect(isToday && done ? (shown == Double(streak) ? 1 : 0.6) : 1)
            .animation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.9), value: shown)
            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                .font(.caption.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Theme.ink : Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide))), \(done ? "logged" : future ? "ahead" : "not logged")")
    }
}

/// Soft wine and copper circles drifting behind a celebration card; still with Reduce Motion.
struct DriftingCircles: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drifting = false

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width, h = geometry.size.height
            ZStack {
                ForEach(0..<6, id: \.self) { i in
                    let size = [150.0, 90, 120, 60, 170, 80][i]
                    Circle()
                        .fill((i.isMultiple(of: 2) ? Theme.red : Theme.accentText).opacity(0.14))
                        .frame(width: size, height: size)
                        .position(x: w * [0.15, 0.85, 0.95, 0.1, 0.6, 0.35][i],
                                  y: h * [0.08, 0.15, 0.55, 0.45, 0.95, 0.75][i] + (drifting ? [14, -10, 18, -16, 12, -12][i] : 0))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) { drifting = true }
        }
    }
}

/// A whole number that counts through every value as it animates.
private struct CountingNumber: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(Int(value.rounded()).formatted())
            .monospacedDigit()
    }
}
