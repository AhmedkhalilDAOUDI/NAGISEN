import SwiftUI

struct ProgressViewScreen: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingGoals = false
    @State private var showingReview = false
    @State private var showingWeightHistory = false
    @State private var showingAddWeight = false

    private var latestWeight: WeightEntry? {
        store.weights.max { $0.date < $1.date }
    }

    private var lastRecorded: String {
        guard let latestWeight else { return "No entries yet" }
        return "Last recorded " + RelativeDateTimeFormatter().localizedString(for: latestWeight.date, relativeTo: .now)
    }

    private var days: [Date] {
        (0..<7).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: .now) }
    }

    var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    NagisenHeader("Your goals", subtitle: "Daily targets and your progress", onBack: { dismiss() })
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("TODAY'S TARGETS")
                                .font(.caption2.weight(.semibold)).tracking(2.2)
                                .foregroundStyle(Theme.muted)
                            Spacer()
                            Button("Edit") { showingGoals = true }
                                .font(.subheadline.weight(.semibold))
                        }
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(store.goals(on: .now).calories.formatted())")
                                .font(.system(size: 40, weight: .regular, design: .serif))
                            Text("kcal / day").font(.subheadline).foregroundStyle(Theme.muted)
                        }
                        Text("Bonus calories: \(store.weeklyCalorieBonus(on: .now).formatted())")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.accentText)
                        HStack {
                            target("Protein", grams: store.goals(on: .now).protein, color: Theme.protein)
                            target("Carbs", grams: store.goals(on: .now).carbs, color: Theme.carbs)
                            target("Fat", grams: store.goals(on: .now).fat, color: Theme.fat)
                        }
                    }
                    .accentCardStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 17) {
                        HStack {
                            Text("Weight")
                                .font(.system(size: 23, weight: .semibold))
                            Spacer()
                            Button { showingWeightHistory = true } label: {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(Theme.muted)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("View weight history")
                        }
                        HStack(alignment: .bottom, spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                if let latestWeight {
                                    Text("\(latestWeight.kilograms.formatted(.number.precision(.fractionLength(1)))) kg")
                                        .font(.system(size: 34, weight: .regular, design: .serif))
                                }
                                Text(lastRecorded)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer(minLength: 0)
                            Button { showingAddWeight = true } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 19, weight: .medium))
                                    .foregroundStyle(Theme.accentText)
                                    .frame(width: 44, height: 44)
                                    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.line, lineWidth: 1))
                            }
                            .accessibilityLabel("Log weight")
                        }
                    }
                    .accentCardStyle(Theme.slate)
                    DailyGuidanceCard()
                    Button { showingReview = true } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(Theme.accentText)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Weekly check-in").font(.system(size: 21, design: .serif))
                                Text("See what your logs suggest").font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                        }
                        .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(.plain)
                    .softCardStyle()
                    VStack(alignment: .leading, spacing: 18) {
                        Text("DAILY CALORIES")
                            .font(.caption2.weight(.semibold)).tracking(2.2)
                            .foregroundStyle(Theme.muted)
                        HStack(alignment: .bottom, spacing: 10) {
                            ForEach(days, id: \.self) { day in
                                let eaten = store.totals(on: day).calories
                                VStack(spacing: 8) {
                                    Text(eaten == 0 ? "–" : "\(eaten)")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(Theme.muted)
                                        .minimumScaleFactor(0.7)
                                        .lineLimit(1)
                                    GeometryReader { geometry in
                                        VStack {
                                            Spacer(minLength: 0)
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(eaten > store.goals(on: day).calories ? Theme.red : Theme.protein)
                                                .frame(height: max(4, geometry.size.height * min(CGFloat(eaten) / CGFloat(max(store.goals(on: day).calories, 1)), 1)))
                                        }
                                    }
                                    .frame(height: 140)
                                    Text(day.formatted(.dateTime.weekday(.narrow)))
                                        .font(.caption.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        Text("Each bar shows a share of your daily goal.")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    .cardStyle()

                    let loggedDays = days.filter { !store.entries(on: $0).isEmpty }
                    let total = loggedDays.reduce(0) { $0 + store.totals(on: $1).calories }
                    HStack(spacing: 14) {
                        StatCard(value: "\(loggedDays.count)", label: "days logged")
                        StatCard(value: loggedDays.isEmpty ? "–" : "\(total / loggedDays.count)", label: "avg. calories / logged day")
                    }
                    Text("Your entries stay on this device. Nutritional values in the starter catalog are estimates; check packaging for accuracy.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                .foregroundStyle(Theme.ink)
                .padding(24)
                .padding(.bottom, 32)
            }
            .scrollClipDisabled()
            .softTopScrollEdgeEffect()
            .background(NagisenBackdrop())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingGoals) {
                NavigationStack { GoalsView() }
            }
            .sheet(isPresented: $showingReview) {
                NavigationStack { WeeklyReviewView() }
            }
            .sheet(isPresented: $showingAddWeight) {
                NavigationStack { AddWeightView() }
            }
            .navigationDestination(isPresented: $showingWeightHistory) {
                WeightHistoryView()
            }
    }

    private func target(_ name: String, grams: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(name.uppercased()).font(.caption2.weight(.semibold))
            }
            .foregroundStyle(color)
            Text("\(grams)g").font(.system(size: 21, design: .serif)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value).font(.system(size: 30, weight: .regular, design: .serif))
                .foregroundStyle(Theme.ink)
            Text(label).font(.caption).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .cardStyle()
    }
}

struct GoalsView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    @State private var calories = ""
    @State private var protein = ""
    @State private var fat = ""
    @State private var selectedWeekday = 0

    private let weekdays = [(1, "Sunday"), (2, "Monday"), (3, "Tuesday"), (4, "Wednesday"),
                            (5, "Thursday"), (6, "Friday"), (7, "Saturday")]

    private func goal(_ text: String) -> Int? {
        guard let value = Int(text), value > 0, value <= 10_000 else { return nil }
        return value
    }

    private var calculatedCarbs: Int? {
        guard let c = goal(calories), let p = goal(protein), let f = goal(fat) else { return nil }
        return NutritionGoals(calories: c, protein: p, carbs: 0, fat: f).calculatedCarbs
    }

    private var valid: Bool { calculatedCarbs != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                NagisenHeader("Daily goals", subtitle: "Your targets, at a glance.", onBack: { dismiss() },
                              actionTitle: "Save", actionEnabled: valid, onAction: save)
                NagisenSection("Schedule") {
                    Picker("Apply to", selection: $selectedWeekday) {
                        Text("Every day").tag(0)
                        ForEach(weekdays, id: \.0) { weekday in
                            Text(weekday.1).tag(weekday.0)
                        }
                    }
                    .frame(minHeight: 54)
                }
                NagisenSection("Energy") {
                    NagisenTextRow("Calories", placeholder: "0", unit: "kcal", text: $calories)
                }
                NagisenSection("Macros") {
                    NagisenTextRow("Protein", placeholder: "0", unit: "g", text: $protein, color: Theme.protein)
                    Divider().overlay(Theme.line)
                    NagisenTextRow("Fat", placeholder: "0", unit: "g", text: $fat, color: Theme.fat)
                    Divider().overlay(Theme.line)
                    HStack {
                        Text("Carbs · calculated")
                        Spacer()
                        Text(calculatedCarbs.map { "\($0) g" } ?? "Over budget")
                            .foregroundStyle(calculatedCarbs == nil ? Theme.accentText : Theme.carbs)
                    }
                    .font(.subheadline)
                    .frame(minHeight: 54)
                }
                Text("Protein uses 4 kcal/g and fat uses 9 kcal/g. The calories left become carbs at 4 kcal/g.")
                    .font(.footnote).foregroundStyle(Theme.muted)
                if selectedWeekday != 0, store.weekdayGoals[selectedWeekday] != nil {
                    Button("Use every-day targets on this day") {
                        store.weekdayGoals.removeValue(forKey: selectedWeekday)
                        loadGoals()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.accentText)
                }
                Text("Choose targets that fit your needs. You can also copy a target from your food plan.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(NagisenBackdrop())
        .tint(Theme.accentText)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            loadGoals()
        }
        .onChange(of: selectedWeekday) { _, _ in loadGoals() }
    }

    private func loadGoals() {
        let value = selectedWeekday == 0 ? store.goals : store.weekdayGoals[selectedWeekday] ?? store.goals
        calories = String(value.calories)
        protein = String(value.protein)
        fat = String(value.fat)
    }

    private func save() {
        guard let c = goal(calories), let p = goal(protein),
              let f = goal(fat), let cb = calculatedCarbs else { return }
        let value = NutritionGoals(calories: c, protein: p, carbs: cb, fat: f)
        if selectedWeekday == 0 { store.goals = value }
        else { store.weekdayGoals[selectedWeekday] = value }
        dismiss()
    }
}

private struct WeeklyReviewView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss

    private var review: WeeklyReview { store.weeklyReview() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                NagisenHeader("Weekly check-in", subtitle: "A small course correction, when the data supports it.",
                              symbol: "xmark", onBack: { dismiss() })
                NagisenSection("Your evidence") {
                    LabeledContent("Food days", value: "\(review.loggedDays) / 14").frame(minHeight: 54)
                    Divider()
                    LabeledContent("Weigh-ins", value: "\(review.weightEntries)").frame(minHeight: 54)
                    if let change = review.trendChangeKg {
                        Divider()
                        LabeledContent("Weight trend", value: "\(change.formatted(.number.precision(.fractionLength(2)))) kg / week")
                            .frame(minHeight: 54)
                    }
                    if let average = review.averageCalories {
                        Divider()
                        LabeledContent("Logged intake", value: "\(average) kcal / day").frame(minHeight: 54)
                    }
                    if let expenditure = review.estimatedExpenditure {
                        Divider()
                        LabeledContent("Energy estimate", value: "≈ \(expenditure) kcal / day").frame(minHeight: 54)
                    }
                }
                Text(review.reason).font(.body).foregroundStyle(Theme.ink)
                if let suggested = review.suggestedCalories {
                    NagisenSection("Suggested target") {
                        LabeledContent("Current", value: "\(store.goals.calories) kcal").frame(minHeight: 54)
                        Divider()
                        LabeledContent("Suggested", value: "\(suggested) kcal").frame(minHeight: 54)
                    }
                    if suggested != store.goals.calories {
                        NagisenPrimaryButton("Use suggested target") {
                            store.apply(review)
                            dismiss()
                        }
                    }
                }
                Text("This is a rough trend from your logged days, not a measure of every meal or a medical prescription. Review changes before applying them.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 32)
        }
        .background(NagisenBackdrop())
        .toolbar(.hidden, for: .navigationBar)
    }
}
