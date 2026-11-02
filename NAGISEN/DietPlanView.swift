import SwiftUI

private struct PlanIngredient {
    let name: String
    let grams: Double
    let kcal100: Double
    let protein100: Double
    let carbs100: Double
    let fat100: Double

    func scaled(_ factor: Double) -> PlanPortion {
        let amount = max(5, (grams * factor / 5).rounded() * 5)
        let ratio = amount / 100
        return PlanPortion(name: name, grams: Int(amount), calories: kcal100 * ratio,
                           protein: protein100 * ratio, carbs: carbs100 * ratio, fat: fat100 * ratio)
    }
}

private struct PlanPortion {
    let name: String
    let grams: Int
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
}

private struct PlanMeal {
    let title: String
    let time: String?
    let portions: [PlanPortion]
    var calories: Int { Int(portions.reduce(0) { $0 + $1.calories }.rounded()) }
    var protein: Int { Int(portions.reduce(0) { $0 + $1.protein }.rounded()) }
    var carbs: Int { Int(portions.reduce(0) { $0 + $1.carbs }.rounded()) }
    var fat: Int { Int(portions.reduce(0) { $0 + $1.fat }.rounded()) }
}

private struct PlanDay {
    let meals: [PlanMeal]
    var calories: Int { meals.reduce(0) { $0 + $1.calories } }
    var protein: Int { meals.reduce(0) { $0 + $1.protein } }
    var carbs: Int { meals.reduce(0) { $0 + $1.carbs } }
    var fat: Int { meals.reduce(0) { $0 + $1.fat } }
}

private enum PlanFood {
    static func item(_ name: String, _ grams: Double, _ kcal: Double, _ protein: Double, _ carbs: Double, _ fat: Double) -> PlanIngredient {
        PlanIngredient(name: name, grams: grams, kcal100: kcal, protein100: protein, carbs100: carbs, fat100: fat)
    }
    static let oats = item("Oats", 65, 389, 16.9, 66.3, 6.9)
    static let yogurt = item("Plain Greek yogurt", 200, 97, 9, 3.9, 5)
    static let berries = item("Berries", 100, 50, 1, 12, 0.3)
    static let banana = item("Banana", 110, 89, 1.1, 22.8, 0.3)
    static let eggs = item("Eggs", 120, 143, 12.6, 0.7, 9.5)
    static let toast = item("Whole-grain bread", 80, 247, 13, 41, 4.2)
    static let avocado = item("Avocado", 85, 160, 2, 8.5, 14.7)
    static let chicken = item("Chicken breast, cooked", 170, 165, 31, 0, 3.6)
    static let rice = item("Brown rice, cooked", 180, 111, 2.6, 23, 0.9)
    static let quinoa = item("Quinoa, cooked", 180, 120, 4.4, 21.3, 1.9)
    static let salmon = item("Salmon, cooked", 170, 206, 22, 0, 12.4)
    static let potatoes = item("Potatoes, cooked", 230, 87, 1.9, 20, 0.1)
    static let vegetables = item("Mixed vegetables", 220, 40, 2, 7, 0.4)
    static let greens = item("Leafy greens", 100, 23, 2.9, 3.6, 0.4)
    static let oliveOil = item("Olive oil", 15, 884, 0, 0, 100)
    static let almonds = item("Almonds", 30, 579, 21.2, 21.6, 49.9)
    static let tofu = item("Firm tofu", 220, 144, 17, 3, 9)
    static let lentils = item("Lentils, cooked", 180, 116, 9, 20, 0.4)
    static let tuna = item("Tuna, canned in water", 150, 116, 26, 0, 1)
    static let cottage = item("Cottage cheese", 200, 98, 11, 3.4, 4.3)
    static let peanutButter = item("Peanut butter", 35, 588, 25, 20, 50)
    static let feta = item("Feta", 60, 265, 14, 4, 21)
    static let walnuts = item("Walnuts", 35, 654, 15, 14, 65)
    static let olives = item("Olives", 60, 115, 0.8, 6, 11)
}

private struct Recipe {
    let title: String
    let ingredients: [PlanIngredient]
}

private enum DietPlanEngine {
    static func direction(_ preference: DietDirection, weight: Double, target: Double?) -> DietDirection {
        guard preference == .automatic else { return preference }
        guard let target else { return .maintain }
        if target < weight - 0.5 { return .lose }
        if target > weight + 0.5 { return .gain }
        return .maintain
    }

    static func calories(weight: Double, height: Double, age: Int,
                         equation: EnergyEquation, activity: DietActivity,
                         direction: DietDirection) -> Int {
        EnergyMath.dailyCalories(weight: weight, height: height, age: age, equation: equation,
                                 activity: activity, direction: direction)
    }

    static func day(style: DietStyle, index: Int, targetCalories: Int, avoiding: [String]) -> PlanDay? {
        let recipes = menu(for: style)
        let picks = recipes.enumerated().compactMap { mealIndex, options -> Recipe? in
            let available = options.filter { recipe in
                !recipe.ingredients.contains { ingredient in
                    avoiding.contains { term in
                        !term.isEmpty && ingredient.name.localizedCaseInsensitiveContains(term)
                    }
                }
            }
            guard !available.isEmpty else { return nil }
            return available[(index + mealIndex) % available.count]
        }
        guard picks.count == recipes.count else { return nil }
        let base = picks.flatMap(\.ingredients).reduce(0.0) { total, item in total + item.kcal100 * item.grams / 100 }
        let factor = Double(targetCalories) / max(base, 1)
        let names = style == .intermittentFasting ? [String(localized: "First meal"), String(localized: "Second meal"), "Dinner"] : ["Breakfast", "Lunch", "Dinner", String(localized: "Snack")]
        let times: [String?] = style == .intermittentFasting ? ["10:00", "14:00", "19:00"] : Array(repeating: nil, count: 4)
        return PlanDay(meals: picks.enumerated().map { position, recipe in
            PlanMeal(title: String(localized: "\(names[position]) · \(recipe.title)"), time: times[position],
                     portions: recipe.ingredients.map { $0.scaled(factor) })
        })
    }

    private static func menu(for style: DietStyle) -> [[Recipe]] {
        let f = PlanFood.self
        let breakfast = [
            Recipe(title: String(localized: "Yogurt, oats & berries"), ingredients: [f.yogurt, f.oats, f.berries]),
            Recipe(title: String(localized: "Eggs, toast & avocado"), ingredients: [f.eggs, f.toast, f.avocado]),
            Recipe(title: String(localized: "Banana oat bowl"), ingredients: [f.oats, f.banana, f.yogurt])
        ]
        let lunch = [
            Recipe(title: String(localized: "Chicken rice bowl"), ingredients: [f.chicken, f.rice, f.vegetables, f.oliveOil]),
            Recipe(title: String(localized: "Tuna quinoa salad"), ingredients: [f.tuna, f.quinoa, f.greens, f.oliveOil]),
            Recipe(title: String(localized: "Tofu rice bowl"), ingredients: [f.tofu, f.rice, f.vegetables, f.oliveOil])
        ]
        let dinner = [
            Recipe(title: String(localized: "Salmon & potatoes"), ingredients: [f.salmon, f.potatoes, f.vegetables]),
            Recipe(title: String(localized: "Chicken & quinoa"), ingredients: [f.chicken, f.quinoa, f.vegetables, f.oliveOil]),
            Recipe(title: String(localized: "Lentil & tofu plate"), ingredients: [f.lentils, f.tofu, f.greens, f.oliveOil])
        ]
        let snack = [
            Recipe(title: String(localized: "Yogurt & almonds"), ingredients: [f.yogurt, f.almonds]),
            Recipe(title: String(localized: "Banana & peanut butter"), ingredients: [f.banana, f.peanutButter]),
            Recipe(title: String(localized: "Cottage cheese & berries"), ingredients: [f.cottage, f.berries])
        ]
        switch style {
        case .balanced: return [breakfast, lunch, dinner, snack]
        case .mediterranean:
            return [
                [Recipe(title: String(localized: "Yogurt, walnuts & berries"), ingredients: [f.yogurt, f.walnuts, f.berries]),
                 Recipe(title: String(localized: "Eggs & whole-grain toast"), ingredients: [f.eggs, f.toast, f.oliveOil])],
                [Recipe(title: String(localized: "Lentil feta salad"), ingredients: [f.lentils, f.feta, f.greens, f.olives, f.oliveOil]),
                 Recipe(title: String(localized: "Tuna quinoa salad"), ingredients: [f.tuna, f.quinoa, f.greens, f.oliveOil])],
                [Recipe(title: String(localized: "Salmon, potatoes & greens"), ingredients: [f.salmon, f.potatoes, f.greens, f.oliveOil]),
                 Recipe(title: String(localized: "Chicken & vegetables"), ingredients: [f.chicken, f.quinoa, f.vegetables, f.oliveOil])],
                [Recipe(title: String(localized: "Fruit & nuts"), ingredients: [f.banana, f.almonds]),
                 Recipe(title: String(localized: "Yogurt & berries"), ingredients: [f.yogurt, f.berries, f.walnuts])]
            ]
        case .highProtein:
            return [
                [Recipe(title: String(localized: "Eggs & Greek yogurt"), ingredients: [f.eggs, f.yogurt, f.berries]),
                 Recipe(title: String(localized: "Cottage cheese oats"), ingredients: [f.cottage, f.oats, f.berries])],
                [Recipe(title: String(localized: "Chicken quinoa bowl"), ingredients: [f.chicken, f.quinoa, f.vegetables]),
                 Recipe(title: String(localized: "Tuna rice bowl"), ingredients: [f.tuna, f.rice, f.vegetables])],
                [Recipe(title: String(localized: "Salmon & tofu plate"), ingredients: [f.salmon, f.tofu, f.vegetables]),
                 Recipe(title: String(localized: "Chicken & potatoes"), ingredients: [f.chicken, f.potatoes, f.vegetables])],
                [Recipe(title: String(localized: "Cottage cheese & almonds"), ingredients: [f.cottage, f.almonds]),
                 Recipe(title: String(localized: "Greek yogurt & peanut butter"), ingredients: [f.yogurt, f.peanutButter])]
            ]
        case .lowerCarb:
            return [
                [Recipe(title: String(localized: "Eggs & avocado"), ingredients: [f.eggs, f.avocado, f.greens]),
                 Recipe(title: String(localized: "Yogurt & walnuts"), ingredients: [f.yogurt, f.walnuts, f.berries])],
                [Recipe(title: String(localized: "Chicken salad"), ingredients: [f.chicken, f.greens, f.avocado, f.oliveOil]),
                 Recipe(title: String(localized: "Tuna feta salad"), ingredients: [f.tuna, f.feta, f.greens, f.oliveOil])],
                [Recipe(title: String(localized: "Salmon & vegetables"), ingredients: [f.salmon, f.vegetables, f.oliveOil]),
                 Recipe(title: String(localized: "Tofu & greens"), ingredients: [f.tofu, f.vegetables, f.oliveOil])],
                [Recipe(title: String(localized: "Cheese & nuts"), ingredients: [f.cottage, f.almonds]),
                 Recipe(title: String(localized: "Yogurt & peanut butter"), ingredients: [f.yogurt, f.peanutButter])]
            ]
        case .keto:
            return [
                [Recipe(title: String(localized: "Eggs, avocado & olive oil"), ingredients: [f.eggs, f.avocado, f.oliveOil]),
                 Recipe(title: String(localized: "Eggs & feta"), ingredients: [f.eggs, f.feta, f.oliveOil])],
                [Recipe(title: String(localized: "Chicken avocado salad"), ingredients: [f.chicken, f.avocado, f.greens, f.oliveOil]),
                 Recipe(title: String(localized: "Tuna olive salad"), ingredients: [f.tuna, f.olives, f.greens, f.oliveOil])],
                [Recipe(title: String(localized: "Salmon & greens"), ingredients: [f.salmon, f.greens, f.oliveOil, f.avocado]),
                 Recipe(title: String(localized: "Chicken, feta & greens"), ingredients: [f.chicken, f.feta, f.greens, f.oliveOil])],
                [Recipe(title: String(localized: "Walnuts & olives"), ingredients: [f.walnuts, f.olives]),
                 Recipe(title: String(localized: "Almonds & feta"), ingredients: [f.almonds, f.feta])]
            ]
        case .intermittentFasting:
            return [
                [Recipe(title: String(localized: "Eggs, toast & yogurt"), ingredients: [f.eggs, f.toast, f.yogurt, f.berries]),
                 Recipe(title: String(localized: "Oat & yogurt bowl"), ingredients: [f.oats, f.yogurt, f.banana, f.almonds])],
                [Recipe(title: String(localized: "Chicken rice bowl"), ingredients: [f.chicken, f.rice, f.vegetables, f.oliveOil]),
                 Recipe(title: String(localized: "Tuna quinoa plate"), ingredients: [f.tuna, f.quinoa, f.vegetables, f.oliveOil])],
                [Recipe(title: String(localized: "Salmon & potatoes"), ingredients: [f.salmon, f.potatoes, f.vegetables, f.yogurt]),
                 Recipe(title: String(localized: "Tofu lentil plate"), ingredients: [f.tofu, f.lentils, f.greens, f.oliveOil])]
            ]
        }
    }
}

struct DietPlanView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDay = 0
    @State private var avoidInput = ""
    @State private var showingGroceries = false
    @State private var mealToLog: PlannedMealSelection?

    /// The plan is sized to the daily calorie goal, which is set (or calculated) in Goals.
    private var target: Int? {
        let calories = store.goals(on: .now).calories
        return calories > 0 ? calories : nil
    }
    private var day: PlanDay? {
        target.flatMap { DietPlanEngine.day(style: store.dietPreferences.style, index: selectedDay,
                                            targetCalories: $0, avoiding: store.foodsToAvoid) }
    }

    private var groceries: [GroceryItem] {
        guard let target else { return [] }
        let portions = (0..<7).compactMap {
            DietPlanEngine.day(style: store.dietPreferences.style, index: $0,
                               targetCalories: target, avoiding: store.foodsToAvoid)
        }.flatMap(\.meals).flatMap(\.portions)
        let grouped = Dictionary(grouping: portions, by: \.name)
        return grouped.map { GroceryItem(name: $0.key, grams: $0.value.reduce(0) { $0 + $1.grams }) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                NagisenHeader("Food plan", subtitle: String(localized: "A week of ideas shaped by your goal."), onBack: { dismiss() })

                VStack(alignment: .leading, spacing: 14) {
                    Text("CHOOSE YOUR STYLE")
                        .font(.caption2.weight(.semibold)).nagisenTracking(2).foregroundStyle(Theme.muted)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                        ForEach(DietStyle.allCases) { style in
                            Button {
                                store.dietPreferences.style = style
                            } label: {
                                Text(ui: style.rawValue)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)
                                    .foregroundStyle(style == store.dietPreferences.style ? Color.white : Theme.ink)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(style == store.dietPreferences.style ? Theme.accent : Theme.paper,
                                                in: RoundedRectangle(cornerRadius: 12))
                            }
                            .accessibilityAddTraits(style == store.dietPreferences.style ? .isSelected : [])
                        }
                    }
                }
                .softCardStyle()

                NagisenSection("Foods to avoid") {
                    HStack {
                        TextField("e.g. peanuts, eggs", text: $avoidInput)
                            .submitLabel(.done)
                            .onSubmit(saveAvoidedFoods)
                        Button("Save") { saveAvoidedFoods() }
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(minHeight: 54)
                }

                if let day, let target {
                    Button { showingGroceries = true } label: {
                        Label("Shopping list for the week", systemImage: "basket")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accentText)
                    .softCardStyle()
                    VStack(alignment: .leading, spacing: 13) {
                        Text("DAILY PLAN")
                            .font(.caption2.weight(.semibold)).nagisenTracking(2).foregroundStyle(Theme.muted)
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(target.formatted())")
                                .font(.system(size: 42, design: .serif))
                            Text("kcal · your daily goal")
                                .font(.subheadline).foregroundStyle(Theme.muted)
                        }
                        Text("Today’s portions: \(day.calories.formatted()) kcal")
                            .font(.subheadline)
                        HStack {
                            macro(String(localized: "PROTEIN"), value: day.protein, color: Theme.protein)
                            macro(String(localized: "CARBS"), value: day.carbs, color: Theme.carbs)
                            macro(String(localized: "FAT"), value: day.fat, color: Theme.fat)
                        }
                        Text("Change the goal in Goals; the plan follows it.")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    .softCardStyle()

                    HStack(spacing: 7) {
                        ForEach(0..<7) { index in
                            Button("\(index + 1)") { selectedDay = index }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(index == selectedDay ? Color.white : Theme.ink)
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .background(index == selectedDay ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                                .accessibilityLabel("Day \(index + 1)")
                        }
                    }
                    ForEach(Array(day.meals.enumerated()), id: \.offset) { _, meal in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(meal.title).font(.system(size: 20, design: .serif))
                                Spacer()
                                if let time = meal.time { Text(time).font(.caption).foregroundStyle(Theme.muted) }
                            }
                            Text("\(meal.calories) kcal · P \(meal.protein)g · C \(meal.carbs)g · F \(meal.fat)g")
                                .font(.subheadline.weight(.medium)).foregroundStyle(Theme.accentText)
                            ForEach(meal.portions, id: \.name) { portion in
                                HStack {
                                    Text(portion.name)
                                    Spacer()
                                    Text("\(portion.grams) g").foregroundStyle(Theme.muted)
                                }
                                .font(.subheadline)
                            }
                            Button("Log this meal") { mealToLog = PlannedMealSelection(meal: meal) }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accentText)
                                .padding(.top, 4)
                        }
                        .softCardStyle()
                    }
                    Text("Nutrition values are estimates. Check food labels and adjust portions. Fasting is a meal schedule, not a lower calorie target. Keto and fasting may need medical guidance, especially with diabetes medication, pregnancy, or a history of disordered eating.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                } else {
                    Text(target == nil
                         ? "Set a daily calorie goal in Goals first. Plans are for adults 18 and older."
                         : "No complete day fits the foods you entered. Try another style or adjust the foods to avoid.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .softCardStyle()
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(24)
            .padding(.bottom, 32)
        }
        .background(NagisenBackdrop())
        .tint(Theme.accentText)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { avoidInput = store.foodsToAvoid.joined(separator: ", ") }
        .sheet(isPresented: $showingGroceries) {
            NavigationStack { GroceryListView(items: groceries) }
        }
        .sheet(item: $mealToLog) { selection in
            NavigationStack { PlannedMealLogView(meal: selection.meal) }
        }
    }

    private func saveAvoidedFoods() {
        store.foodsToAvoid = avoidInput.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func macro(_ label: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(ui: label).font(.caption2.weight(.semibold)).nagisenTracking(1)
            }
            .foregroundStyle(color)
            Text("\(value)g").font(.system(size: 21, design: .serif)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GroceryItem: Identifiable {
    let name: String
    let grams: Int
    var id: String { name }
}

private struct PlannedMealSelection: Identifiable {
    let id = UUID()
    let meal: PlanMeal
}

private struct GroceryListView: View {
    @Environment(\.dismiss) private var dismiss
    let items: [GroceryItem]
    @State private var checked: Set<String> = []

    private var shareText: String {
        "NAGISEN · Weekly shopping list\n" + items.map { "• \($0.name): \($0.grams) g" }.joined(separator: "\n")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                NagisenHeader("Shopping list", subtitle: String(localized: "Seven days, gathered together."), symbol: "xmark", onBack: { dismiss() })
                ShareLink(item: shareText) {
                    Label("Share list", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                }
                NagisenSection("Ingredients") {
                    ForEach(items) { item in
                        Button { if checked.contains(item.id) { checked.remove(item.id) } else { checked.insert(item.id) } } label: {
                            HStack {
                                Image(systemName: checked.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(Theme.accentText)
                                Text(item.name).foregroundStyle(Theme.ink)
                                Spacer()
                                Text("\(item.grams) g").foregroundStyle(Theme.muted)
                            }
                            .frame(minHeight: 54)
                        }
                        .buttonStyle(.plain)
                        if item.id != items.last?.id { Divider() }
                    }
                }
                Text("Amounts are estimates for one person. Check the plan and food labels before shopping.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 32)
        }
        .background(NagisenBackdrop())
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct PlannedMealLogView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    let meal: PlanMeal
    @State private var mealSlot = Meal.lunch
    @State private var date = Date.now

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                NagisenHeader("Log planned meal", subtitle: meal.title, symbol: "xmark", onBack: { dismiss() })
                NagisenSection("Diary") {
                    NagisenPicker("Meal", selection: $mealSlot, options: Meal.allCases.map { ($0, $0.rawValue) })
                    .frame(minHeight: 54)
                    Divider()
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                        .frame(minHeight: 54)
                }
                NagisenSection("What will be added") {
                    ForEach(meal.portions, id: \.name) { portion in
                        HStack {
                            Text(portion.name)
                            Spacer()
                            Text("\(portion.grams) g").foregroundStyle(Theme.muted)
                        }
                        .frame(minHeight: 54)
                        if portion.name != meal.portions.last?.name { Divider() }
                    }
                }
                Text("\(meal.calories) kcal · P \(meal.protein) g · C \(meal.carbs) g · F \(meal.fat) g")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                NagisenPrimaryButton("Add \(meal.portions.count) foods to diary") {
                    for portion in meal.portions {
                        let food = Food(name: portion.name, serving: "\(portion.grams) g",
                                        calories: Int(portion.calories.rounded()),
                                        protein: portion.protein, carbs: portion.carbs, fat: portion.fat,
                                        source: "NAGISEN food plan estimate")
                        store.add(food, to: mealSlot, servings: 1, on: date,
                                  quantity: Double(portion.grams), unit: "g")
                    }
                    dismiss()
                }
            }
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 32)
        }
        .background(NagisenBackdrop())
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// The daily calorie budget: calculated from a weekly rate ("Standard") or typed by the person
/// ("Custom"), with the weight change, goal date and day-by-day prediction that follow from it.
struct TargetCalculatorView: View {
    @EnvironmentObject private var store: NutritionStore
    @EnvironmentObject private var health: HealthManager
    @Environment(\.dismiss) private var dismiss
    @State private var age = ""
    @State private var height = ""
    @State private var targetWeight = ""
    @State private var customText = ""
    @State private var applied = false

    private var weight: Double? {
        store.weights.max { $0.date < $1.date }?.kilograms ?? health.weightKilograms
    }

    private func number(_ text: String, in range: ClosedRange<Double>) -> Double? {
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), value.isFinite,
              range.contains(value) else { return nil }
        return value
    }

    private var profile: PersonalProfile? {
        let ageValue = age.isEmpty ? nil : Int(age).flatMap { (1...120).contains($0) ? $0 : nil }
        let heightValue = height.isEmpty ? nil : number(height, in: 50...250)
        let targetValue = targetWeight.isEmpty ? nil : number(targetWeight, in: 20...500)
        if (!age.isEmpty && ageValue == nil) || (!height.isEmpty && heightValue == nil)
            || (!targetWeight.isEmpty && targetValue == nil) { return nil }
        return PersonalProfile(age: ageValue, heightCm: heightValue, targetWeightKg: targetValue)
    }

    private var isCustom: Bool { store.dietPreferences.customCalories != nil }

    private var maintenance: Double? {
        guard let weight, let profile, let age = profile.age, age >= 18, let height = profile.heightCm,
              let equation = store.dietPreferences.equation,
              let activity = store.dietPreferences.activity else { return nil }
        return EnergyMath.maintenance(weight: weight, height: height, age: age, equation: equation, activity: activity)
    }

    private var rate: Double {
        store.dietPreferences.weeklyRate ?? {
            switch store.dietPreferences.direction {
            case .lose: -0.25
            case .gain: 0.25
            default: 0
            }
        }()
    }

    private var budget: Int? {
        if let custom = store.dietPreferences.customCalories { return custom }
        guard let weight, let profile, let age = profile.age, age >= 18, let height = profile.heightCm,
              let equation = store.dietPreferences.equation, let activity = store.dietPreferences.activity else { return nil }
        return EnergyMath.dailyCalories(weight: weight, height: height, age: age, equation: equation,
                                        activity: activity, weeklyRate: rate)
    }

    private var projection: WeightProjection? {
        guard let maintenance, let budget, let weight else { return nil }
        return WeightProjection(maintenance: maintenance, calories: budget, weight: weight, target: profile?.targetWeightKg)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                NagisenHeader("Calorie budget", subtitle: String(localized: "What you eat, and where it takes you."), onBack: { dismiss() })
                typePicker
                NagisenSection("Budget") {
                    if isCustom {
                        NagisenTextRow("Daily calories", placeholder: "2000", unit: "kcal", text: $customText)
                    } else {
                        HStack(alignment: .firstTextBaseline) {
                            Text(budget.map { $0.formatted() } ?? "—").font(.system(size: 40, design: .serif))
                            Text("average daily calories").font(.subheadline).foregroundStyle(Theme.muted)
                        }
                        .frame(minHeight: 64)
                        Divider().overlay(Theme.line)
                        NavigationLink {
                            WeeklyRateView(maintenance: maintenance, weight: weight, target: profile?.targetWeightKg)
                        } label: {
                            LabeledContent("Weekly rate", value: WeeklyRate.name(rate)).frame(minHeight: 54)
                        }
                    }
                    Divider().overlay(Theme.line)
                    NagisenPicker("Activity", selection: $store.dietPreferences.activity,
                                  options: [(nil, String(localized: "Choose"))] + DietActivity.allCases.map { (Optional($0), $0.rawValue) })
                        .frame(minHeight: 52)
                }
                if let projection {
                    projectionCards(projection)
                } else if isCustom {
                    Text("Add your age, height, a logged weight, equation and activity below to see how this budget moves your weight.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                }
                NagisenSection("About you") {
                    NagisenTextRow("Age", placeholder: String(localized: "Years"), text: $age)
                    Divider().overlay(Theme.line)
                    NagisenTextRow("Height", placeholder: "0", unit: "cm", text: $height, keyboard: .decimalPad)
                    Divider().overlay(Theme.line)
                    HStack {
                        Text("Current weight")
                        Spacer()
                        Text(weight.map { "\($0.formatted(.number.precision(.fractionLength(1)))) kg" } ?? String(localized: "Log a weight in Goals"))
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(minHeight: 54)
                    Divider().overlay(Theme.line)
                    NagisenTextRow("Target weight", placeholder: "0", unit: "kg", text: $targetWeight, keyboard: .decimalPad)
                    Divider().overlay(Theme.line)
                    NagisenPicker("Calorie equation", selection: $store.dietPreferences.equation,
                                  options: [(nil, String(localized: "Choose"))] + EnergyEquation.allCases.map { (Optional($0), $0.rawValue) })
                        .frame(minHeight: 52)
                }
                if let budget {
                    Button(applied ? String(localized: "Set as your daily goal") : String(localized: "Use \(budget.formatted()) kcal as my daily goal")) { apply(budget) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                        .disabled(applied)
                } else if !isCustom {
                    Text("Fill in your age (18 or older), height, a logged weight, equation and activity to calculate a budget.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                }
                Text("Estimates use about 7,700 kcal per kg of body weight. Real weight moves with water, salt and training, so expect the line to wobble around the prediction.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(NagisenBackdrop())
        .tint(Theme.accentText)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            age = store.profile.age.map(String.init) ?? ""
            height = store.profile.heightCm.map { $0.formatted() } ?? ""
            targetWeight = store.profile.targetWeightKg.map { $0.formatted() } ?? ""
            customText = store.dietPreferences.customCalories.map(String.init) ?? ""
        }
        // Body details save as they become valid, so leaving the screen never loses them.
        .onChange(of: profile) { _, value in if let value { store.profile = value }; applied = false }
        .onChange(of: customText) { _, text in
            if isCustom, let value = Int(text), (800...8000).contains(value) { store.dietPreferences.customCalories = value }
        }
        .onChange(of: budget) { _, _ in applied = false }
    }

    private var typePicker: some View {
        HStack(spacing: 12) {
            typeCard(String(localized: "Standard"), detail: String(localized: "Calculated for you"), selected: !isCustom) {
                store.dietPreferences.customCalories = nil
            }
            typeCard(String(localized: "Custom"), detail: String(localized: "Set by you"), selected: isCustom) {
                let start = Int(customText) ?? budget ?? store.goals.calories
                store.dietPreferences.customCalories = start
                customText = String(start)
            }
        }
    }

    private func typeCard(_ title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(title).font(.system(size: 22, design: .serif))
                    .foregroundStyle(selected ? Theme.accentText : Theme.ink)
                Text(detail).font(.caption).foregroundStyle(Theme.muted)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Theme.accentText : Theme.muted)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .softCardStyle()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func projectionCards(_ projection: WeightProjection) -> some View {
        let perWeek = abs(projection.weeklyChange)
        let grams = Int((abs(projection.dailyChange) * 1000).rounded())
        let verb = projection.dailyChange < 0 ? String(localized: "lose") : String(localized: "gain")
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lightbulb").foregroundStyle(Theme.accentText)
                VStack(alignment: .leading, spacing: 6) {
                    if grams == 0 {
                        Text("At this budget your weight should hold steady.")
                    } else {
                        Text("At this budget you'd \(verb) about \(perWeek.formatted(.number.precision(.fractionLength(2)))) kg a week, roughly \(grams) g a day.")
                    }
                    if let date = projection.goalDate {
                        Text("You're projected to reach your goal on \(date.formatted(.dateTime.day().month(.wide).year())).")
                            .font(.subheadline.weight(.semibold))
                    } else if projection.target != nil, grams > 0 {
                        Text("This budget moves you away from your target weight.").foregroundStyle(Theme.accentText)
                    }
                }
                .font(.subheadline)
            }
        }
        .softCardStyle()
        if grams > 0 {
            NagisenSection("Next 7 days") {
                ForEach(Array(projection.forecast(days: 7).enumerated()), id: \.offset) { index, day in
                    if index > 0 { Divider().overlay(Theme.line) }
                    HStack {
                        Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                        Spacer()
                        Text("\(day.kilograms.formatted(.number.precision(.fractionLength(2)))) kg")
                            .monospacedDigit().foregroundStyle(Theme.muted)
                    }
                    .font(.subheadline)
                    .frame(minHeight: 44)
                }
            }
        }
    }

    private func apply(_ calories: Int) {
        let current = store.goals
        if let day = DietPlanEngine.day(style: store.dietPreferences.style, index: 0,
                                        targetCalories: calories, avoiding: store.foodsToAvoid) {
            store.goals = NutritionGoals(calories: calories, protein: day.protein, carbs: day.carbs, fat: day.fat).balanced
        } else {
            store.goals = NutritionGoals(calories: calories, protein: current.protein, carbs: 0, fat: current.fat).balanced
        }
        applied = true
    }
}

/// Maintain or lose (gain) a set amount each week, with the calories and the date each choice means.
private struct WeeklyRateView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    let maintenance: Double?
    let weight: Double?
    let target: Double?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                NagisenHeader("Weekly rate", subtitle: String(localized: "How fast you want to get there."), onBack: { dismiss() })
                VStack(spacing: 0) {
                    let options = WeeklyRate.options(weight: weight ?? 0, target: target)
                    ForEach(options, id: \.self) { rate in
                        if rate != options.first { Divider().overlay(Theme.line) }
                        row(rate)
                    }
                }
                .padding(.horizontal, 18)
                .nagisenPanel()
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 32)
        }
        .background(NagisenBackdrop())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func row(_ rate: Double) -> some View {
        let selected = (store.dietPreferences.weeklyRate ?? 0) == rate && store.dietPreferences.weeklyRate != nil
        return Button {
            store.dietPreferences.weeklyRate = rate
            store.dietPreferences.direction = rate < 0 ? .lose : rate > 0 ? .gain : .maintain
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(WeeklyRate.name(rate)).font(.body.weight(.medium))
                        .foregroundStyle(selected ? Theme.accentText : Theme.ink)
                    HStack(spacing: 16) {
                        if let maintenance {
                            Label("\(EnergyMath.rounded(maintenance + rate * 7700 / 7).formatted()) kcal", systemImage: "flame")
                        }
                        if let weight, let date = WeeklyRate.goalDate(weight: weight, target: target, rate: rate) {
                            Label(date.formatted(.dateTime.day().month(.abbreviated).year()), systemImage: "calendar")
                        }
                    }
                    .font(.subheadline).foregroundStyle(Theme.muted)
                }
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(Theme.accentText) }
            }
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
