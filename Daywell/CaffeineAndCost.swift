import Foundation

// MARK: - Caffeine

/// One caffeinated drink, at the moment it was had.
struct CaffeineEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date = .now
    var milligrams: Int
    var name: String = ""

    var label: String { name.isEmpty ? "Caffeine" : name }
}

/// A drink somebody actually has, so logging is one tap instead of a number.
struct CaffeineDrink: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let milligrams: Int
    let symbol: String

    static let presets: [CaffeineDrink] = [
        CaffeineDrink(name: "Atay", milligrams: 32, symbol: "leaf.fill"),
        CaffeineDrink(name: "Espresso", milligrams: 63, symbol: "cup.and.saucer.fill"),
        CaffeineDrink(name: "Monster Ultra", milligrams: 150, symbol: "bolt.fill")
    ]
}

/// Caffeine leaves the body on a half-life curve: half of it every few hours. The point of the
/// model is the evening number — how much is still working when the lights go out.
enum CaffeineMath {
    static let defaultHalfLifeHours = 5.0

    /// What is left of one dose after `hours`.
    static func remaining(_ milligrams: Double, hours: Double, halfLife: Double) -> Double {
        guard milligrams > 0 else { return 0 }
        guard hours > 0 else { return milligrams }
        guard halfLife > 0 else { return 0 }
        return milligrams * pow(0.5, hours / halfLife)
    }

    /// Everything still in the body at `time`.
    static func level(entries: [CaffeineEntry], at time: Date, halfLife: Double) -> Double {
        entries.reduce(0) { total, entry in
            let hours = time.timeIntervalSince(entry.date) / 3600
            guard hours >= 0 else { return total }
            return total + remaining(Double(entry.milligrams), hours: hours, halfLife: halfLife)
        }
    }

    /// Everything drunk on a calendar day, ignoring what has since worn off.
    static func total(entries: [CaffeineEntry], on day: Date, calendar: Calendar = .current) -> Int {
        entries.filter { calendar.isDate($0.date, inSameDayAs: day) }
            .reduce(0) { $0 + $1.milligrams }
    }

    static func entries(entries: [CaffeineEntry], on day: Date, calendar: Calendar = .current) -> [CaffeineEntry] {
        entries.filter { calendar.isDate($0.date, inSameDayAs: day) }.sorted { $0.date < $1.date }
    }

    /// A point per quarter hour from the first drink to `end`, for the decay chart.
    static func curve(entries: [CaffeineEntry],
                      start: Date,
                      end: Date,
                      step: TimeInterval = 900,
                      halfLife: Double) -> [(date: Date, level: Double)] {
        let beginning = entries.map(\.date).min() ?? start
        var points: [(date: Date, level: Double)] = []
        var moment = beginning
        while moment <= end {
            points.append((moment, level(entries: entries, at: moment, halfLife: halfLife)))
            moment = moment.addingTimeInterval(step)
        }
        if let last = points.last, last.date < end {
            points.append((end, level(entries: entries, at: end, halfLife: halfLife)))
        }
        return points
    }

    static func cutoff(hour: Int, on day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: min(23, max(0, hour)), minute: 0, second: 0, of: day)
            ?? calendar.startOfDay(for: day).addingTimeInterval(TimeInterval(hour * 3600))
    }
}

// MARK: - Cost

/// What a food costs, either by weight or by serving. Weight is preferred because portions vary.
struct FoodPrice: Codable, Equatable {
    var per100g: Double? = nil
    var perServing: Double? = nil
    /// What was actually bought, kept so the price can be explained rather than just stored.
    var boughtGrams: Double? = nil
    var boughtServings: Double? = nil
    var paid: Double? = nil

    var isEmpty: Bool { per100g == nil && perServing == nil }

    /// "1 kg for 60 MAD" — the purchase behind the price, when it is known.
    var purchaseSummary: String? {
        guard let paid else { return nil }
        if let grams = boughtGrams {
            let amount = grams >= 1000
                ? "\((grams / 1000).formatted(.number.precision(.fractionLength(0...2)))) kg"
                : "\(grams.formatted(.number.precision(.fractionLength(0...0)))) g"
            return "\(amount) for \(paid.formatted(.number.precision(.fractionLength(0...2)))) \(UserRegion.currency)"
        }
        if let servings = boughtServings {
            return "\(servings.formatted(.number.precision(.fractionLength(0...2)))) servings for \(paid.formatted(.number.precision(.fractionLength(0...2)))) \(UserRegion.currency)"
        }
        return nil
    }
}

/// The unit someone thinks in when they buy: a weight or a number of servings.
enum PriceAmountUnit: String, CaseIterable, Identifiable {
    case grams = "grams"
    case servings = "servings"

    var id: String { rawValue }
}

enum FoodCost {
    /// A barcode identifies a packaged product; brand and name distinguish unscanned foods.
    static func key(for food: Food) -> String {
        if let barcode = food.barcode?.filter(\.isNumber), !barcode.isEmpty {
            return "barcode:\(barcode)"
        }
        let name = legacyKey(for: food)
        let brand = food.brand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return brand.isEmpty ? name : "brand:\(brand)|\(name)"
    }

    static func legacyKey(for food: Food) -> String {
        food.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func price(for food: Food, prices: [String: FoodPrice]) -> FoodPrice? {
        prices[key(for: food)] ?? prices[legacyKey(for: food)]
    }

    static func grams(of entry: DiaryEntry) -> Double? {
        guard let perServing = entry.food.gramsPerServing else { return nil }
        return perServing * entry.servings
    }

    static func cost(of entry: DiaryEntry, price: FoodPrice?) -> Double? {
        guard let price, !price.isEmpty else { return nil }
        if let per100g = price.per100g, let grams = grams(of: entry), grams > 0 {
            return grams / 100 * per100g
        }
        if let perServing = price.perServing {
            return perServing * entry.servings
        }
        return nil
    }

    static func cost(entry: DiaryEntry, prices: [String: FoodPrice]) -> Double? {
        cost(of: entry, price: price(for: entry.food, prices: prices))
    }

    static func dayCost(entries: [DiaryEntry],
                        prices: [String: FoodPrice],
                        on day: Date,
                        calendar: Calendar = .current) -> Double {
        entries.filter { calendar.isDate($0.date, inSameDayAs: day) }
            .compactMap { cost(entry: $0, prices: prices) }
            .reduce(0, +)
    }

    /// Spend divided by protein, so protein sources can be compared honestly.
    static func costPerGramOfProtein(entries: [DiaryEntry],
                                     prices: [String: FoodPrice],
                                     on day: Date,
                                     calendar: Calendar = .current) -> Double? {
        let dayEntries = entries.filter { calendar.isDate($0.date, inSameDayAs: day) }
        let protein = dayEntries.reduce(0) { $0 + $1.protein }
        guard protein >= 5 else { return nil }
        let spend = dayEntries.compactMap { cost(entry: $0, prices: prices) }.reduce(0, +)
        guard spend > 0 else { return nil }
        return spend / protein
    }

    /// A food's price per 100 g of protein, for ranking what is worth buying.
    static func proteinValue(of food: Food, price: FoodPrice) -> Double? {
        guard let per100g = price.per100g, food.protein > 0 else { return nil }
        return per100g / food.protein * 100
    }

    /// Turns "I bought this much for this much" into the price the diary uses.
    static func derive(amount: Double, unit: PriceAmountUnit, paid: Double, food: Food) -> FoodPrice? {
        guard amount > 0, paid >= 0 else { return nil }
        switch unit {
        case .grams:
            return FoodPrice(per100g: paid / amount * 100,
                             boughtGrams: amount,
                             paid: paid)
        case .servings:
            return FoodPrice(perServing: paid / amount,
                             boughtServings: amount,
                             paid: paid)
        }
    }

    static func display(_ value: Double) -> String {
        let digits = value >= 100 ? 0 : (value >= 10 ? 1 : 2)
        return value.formatted(.number.precision(.fractionLength(digits))) + " " + UserRegion.currency
    }
}

/// The country chosen during setup. Prices are shown in its currency, and online price suggestions
/// (which only cover Moroccan shops, in MAD) are offered only there. Morocco when none was chosen.
enum UserRegion {
    static let key = "nagisen.country"
    static var code: String { UserDefaults.standard.string(forKey: key) ?? "MA" }
    static var currency: String { currency(for: code) }
    static var hasPriceSuggestions: Bool { code == "MA" }

    static func currency(for code: String) -> String {
        Locale(identifier: "en_\(code)").currency?.identifier ?? "MAD"
    }
}
