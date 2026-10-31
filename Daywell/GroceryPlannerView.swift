import SwiftUI
import PhotosUI
import Vision
import UIKit

enum GroceryPlanner {
    private enum Role {
        case breakfast, protein, starch, vegetable, fruit, snack, flexible
    }

    private static func role(_ food: Food) -> Role {
        let name = food.name.lowercased()
        if ["egg", "oat", "cereal", "yogurt", "milk", "bread", "toast"].contains(where: name.contains) { return .breakfast }
        if ["chicken", "beef", "turkey", "fish", "salmon", "tuna", "tofu", "lentil", "bean", "shrimp"].contains(where: name.contains) { return .protein }
        if ["rice", "pasta", "potato", "quinoa", "couscous", "noodle"].contains(where: name.contains) { return .starch }
        if ["broccoli", "spinach", "vegetable", "carrot", "tomato", "pepper", "salad", "lettuce", "cucumber"].contains(where: name.contains) { return .vegetable }
        if ["apple", "banana", "berry", "berries", "orange", "fruit", "grape", "pear"].contains(where: name.contains) { return .fruit }
        if ["almond", "nut", "peanut", "avocado", "chocolate", "bar"].contains(where: name.contains) { return .snack }
        return .flexible
    }

    private static func score(calories: Double, protein: Double, carbs: Double, fat: Double,
                              goal: NutritionGoals) -> Double {
        let energyGap = (calories - Double(goal.calories)) / Double(max(goal.calories, 1))
        let proteinGap = (protein - Double(goal.protein)) / Double(max(goal.protein, 1))
        let carbGap = (carbs - Double(goal.carbs)) / Double(max(goal.carbs, 1))
        let fatGap = (fat - Double(goal.fat)) / Double(max(goal.fat, 1))
        return 2 * energyGap * energyGap + 2 * proteinGap * proteinGap +
               carbGap * carbGap + 1.5 * fatGap * fatGap
    }

    static func make(stock: [GroceryStock], count: Int, start: Date,
                     goalsForDate: (Date) -> NutritionGoals, avoiding: [String],
                     diary: [DiaryEntry] = [], anchorEntryIDs: [UUID]? = nil,
                     createdAt: Date = .now) -> GroceryPlan? {
        let anchors = Set(anchorEntryIDs ?? diary.map(\.id))
        let newEntries = diary.filter { !anchors.contains($0.id) }
        let usable = stock.filter { item in
            !avoiding.contains { term in
                let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.isEmpty && item.food.name.localizedCaseInsensitiveContains(trimmed)
            }
        }
        guard (1...7).contains(count), !usable.isEmpty else { return nil }
        var remaining = Dictionary(uniqueKeysWithValues: usable.map { ($0.id, $0.servings) })
        // A logged food consumes stock only when it was logged after this plan began.
        // Match barcodes first, then the same normalized name, brand and serving.
        for entry in newEntries {
            guard let item = usable.first(where: { sameFood($0.food, entry.food) }) else { continue }
            remaining[item.id, default: 0] = max(0, remaining[item.id, default: 0] - entry.servings)
        }
        var days: [GroceryPlanDay] = []
        let startDay = Calendar.current.startOfDay(for: start)
        for dayIndex in 0..<count {
            guard let date = Calendar.current.date(byAdding: .day, value: dayIndex, to: startDay) else { return nil }
            var goal = goalsForDate(date).balanced
            let eaten = diary.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
            goal.calories = max(0, goal.calories - eaten.reduce(0) { $0 + $1.calories })
            goal.protein = max(0, goal.protein - Int(eaten.reduce(0.0) { $0 + $1.protein }.rounded()))
            goal.carbs = max(0, goal.carbs - Int(eaten.reduce(0.0) { $0 + $1.carbs }.rounded()))
            goal.fat = max(0, goal.fat - Int(eaten.reduce(0.0) { $0 + $1.fat }.rounded()))
            let daysLeft = Double(count - dayIndex)
            // Reserve an even share of each grocery for later days. The optimizer can
            // leave food unused if adding it would move the plan further from the goals.
            let allowances = usable.map { max(0, (remaining[$0.id] ?? 0) / daysLeft) }
            var amounts = Array(repeating: 0.0, count: usable.count)
            var calories = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0
            for _ in 0..<1600 {
                let current = score(calories: calories, protein: protein, carbs: carbs, fat: fat, goal: goal)
                var bestIndex: Int?
                var bestAmount = 0.0
                var bestGain = 0.000001
                for index in usable.indices {
                    let available = allowances[index] - amounts[index]
                    guard available > 0.0001 else { continue }
                    let amount = min(0.1, available)
                    let food = usable[index].food
                    let next = score(calories: calories + Double(food.calories) * amount,
                                     protein: protein + food.protein * amount,
                                     carbs: carbs + food.carbs * amount,
                                     fat: fat + food.fat * amount, goal: goal)
                    let gain = current - next
                    if gain > bestGain {
                        bestGain = gain
                        bestIndex = index
                        bestAmount = amount
                    }
                }
                guard let index = bestIndex else { break }
                amounts[index] += bestAmount
                let food = usable[index].food
                calories += Double(food.calories) * bestAmount
                protein += food.protein * bestAmount
                carbs += food.carbs * bestAmount
                fat += food.fat * bestAmount
            }
            let slices = usable.indices.compactMap { index -> (GroceryStock, Double)? in
                amounts[index] > 0.0001 ? (usable[index], amounts[index]) : nil
            }
            var byMeal: [Meal: [GroceryPlanPortion]] = [:]
            let proteinCount = slices.filter { role($0.0.food) == .protein && $0.1 > 0.001 }.count
            var proteinIndex = 0
            for (index, slice) in slices.enumerated() {
                let (item, amount) = slice
                guard amount > 0.001 else { continue }
                remaining[item.id, default: 0] -= amount
                let destinations: [(Meal, Double)]
                switch role(item.food) {
                case .breakfast: destinations = [(.breakfast, amount)]
                case .fruit, .snack: destinations = [(.snacks, amount)]
                case .protein:
                    if proteinCount == 1 && amount >= 0.2 {
                        destinations = [(.lunch, amount / 2), (.dinner, amount / 2)]
                    } else {
                        destinations = [((dayIndex + proteinIndex).isMultiple(of: 2) ? .lunch : .dinner, amount)]
                    }
                    proteinIndex += 1
                case .starch, .vegetable:
                    destinations = amount >= 0.2 ? [(.lunch, amount / 2), (.dinner, amount / 2)]
                                                  : [(.lunch, amount)]
                case .flexible:
                    destinations = [([Meal.breakfast, .lunch, .dinner][(dayIndex + index) % 3], amount)]
                }
                for (meal, portion) in destinations {
                    byMeal[meal, default: []].append(GroceryPlanPortion(stockID: item.id, food: item.food,
                                                                        servings: portion))
                }
            }
            let meals = Meal.allCases.compactMap { meal -> GroceryPlanMeal? in
                guard let portions = byMeal[meal], !portions.isEmpty else { return nil }
                let names = portions.prefix(2).map { $0.food.name.components(separatedBy: ",").first ?? $0.food.name }
                let title = names.joined(separator: " & ")
                return GroceryPlanMeal(meal: meal, title: title, portions: portions)
            }
            days.append(GroceryPlanDay(date: date, meals: meals))
        }
        let availableStock = usable.map { item -> GroceryStock in
            var copy = item
            copy.servings = max(0, item.servings - newEntries.filter { sameFood(item.food, $0.food) }
                .reduce(0.0) { $0 + $1.servings })
            return copy
        }
        return GroceryPlan(createdAt: createdAt, days: days, stockSnapshot: availableStock,
                           anchorEntryIDs: Array(anchors))
    }

    private static func sameFood(_ left: Food, _ right: Food) -> Bool {
        if let leftCode = left.barcode, let rightCode = right.barcode,
           !leftCode.isEmpty, leftCode == rightCode { return true }
        return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedSame &&
            left.brand.localizedCaseInsensitiveCompare(right.brand) == .orderedSame &&
            left.serving.localizedCaseInsensitiveCompare(right.serving) == .orderedSame
    }
}

private enum KitchenMacro: String, CaseIterable {
    case protein = "Protein"
    case carb = "Carb"
    case fat = "Fat"

    var color: Color {
        switch self {
        case .protein: Theme.protein
        case .carb: Theme.carbs
        case .fat: Theme.fat
        }
    }

    static func dominant(in food: Food) -> KitchenMacro {
        let protein = max(0, food.protein)
        let carbs = max(0, food.carbs)
        let fat = max(0, food.fat)
        if protein >= carbs && protein >= fat { return .protein }
        if carbs >= fat { return .carb }
        return .fat
    }
}

struct GroceryPlannerView: View {
    var showBackButton = true
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var editingPicks = false
    @AppStorage(QuickPicks.storageKey) private var hiddenPicks = Data()
    @State private var dayCount = 3
    @State private var selectedDay = 0
    @State private var selectedFood: Food?
    @State private var onlineFoods: [Food] = []
    @State private var onlineStatus: String?
    @State private var isSearchingOnline = false
    @State private var quantity = "1"
    @State private var quantityUnit = PortionUnit.serving
    @State private var showingCreate = false
    @State private var showingScanner = false
    @State private var showingCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoStatus: String?
    @State private var correctingFood: Food?
    @State private var showingRegenerate = false
    @State private var livePlan: GroceryPlan?
    @State private var hasRefreshedPlan = false

    /// With no search: your usual foods, minus any you removed. While searching: everything you've
    /// created or logged that matches.
    private var suggestions: [Food] {
        guard search.isEmpty else {
            return store.myFoods.filter {
                $0.name.localizedCaseInsensitiveContains(search) || $0.brand.localizedCaseInsensitiveContains(search)
            }.prefix(20).map { $0 }
        }
        return store.frequentFoods(limit: 8, excluding: QuickPicks.hidden(in: hiddenPicks))
    }

    private func removeQuickPick(_ food: Food) {
        var hidden = QuickPicks.hidden(in: hiddenPicks)
        hidden.insert(NutritionStore.foodKey(food))
        withAnimation(.smooth(duration: 0.2)) { hiddenPicks = QuickPicks.encode(hidden) }
    }

    private var moroccanMatches: [Food] { MoroccanFoodCatalog.search(search) }

    private var plan: GroceryPlan? { hasRefreshedPlan ? livePlan : store.groceryPlan }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if showBackButton {
                    NagisenHeader("Kitchen", subtitle: "Meals made with what you actually bought.", onBack: { dismiss() })
                        .padding(.horizontal, 20)
                } else {
                    NagisenPageHeading(kicker: "NAGISEN LAB", title: "Kitchen",
                                       subtitle: "Your kitchen. Your plan.")
                        .padding(.horizontal, 20)
                }
                finderPanel
                if !store.groceryStock.isEmpty {
                    kitchenPanel
                    plannerPanel
                }
                if let plan {
                    planSection(plan).padding(.horizontal, 20)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 90)
        }
        .scrollClipDisabled()
        .softTopScrollEdgeEffect()
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .background(NagisenBackdrop())
        .foregroundStyle(Theme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if let count = store.groceryPlan?.days.count { dayCount = count }
            refreshPlan()
        }
        .onChange(of: store.entries.map { "\($0.id):\($0.servings):\($0.date.timeIntervalSince1970)" }) { _, _ in refreshPlan() }
        .onChange(of: store.groceryStock.map { "\($0.id):\($0.servings):\($0.food.id)" }) { _, _ in refreshPlan() }
        .onChange(of: "\(store.goals.calories):\(store.goals.protein):\(store.goals.fat):\(store.goals.carbs)") { _, _ in refreshPlan() }
        .onChange(of: store.foodsToAvoid) { _, _ in refreshPlan() }
        .onChange(of: store.weekdayGoals.keys.sorted().compactMap { key -> String? in
            guard let value = store.weekdayGoals[key] else { return nil }
            return "\(key):\(value.calories):\(value.protein):\(value.fat):\(value.carbs)"
        }) { _, _ in refreshPlan() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    photoStatus = "Couldn’t read this photo. Try another one or search by name."
                    return
                }
                await recognizeProduct(in: image)
            }
        }
        .task(id: search) {
            onlineFoods = []
            onlineStatus = nil
            isSearchingOnline = false
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            guard query.count >= 2 else { return }
            onlineStatus = "Searching the internet…"
            isSearchingOnline = true
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await searchOnline(query)
        }
        .sheet(item: $selectedFood) { food in
            quantitySheet(food)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingCreate) {
            NavigationStack {
                CreateFoodView { food in
                    store.customFoods.insert(food, at: 0)
                    showingCreate = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { select(food) }
                }
            }
        }
        .sheet(isPresented: $showingScanner) {
            BarcodeScannerView { food in
                showingScanner = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if (food.missingMacros ?? []).isEmpty { select(food) }
                    else { correctingFood = food }
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            ProductCameraView { image in
                showingCamera = false
                if let image { Task { await recognizeProduct(in: image) } }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $correctingFood) { food in
            NavigationStack {
                CreateFoodView(initialFood: food) { corrected in
                    store.customFoods.insert(corrected, at: 0)
                    correctingFood = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { select(corrected) }
                }
            }
        }
        .nagisenDialog("Replace this plan?", isPresented: $showingRegenerate,
                       message: "The current plan will be replaced. Foods you already logged stay in your diary.") {
            [NagisenAction(title: "Generate new plan") { generate() }]
        }
    }

    private var finderPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Find a food")
                    .font(.system(size: 25, design: .serif))
                Text("Search a product or add it from its package.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 11) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.accentText)
                TextField("Food or brand", text: $search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await searchOnline(search) } }
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.muted)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(Theme.paper.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))

            HStack(alignment: .top, spacing: 4) {
                Button { showingScanner = true } label: { labToolLabel("Barcode", symbol: "barcode.viewfinder") }
                Button { showingCamera = true } label: { labToolLabel("Camera", symbol: "camera") }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                PhotosPicker(selection: $photoItem, matching: .images) {
                    labToolLabel("Photo", symbol: "photo")
                }
                Button { showingCreate = true } label: { labToolLabel("Manual", symbol: "square.and.pencil") }
            }
            .buttonStyle(.plain)

            if let photoStatus {
                Text(photoStatus).font(.caption).foregroundStyle(Theme.muted)
            }

            if search.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                Rectangle().fill(Theme.line).frame(height: 1)
                HStack {
                    Text("MOROCCO CATALOG")
                        .font(.caption2.weight(.semibold)).tracking(1.8).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("\(MoroccanFoodCatalog.foods.count.formatted()) products")
                        .font(.caption2).foregroundStyle(Theme.muted)
                }
                if moroccanMatches.isEmpty {
                    Text("No local match. Try the online search below.")
                        .font(.caption).foregroundStyle(Theme.muted)
                } else {
                    ForEach(moroccanMatches.prefix(10)) { food in
                        Button { select(food) } label: {
                            labResultRow(food, detail: "\(food.brand.isEmpty ? "Morocco catalog" : food.brand) · \(food.calories) kcal / \(food.serving)")
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Open Food Facts (ODbL). Check the package label for accuracy.")
                    .font(.caption2).foregroundStyle(Theme.muted)
                Rectangle().fill(Theme.line).frame(height: 1)
                Button { Task { await searchOnline(search) } } label: {
                    HStack {
                        Label("Search online", systemImage: "globe")
                        Spacer()
                        if isSearchingOnline { SwiftUI.ProgressView().tint(Theme.accentText) }
                        else { Image(systemName: "arrow.right") }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                }
                .buttonStyle(.plain)
                if let onlineStatus {
                    Text(onlineStatus).font(.caption).foregroundStyle(Theme.muted)
                }
                if !onlineFoods.isEmpty {
                    Text("ONLINE MATCHES")
                        .font(.caption2.weight(.semibold)).tracking(1.8).foregroundStyle(Theme.muted)
                    ForEach(onlineFoods.prefix(10)) { food in
                        Button {
                            if (food.missingMacros ?? []).isEmpty { select(food) }
                            else { correctingFood = food }
                        } label: {
                            labResultRow(food, detail: "\(food.brand.isEmpty ? "Open Food Facts" : food.brand) · \(food.serving)")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !suggestions.isEmpty || (search.isEmpty && !QuickPicks.hidden(in: hiddenPicks).isEmpty) {
                Rectangle().fill(Theme.line).frame(height: 1)
                HStack {
                    Text(search.isEmpty ? "QUICK PICKS" : "ON THIS IPHONE")
                        .font(.caption2.weight(.semibold)).tracking(1.8).foregroundStyle(Theme.muted)
                    Spacer()
                    if search.isEmpty {
                        Button(editingPicks ? "Done" : "Edit") {
                            withAnimation(.smooth(duration: 0.2)) { editingPicks.toggle() }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(minHeight: 44)
                    }
                }
                if search.isEmpty && suggestions.isEmpty {
                    Text("No quick picks left. Foods you log often will show up here.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                ForEach(suggestions.prefix(search.isEmpty ? 5 : 8)) { food in
                    HStack(spacing: 10) {
                        if editingPicks && search.isEmpty {
                            Button { removeQuickPick(food) } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.title3)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, Theme.accent)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(food.name) from quick picks")
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                        Button { select(food) } label: {
                            labResultRow(food, detail: "\(food.serving) · \(food.calories) kcal")
                        }
                        .buttonStyle(.plain)
                        .disabled(editingPicks && search.isEmpty)
                    }
                }
                if editingPicks && search.isEmpty && !QuickPicks.hidden(in: hiddenPicks).isEmpty {
                    Button("Restore removed (\(QuickPicks.hidden(in: hiddenPicks).count))") {
                        withAnimation(.smooth(duration: 0.2)) { hiddenPicks = QuickPicks.encode([]) }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(minHeight: 44)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nagisenGlass(in: RoundedRectangle(cornerRadius: 20), tint: Theme.surface.opacity(0.18))
        .padding(.horizontal, 18)
    }

    private func labToolLabel(_ title: String, symbol: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 23, weight: .light))
                .foregroundStyle(Theme.accentText)
                .frame(height: 26)
            Text(title).font(.caption.weight(.medium)).foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityLabel(title)
    }

    private func labResultRow(_ food: Food, detail: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(food.name).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Text(detail).font(.caption).foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.accentText)
        }
        .frame(minHeight: 49)
        .contentShape(Rectangle())
    }

    private var kitchenPanel: some View {
        VStack(alignment: .leading, spacing: 19) {
            VStack(alignment: .leading, spacing: 5) {
                Text("In your kitchen")
                    .font(.system(size: 25, design: .serif))
                Text("\(store.groceryStock.count) \(store.groceryStock.count == 1 ? "food" : "foods") · grouped by the macro with the most grams per serving")
                    .font(.subheadline).foregroundStyle(Theme.muted)
            }
            ForEach(KitchenMacro.allCases, id: \.self) { macro in
                let items = store.groceryStock.filter { KitchenMacro.dominant(in: $0.food) == macro }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Circle().fill(macro.color).frame(width: 8, height: 8)
                            Text(macro.rawValue.uppercased())
                                .font(.caption2.weight(.semibold)).tracking(1.8)
                                .foregroundStyle(macro.color)
                            Spacer()
                            Text("\(items.count)")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(items) { item in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.food.name)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(2)
                                    HStack(spacing: 8) {
                                        Text(stockDescription(item))
                                            .font(.caption).foregroundStyle(Theme.muted)
                                        Spacer(minLength: 4)
                                        Button { select(item.food) } label: {
                                            Image(systemName: "pencil")
                                                .foregroundStyle(Theme.accentText)
                                                .frame(width: 40, height: 40)
                                        }
                                        .accessibilityLabel("Edit \(item.food.name)")
                                        Button { remove(item.id) } label: {
                                            Image(systemName: "minus.circle")
                                                .foregroundStyle(Theme.muted)
                                                .frame(width: 40, height: 40)
                                        }
                                        .accessibilityLabel("Remove \(item.food.name)")
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                if item.id != items.last?.id {
                                    Rectangle().fill(Theme.line).frame(height: 1)
                                        .padding(.vertical, 9)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(15)
                    .background(macro.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 15))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nagisenGlass(in: RoundedRectangle(cornerRadius: 20), tint: Theme.surface.opacity(0.18))
        .padding(.horizontal, 18)
    }

    private var plannerPanel: some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Make a plan")
                    .font(.system(size: 25, design: .serif))
                Text("Only your groceries, across the days you choose.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 5) {
                ForEach(1...7, id: \.self) { count in
                    Button { dayCount = count } label: {
                        Text("\(count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(dayCount == count ? Color.white : Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(dayCount == count ? Theme.accent : Theme.paper.opacity(0.55),
                                        in: RoundedRectangle(cornerRadius: 10))
                    }
                    .accessibilityLabel("\(count) \(count == 1 ? "day" : "days")")
                    .accessibilityAddTraits(dayCount == count ? .isSelected : [])
                }
            }
            .buttonStyle(.plain)
            HStack {
                Text("Daily target").foregroundStyle(Theme.muted)
                Spacer()
                Text("\(store.goals(on: .now).calories.formatted()) kcal")
            }
            .font(.subheadline)
            let target = store.goals(on: .now)
            Text("\(target.protein)g protein · \(target.fat)g fat · \(target.carbs)g carbs")
                .font(.caption).foregroundStyle(Theme.muted)
            Button {
                if plan != nil { showingRegenerate = true } else { generate() }
            } label: {
                HStack {
                    Text(plan == nil ? "Make my meal plan" : "Make a new plan")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(16)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nagisenGlass(in: RoundedRectangle(cornerRadius: 20), tint: Theme.surface.opacity(0.18))
        .padding(.horizontal, 18)
    }

    private func planSection(_ plan: GroceryPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("YOUR PLAN")
                    .font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(Theme.muted)
                Text("\(plan.days.count) days from your groceries")
                    .font(.system(size: 27, design: .serif))
                Text("Calories and macros are estimates from the foods you entered. If groceries are short, the plan will show the gap instead of adding ingredients.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 8) {
                ForEach(plan.days.indices, id: \.self) { index in
                    Button("\(index + 1)") { selectedDay = index }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(index == selectedDay ? Color.white : Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(index == selectedDay ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: 9))
                        .accessibilityLabel("Plan day \(index + 1)")
                }
            }
            let day = plan.days[min(selectedDay, plan.days.count - 1)]
            let goal = store.goals(on: day.date)
            let logged = store.entries(on: day.date)
            let eatenCalories = logged.reduce(0) { $0 + $1.calories }
            let eatenProtein = logged.reduce(0.0) { $0 + $1.protein }
            let eatenCarbs = logged.reduce(0.0) { $0 + $1.carbs }
            let eatenFat = logged.reduce(0.0) { $0 + $1.fat }
            HStack(alignment: .firstTextBaseline) {
                Text(day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.system(size: 22, design: .serif))
                Spacer()
                Text("\(day.calories + eatenCalories) / \(goal.calories) kcal")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accentText)
            }
            if !logged.isEmpty {
                Text("\(eatenCalories) eaten · \(day.calories) still planned")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 14) {
                planMacro("Protein", grams: day.protein + eatenProtein, target: goal.protein, color: Theme.protein)
                planMacro("Carbs", grams: day.carbs + eatenCarbs, target: goal.carbs, color: Theme.carbs)
                planMacro("Fat", grams: day.fat + eatenFat, target: goal.fat, color: Theme.fat)
            }
            if day.calories + eatenCalories < goal.calories * 9 / 10 ||
                day.protein + eatenProtein < Double(goal.protein) * 0.9 ||
                day.fat + eatenFat < Double(goal.fat) * 0.9 ||
                day.carbs + eatenCarbs < Double(goal.carbs) * 0.9 {
                Label("Your available groceries cannot fully meet these targets. Add more food and make a new plan.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(Theme.accentText)
            }
            if !logged.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("ALREADY EATEN", systemImage: "checkmark.circle")
                            .font(.caption2.weight(.semibold)).tracking(1.5)
                            .foregroundStyle(Theme.muted)
                        Spacer()
                        Text("\(eatenCalories) kcal")
                            .font(.caption.weight(.semibold))
                    }
                    ForEach(logged) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.food.name).font(.subheadline)
                                .lineLimit(2)
                            Spacer(minLength: 12)
                            Text("\(entry.calories) kcal")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
                .softCardStyle()
            }
            if day.meals.isEmpty {
                Text("No meals remain to plan from your available groceries.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
            }
            ForEach(day.meals) { meal in
                let alreadyLogged = store.entries.contains { $0.planMealID == meal.id }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(meal.meal.rawValue.uppercased())
                            .font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(Theme.muted)
                        Spacer()
                        Text("\(meal.calories) kcal")
                            .font(.caption.weight(.semibold))
                    }
                    Text(meal.title).font(.system(size: 20, design: .serif))
                    ForEach(meal.portions) { portion in
                        HStack(alignment: .firstTextBaseline) {
                            Text(portion.food.name).font(.subheadline)
                            Spacer()
                            Text("\(portion.servings.formatted(.number.precision(.fractionLength(0...1)))) × \(portion.food.serving)")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    Button(alreadyLogged ? "Logged" : "Log this meal") {
                        guard !alreadyLogged else { return }
                        for portion in meal.portions {
                            store.add(portion.food, to: meal.meal, servings: portion.servings,
                                      on: day.date, planMealID: meal.id)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .disabled(alreadyLogged)
                }
                .softCardStyle()
            }
            let used = Dictionary(grouping: plan.days.flatMap(\.meals).flatMap(\.portions), by: \.stockID)
            let left = plan.stockSnapshot.compactMap { item -> String? in
                let consumed = used[item.id, default: []].reduce(0.0) { $0 + $1.servings }
                let remaining = item.servings - consumed
                guard remaining > 0.05 else { return nil }
                return leftoverDescription(for: item.food, servings: remaining)
            }
            if !left.isEmpty {
                Text("LEFT AFTER THE PLAN")
                    .font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(Theme.muted)
                Text(left.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }

    private func planMacro(_ name: String, grams: Double, target: Int, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(name) \(Int(grams.rounded()))/\(target)g")
                .font(.caption2.weight(.medium)).foregroundStyle(Theme.muted)
        }
    }

    private func leftoverDescription(for food: Food, servings: Double) -> String {
        let name = food.name.lowercased()
        if name.range(of: #"\beggs?\b"#, options: .regularExpression) != nil {
            let count = servings.formatted(.number.precision(.fractionLength(0...1)))
            return "\(food.name): \(count) \(abs(servings - 1) < 0.05 ? "egg" : "eggs")"
        }
        guard let gramsPerServing = food.gramsPerServing else {
            return "\(food.name): gram weight unavailable"
        }
        let grams = (servings * gramsPerServing).formatted(.number.precision(.fractionLength(0...1)))
        return "\(food.name): \(grams) g"
    }

    private func quantitySheet(_ food: Food) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(food.name).font(.system(size: 28, design: .serif))
            Text("How much did you buy? One serving is \(food.serving).")
                .font(.subheadline).foregroundStyle(Theme.muted)
            if let grams = food.gramsPerServing, grams > 0 {
                Picker("Unit", selection: $quantityUnit) {
                    Text("Servings").tag(PortionUnit.serving)
                    Text("Grams").tag(PortionUnit.grams)
                }
                .pickerStyle(.segmented)
                .onChange(of: quantityUnit) { _, unit in
                    let current = Double(quantity.replacingOccurrences(of: ",", with: ".")) ?? 1
                    let converted = unit == .grams ? current * grams : current / grams
                    quantity = converted.formatted(.number.precision(.fractionLength(0...2)))
                }
            }
            HStack {
                TextField(quantityUnit == .grams ? "Grams" : "Servings", text: $quantity).keyboardType(.decimalPad)
                    .font(.system(size: 28, design: .rounded))
                Text(quantityUnit == .grams ? "g" : "servings").foregroundStyle(Theme.muted)
            }
            .padding(16).nagisenGlass(in: RoundedRectangle(cornerRadius: 12), tint: Theme.surface.opacity(0.18))
            if quantityUnit == .grams, let servings = parsedQuantity(for: food) {
                Text("≈ \(servings.formatted(.number.precision(.fractionLength(0...2)))) servings")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            Button("Save grocery") { save(food) }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(.white)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                .disabled(parsedQuantity(for: food) == nil)
        }
        .padding(24)
        .background(NagisenBackdrop())
        .foregroundStyle(Theme.ink)
    }

    private func parsedQuantity(for food: Food) -> Double? {
        guard let amount = Double(quantity.replacingOccurrences(of: ",", with: ".")),
              amount >= 0.1, amount <= (quantityUnit == .grams ? 100_000 : 1_000) else { return nil }
        if quantityUnit == .grams {
            guard let grams = food.gramsPerServing, grams > 0 else { return nil }
            let servings = amount / grams
            return servings >= 0.001 && servings <= 1_000 ? servings : nil
        }
        return amount
    }

    private func searchOnline(_ text: String) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return }
        isSearchingOnline = true
        onlineStatus = "Searching the internet…"
        do {
            let results = try await OpenFoodFactsService().search(query)
            guard !Task.isCancelled, search.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
            onlineFoods = results
            onlineStatus = results.isEmpty ? "No online matches. Try a brand or add it manually." : nil
        } catch {
            guard !Task.isCancelled, search.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
            onlineStatus = "Internet search is unavailable. Try again or add it manually."
        }
        isSearchingOnline = false
    }

    private func select(_ food: Food) {
        quantity = store.groceryStock.first(where: { sameFood($0.food, food) })?.servings.formatted() ?? "1"
        quantityUnit = .serving
        selectedFood = food
    }

    private func stockDescription(_ item: GroceryStock) -> String {
        let servings = item.servings.formatted(.number.precision(.fractionLength(0...2)))
        guard let grams = item.food.gramsPerServing else { return "\(servings) × \(item.food.serving)" }
        let totalGrams = (item.servings * grams).formatted(.number.precision(.fractionLength(0...1)))
        return "\(totalGrams) g · \(servings) servings"
    }

    private func recognizeProduct(in image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.82) else {
            photoStatus = "Couldn’t read this photo. Try another one or search by name."
            return
        }
        photoStatus = "Reading the package on this iPhone…"
        let result = await Task.detached(priority: .userInitiated) { () -> ProductPhotoResult in
            let barcode = VNDetectBarcodesRequest()
            let text = VNRecognizeTextRequest()
            text.recognitionLevel = .accurate
            text.usesLanguageCorrection = true
            let classification = VNClassifyImageRequest()
            do {
                try VNImageRequestHandler(data: data, options: [:]).perform([barcode, text, classification])
            } catch {
                return ProductPhotoResult(barcode: nil, query: nil)
            }
            let code = (barcode.results ?? []).compactMap(\.payloadStringValue)
                .first { (8...14).contains($0.filter(\.isNumber).count) }
            let ignored = ["nutrition", "ingredients", "energy", "calories", "per 100", "net weight", "made in"]
            let lines = (text.results ?? [])
                .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { line in
                    line.count >= 3 && line.count <= 45 && line.rangeOfCharacter(from: .letters) != nil &&
                        !ignored.contains(where: { line.localizedCaseInsensitiveContains($0) })
                }
            let packageName = lines.prefix(2).joined(separator: " ")
            let visualName = (classification.results ?? []).first {
                $0.confidence >= 0.12 && !$0.identifier.lowercased().contains("non-food")
            }?.identifier.components(separatedBy: ",").first
            return ProductPhotoResult(barcode: code,
                                      query: packageName.isEmpty ? visualName : packageName)
        }.value

        if let code = result.barcode {
            do {
                let food = try await OpenFoodFactsService().lookup(barcode: code)
                photoStatus = "Barcode matched \(food.name). Check its label before adding."
                if (food.missingMacros ?? []).isEmpty { select(food) }
                else { correctingFood = food }
                return
            } catch {
                // Package text may still find the product when its barcode is absent online.
            }
        }
        guard let query = result.query?.trimmingCharacters(in: .whitespacesAndNewlines),
              query.count >= 2 else {
            photoStatus = "No clear product match. Try the barcode or search by name."
            return
        }
        search = query
        photoStatus = "Photo suggests “\(query)”. Review the online results before adding."
    }

    private func sameFood(_ a: Food, _ b: Food) -> Bool {
        if a.id == b.id { return true }
        if let barcode = a.barcode, !barcode.isEmpty, barcode == b.barcode { return true }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedSame &&
            a.brand.localizedCaseInsensitiveCompare(b.brand) == .orderedSame &&
            a.serving.localizedCaseInsensitiveCompare(b.serving) == .orderedSame
    }

    private func save(_ food: Food) {
        guard let amount = parsedQuantity(for: food) else { return }
        if let index = store.groceryStock.firstIndex(where: { sameFood($0.food, food) }) {
            store.groceryStock[index].servings = amount
            store.groceryStock[index].food = food
        } else {
            store.groceryStock.append(GroceryStock(food: food, servings: amount))
        }
        selectedFood = nil
    }

    private func remove(_ id: UUID) {
        store.groceryStock.removeAll { $0.id == id }
    }

    private func generate() {
        store.groceryPlan = GroceryPlanner.make(stock: store.groceryStock, count: dayCount,
                                                start: .now, goalsForDate: { store.goals(on: $0) },
                                                avoiding: store.foodsToAvoid, diary: store.entries)
        livePlan = store.groceryPlan
        hasRefreshedPlan = true
        selectedDay = 0
    }

    private func refreshPlan() {
        hasRefreshedPlan = true
        guard var base = store.groceryPlan else { livePlan = nil; return }
        guard !store.groceryStock.isEmpty else {
            livePlan = nil
            store.groceryPlan = nil
            return
        }
        if base.anchorEntryIDs == nil {
            base.anchorEntryIDs = store.entries.map(\.id)
            store.groceryPlan = base
        }
        livePlan = GroceryPlanner.make(stock: store.groceryStock, count: base.days.count,
                                       start: base.days.first?.date ?? .now,
                                       goalsForDate: { store.goals(on: $0) },
                                       avoiding: store.foodsToAvoid, diary: store.entries,
                                       anchorEntryIDs: base.anchorEntryIDs,
                                       createdAt: base.createdAt)
    }
}

private struct ProductPhotoResult: Sendable {
    let barcode: String?
    let query: String?
}

private struct ProductCameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onCapture: (UIImage?) -> Void
        init(onCapture: @escaping (UIImage?) -> Void) { self.onCapture = onCapture }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onCapture(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onCapture(nil) }
    }
}
