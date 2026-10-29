import Foundation

/// A bundled snapshot of products listed for Morocco in Open Food Facts.
/// Online Open Food Facts search remains available alongside this catalog.
enum MoroccanFoodCatalog {
    private struct Snapshot: Decodable { let foods: [Food] }

    static let foods: [Food] = {
        guard let url = Bundle.main.url(forResource: "MoroccanFoods", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return [] }
        return snapshot.foods
    }()

    static func search(_ query: String) -> [Food] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else { return [] }
        let matching = foods.filter {
            $0.name.localizedStandardContains(term) || $0.brand.localizedStandardContains(term) ||
            ($0.barcode?.contains(term) ?? false)
        }
        return Array(matching.sorted { left, right in
            let leftName = left.name.range(of: term, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
            let rightName = right.name.range(of: term, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
            if leftName != rightName { return leftName }
            let leftBrand = left.brand.range(of: term, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
            let rightBrand = right.brand.range(of: term, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
            if leftBrand != rightBrand { return leftBrand }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }.prefix(30))
    }
}

enum FoodLookupError: LocalizedError {
    case invalidBarcode
    case notFound
    case missingNutrition
    case serverUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidBarcode: "Enter a valid barcode number."
        case .notFound: "This barcode is not in Open Food Facts. You can add the food manually."
        case .missingNutrition: "This product has no usable nutrition data. You can add it manually."
        case .serverUnavailable: "Food search is unavailable right now. Check your connection and try again."
        }
    }
}

struct OpenFoodFactsService {
    private let userAgent = "NAGISEN/0.15.0 (iOS prototype; com.daywell.nutrition)"

    func search(_ query: String) async throws -> [Food] {
        guard var url = URLComponents(string: "https://search.openfoodfacts.org/search") else {
            throw FoodLookupError.serverUnavailable
        }
        url.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page_size", value: "24"),
            URLQueryItem(name: "langs", value: "en,fr")
        ]
        guard let requestURL = url.url else { throw FoodLookupError.serverUnavailable }
        let data = try await fetch(requestURL)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        return response.hits.compactMap { $0.asFood() }
    }

    func lookup(barcode: String) async throws -> Food {
        let cleaned = barcode.filter(\.isNumber)
        guard (8...14).contains(cleaned.count) else { throw FoodLookupError.invalidBarcode }
        guard var url = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(cleaned).json") else {
            throw FoodLookupError.serverUnavailable
        }
        url.queryItems = [URLQueryItem(name: "fields", value: "code,product_name,brands,serving_size,nutriments")]
        guard let requestURL = url.url else { throw FoodLookupError.serverUnavailable }
        let data = try await fetch(requestURL)
        let response = try JSONDecoder().decode(ProductResponse.self, from: data)
        guard response.status == 1, let product = response.product else { throw FoodLookupError.notFound }
        guard let food = product.asFood() else { throw FoodLookupError.missingNutrition }
        return food
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw FoodLookupError.serverUnavailable
            }
            return data
        } catch {
            throw FoodLookupError.serverUnavailable
        }
    }
}

private struct SearchResponse: Decodable {
    var hits: [OpenFoodFactsProduct]
}

private struct ProductResponse: Decodable {
    var status: Int?
    var product: OpenFoodFactsProduct?
}

private struct BrandField: Decodable {
    let text: String

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let string = try? value.decode(String.self) {
            text = string
        } else {
            text = (try value.decode([String].self)).joined(separator: ", ")
        }
    }
}

private struct OpenFoodFactsProduct: Decodable {
    var code: String?
    var name: String?
    var brands: BrandField?
    var servingSize: String?
    var nutriments: Nutriments?

    enum CodingKeys: String, CodingKey {
        case code, brands, nutriments
        case name = "product_name"
        case servingSize = "serving_size"
    }

    func asFood() -> Food? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
              let nutrient = nutriments,
              let kcal = nutrient.calories, kcal.isFinite, kcal >= 0, kcal < 10000 else { return nil }
        let servingText = servingSize?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let grams = Food(name: name, serving: servingText, calories: 0,
                         protein: 0, carbs: 0, fat: 0).gramsPerServing
        let serving = grams == nil ? "100 g" : servingText
        let factor = (grams ?? 100) / 100
        guard factor > 0, factor <= 100 else { return nil }
        let missing = [("protein", nutrient.protein), ("carbs", nutrient.carbs), ("fat", nutrient.fat)]
            .compactMap { $0.1 == nil ? $0.0 : nil }
        return Food(name: name, brand: brands?.text ?? "", serving: serving,
                    calories: Int((kcal * factor).rounded()),
                    protein: max(0, (nutrient.protein ?? 0) * factor),
                    carbs: max(0, (nutrient.carbs ?? 0) * factor),
                    fat: max(0, (nutrient.fat ?? 0) * factor),
                    fiber: nutrient.fiber.map { max(0, $0 * factor) },
                    sodium: nutrient.sodium.map { max(0, $0 * factor) },
                    barcode: code, source: "Open Food Facts", missingMacros: missing)
    }
}

private struct Nutriments: Decodable {
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var fiber: Double?
    var sodium: Double?

    enum CodingKeys: String, CodingKey {
        case calories = "energy-kcal_100g"
        case protein = "proteins_100g"
        case carbs = "carbohydrates_100g"
        case fat = "fat_100g"
        case fiber = "fiber_100g"
        case sodium = "sodium_100g"
    }
}
