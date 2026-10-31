import SwiftUI

enum PortionUnit: String, CaseIterable {
    case serving = "Serving"
    case grams = "Grams"
}

struct LogFoodView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    let food: Food
    let date: Date
    @State private var meal: Meal
    @State private var amount = "1"
    @State private var unit = PortionUnit.serving
    @State private var correctedFood: Food?
    @State private var showingCorrection = false
    let onLogged: (Meal) -> Void

    private var selectedFood: Food { correctedFood ?? food }

    init(food: Food, date: Date, initialMeal: Meal, onLogged: @escaping (Meal) -> Void) {
        self.food = food
        self.date = date
        self._meal = State(initialValue: initialMeal)
        self.onLogged = onLogged
    }

    private var quantity: Double? {
        guard let value = Double(amount.replacingOccurrences(of: ",", with: ".")),
              value.isFinite, value > 0, value <= 10_000 else { return nil }
        return value
    }

    private var effectiveServings: Double? {
        guard let quantity else { return nil }
        let servings: Double
        if unit == .grams {
            guard let grams = selectedFood.gramsPerServing, grams > 0 else { return nil }
            servings = quantity / grams
        } else {
            servings = quantity
        }
        return servings <= 100 ? servings : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                NagisenHeader("Log food", subtitle: "Add it to your day.", onBack: { dismiss() })
                Text(selectedFood.name).font(.system(size: 26, design: .serif))
                Text([selectedFood.brand, selectedFood.serving].filter { !$0.isEmpty }.joined(separator: " · "))
                    .foregroundStyle(Theme.muted)
                if let source = selectedFood.source {
                    Text(source).font(.caption).foregroundStyle(Theme.muted)
                }
                if food.source == "Open Food Facts" {
                    Button("Check or correct nutrition") { showingCorrection = true }
                        .font(.subheadline.weight(.medium))
                    Text("Community data can be incomplete. Compare calories, serving size and macros with the package before logging.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                if let missing = selectedFood.missingMacros, !missing.isEmpty {
                    Text("Missing from this entry: \(missing.joined(separator: ", ")). Daily macro totals may be low.")
                        .font(.caption.weight(.medium)).foregroundStyle(Theme.accentText)
                }
                NagisenSection("Log to diary") {
                NagisenPicker("Meal", selection: $meal, options: Meal.allCases.map { ($0, $0.rawValue) })
                .frame(minHeight: 54)
                Divider()
                if selectedFood.gramsPerServing != nil {
                    NagisenPicker("Serving unit", selection: $unit, options: PortionUnit.allCases.map { ($0, $0.rawValue) })
                    .onChange(of: unit) { _, newUnit in
                        amount = newUnit == .grams ? String(Int(selectedFood.gramsPerServing ?? 100)) : "1"
                    }
                    .frame(minHeight: 54)
                    Divider()
                }
                HStack(spacing: 14) {
                    Text(unit == .grams ? "Grams" : "Servings")
                    Spacer()
                    Button {
                        adjustAmount(by: unit == .grams ? -10 : -0.5)
                    } label: {
                        Image(systemName: "minus.circle.fill").font(.title2)
                    }
                    .disabled((quantity ?? 0) <= (unit == .grams ? 10 : 0.5))
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 65)
                        .accessibilityLabel(unit == .grams ? "Grams" : "Servings")
                    Button {
                        adjustAmount(by: unit == .grams ? 10 : 0.5)
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                }
                .frame(minHeight: 54)
                Divider()
                LabeledContent("Date", value: date.formatted(date: .abbreviated, time: .omitted))
                    .frame(minHeight: 54)
            }
                NagisenSection("Nutrition for this amount") {
                LabeledContent("Calories", value: "\(Int((Double(selectedFood.calories) * (effectiveServings ?? 0)).rounded())) kcal")
                    .frame(minHeight: 48)
                Divider()
                macroLine("Protein", value: selectedFood.protein * (effectiveServings ?? 0), color: Theme.protein)
                Divider()
                macroLine("Carbs", value: selectedFood.carbs * (effectiveServings ?? 0), color: Theme.carbs)
                Divider()
                macroLine("Fat", value: selectedFood.fat * (effectiveServings ?? 0), color: Theme.fat)
                if let fiber = selectedFood.fiber {
                    Divider()
                    LabeledContent("Fiber", value: "\((fiber * (effectiveServings ?? 0)).formatted(.number.precision(.fractionLength(1)))) g")
                        .frame(minHeight: 48)
                }
                if let sodium = selectedFood.sodium {
                    Divider()
                    LabeledContent("Sodium", value: "\((sodium * (effectiveServings ?? 0) * 1000).formatted(.number.precision(.fractionLength(0)))) mg")
                        .frame(minHeight: 48)
                }
                }
            }
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 100)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(NagisenBackdrop())
        .tint(Theme.accentText)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingCorrection) {
            NavigationStack {
                CreateFoodView(initialFood: selectedFood) { correctedFood = $0; showingCorrection = false }
            }
        }
        .safeAreaInset(edge: .bottom) {
            NagisenPrimaryButton("Add to \(meal.rawValue)", enabled: effectiveServings != nil) {
                guard let quantity, let servings = effectiveServings else { return }
                if let correctedFood { store.customFoods.insert(correctedFood, at: 0) }
                store.add(selectedFood, to: meal, servings: servings, on: date,
                          quantity: quantity, unit: unit == .grams ? "g" : "serving")
                dismiss()
                onLogged(meal)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Theme.paper)
        }
    }

    private func adjustAmount(by delta: Double) {
        let next = max(unit == .grams ? 10 : 0.5, (quantity ?? 0) + delta)
        amount = next.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func macroLine(_ name: String, value: Double, color: Color) -> some View {
        HStack(spacing: 9) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(name).foregroundStyle(color)
            Spacer()
            Text("\(value.formatted(.number.precision(.fractionLength(1)))) g")
                .foregroundStyle(Theme.ink)
        }
        .frame(minHeight: 48)
    }
}

struct CreateFoodView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var brand = ""
    @State private var serving = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var fiber = ""
    @State private var sodium = ""
    private let initialFood: Food?
    let onSave: (Food) -> Void

    init(initialFood: Food? = nil, onSave: @escaping (Food) -> Void) {
        self.initialFood = initialFood
        self.onSave = onSave
        _name = State(initialValue: initialFood?.name ?? "")
        _brand = State(initialValue: initialFood?.brand ?? "")
        _serving = State(initialValue: initialFood?.serving ?? "")
        _calories = State(initialValue: initialFood.map { String($0.calories) } ?? "")
        _protein = State(initialValue: initialFood.map { String($0.protein) } ?? "")
        _carbs = State(initialValue: initialFood.map { String($0.carbs) } ?? "")
        _fat = State(initialValue: initialFood.map { String($0.fat) } ?? "")
        _fiber = State(initialValue: initialFood?.fiber.map { String($0) } ?? "")
        _sodium = State(initialValue: initialFood?.sodium.map { String($0 * 1000) } ?? "")
    }

    private func number(_ text: String) -> Double? {
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")),
              value.isFinite, value >= 0, value <= 100_000 else { return nil }
        return value
    }

    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !serving.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        number(calories) != nil && number(protein) != nil && number(carbs) != nil && number(fat) != nil &&
        (fiber.isEmpty || number(fiber) != nil) && (sodium.isEmpty || number(sodium) != nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                NagisenHeader(initialFood == nil ? "Custom food" : "Correct nutrition",
                              subtitle: initialFood == nil ? "Keep your own favourites close." : "Use the package label as your guide.",
                              symbol: "xmark", onBack: { dismiss() })
                NagisenSection("Food") {
                    TextField("Name", text: $name).frame(minHeight: 54)
                    Divider()
                    TextField("Brand (optional)", text: $brand).frame(minHeight: 54)
                    Divider()
                    TextField("Serving, e.g. 100 g or 1 cup", text: $serving).frame(minHeight: 54)
                }
                NagisenSection("Nutrition per serving") {
                    NagisenTextRow("Calories", placeholder: "0", unit: "kcal", text: $calories, keyboard: .decimalPad)
                    Divider()
                    NagisenTextRow("Protein", placeholder: "0", unit: "g", text: $protein, keyboard: .decimalPad, color: Theme.protein)
                    Divider()
                    NagisenTextRow("Carbs", placeholder: "0", unit: "g", text: $carbs, keyboard: .decimalPad, color: Theme.carbs)
                    Divider()
                    NagisenTextRow("Fat", placeholder: "0", unit: "g", text: $fat, keyboard: .decimalPad, color: Theme.fat)
                }
                NagisenSection("Extra details · optional") {
                    NagisenTextRow("Fiber", placeholder: "—", unit: "g", text: $fiber, keyboard: .decimalPad)
                    Divider()
                    NagisenTextRow("Sodium", placeholder: "—", unit: "mg", text: $sodium, keyboard: .decimalPad)
                }
                NagisenPrimaryButton("Save food", enabled: valid) {
                    guard valid, let calories = number(calories), let protein = number(protein),
                          let carbs = number(carbs), let fat = number(fat) else { return }
                    onSave(Food(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                brand: brand.trimmingCharacters(in: .whitespacesAndNewlines),
                                serving: serving.trimmingCharacters(in: .whitespacesAndNewlines),
                                calories: Int(calories.rounded()), protein: protein, carbs: carbs, fat: fat,
                                fiber: self.fiber.isEmpty ? nil : number(self.fiber),
                                sodium: self.sodium.isEmpty ? nil : number(self.sodium).map { $0 / 1000 },
                                barcode: initialFood?.barcode,
                                source: initialFood == nil ? nil : "Corrected by you"))
                }
            }
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(NagisenBackdrop())
        .tint(Theme.accentText)
        .toolbar(.hidden, for: .navigationBar)
    }
}
