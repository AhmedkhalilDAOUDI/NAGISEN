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
        CaffeineDrink(name: "Espresso", milligrams: 63, symbol: "cup.and.saucer.fill"),
        CaffeineDrink(name: "Coffee", milligrams: 95, symbol: "cup.and.saucer.fill"),
        CaffeineDrink(name: "Nescafé", milligrams: 65, symbol: "mug.fill"),
        CaffeineDrink(name: "Atay", milligrams: 32, symbol: "leaf.fill"),
        CaffeineDrink(name: "Green tea", milligrams: 28, symbol: "leaf.fill"),
        CaffeineDrink(name: "Red Bull", milligrams: 80, symbol: "bolt.fill"),
        CaffeineDrink(name: "Cola 330 ml", milligrams: 34, symbol: "cup.and.saucer.fill"),
        CaffeineDrink(name: "Energy shot", milligrams: 100, symbol: "bolt.fill")
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

    var isEmpty: Bool { per100g == nil && perServing == nil }
}

enum FoodCost {
    /// Prices follow the food's name, so the same food logged twice is priced once.
    static func key(for food: Food) -> String {
        food.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
        cost(of: entry, price: prices[key(for: entry.food)])
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

    static func display(_ value: Double) -> String {
        let digits = value >= 100 ? 0 : (value >= 10 ? 1 : 2)
        return value.formatted(.number.precision(.fractionLength(digits))) + " MAD"
    }
}
