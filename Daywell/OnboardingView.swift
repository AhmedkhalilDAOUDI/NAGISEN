import SwiftUI

/// Mifflin–St Jeor daily calories, shared by the diet plan and first-launch setup.
enum EnergyMath {
    static func dailyCalories(weight: Double, height: Double, age: Int, equation: EnergyEquation,
                              activity: DietActivity, direction: DietDirection) -> Int {
        let resting = 10 * weight + 6.25 * height - 5 * Double(age) + (equation == .male ? 5 : -161)
        let maintenance = resting * activity.factor
        let adjustment: Double = direction == .lose ? -300 : direction == .gain ? 250 : 0
        return Int((max(1200, maintenance + adjustment) / 25).rounded() * 25)
    }
}

/// What first-launch setup asks, and the targets it works out from the answers.
struct OnboardingPlan {
    static let doneKey = "nagisen.onboarded"
    static let tracksCreatineKey = "nagisen.tracksCreatine"

    var equation: EnergyEquation?
    var age = ""
    var height = ""
    var weight = ""
    var direction: DietDirection?
    var trainingDays: Int?
    var country = Locale.current.region?.identifier ?? "MA"
    var takesCreatine: Bool?

    var ageValue: Int? { Int(age).flatMap { (13...100).contains($0) ? $0 : nil } }
    var heightValue: Double? { Self.number(height).flatMap { (120...230).contains($0) ? $0 : nil } }
    var weightValue: Double? { Self.number(weight).flatMap { (30...300).contains($0) ? $0 : nil } }

    /// Training days a week, as the activity level the calorie estimate uses.
    static func activity(trainingDays: Int) -> DietActivity {
        switch trainingDays {
        case ...1: .sedentary
        case 2...3: .light
        case 4...5: .moderate
        default: .veryActive
        }
    }

    /// Calories from Mifflin–St Jeor; protein 2 g/kg when cutting, 1.8 g/kg otherwise; fat about 27%
    /// of calories; carbs fill the rest. Nil until every answer the estimate needs is in.
    var goals: NutritionGoals? {
        guard let equation, let age = ageValue, let height = heightValue, let weight = weightValue,
              let direction, let trainingDays else { return nil }
        let calories = EnergyMath.dailyCalories(weight: weight, height: height, age: age, equation: equation,
                                                activity: Self.activity(trainingDays: trainingDays),
                                                direction: direction)
        let protein = Int((weight * (direction == .lose ? 2.0 : 1.8)).rounded())
        let fat = Int((Double(calories) * 0.27 / 9).rounded())
        let carbs = max(0, (calories - 4 * protein - 9 * fat) / 4)
        return NutritionGoals(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }

    /// About 35 mL per kilogram, rounded to a glass (250 mL), between 1.5 and 4 L.
    var waterGoalML: Int? {
        weightValue.map { min(4000, max(1500, Int(($0 * 35 / 250).rounded()) * 250)) }
    }

    static func hasHistory(_ store: NutritionStore) -> Bool {
        !store.entries.isEmpty || !store.weights.isEmpty || !store.workouts.isEmpty ||
            !store.completedLoggingDays.isEmpty || store.profile.age != nil
    }

    func apply(to store: NutritionStore) {
        guard let goals, let weight = weightValue else { return }
        store.dietPreferences.equation = equation
        store.dietPreferences.direction = direction ?? .maintain
        store.dietPreferences.activity = trainingDays.map(Self.activity(trainingDays:))
        store.profile.age = ageValue
        store.profile.heightCm = heightValue
        store.weights.append(WeightEntry(kilograms: weight))
        store.goals = goals
        if let waterGoalML { store.waterGoalML = waterGoalML }
        UserDefaults.standard.set(country, forKey: UserRegion.key)
        UserDefaults.standard.set(takesCreatine ?? false, forKey: Self.tracksCreatineKey)
    }

    private static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }
}

/// First launch: a few quiet questions, one per page, then the targets they lead to.
struct OnboardingView: View {
    let onFinish: () -> Void
    @EnvironmentObject private var store: NutritionStore
    @State private var plan = OnboardingPlan()
    @State private var step = 0
    @FocusState private var focused: Bool

    private let questions = 6

    private static let countries: [(value: String, label: String)] = Locale.Region.isoRegions
        .filter { $0.identifier.count == 2 && $0.subRegions.isEmpty }
        .compactMap { region in
            Locale.current.localizedString(forRegionCode: region.identifier).map { (region.identifier, $0) }
        }
        .sorted { $0.label < $1.label }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if step > 0 { progress }
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    page
                }
                .padding(.horizontal, 26)
                .padding(.top, step == 0 ? 0 : 30)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, minHeight: step == 0 ? 560 : nil,
                       alignment: step == 0 ? .bottomLeading : .topLeading)
                .id(step)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 24)),
                                        removal: .opacity))
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            NagisenPrimaryButton(buttonTitle, enabled: canContinue) { advance() }
                .padding(.horizontal, 26)
                .padding(.bottom, 12)
        }
        .foregroundStyle(Theme.ink)
        .background(NagisenBackdrop())
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }

    // MARK: - Pages

    @ViewBuilder
    private var page: some View {
        switch step {
        case 0: welcome
        case 1:
            question("Your body", "Which calorie equation fits you?",
                     "Used only to estimate how much energy you burn.")
            choices([(EnergyEquation.female, "Female", nil as String?), (.male, "Male", nil)],
                    selection: $plan.equation)
        case 2:
            question("About you", "Age, height and weight",
                     "Your starting point. Weight goes into your progress as today's entry.")
            VStack(spacing: 0) {
                numberRow("Age", unit: "years", text: $plan.age, valid: plan.ageValue != nil, decimal: false)
                Divider().overlay(Theme.ink.opacity(0.08))
                numberRow("Height", unit: "cm", text: $plan.height, valid: plan.heightValue != nil, decimal: true)
                Divider().overlay(Theme.ink.opacity(0.08))
                numberRow("Weight", unit: "kg", text: $plan.weight, valid: plan.weightValue != nil, decimal: true)
            }
            .padding(.horizontal, 18)
            .nagisenPanel()
        case 3:
            question("Your goal", "What are you working toward?", nil)
            choices([(DietDirection.lose, "Cut", "Lose fat, about 300 kcal under maintenance" as String?),
                     (.maintain, "Maintain", "Hold your weight where it is"),
                     (.gain, "Bulk", "Build, about 250 kcal over maintenance")],
                    selection: $plan.direction)
        case 4:
            question("Training", "How often do you train?", "Sets the activity level in your calorie estimate.")
            choices([(1, "Rarely", "0 to 1 day a week" as String?), (3, "Sometimes", "2 to 3 days a week"),
                     (5, "Often", "4 to 5 days a week"), (7, "Almost daily", "6 to 7 days a week")],
                    selection: $plan.trainingDays)
        case 5:
            question("Where you live", "Your country", "Prices you enter are shown in its currency.")
            NagisenPicker("Country", selection: $plan.country, options: Self.countries)
                .frame(minHeight: 56)
                .padding(.horizontal, 18)
                .nagisenPanel()
            Text("Currency: \(UserRegion.currency(for: plan.country))")
                .font(.caption).foregroundStyle(Theme.muted)
        case 6:
            question("Supplements", "Do you take creatine daily?",
                     "Adds a daily switch on your Dashboard to mark it taken.")
            choices([(true, "Yes", nil as String?), (false, "No", nil)], selection: $plan.takesCreatine)
        default: summary
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            LogoMark().frame(width: 72, height: 72)
            Text("NAGISEN")
                .font(.caption.weight(.semibold)).tracking(6)
                .foregroundStyle(Theme.muted)
            Text("Let's make it yours.")
                .font(.system(size: 38, weight: .regular, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
            Text("Six short questions, so your daily targets fit your body and your goal. You start with a clean slate: nothing logged, nothing borrowed.")
                .font(.body).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var summary: some View {
        question("Your targets", "Here's where you start", "You can change any of this later in Goals.")
        if let goals = plan.goals {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(goals.calories.formatted())
                        .font(.system(size: 56, weight: .regular, design: .serif))
                        .foregroundStyle(Theme.accentText)
                    Text("kcal a day").font(.subheadline).foregroundStyle(Theme.muted)
                }
                HStack(spacing: 0) {
                    macro("Protein", goals.protein, Theme.protein)
                    macro("Carbs", goals.carbs, Theme.carbs)
                    macro("Fat", goals.fat, Theme.fat)
                }
                if let water = plan.waterGoalML {
                    Rectangle().fill(Theme.ink.opacity(0.08)).frame(height: 0.5)
                    HStack {
                        Label("Water", systemImage: "drop").foregroundStyle(Theme.muted)
                        Spacer()
                        Text("\((Double(water) / 1000).formatted(.number.precision(.fractionLength(0...2)))) L a day")
                    }
                    .font(.subheadline)
                }
            }
            .padding(22)
            .nagisenPanel()
        }
    }

    // MARK: - Pieces

    private var progress: some View {
        HStack(spacing: 14) {
            Button { withAnimation(.smooth(duration: 0.35)) { step -= 1 } } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            HStack(spacing: 5) {
                ForEach(1...questions + 1, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Theme.accentText : Theme.ink.opacity(0.12))
                        .frame(height: 2)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(step) of \(questions + 1)")
        }
        .padding(.leading, 12).padding(.trailing, 26)
        .padding(.top, 6)
    }

    private func question(_ kicker: String, _ title: String, _ detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(kicker.uppercased())
                .font(.caption2.weight(.semibold)).tracking(2.4)
                .foregroundStyle(Theme.muted)
            Text(title)
                .font(.system(size: 32, weight: .regular, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail).font(.subheadline).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func choices<Value: Hashable>(_ options: [(Value, String, String?)],
                                          selection: Binding<Value?>) -> some View {
        VStack(spacing: 10) {
            ForEach(options, id: \.1) { value, title, detail in
                let chosen = selection.wrappedValue == value
                Button { withAnimation(.smooth(duration: 0.2)) { selection.wrappedValue = value } } label: {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title).font(.system(size: 19, design: .serif))
                            if let detail {
                                Text(detail).font(.caption).foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 8)
                        ZStack {
                            Circle().strokeBorder(chosen ? Theme.accentText : Theme.ink.opacity(0.2), lineWidth: 0.75)
                            if chosen { Circle().fill(Theme.accentText).padding(5) }
                        }
                        .frame(width: 22, height: 22)
                    }
                    .padding(.horizontal, 18).frame(minHeight: 64)
                    .contentShape(Rectangle())
                    .nagisenPanel(cornerRadius: 18)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Theme.accentText.opacity(chosen ? 0.55 : 0), lineWidth: 0.75)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }

    private func numberRow(_ title: String, unit: String, text: Binding<String>, valid: Bool, decimal: Bool) -> some View {
        HStack(spacing: 10) {
            Text(title).foregroundStyle(Theme.muted)
            Spacer()
            TextField("0", text: text)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .focused($focused)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 24, design: .serif))
                .foregroundStyle(text.wrappedValue.isEmpty || valid ? Theme.ink : Theme.danger)
                .frame(maxWidth: 120)
            Text(unit).font(.subheadline).foregroundStyle(Theme.muted).frame(width: 44, alignment: .leading)
        }
        .frame(minHeight: 60)
    }

    private func macro(_ name: String, _ grams: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name.uppercased()).font(.caption2.weight(.semibold)).tracking(1.6).foregroundStyle(color)
            Text("\(grams) g").font(.system(size: 22, design: .serif))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Flow

    private var buttonTitle: String {
        switch step {
        case 0: "Begin"
        case questions + 1: "Start NAGISEN"
        default: "Continue"
        }
    }

    private var canContinue: Bool {
        switch step {
        case 1: plan.equation != nil
        case 2: plan.ageValue != nil && plan.heightValue != nil && plan.weightValue != nil
        case 3: plan.direction != nil
        case 4: plan.trainingDays != nil
        case 6: plan.takesCreatine != nil
        case questions + 1: plan.goals != nil
        default: true
        }
    }

    private func advance() {
        focused = false
        if step == questions + 1 {
            plan.apply(to: store)
            onFinish()
        } else {
            withAnimation(.smooth(duration: 0.35)) { step += 1 }
        }
    }
}

/// The logo's mark: the sun over its two horizon lines.
private struct LogoMark: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size.width
            VStack(spacing: size * 0.09) {
                // The sun's red from the app icon, as in the launch intro.
                Circle().fill(Color(red: 0.70, green: 0.32, blue: 0.25)).frame(width: size * 0.62, height: size * 0.62)
                VStack(spacing: size * 0.06) {
                    Capsule().frame(width: size * 0.9, height: max(1.5, size * 0.035))
                    Capsule().frame(width: size * 0.55, height: max(1, size * 0.022))
                }
                .foregroundStyle(Theme.ink)
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}
