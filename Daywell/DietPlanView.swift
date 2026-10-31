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
        let resting = 10 * weight + 6.25 * height - 5 * Double(age) + (equation == .male ? 5 : -161)
        let maintenance = resting * activity.factor
        let adjustment: Double = direction == .lose ? -300 : direction == .gain ? 250 : 0
        return Int((max(1200, maintenance + adjustment) / 25).rounded() * 25)
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
        let names = style == .intermittentFasting ? ["First meal", "Second meal", "Dinner"] : ["Breakfast", "Lunch", "Dinner", "Snack"]
        let times: [String?] = style == .intermittentFasting ? ["10:00", "14:00", "19:00"] : Array(repeating: nil, count: 4)
        return PlanDay(meals: picks.enumerated().map { position, recipe in
            PlanMeal(title: "\(names[position]) · \(recipe.title)", time: times[position],
                     portions: recipe.ingredients.map { $0.scaled(factor) })
        })
    }

    private static func menu(for style: DietStyle) -> [[Recipe]] {
        let f = PlanFood.self
        let breakfast = [
            Recipe(title: "Yogurt, oats & berries", ingredients: [f.yogurt, f.oats, f.berries]),
            Recipe(title: "Eggs, toast & avocado", ingredients: [f.eggs, f.toast, f.avocado]),
            Recipe(title: "Banana oat bowl", ingredients: [f.oats, f.banana, f.yogurt])
        ]
        let lunch = [
            Recipe(title: "Chicken rice bowl", ingredients: [f.chicken, f.rice, f.vegetables, f.oliveOil]),
            Recipe(title: "Tuna quinoa salad", ingredients: [f.tuna, f.quinoa, f.greens, f.oliveOil]),
            Recipe(title: "Tofu rice bowl", ingredients: [f.tofu, f.rice, f.vegetables, f.oliveOil])
        ]
        let dinner = [
            Recipe(title: "Salmon & potatoes", ingredients: [f.salmon, f.potatoes, f.vegetables]),
            Recipe(title: "Chicken & quinoa", ingredients: [f.chicken, f.quinoa, f.vegetables, f.oliveOil]),
            Recipe(title: "Lentil & tofu plate", ingredients: [f.lentils, f.tofu, f.greens, f.oliveOil])
        ]
        let snack = [
            Recipe(title: "Yogurt & almonds", ingredients: [f.yogurt, f.almonds]),
            Recipe(title: "Banana & peanut butter", ingredients: [f.banana, f.peanutButter]),
            Recipe(title: "Cottage cheese & berries", ingredients: [f.cottage, f.berries])
        ]
        switch style {
        case .balanced: return [breakfast, lunch, dinner, snack]
        case .mediterranean:
            return [
                [Recipe(title: "Yogurt, walnuts & berries", ingredients: [f.yogurt, f.walnuts, f.berries]),
                 Recipe(title: "Eggs & whole-grain toast", ingredients: [f.eggs, f.toast, f.oliveOil])],
                [Recipe(title: "Lentil feta salad", ingredients: [f.lentils, f.feta, f.greens, f.olives, f.oliveOil]),
                 Recipe(title: "Tuna quinoa salad", ingredients: [f.tuna, f.quinoa, f.greens, f.oliveOil])],
                [Recipe(title: "Salmon, potatoes & greens", ingredients: [f.salmon, f.potatoes, f.greens, f.oliveOil]),
                 Recipe(title: "Chicken & vegetables", ingredients: [f.chicken, f.quinoa, f.vegetables, f.oliveOil])],
                [Recipe(title: "Fruit & nuts", ingredients: [f.banana, f.almonds]),
                 Recipe(title: "Yogurt & berries", ingredients: [f.yogurt, f.berries, f.walnuts])]
            ]
        case .highProtein:
            return [
                [Recipe(title: "Eggs & Greek yogurt", ingredients: [f.eggs, f.yogurt, f.berries]),
                 Recipe(title: "Cottage cheese oats", ingredients: [f.cottage, f.oats, f.berries])],
                [Recipe(title: "Chicken quinoa bowl", ingredients: [f.chicken, f.quinoa, f.vegetables]),
                 Recipe(title: "Tuna rice bowl", ingredients: [f.tuna, f.rice, f.vegetables])],
                [Recipe(title: "Salmon & tofu plate", ingredients: [f.salmon, f.tofu, f.vegetables]),
                 Recipe(title: "Chicken & potatoes", ingredients: [f.chicken, f.potatoes, f.vegetables])],
                [Recipe(title: "Cottage cheese & almonds", ingredients: [f.cottage, f.almonds]),
                 Recipe(title: "Greek yogurt & peanut butter", ingredients: [f.yogurt, f.peanutButter])]
            ]
        case .lowerCarb:
            return [
                [Recipe(title: "Eggs & avocado", ingredients: [f.eggs, f.avocado, f.greens]),
                 Recipe(title: "Yogurt & walnuts", ingredients: [f.yogurt, f.walnuts, f.berries])],
                [Recipe(title: "Chicken salad", ingredients: [f.chicken, f.greens, f.avocado, f.oliveOil]),
                 Recipe(title: "Tuna feta salad", ingredients: [f.tuna, f.feta, f.greens, f.oliveOil])],
                [Recipe(title: "Salmon & vegetables", ingredients: [f.salmon, f.vegetables, f.oliveOil]),
                 Recipe(title: "Tofu & greens", ingredients: [f.tofu, f.vegetables, f.oliveOil])],
                [Recipe(title: "Cheese & nuts", ingredients: [f.cottage, f.almonds]),
                 Recipe(title: "Yogurt & peanut butter", ingredients: [f.yogurt, f.peanutButter])]
            ]
        case .keto:
            return [
                [Recipe(title: "Eggs, avocado & olive oil", ingredients: [f.eggs, f.avocado, f.oliveOil]),
                 Recipe(title: "Eggs & feta", ingredients: [f.eggs, f.feta, f.oliveOil])],
                [Recipe(title: "Chicken avocado salad", ingredients: [f.chicken, f.avocado, f.greens, f.oliveOil]),
                 Recipe(title: "Tuna olive salad", ingredients: [f.tuna, f.olives, f.greens, f.oliveOil])],
                [Recipe(title: "Salmon & greens", ingredients: [f.salmon, f.greens, f.oliveOil, f.avocado]),
                 Recipe(title: "Chicken, feta & greens", ingredients: [f.chicken, f.feta, f.greens, f.oliveOil])],
                [Recipe(title: "Walnuts & olives", ingredients: [f.walnuts, f.olives]),
                 Recipe(title: "Almonds & feta", ingredients: [f.almonds, f.feta])]
            ]
        case .intermittentFasting:
            return [
                [Recipe(title: "Eggs, toast & yogurt", ingredients: [f.eggs, f.toast, f.yogurt, f.berries]),
                 Recipe(title: "Oat & yogurt bowl", ingredients: [f.oats, f.yogurt, f.banana, f.almonds])],
                [Recipe(title: "Chicken rice bowl", ingredients: [f.chicken, f.rice, f.vegetables, f.oliveOil]),
                 Recipe(title: "Tuna quinoa plate", ingredients: [f.tuna, f.quinoa, f.vegetables, f.oliveOil])],
                [Recipe(title: "Salmon & potatoes", ingredients: [f.salmon, f.potatoes, f.vegetables, f.yogurt]),
                 Recipe(title: "Tofu lentil plate", ingredients: [f.tofu, f.lentils, f.greens, f.oliveOil])]
            ]
        }
    }
}

struct DietPlanView: View {
    @EnvironmentObject private var store: NutritionStore
    @EnvironmentObject private var health: HealthManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDay = 0
    @State private var avoidInput = ""
    @State private var showingGroceries = false
    @State private var mealToLog: PlannedMealSelection?

    private var weight: Double? {
        store.weights.max { $0.date < $1.date }?.kilograms ?? health.weightKilograms
    }
    private var target: Int? {
        guard let weight, let age = store.profile.age, age >= 18,
              let height = store.profile.heightCm,
              let equation = store.dietPreferences.equation,
              let activity = store.dietPreferences.activity else { return nil }
        let direction = DietPlanEngine.direction(store.dietPreferences.direction, weight: weight,
                                                  target: store.profile.targetWeightKg)
        return DietPlanEngine.calories(weight: weight, height: height, age: age,
                                       equation: equation, activity: activity, direction: direction)
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
                NagisenHeader("Food plan", subtitle: "A week of ideas shaped by your goal.", onBack: { dismiss() })

                VStack(alignment: .leading, spacing: 14) {
                    Text("CHOOSE YOUR STYLE")
                        .font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(Theme.muted)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                        ForEach(DietStyle.allCases) { style in
                            Button {
                                store.dietPreferences.style = style
                            } label: {
                                Text(style.rawValue)
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

                VStack(alignment: .leading, spacing: 15) {
                    Text("CALCULATE YOUR TARGET")
                        .font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(Theme.muted)
                    HStack {
                        Text("Current weight")
                        Spacer()
                        Text(weight.map { "\($0.formatted(.number.precision(.fractionLength(1)))) kg" } ?? "Add in You")
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(minHeight: 46)
                    Divider()
                    HStack {
                        Text("Age & height")
                        Spacer()
                        Text(store.profile.age.flatMap { age in store.profile.heightCm.map { "\(age)y · \(Int($0)) cm" } } ?? "Add in You")
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(minHeight: 46)
                    Divider()
                    NagisenPicker("Calorie equation", selection: $store.dietPreferences.equation,
                                  options: [(nil, "Choose")] + EnergyEquation.allCases.map { (Optional($0), $0.rawValue) })
                    .frame(minHeight: 48)
                    Divider()
                    NagisenPicker("Activity", selection: $store.dietPreferences.activity,
                                  options: [(nil, "Choose")] + DietActivity.allCases.map { (Optional($0), $0.rawValue) })
                    .frame(minHeight: 48)
                    Divider()
                    NagisenPicker("Goal", selection: $store.dietPreferences.direction,
                                  options: DietDirection.allCases.map { ($0, $0.rawValue) })
                    .frame(minHeight: 48)
                    Text("Uses the Mifflin–St Jeor estimate. Activity and body data affect the result; adjust your daily goals if your needs differ.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                .softCardStyle()

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
                            .font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(Theme.muted)
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(target.formatted())")
                                .font(.system(size: 42, design: .serif))
                            Text("kcal target")
                                .font(.subheadline).foregroundStyle(Theme.muted)
                        }
                        Text("Today’s portions: \(day.calories.formatted()) kcal")
                            .font(.subheadline)
                        HStack {
                            macro("PROTEIN", value: day.protein, color: Theme.protein)
                            macro("CARBS", value: day.carbs, color: Theme.carbs)
                            macro("FAT", value: day.fat, color: Theme.fat)
                        }
                        Button("Use these as my daily goals") {
                            store.goals = NutritionGoals(calories: target, protein: day.protein,
                                                         carbs: day.carbs, fat: day.fat).balanced
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
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
                         ? "Add a weight in You → Weight log, enter your age and height in Body details, then choose a calorie equation and activity level here. Plans are for adults 18 and older."
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
                Text(label).font(.caption2.weight(.semibold)).tracking(1)
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
                NagisenHeader("Shopping list", subtitle: "Seven days, gathered together.", symbol: "xmark", onBack: { dismiss() })
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
