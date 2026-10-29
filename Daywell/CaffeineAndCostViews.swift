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
                || arguments.contains("-NAGISENOpenFoodPicker") {
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

    @State private var text = ""
    @State private var isLooking = false
    @State private var lookupNote: String?
    @FocusState private var focused: Bool

    var body: some View {
        let price = store.price(for: food)
        let byWeight = food.gramsPerServing != nil

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name).font(.subheadline).lineLimit(1)
                    Text(byWeight ? "per 100 g" : "per serving · \(food.serving)")
                        .font(.caption2).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 6)
                TextField(price == nil ? "—" : FoodCost.display(currentValue(price)), text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                    .focused($focused)
                Text("MAD").font(.caption).foregroundStyle(Theme.muted)
                Button {
                    lookUp()
                } label: {
                    if isLooking {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "sparkles").font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accentText)
                .disabled(isLooking)
                .accessibilityLabel("Ask the assistant for the price of \(food.name)")

                Button("Set") { commit(byWeight: byWeight) }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .disabled(parsed == nil)
            }

            if let lookupNote {
                Text(lookupNote)
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(Theme.ink)
        .onAppear { text = price.map { currentValue($0).formatted(.number.precision(.fractionLength(0...2))) } ?? "" }
    }

    private var parsed: Double? {
        let value = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let number = Double(value), number >= 0 else { return nil }
        return number
    }

    private func currentValue(_ price: FoodPrice?) -> Double {
        guard let price else { return 0 }
        return price.per100g ?? price.perServing ?? 0
    }

    /// Asks DeepSeek for a typical Moroccan price and puts it in the field. It is only a suggestion:
    /// nothing is stored until Set is pressed.
    private func lookUp() {
        guard !isLooking else { return }
        isLooking = true
        lookupNote = nil
        let byWeight = food.gramsPerServing != nil
        Task {
            do {
                let suggestion = try await DeepSeekPrice.lookup(food: food)
                let value = suggestion.value(perHundredGrams: byWeight)
                let range: String
                if let low = suggestion.low, let high = suggestion.high {
                    range = "Estimate \(FoodCost.display(low))–\(FoodCost.display(high)). "
                } else {
                    range = ""
                }
                let note = suggestion.note.map { " \($0)" } ?? ""
                await MainActor.run {
                    if let value {
                        text = value.formatted(.number.precision(.fractionLength(0...2)))
                    }
                    lookupNote = range + (value == nil ? "No price for this unit." : "Press Set to keep it.") + note
                    isLooking = false
                }
            } catch {
                await MainActor.run {
                    lookupNote = error.localizedDescription
                    isLooking = false
                }
            }
        }
    }

    private func commit(byWeight: Bool) {
        guard let value = parsed else { return }
        if value == 0 {
            store.setPrice(FoodPrice(), for: food)
        } else if byWeight {
            store.setPrice(FoodPrice(per100g: value), for: food)
        } else {
            store.setPrice(FoodPrice(perServing: value), for: food)
        }
        focused = false
        lookupNote = nil
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
