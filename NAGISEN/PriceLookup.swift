import Foundation

/// A current retailer listing, used only when its food name and package weight can be matched.
struct RetailPriceQuote: Equatable {
    let per100g: Double
    let productName: String
    let sourceURL: URL
}

enum RetailPriceService {
    static func lookup(food: Food) async -> RetailPriceQuote? {
        // A different brand's shelf price must never be presented as this product's price.
        guard food.brand.isEmpty, food.gramsPerServing != nil,
              var components = URLComponents(string: "https://www.mymarket.ma/search/suggest.json") else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: food.name),
                                 URLQueryItem(name: "resources[type]", value: "product")]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parse(data, food: food)
    }

    static func parse(_ data: Data, food: Food) -> RetailPriceQuote? {
        guard food.brand.isEmpty,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let resources = root["resources"] as? [String: Any],
              let results = resources["results"] as? [String: Any],
              let products = results["products"] as? [[String: Any]] else { return nil }
        let wanted = ReceiptMatcher.tokens(food.name)
        guard !wanted.isEmpty else { return nil }
        let expandedWanted = ReceiptMatcher.expanded(wanted)
        for product in products {
            guard let title = product["title"] as? String,
                  let path = product["url"] as? String,
                  let url = URL(string: path, relativeTo: URL(string: "https://www.mymarket.ma"))?.absoluteURL,
                  url.host == "www.mymarket.ma",
                  let rawPrice = product["price"] as? String,
                  let price = Double(rawPrice.replacingOccurrences(of: ",", with: ".")),
                  price.isFinite, price > 0,
                  let grams = packageGrams(in: title) else { continue }
            let titleWithoutWeight = title.replacingOccurrences(
                of: #"\b\d+(?:[.,]\d+)?\s*(?:kg|g)\b"#, with: "",
                options: [.regularExpression, .caseInsensitive])
            let listed = ReceiptMatcher.tokens(titleWithoutWeight)
            let expandedListed = ReceiptMatcher.expanded(listed)
            // Both directions must match. This excludes ordinary potatoes and flavored products.
            guard wanted.isSubset(of: expandedListed), listed.isSubset(of: expandedWanted) else { continue }
            let per100g = price / grams * 100
            guard per100g.isFinite, per100g > 0 else { continue }
            return RetailPriceQuote(per100g: per100g, productName: title, sourceURL: url)
        }
        return nil
    }

    private static func packageGrams(in title: String) -> Double? {
        guard let range = title.range(of: #"\b\d+(?:[.,]\d+)?\s*(?:kg|g)\b"#,
                                      options: [.regularExpression, .caseInsensitive]) else { return nil }
        let match = String(title[range]).lowercased().replacingOccurrences(of: " ", with: "")
        let kilograms = match.hasSuffix("kg")
        let number = kilograms ? String(match.dropLast(2)) : String(match.dropLast())
        guard let amount = Double(number.replacingOccurrences(of: ",", with: ".")), amount > 0 else { return nil }
        return amount * (kilograms ? 1000 : 1)
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
