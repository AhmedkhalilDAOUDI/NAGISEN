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
        let unpriced = store.unpricedFoods(limit: 100).count

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("SPEND", systemImage: "banknote.fill")
                    .font(.caption2.weight(.semibold)).tracking(2)
                    .foregroundStyle(Theme.accentText)
                Spacer()
                Button(unpriced > 0 ? "\(unpriced) to price" : "Prices") { showingDetails = true }
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

            if cost == 0 && unpriced > 0 {
                Text("Add prices to see what your day costs.")
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
            if arguments.contains("-NAGISENOpenCost") || arguments.contains("-NAGISENOpenReceipt") {
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
            .task {
                // Test-only: opens the scanner for a screenshot once this sheet has settled.
                guard ProcessInfo.processInfo.arguments.contains("-NAGISENOpenReceipt") else { return }
                try? await Task.sleep(nanoseconds: 600_000_000)
                showingReceipt = true
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
        let foods = pricedFoods()
        return VStack(alignment: .leading, spacing: 12) {
            Text("Prices")
                .font(.system(size: 19, design: .serif))
                .foregroundStyle(Theme.ink)
            Text("Set what a food costs, or scan a receipt and let it fill these in. Weight-based prices follow the portion you log.")
                .font(.caption).foregroundStyle(Theme.muted)

            if foods.isEmpty {
                Text("Log some food first, then price it here.")
                    .font(.caption).foregroundStyle(Theme.muted)
            } else {
                ForEach(foods) { food in
                    PriceRow(food: food)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nagisenGlass(in: RoundedRectangle(cornerRadius: 20))
    }

    /// Foods eaten in the last 30 days, with anything unpriced first.
    private func pricedFoods() -> [Food] {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        var seen: Set<String> = []
        var result: [Food] = []
        for entry in store.entries.sorted(by: { $0.date > $1.date }) where entry.date >= cutoff {
            let key = FoodCost.key(for: entry.food)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(entry.food)
        }
        return result.sorted { a, b in
            let aPriced = store.price(for: a) != nil
            let bPriced = store.price(for: b) != nil
            return aPriced == bPriced ? a.name < b.name : !aPriced
        }
    }
}

private struct PriceRow: View {
    @EnvironmentObject private var store: NutritionStore
    let food: Food

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let price = store.price(for: food)
        let byWeight = food.gramsPerServing != nil

        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name).font(.subheadline).lineLimit(1)
                Text(byWeight ? "per 100 g" : "per serving · \(food.serving)")
                    .font(.caption2).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 6)
            TextField(price == nil ? "—" : FoodCost.display(currentValue(price)),
                      text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 78)
                .focused($focused)
            Text("MAD").font(.caption).foregroundStyle(Theme.muted)
            Button("Set") { commit(byWeight: byWeight) }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .disabled(parsed == nil)
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
    }
}
