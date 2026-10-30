import XCTest
@testable import Daywell

final class CaffeineAndCostTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Africa/Casablanca")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: - Caffeine decay

    func testHalfTheCaffeineIsGoneAfterOneHalfLife() {
        let left = CaffeineMath.remaining(100, hours: 5, halfLife: 5)
        XCTAssertEqual(left, 50, accuracy: 0.001)
    }

    func testLevelHalvesEveryHalfLifeAcrossHours() {
        XCTAssertEqual(CaffeineMath.remaining(200, hours: 0, halfLife: 5), 200, accuracy: 0.001)
        XCTAssertEqual(CaffeineMath.remaining(200, hours: 10, halfLife: 5), 50, accuracy: 0.001)
        XCTAssertEqual(CaffeineMath.remaining(200, hours: 15, halfLife: 5), 25, accuracy: 0.001)
    }

    func testLevelSumsEveryDoseStillInTheBody() {
        let entries = [
            CaffeineEntry(date: date(2026, 10, 29, 8), milligrams: 100, name: "Coffee"),
            CaffeineEntry(date: date(2026, 10, 29, 13), milligrams: 60, name: "Atay")
        ]
        // 6 hours after the first and 1 hour after the second.
        let level = CaffeineMath.level(entries: entries, at: date(2026, 10, 29, 14), halfLife: 5)
        let expected = 100 * pow(0.5, 6.0 / 5.0) + 60 * pow(0.5, 1.0 / 5.0)
        XCTAssertEqual(level, expected, accuracy: 0.001)
    }

    func testADoseLoggedLaterDoesNotCountYet() {
        let entries = [CaffeineEntry(date: date(2026, 10, 29, 18), milligrams: 80, name: "Coffee")]
        let level = CaffeineMath.level(entries: entries, at: date(2026, 10, 29, 15), halfLife: 5)
        XCTAssertEqual(level, 0, accuracy: 0.001)
    }

    func testDailyTotalIgnoresOtherDays() {
        let entries = [
            CaffeineEntry(date: date(2026, 10, 28, 9), milligrams: 95, name: "Coffee"),
            CaffeineEntry(date: date(2026, 10, 29, 9), milligrams: 63, name: "Espresso"),
            CaffeineEntry(date: date(2026, 10, 29, 16), milligrams: 32, name: "Atay")
        ]
        XCTAssertEqual(CaffeineMath.total(entries: entries, on: date(2026, 10, 29), calendar: calendar), 95)
    }

    func testBedtimeLevelFallsAsTheDaysGoesOn() {
        let entries = [CaffeineEntry(date: date(2026, 10, 29, 8), milligrams: 200, name: "Coffee")]
        let bedtime = CaffeineMath.cutoff(hour: 23, on: date(2026, 10, 29), calendar: calendar)
        let level = CaffeineMath.level(entries: entries, at: bedtime, halfLife: 5)
        // 15 hours after a 200 mg dose: 200 * 0.5^3 = 25 mg.
        XCTAssertEqual(level, 25, accuracy: 0.001)
    }

    func testCurveEndsWhereTheDayEnds() {
        let entries = [CaffeineEntry(date: date(2026, 10, 29, 8), milligrams: 100, name: "Coffee")]
        let start = date(2026, 10, 29, 8)
        let end = date(2026, 10, 29, 23)
        let points = CaffeineMath.curve(entries: entries, start: start, end: end, halfLife: 5)
        XCTAssertGreaterThan(points.count, 50)
        XCTAssertEqual(points.first?.date, start)
        XCTAssertEqual(points.last?.date, end)
        XCTAssertEqual(points.first?.level ?? 0, 100, accuracy: 0.001)
        // 15 hours is three half-lives, so a 100 mg dose is down to 12.5 mg.
        XCTAssertEqual(points.last?.level ?? 0, 12.5, accuracy: 0.5)
        // The curve only ever comes down.
        XCTAssertEqual(points.map(\.level), points.map(\.level).sorted(by: >))
    }

    // MARK: - Cost

    private func food(_ name: String, serving: String, protein: Double = 10) -> Food {
        Food(name: name, serving: serving, calories: 200, protein: protein, carbs: 20, fat: 5)
    }

    private func entry(_ food: Food, servings: Double, on day: Date) -> DiaryEntry {
        DiaryEntry(food: food, meal: .lunch, servings: servings, date: day)
    }

    func testAWeightPriceFollowsThePortion() {
        let chicken = food("Chicken breast", serving: "100 g", protein: 31)
        let price = FoodPrice(per100g: 12)
        XCTAssertEqual(FoodCost.cost(entry: entry(chicken, servings: 1, on: .now), prices: [FoodCost.key(for: chicken): price]) ?? 0,
                       12, accuracy: 0.001)
        XCTAssertEqual(FoodCost.cost(entry: entry(chicken, servings: 2.5, on: .now), prices: [FoodCost.key(for: chicken): price]) ?? 0,
                       30, accuracy: 0.001)
    }

    func testAServingPriceIsUsedWhenThereIsNoWeight() {
        let coffee = food("Café noir", serving: "1 cup", protein: 0)
        let price = FoodPrice(perServing: 4)
        let cost = FoodCost.cost(entry: entry(coffee, servings: 2, on: .now),
                                 prices: [FoodCost.key(for: coffee): price])
        XCTAssertEqual(cost ?? 0, 8, accuracy: 0.001)
    }

    func testAnUnpricedFoodCostsNothingRatherThanZero() {
        let eggs = food("Eggs", serving: "2 eggs")
        XCTAssertNil(FoodCost.cost(entry: entry(eggs, servings: 1, on: .now), prices: [:]))
    }

    func testDayCostIsTheSumOfThatDaysFood() {
        let rice = food("Rice", serving: "100 g")
        let chicken = food("Chicken breast", serving: "100 g")
        let prices = [FoodCost.key(for: rice): FoodPrice(per100g: 3),
                      FoodCost.key(for: chicken): FoodPrice(per100g: 12)]
        let day = date(2026, 10, 29, 13)
        let entries = [
            entry(rice, servings: 2, on: day),
            entry(chicken, servings: 1.5, on: day),
            entry(chicken, servings: 3, on: date(2026, 10, 28, 13))
        ]
        let cost = FoodCost.dayCost(entries: entries, prices: prices, on: day, calendar: calendar)
        XCTAssertEqual(cost, 6 + 18, accuracy: 0.001)
    }

    func testCostPerGramOfProteinNeedsRealProteinAndRealMoney() {
        let chicken = food("Chicken breast", serving: "100 g", protein: 30)
        let prices = [FoodCost.key(for: chicken): FoodPrice(per100g: 12)]
        let day = date(2026, 10, 29, 13)
        let entries = [entry(chicken, servings: 1, on: day)]
        let perGram = FoodCost.costPerGramOfProtein(entries: entries, prices: prices, on: day, calendar: calendar)
        XCTAssertEqual(perGram ?? 0, 12.0 / 30.0, accuracy: 0.0001)

        let nothing = food("Lettuce", serving: "100 g", protein: 1)
        let nothingPrice = [FoodCost.key(for: nothing): FoodPrice(per100g: 2)]
        XCTAssertNil(FoodCost.costPerGramOfProtein(entries: [entry(nothing, servings: 1, on: day)],
                                                   prices: nothingPrice, on: day, calendar: calendar))
    }

    func testABoughtAmountBecomesAPrice() {
        let chicken = food("Chicken breast", serving: "100 g", protein: 31)
        let price = FoodCost.derive(amount: 1000, unit: .grams, paid: 60, food: chicken)
        XCTAssertEqual(price?.per100g ?? 0, 6, accuracy: 0.001)
        XCTAssertEqual(price?.boughtGrams ?? 0, 1000, accuracy: 0.001)
        XCTAssertEqual(price?.paid ?? 0, 60, accuracy: 0.001)
        XCTAssertEqual(price?.purchaseSummary, "1 kg for 60 MAD")
    }

    func testAServingAmountBecomesAPrice() {
        let yogurt = food("Greek yogurt", serving: "1 pot")
        let price = FoodCost.derive(amount: 10, unit: .servings, paid: 35, food: yogurt)
        XCTAssertEqual(price?.perServing ?? 0, 3.5, accuracy: 0.001)
        XCTAssertNil(price?.per100g)
        XCTAssertEqual(price?.purchaseSummary, "10 servings for 35 MAD")
    }

    func testAnEmptyAmountIsRefused() {
        let egg = food("Egg", serving: "1 large")
        XCTAssertNil(FoodCost.derive(amount: 0, unit: .grams, paid: 45, food: egg))
        XCTAssertNil(FoodCost.derive(amount: 30, unit: .grams, paid: -1, food: egg))
    }

    func testPricePerHundredGramsOfProteinRanksFoods() {
        let whey = food("Whey", serving: "100 g", protein: 80)
        let beef = food("Beef", serving: "100 g", protein: 26)
        let wheyValue = FoodCost.proteinValue(of: whey, price: FoodPrice(per100g: 90)) ?? 0
        let beefValue = FoodCost.proteinValue(of: beef, price: FoodPrice(per100g: 75)) ?? 0
        XCTAssertLessThan(wheyValue, beefValue, "whey should be the cheaper protein per gram")
    }

    func testOpenPricesUsesTheExactBarcodeAndPackageWeight() throws {
        let data = Data("""
        {"items":[
          {"product_code":"6111242100985","currency":"MAD","price":2.95,"date":"2024-07-11","price_per":null,"price_is_discounted":false,"duplicate_of":null,"product":{"product_quantity":80,"product_quantity_unit":"g"}},
          {"product_code":"other","currency":"MAD","price":1,"date":"2026-10-29","price_per":"KILOGRAM","product":null}
        ]}
        """.utf8)
        let result = try XCTUnwrap(OpenPricesService.parse(data, barcode: "6111242100985"))
        XCTAssertEqual(result.value, 2.95 / 80 * 100, accuracy: 0.001)
        XCTAssertEqual(result.date, "2024-07-11")
    }

    func testOpenPricesRejectsDifferentCurrencyDiscountAndVolume() {
        let data = Data("""
        {"items":[
          {"product_code":"12345678","currency":"EUR","price":3,"date":"2026-10-29","price_per":"KILOGRAM"},
          {"product_code":"12345678","currency":"MAD","price":3,"date":"2026-10-29","price_per":"KILOGRAM","price_is_discounted":true},
          {"product_code":"12345678","currency":"MAD","price":3,"date":"2026-10-29","price_per":"UNIT","product":{"product_quantity":1000,"product_quantity_unit":"ml"}}
        ]}
        """.utf8)
        XCTAssertNil(OpenPricesService.parse(data, barcode: "12345678"))
    }

    func testBarcodePricesDoNotLeakBetweenBrandsAndLegacyPricesStillLoad() {
        var first = food("Greek yogurt", serving: "100 g")
        first.brand = "Brand A"
        first.barcode = "6111242100985"
        var second = first
        second.brand = "Brand B"
        second.barcode = "6111242106277"
        XCTAssertNotEqual(FoodCost.key(for: first), FoodCost.key(for: second))
        let prices = [FoodCost.key(for: first): FoodPrice(per100g: 8)]
        XCTAssertNil(FoodCost.price(for: second, prices: prices))
        XCTAssertEqual(FoodCost.price(for: first, prices: prices)?.per100g, 8)
        XCTAssertEqual(FoodCost.price(for: second, prices: ["greek yogurt": FoodPrice(per100g: 6)])?.per100g, 6)
    }
}
