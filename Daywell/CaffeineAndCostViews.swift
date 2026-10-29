import SwiftUI

// MARK: - Caffeine card

/// What is in the system right now, and how much will still be there at bedtime.
struct CaffeineCard: View {
    @EnvironmentObject private var store: NutritionStore
    let date: Date
    @State private var showingDetails = false

    var body: some View {
        let now = Date()
        let level = store.caffeineLevel(at: now)
        let bedtime = store.caffeineAtBedtime(on: date)
        let total = store.caffeineTotal(on: date)

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("CAFFEINE", systemImage: "bolt.fill")
                    .font(.caption2.weight(.semibold)).tracking(2)
                    .foregroundStyle(Theme.accentText)
                Spacer()
                Button("Details") { showingDetails = true }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(Int(level.rounded()).formatted())
                    .font(.system(size: 34, weight: .light, design: .serif))
                Text("mg in you now")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                Spacer()
                Text("\(total) mg today")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            }

            HStack(spacing: 6) {
                Image(systemName: bedtimeWarning(bedtime.level) ? "moon.zzz.fill" : "moon.fill")
                    .font(.caption)
                    .foregroundStyle(bedtimeWarning(bedtime.level) ? Theme.red : Theme.muted)
                Text("\(Int(bedtime.level.rounded())) mg left at \(bedtime.time.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(bedtimeWarning(bedtime.level) ? Theme.red : Theme.muted)
                Spacer()
            }

            HStack(spacing: 9) {
                ForEach(CaffeineDrink.presets.prefix(3)) { drink in
                    Button("+ \(drink.name)") { store.addCaffeine(drink) }
                }
            }
            .font(.caption.weight(.semibold))
        }
        .cardStyle()
        .sheet(isPresented: $showingDetails) { CaffeineDetailView(date: date) }
        #if DEBUG
        .onAppear {
            // Test-only: opens the sheet for a screenshot.
            if ProcessInfo.processInfo.arguments.contains("-NAGISENOpenCaffeine") {
                showingDetails = true
            }
        }
        #endif
    }

    private func bedtimeWarning(_ level: Double) -> Bool { level >= 50 }
}

private struct CaffeineDetailView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    let date: Date

    @State private var customMilligrams = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    curve
                    drinks
                    settings
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .background(Theme.surface.ignoresSafeArea())
            .navigationTitle("Caffeine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var curve: some View {
        let entries = store.caffeineEntries(on: date)
        let bedtime = store.caffeineAtBedtime(on: date)
        let end = max(bedtime.time, Date()).addingTimeInterval(3600)
        let start = Calendar.current.startOfDay(for: date)
        let points = CaffeineMath.curve(entries: entries, start: start, end: end,
                                        halfLife: store.caffeineHalfLifeHours)
        let peak = max(points.map(\.level).max() ?? 0, 1)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Today's curve")
                .font(.system(size: 19, design: .serif))
                .foregroundStyle(Theme.ink)

            Canvas { context, size in
                guard points.count > 1 else { return }
                let span = end.timeIntervalSince(start)
                func point(_ date: Date, _ level: Double) -> CGPoint {
                    let x = CGFloat(date.timeIntervalSince(start) / max(span, 1)) * size.width
                    let y = size.height - CGFloat(level / peak) * (size.height - 8)
                    return CGPoint(x: x, y: y)
                }

                var path = Path()
                path.move(to: point(points[0].date, 0))
                for p in points { path.addLine(to: point(p.date, p.level)) }
                path.addLine(to: point(points[points.count - 1].date, 0))
                path.closeSubpath()
                context.fill(path, with: .color(Theme.accentText.opacity(0.18)))

                var line = Path()
                line.move(to: point(points[0].date, points[0].level))
                for p in points.dropFirst() { line.addLine(to: point(p.date, p.level)) }
                context.stroke(line, with: .color(Theme.accentText), lineWidth: 1.8)

                let x = point(bedtime.time, 0).x
                var marker = Path()
                marker.move(to: CGPoint(x: x, y: 0))
                marker.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(marker, with: .color(Theme.muted.opacity(0.7)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            .frame(height: 120)

            HStack {
                Text("peak \(Int(peak.rounded())) mg")
                Spacer()
                Text("bedtime \(Int(bedtime.level.rounded())) mg")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.muted)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nagisenGlass(in: RoundedRectangle(cornerRadius: 20))
    }

    private var drinks: some View {
        let entries = store.caffeineEntries(on: date)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Drinks")
                .font(.system(size: 19, design: .serif))
                .foregroundStyle(Theme.ink)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ForEach(CaffeineDrink.presets) { drink in
                    Button {
                        store.addCaffeine(drink, at: drinkTime())
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(drink.name).font(.caption.weight(.semibold))
                            Text("\(drink.milligrams) mg").font(.caption2).foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.ink)
                }
            }

            HStack(spacing: 8) {
                TextField("Custom mg", text: $customMilligrams)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                Button("Add") {
                    if let value = Int(customMilligrams), value > 0 {
                        store.addCaffeine(milligrams: value, name: "Custom", at: drinkTime())
                        customMilligrams = ""
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                Spacer()
            }

            if entries.isEmpty {
                Text("Nothing logged on this day.")
                    .font(.caption).foregroundStyle(Theme.muted)
            } else {
                ForEach(entries) { entry in
                    HStack(spacing: 10) {
                        Text(entry.date.formatted(date: .omitted, time: .shortened))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.muted)
                        Text(entry.label).font(.subheadline)
                        Spacer()
                        Text("\(entry.milligrams) mg")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.muted)
                        Button {
                            store.deleteCaffeine(entry)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(Theme.red)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(entry.label)")
                    }
                    .foregroundStyle(Theme.ink)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nagisenGlass(in: RoundedRectangle(cornerRadius: 20))
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your curve")
                .font(.system(size: 19, design: .serif))
                .foregroundStyle(Theme.ink)

            Stepper(value: $store.caffeineHalfLifeHours, in: 3...7, step: 0.5) {
                HStack {
                    Text("Half-life").font(.subheadline)
                    Spacer()
                    Text("\(store.caffeineHalfLifeHours.formatted(.number.precision(.fractionLength(1)))) h")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.muted)
                }
            }

            Stepper(value: $store.caffeineBedtimeHour, in: 18...23) {
                HStack {
                    Text("Bedtime").font(.subheadline)
                    Spacer()
                    Text(String(format: "%02d:00", store.caffeineBedtimeHour))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.muted)
                }
            }

            Text("Most people clear caffeine at about 5 hours. The number at bedtime is what can still keep you awake.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .foregroundStyle(Theme.ink)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nagisenGlass(in: RoundedRectangle(cornerRadius: 20))
    }

    /// A drink added while looking at today counts from now; on a past day there is no sensible
    /// time to invent, so it lands at noon.
    private func drinkTime() -> Date {
        Calendar.current.isDateInToday(date)
            ? .now
            : Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }
}

// MARK: - Cost card

struct CostCard: View {
    @EnvironmentObject private var store: NutritionStore
    let date: Date
    @State private var showingDetails = false

    var body: some View {
        let cost = store.cost(on: date)
        let protein = store.proteinCost(on: date)
        let priced = store.costFoods.count

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("SPEND", systemImage: "banknote.fill")
                    .font(.caption2.weight(.semibold)).tracking(2)
                    .foregroundStyle(Theme.accentText)
                Spacer()
                Button("Prices") { showingDetails = true }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(FoodCost.display(cost))
                    .font(.system(size: 34, weight: .light, design: .serif))
                Text("today")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                Spacer()
                if let protein {
                    Text("\(FoodCost.display(protein)) / g protein")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                }
            }

            if cost == 0 {
                Text(priced == 0 ? "Add foods to see what your day costs." : "Set prices to see what your day costs.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
        .cardStyle()
        .sheet(isPresented: $showingDetails) { CostDetailView() }
        #if DEBUG
        .onAppear {
            // Test-only: opens the sheet for a screenshot.
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-NAGISENOpenCost")
                || arguments.contains("-NAGISENOpenReceipt")
                || arguments.contains("-NAGISENOpenFoodPicker")
                || arguments.contains("-NAGISENOpenPriceEditor") {
                showingDetails = true
            }
        }
        #endif
    }
}

private struct CostDetailView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingReceipt = false
    @State private var showingFoodPicker = false
    #if DEBUG
    @State private var debugFood: Food?
    #endif


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summary
                    prices
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .background(Theme.surface.ignoresSafeArea())
            .navigationTitle("Cost")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingReceipt = true
                    } label: {
                        Label("Scan receipt", systemImage: "doc.text.viewfinder")
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showingReceipt) {
                ReceiptPriceView().environmentObject(store)
            }
            #if DEBUG
            .sheet(item: $debugFood) { food in
                PriceEditorView(food: food).environmentObject(store)
            }
            #endif
            .sheet(isPresented: $showingFoodPicker) {
                PriceFoodPicker { food in
                    store.addCostFood(food)
                }
                .environmentObject(store)
            }
            #if DEBUG
            .task {
                // Test-only: opens a child sheet for a screenshot once this one has settled.
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("-NAGISENOpenReceipt") {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    showingReceipt = true
                } else if arguments.contains("-NAGISENOpenFoodPicker") {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    showingFoodPicker = true
                } else if arguments.contains("-NAGISENOpenPriceEditor") {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    debugFood = store.costFoods.first ?? store.allFoods.first
                }
            }
            #endif
        }
    }

    private var summary: some View {
        let today = Date()
        let calendar = Calendar.current
        let week = (0..<7).map { offset -> Double in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return store.cost(on: day)
        }
        let weekTotal = week.reduce(0, +)
        let weekAverage = weekTotal / 7
        let month = store.entries
            .filter { calendar.isDate($0.date, equalTo: today, toGranularity: .month) }
            .compactMap { FoodCost.cost(entry: $0, prices: store.foodPrices) }
            .reduce(0, +)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(FoodCost.display(store.cost(on: today)))
                    .font(.system(size: 32, weight: .light, design: .serif))
                Text("today").font(.subheadline).foregroundStyle(Theme.muted)
            }
            HStack {
                Text("7-day average").font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                Text(FoodCost.display(weekAverage)).font(.caption.monospacedDigit())
            }
            HStack {
                Text("This month so far").font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                Text(FoodCost.display(month)).font(.caption.monospacedDigit())
            }
            HStack {
                Text("Cost per gram of protein").font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                Text(store.proteinCost(on: today).map(FoodCost.display) ?? "—")
                    .font(.caption.monospacedDigit())
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nagisenGlass(in: RoundedRectangle(cornerRadius: 20))
    }

    private var prices: some View {
        let foods = store.costFoods
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Prices")
                    .font(.system(size: 19, design: .serif))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button {
                    showingFoodPicker = true
                } label: {
                    Label("Add", systemImage: "plus.circle")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Theme.accentText)
            }
            Text("Add a food, then set its price by hand or ask the assistant for a typical Moroccan price. Weight-based prices follow the portion you log.")
                .font(.caption).foregroundStyle(Theme.muted)

            if foods.isEmpty {
                Text("No foods yet. Add one to price it.")
                    .font(.caption).foregroundStyle(Theme.muted)
            } else {
                ForEach(foods) { food in
                    HStack(spacing: 8) {
                        PriceRow(food: food)
                        Button {
                            store.removeCostFood(food)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(Theme.red)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(food.name) from the price list")
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nagisenGlass(in: RoundedRectangle(cornerRadius: 20))
    }
}


private struct PriceRow: View {
    @EnvironmentObject private var store: NutritionStore
    let food: Food

    @State private var showingEditor = false

    var body: some View {
        let price = store.price(for: food)
        Button {
            showingEditor = true
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(subtitle(price))
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(priceText(price))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(price == nil || price?.isEmpty == true ? Theme.muted : Theme.accentText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink)
        .sheet(isPresented: $showingEditor) {
            PriceEditorView(food: food).environmentObject(store)
        }
    }

    private func subtitle(_ price: FoodPrice?) -> String {
        if let summary = price?.purchaseSummary { return summary }
        return food.gramsPerServing != nil ? "per 100 g" : "per serving · \(food.serving)"
    }

    private func priceText(_ price: FoodPrice?) -> String {
        guard let price, !price.isEmpty else { return "Set price" }
        if let per100g = price.per100g { return FoodCost.display(per100g) + " / 100 g" }
        if let perServing = price.perServing { return FoodCost.display(perServing) + " / serving" }
        return "Set price"
    }
}

/// Records a price the way a shop records it: how much was bought, and what it cost.
private struct PriceEditorView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    let food: Food

    @State private var unit: PriceAmountUnit = .grams
    @State private var amount = ""
    @State private var paid = ""
    @State private var isLooking = false
    @State private var note: String?

    private var amountValue: Double? { number(amount) }
    private var paidValue: Double? { number(paid) }

    private var derived: FoodPrice? {
        guard let amountValue, let paidValue else { return nil }
        return FoodCost.derive(amount: amountValue, unit: unit, paid: paidValue, food: food)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    fields
                    result
                    assistant
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .background(Theme.surface.ignoresSafeArea())
            .navigationTitle(food.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let derived { store.setPrice(derived, for: food) }
                        dismiss()
                    }
                    .disabled(derived == nil)
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How much did you buy?")
                .font(.system(size: 19, design: .serif))
                .foregroundStyle(Theme.ink)
            Text("Enter the amount and what you paid. The price per 100 g or per serving is worked out from it.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Unit", selection: $unit) {
                ForEach(PriceAmountUnit.allCases) { value in
                    Text(value.rawValue.capitalized).tag(value)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(unit == .grams ? "Amount in grams" : "Number of servings")
                        .font(.caption).foregroundStyle(Theme.muted)
                    TextField("0", text: $amount)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Paid in MAD").font(.caption).foregroundStyle(Theme.muted)
                    TextField("0", text: $paid)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if unit == .grams, food.gramsPerServing != nil {
                Text("One serving of this food is \(food.serving).")
                    .font(.caption2).foregroundStyle(Theme.muted)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nagisenGlass(in: RoundedRectangle(cornerRadius: 20))
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let derived {
                if let per100g = derived.per100g {
                    Text("\(FoodCost.display(per100g)) per 100 g")
                        .font(.system(size: 24, weight: .light, design: .serif))
                        .foregroundStyle(Theme.ink)
                    if let grams = food.gramsPerServing {
                        Text("One serving (\(food.serving)) costs \(FoodCost.display(per100g * grams / 100)).")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                } else if let perServing = derived.perServing {
                    Text("\(FoodCost.display(perServing)) per serving")
                        .font(.system(size: 24, weight: .light, design: .serif))
                        .foregroundStyle(Theme.ink)
                }
            } else {
                Text("Fill in the amount and the price paid.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .nagisenGlass(in: RoundedRectangle(cornerRadius: 20))
    }

    private var assistant: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                lookUp()
            } label: {
                HStack(spacing: 8) {
                    if isLooking { ProgressView().controlSize(.small) }
                    else { Image(systemName: "sparkles") }
                    Text(isLooking ? "Asking…" : "Ask DeepSeek for a typical price")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Theme.accentText)
            }
            .buttonStyle(.plain)
            .disabled(isLooking)

            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .nagisenGlass(in: RoundedRectangle(cornerRadius: 20))
    }

    private func prefill() {
        guard let price = store.price(for: food) else {
            unit = food.gramsPerServing != nil ? .grams : .servings
            return
        }
        if let grams = price.boughtGrams, let paidValue = price.paid {
            unit = .grams
            amount = grams.formatted(.number.precision(.fractionLength(0...2)))
            paid = paidValue.formatted(.number.precision(.fractionLength(0...2)))
        } else if let servings = price.boughtServings, let paidValue = price.paid {
            unit = .servings
            amount = servings.formatted(.number.precision(.fractionLength(0...2)))
            paid = paidValue.formatted(.number.precision(.fractionLength(0...2)))
        } else if let per100g = price.per100g {
            unit = .grams
            amount = "100"
            paid = per100g.formatted(.number.precision(.fractionLength(0...2)))
        } else if let perServing = price.perServing {
            unit = .servings
            amount = "1"
            paid = perServing.formatted(.number.precision(.fractionLength(0...2)))
        }
    }

    /// The assistant gives a unit price; it is turned into what that amount would cost.
    private func lookUp() {
        isLooking = true
        note = nil
        Task {
            do {
                let suggestion = try await DeepSeekPrice.lookup(food: food)
                await MainActor.run {
                    if unit == .grams, let per100g = suggestion.per100g,
                       let grams = amountValue {
                        paid = (per100g * grams / 100).formatted(.number.precision(.fractionLength(0...2)))
                    } else if unit == .servings, let perServing = suggestion.perServing,
                              let count = amountValue {
                        paid = (perServing * count).formatted(.number.precision(.fractionLength(0...2)))
                    } else if amountValue == nil, let per100g = suggestion.per100g, unit == .grams {
                        amount = "100"
                        paid = per100g.formatted(.number.precision(.fractionLength(0...2)))
                    } else if amountValue == nil, let perServing = suggestion.perServing, unit == .servings {
                        amount = "1"
                        paid = perServing.formatted(.number.precision(.fractionLength(0...2)))
                    }
                    let range: String
                    if let low = suggestion.low, let high = suggestion.high {
                        range = "Typical \(FoodCost.display(low))–\(FoodCost.display(high)). "
                    } else { range = "" }
                    note = range + "Press Save to keep it. " + (suggestion.note ?? "")
                    isLooking = false
                }
            } catch {
                await MainActor.run {
                    note = error.localizedDescription
                    isLooking = false
                }
            }
        }
    }

    private func number(_ text: String) -> Double? {
        let value = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let parsed = Double(value) else { return nil }
        return parsed
    }
}


/// Picks a food to price from the same sources the food log searches: your own foods, the
/// Moroccan catalogue and Open Food Facts online.
private struct PriceFoodPicker: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    let onPick: (Food) -> Void

    @State private var search = ""
    @State private var online: [Food] = []
    @State private var isSearchingOnline = false
    @State private var searchTask: Task<Void, Never>?

    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var localMatches: [Food] {
        guard !query.isEmpty else { return Array(store.allFoods.prefix(250)) }
        return store.allFoods.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
                $0.brand.localizedCaseInsensitiveContains(query)
        }
    }

    private var catalogMatches: [Food] {
        guard query.count >= 2 else { return [] }
        let known = Set(localMatches.map { FoodCost.key(for: $0) })
        return MoroccanFoodCatalog.search(query).filter { !known.contains(FoodCost.key(for: $0)) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !localMatches.isEmpty {
                    Section("Your foods") {
                        ForEach(localMatches) { row($0) }
                    }
                }
                if !catalogMatches.isEmpty {
                    Section("Moroccan foods") {
                        ForEach(catalogMatches) { row($0) }
                    }
                }
                Section {
                    if isSearchingOnline {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Searching online…").font(.subheadline).foregroundStyle(Theme.muted)
                        }
                    } else if online.isEmpty {
                        Text(query.count >= 2 ? "No online matches." : "Type a name to search online.")
                            .font(.caption).foregroundStyle(Theme.muted)
                    } else {
                        ForEach(online) { row($0) }
                    }
                } header: {
                    Text("Online")
                }
            }
            .searchable(text: $search, prompt: "Food or brand")
            .autocorrectionDisabled()
            .navigationTitle("Add a food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .onChange(of: search) { _, _ in searchOnline() }
            .onDisappear { searchTask?.cancel() }
            #if DEBUG
            .task {
                // Test-only: exercises the pick path without a tap.
                guard ProcessInfo.processInfo.arguments.contains("-NAGISENAutoPick"),
                      let first = localMatches.first else { return }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                onPick(first)
                dismiss()
            }
            #endif
        }
    }

    private func row(_ food: Food) -> some View {
        Button {
            onPick(food)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text("\(food.serving) · \(food.calories) kcal")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                if let price = store.price(for: food), let value = price.per100g ?? price.perServing {
                    Text(FoodCost.display(value))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    /// Online results are debounced so typing does not fire a request per keystroke.
    private func searchOnline() {
        searchTask?.cancel()
        let text = query
        guard text.count >= 2 else {
            online = []
            isSearchingOnline = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { isSearchingOnline = true }
            let results = (try? await OpenFoodFactsService().search(text)) ?? []
            guard !Task.isCancelled else { return }
            let known = Set(localMatches.map { FoodCost.key(for: $0) })
                .union(catalogMatches.map { FoodCost.key(for: $0) })
            await MainActor.run {
                online = results.filter { !known.contains(FoodCost.key(for: $0)) }
                isSearchingOnline = false
            }
        }
    }
}
