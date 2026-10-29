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
}

enum PriceLookupError: LocalizedError {
    case missingKey
    case unreadableAnswer

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Add your DeepSeek key in Coach first."
        case .unreadableAnswer: return "The answer could not be read. Try again."
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

    static func lookup(food: Food) async throws -> PriceSuggestion {
        guard let key = loadKey() else { throw PriceLookupError.missingKey }

        let byWeight = food.gramsPerServing != nil
        let unit = byWeight ? "100 grams" : "one serving (\(food.serving))"
        let prompt = """
        What does "\(food.name)" cost in Morocco, in Moroccan dirham (MAD), per \(unit)?

        Use typical supermarket and local shop prices. If you do not know this food, still give your \
        best estimate but say so in the note. Reply with JSON only, no prose and no code fences:
        {"per100g": number or null, "perServing": number or null, "low": number, "high": number, "note": "one short sentence"}
        """

        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let payload: [String: Any] = [
            "model": "deepseek-flash",
            "thinking": ["type": "disabled"],
            "max_tokens": 300,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PriceLookupError.unreadableAnswer
        }
        struct Completion: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { var content: String? }
                var message: Message
            }
            var choices: [Choice]
        }
        guard let completion = try? JSONDecoder().decode(Completion.self, from: data),
              let text = completion.choices.first?.message.content,
              let suggestion = parse(text) else {
            throw PriceLookupError.unreadableAnswer
        }
        return suggestion
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
            if let value = object[key] as? String { return Double(value.replacingOccurrences(of: ",", with: ".")) }
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
