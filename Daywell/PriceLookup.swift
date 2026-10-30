import Foundation
import Security

/// A price the assistant suggests, with the range it thinks is plausible.
struct PriceSuggestion: Equatable {
    var per100g: Double?
    var perServing: Double?
    var low: Double?
    var high: Double?
    var note: String?

    /// The number to put in the field, in the unit the food is priced by.
    func value(perHundredGrams: Bool) -> Double? {
        perHundredGrams ? per100g : perServing
    }

    func value(perHundredGrams: Bool, gramsPerServing: Double?) -> Double? {
        if let direct = value(perHundredGrams: perHundredGrams) { return direct }
        guard let gramsPerServing, gramsPerServing > 0 else { return nil }
        if perHundredGrams, let perServing { return perServing / gramsPerServing * 100 }
        if !perHundredGrams, let per100g { return per100g * gramsPerServing / 100 }
        return nil
    }
}

enum PriceLookupError: LocalizedError {
    case missingKey
    case http(Int)
    case noEstimate
    case emptyAnswer
    case unreadableAnswer
    case unitMismatch

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Add your DeepSeek key in Coach first."
        case .http(400), .http(422): return "DeepSeek rejected the price request. Try again after updating the app."
        case .http(401): return "DeepSeek rejected your API key. Check it in Coach settings."
        case .http(402): return "Your DeepSeek account has no API credit. Add credit or enter the shelf price."
        case .http(429): return "DeepSeek's request limit was reached. Try again in a moment."
        case .http(500), .http(503): return "DeepSeek is unavailable right now. Try again later."
        case .http(let code): return "DeepSeek returned error \(code). Try again later."
        case .noEstimate: return "DeepSeek couldn't make a useful estimate for this product. Enter the shelf or receipt price."
        case .emptyAnswer: return "DeepSeek returned an empty answer. Try again."
        case .unreadableAnswer: return "DeepSeek returned an unreadable price. Try again."
        case .unitMismatch: return "DeepSeek didn't give a price in the right unit. Enter the shelf price."
        }
    }
}

/// Asks DeepSeek what a food typically costs in Morocco.
///
/// The answer is only ever a suggestion shown next to the field — a shop's shelf, a receipt or the
/// person's own typing are the sources that actually get stored.
enum DeepSeekPrice {
    private static let account = "daywell.deepseek.api-key"

    static var hasKey: Bool { loadKey() != nil }

    static func lookup(food: Food, observed: ObservedPrice? = nil) async throws -> PriceSuggestion {
        guard let key = loadKey() else { throw PriceLookupError.missingKey }

        let byWeight = food.gramsPerServing != nil
        let unit = byWeight ? "100 grams" : "one serving (\(food.serving))"
        let identity = [food.brand, food.name, food.packageQuantity ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        let reference = observed.map {
            "A real Open Prices record for this exact barcode was \(FoodCost.display($0.value)) per 100 g on \($0.date). It may be outdated."
        } ?? "No verified Moroccan price record is available for this product."
        let prompt = """
        Estimate the current Moroccan retail price of this product: \(identity).
        Barcode: \(food.barcode ?? "unknown"). Unit requested: MAD per \(unit).
        \(reference)

        Do not confuse a package price with a price per 100 g, and do not substitute another \
        brand or package size. You have no live web access. Give a cautious estimate and a \
        plausible range when the product is identifiable. If its identity is too vague, use \
        null for both prices. Say clearly in the note that this is unverified. Return JSON only.
        Example JSON: {"per100g": 12.5, "perServing": null, "low": 9, "high": 16, "note": "Unverified estimate."}
        """

        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let payload: [String: Any] = [
            "model": "deepseek-flash",
            "thinking": ["type": "disabled"],
            "max_tokens": 500,
            "response_format": ["type": "json_object"],
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        struct Completion: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { var content: String? }
                var message: Message
                var finishReason: String?
                enum CodingKeys: String, CodingKey {
                    case message
                    case finishReason = "finish_reason"
                }
            }
            var choices: [Choice]
        }
        for attempt in 0..<2 {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw PriceLookupError.unreadableAnswer }
            guard (200..<300).contains(http.statusCode) else { throw PriceLookupError.http(http.statusCode) }
            guard let completion = try? JSONDecoder().decode(Completion.self, from: data),
                  let choice = completion.choices.first else { throw PriceLookupError.unreadableAnswer }
            let text = choice.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty {
                if attempt == 0 { continue }
                throw PriceLookupError.emptyAnswer
            }
            if let suggestion = parse(text) { return suggestion }
            if choice.finishReason == "length" { throw PriceLookupError.unreadableAnswer }
            if text.contains("per100g") || text.contains("perServing") { throw PriceLookupError.noEstimate }
            throw PriceLookupError.unreadableAnswer
        }
        throw PriceLookupError.emptyAnswer
    }

    /// Pulls the JSON object out of whatever the model wrapped it in.
    static func parse(_ text: String) -> PriceSuggestion? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return nil }
        let json = String(text[start...end])
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        func number(_ key: String) -> Double? {
            if let value = object[key] as? Double { return value > 0 ? value : nil }
            if let value = object[key] as? Int { return value > 0 ? Double(value) : nil }
            if let value = object[key] as? String,
               let parsed = Double(value.replacingOccurrences(of: ",", with: ".")),
               parsed.isFinite, parsed > 0 { return parsed }
            return nil
        }

        let suggestion = PriceSuggestion(per100g: number("per100g"),
                                         perServing: number("perServing"),
                                         low: number("low"),
                                         high: number("high"),
                                         note: (object["note"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines))
        guard suggestion.per100g != nil || suggestion.perServing != nil else { return nil }
        return suggestion
    }

    private static func loadKey() -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword,
                                          kSecAttrService: "Daywell",
                                          kSecAttrAccount: account,
                                          kSecReturnData: true,
                                          kSecMatchLimit: kSecMatchLimitOne] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// A community price for the exact barcode. Only Moroccan dirham records are considered.
struct ObservedPrice: Equatable {
    let value: Double             // MAD per 100 g
    let date: String               // ISO date from Open Prices

    var isRecent: Bool {
        guard let day = Self.dayFormatter.date(from: date) else { return false }
        return day <= .now && day >= Date.now.addingTimeInterval(-365 * 24 * 3600)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

enum OpenPricesService {
    static func lookup(food: Food) async -> ObservedPrice? {
        guard let barcode = food.barcode?.filter(\.isNumber), (8...14).contains(barcode.count),
              var components = URLComponents(string: "https://prices.openfoodfacts.org/api/v1/prices") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "product_code", value: barcode),
            URLQueryItem(name: "currency", value: "MAD"),
            URLQueryItem(name: "type", value: "PRODUCT"),
            URLQueryItem(name: "size", value: "100")
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("NAGISEN/0.16 (https://github.com/AhmedkhalilDAOUDI/NAGISEN)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parse(data, barcode: barcode)
    }

    static func parse(_ data: Data, barcode: String) -> ObservedPrice? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return nil }
        return items.compactMap { item -> ObservedPrice? in
            guard let itemCode = item["product_code"] as? String,
                  itemCode.drop(while: { $0 == "0" }) == barcode.drop(while: { $0 == "0" }),
                  item["currency"] as? String == "MAD",
                  item["price_is_discounted"] as? Bool != true,
                  item["duplicate_of"] is NSNull || item["duplicate_of"] == nil,
                  let price = item["price"] as? Double, price.isFinite, price > 0,
                  let date = item["date"] as? String, !date.isEmpty,
                  date <= Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)) else { return nil }
            let unit = item["price_per"] as? String
            let per100g: Double
            if unit == "KILOGRAM" {
                per100g = price / 10
            } else if unit == nil || unit == "UNIT" {
                guard let product = item["product"] as? [String: Any],
                      let amount = product["product_quantity"] as? Double, amount > 0,
                      let amountUnit = product["product_quantity_unit"] as? String else { return nil }
                switch amountUnit.lowercased() {
                case "g": per100g = price / amount * 100
                case "kg": per100g = price / (amount * 1000) * 100
                default: return nil
                }
            } else { return nil }
            guard per100g.isFinite, per100g > 0, per100g < 100_000 else { return nil }
            return ObservedPrice(value: per100g, date: date)
        }.sorted { $0.date > $1.date }.first
    }
}
