import XCTest
@testable import Daywell

final class ReceiptPriceTests: XCTestCase {

    private func food(_ name: String, serving: String, protein: Double = 10) -> Food {
        Food(name: name, serving: serving, calories: 200, protein: protein, carbs: 20, fat: 5)
    }

    // MARK: - Putting rows back together

    func testFragmentsOnTheSamePrintedLineAreJoined() {
        // Real receipts print the product and its price as separate observations.
        let fragments = [
            ReceiptRows.Fragment(text: "90,00", x: 0.72, y: 0.61),
            ReceiptRows.Fragment(text: "POULET BLANC 1,250 KG", x: 0.05, y: 0.60),
            ReceiptRows.Fragment(text: "12,50", x: 0.75, y: 0.52),
            ReceiptRows.Fragment(text: "LAIT CENTRAL 1L", x: 0.05, y: 0.51)
        ]
        let rows = ReceiptRows.join(fragments)
        XCTAssertEqual(rows, ["POULET BLANC 1,250 KG  90,00", "LAIT CENTRAL 1L  12,50"])
    }

    // MARK: - Reading a row

    func testAWeighedRowCarriesItsWeightAndPrice() throws {
        let line = try XCTUnwrap(ReceiptParser.parseLine("POULET BLANC 1,250 KG  90,00"))
        XCTAssertEqual(line.name, "POULET BLANC")
        XCTAssertEqual(line.grams ?? 0, 1250, accuracy: 0.1)
        XCTAssertEqual(line.total, 90, accuracy: 0.001)

        let chicken = food("Chicken breast, cooked", serving: "100 g")
        let price = try XCTUnwrap(ReceiptMatcher.price(for: line, food: chicken))
        XCTAssertEqual(price.per100g ?? 0, 7.2, accuracy: 0.001)
    }

    func testAVolumeRowIsTreatedAsWeight() throws {
        let line = try XCTUnwrap(ReceiptParser.parseLine("LAIT CENTRAL 1L  12,50"))
        XCTAssertEqual(line.grams ?? 0, 1000, accuracy: 0.1)
        let milk = food("Milk, semi-skimmed", serving: "100 ml")
        let price = try XCTUnwrap(ReceiptMatcher.price(for: line, food: milk))
        XCTAssertEqual(price.per100g ?? 0, 1.25, accuracy: 0.001)
    }

    func testATwoTimesRowUsesTheTotalOnTheLine() throws {
        let line = try XCTUnwrap(ReceiptParser.parseLine("2 X YAOURT NATURE 3,50  7,00"))
        XCTAssertEqual(line.quantity ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(line.total, 7, accuracy: 0.001)
        let yogurt = food("Greek yogurt, plain", serving: "1 pot")
        let price = try XCTUnwrap(ReceiptMatcher.price(for: line, food: yogurt))
        XCTAssertEqual(price.perServing ?? 0, 3.5, accuracy: 0.001)
    }

    func testAPackCountDividesThePrice() throws {
        let line = try XCTUnwrap(ReceiptParser.parseLine("OEUF 30  45,00"))
        XCTAssertEqual(line.quantity ?? 0, 30, accuracy: 0.001)
        let egg = food("Egg", serving: "1 large")
        let price = try XCTUnwrap(ReceiptMatcher.price(for: line, food: egg))
        XCTAssertEqual(price.perServing ?? 0, 1.5, accuracy: 0.001)
    }

    func testThousandsInAPriceSurvive() throws {
        let line = try XCTUnwrap(ReceiptParser.parseLine("HUILE D OLIVE 5 L  1 234,50"))
        XCTAssertEqual(line.total, 1234.50, accuracy: 0.01)
    }

    func testTheShopsOwnLinesAreNotProducts() {
        XCTAssertNil(ReceiptParser.parseLine("TOTAL A PAYER 283,40"))
        XCTAssertNil(ReceiptParser.parseLine("TVA 20% 47,23"))
        XCTAssertNil(ReceiptParser.parseLine("RENDU 16,60"))
        XCTAssertNil(ReceiptParser.parseLine("MERCI DE VOTRE VISITE"))
    }

    func testAProductNamedLikeAccountingSurvives() throws {
        // "DATTES" must not be mistaken for the word "DATE".
        let line = try XCTUnwrap(ReceiptParser.parseLine("DATTES 0,500 KG  39,90"))
        XCTAssertEqual(line.name, "DATTES")
    }

    // MARK: - Matching

    func testTheRightFoodWinsTheMatch() throws {
        let line = try XCTUnwrap(ReceiptParser.parseLine("POULET BLANC 1,250 KG  90,00"))
        let foods = [food("Chicken breast, cooked", serving: "100 g"),
                     food("Egg", serving: "1 large"),
                     food("Whole wheat bread", serving: "1 slice")]
        let best = try XCTUnwrap(ReceiptMatcher.candidates(for: line, in: foods).first)
        XCTAssertEqual(best.food.name, "Chicken breast, cooked")
        XCTAssertGreaterThan(best.score, 0.5)
    }

    func testAnUnrelatedRowFindsNothing() {
        let line = ReceiptParser.parseLine("PILES AA 4  25,00")!
        let foods = [food("Chicken breast, cooked", serving: "100 g")]
        XCTAssertTrue(ReceiptMatcher.candidates(for: line, in: foods).isEmpty)
    }

    // MARK: - Assistant price lookup

    func testTheAssistantAnswerIsReadEvenWhenItIsWrappedInProse() {
        let answer = """
        Sure — here is what it usually costs:
        ```json
        {"per100g": 12.5, "perServing": null, "low": 9, "high": 16, "note": "Around 12-16 MAD at supermarkets."}
        ```
        """
        let suggestion = DeepSeekPrice.parse(answer)
        XCTAssertEqual(suggestion?.per100g, 12.5)
        XCTAssertNil(suggestion?.perServing)
        XCTAssertEqual(suggestion?.low, 9)
        XCTAssertEqual(suggestion?.high, 16)
        XCTAssertEqual(suggestion?.value(perHundredGrams: true), 12.5)
        XCTAssertNil(suggestion?.value(perHundredGrams: false))
    }

    func testAnAnswerWithNoPricesIsRejected() {
        XCTAssertNil(DeepSeekPrice.parse("I do not know."))
        XCTAssertNil(DeepSeekPrice.parse("{\"note\": \"no idea\"}"))
    }

    func testNumbersArrivingAsTextStillParse() {
        let suggestion = DeepSeekPrice.parse("{\"perServing\": \"3,50\", \"low\": 3, \"high\": 5}")
        XCTAssertEqual(suggestion?.perServing, 3.5)
    }

    func testAssistantServingPriceCanBeConvertedToTheRequestedWeightUnit() throws {
        let suggestion = try XCTUnwrap(DeepSeekPrice.parse(
            "{\"per100g\":null,\"perServing\":8,\"low\":6,\"high\":10}"))
        XCTAssertEqual(suggestion.value(perHundredGrams: true, gramsPerServing: 200) ?? 0,
                       4, accuracy: 0.001)
        XCTAssertNil(suggestion.value(perHundredGrams: true, gramsPerServing: nil))
    }

    func testPriceLookupErrorsExplainTheActualProblem() {
        XCTAssertTrue(PriceLookupError.http(402).localizedDescription.contains("credit"))
        XCTAssertTrue(PriceLookupError.noEstimate.localizedDescription.contains("estimate"))
        XCTAssertTrue(PriceLookupError.unitMismatch.localizedDescription.contains("unit"))
    }

    func testRetailerPriceMatchesSweetPotatoAndConvertsKilograms() throws {
        let response = """
        {"resources":{"results":{"products":[
          {"title":"Pomme de Terre Rouge 1Kg","price":"8.50","url":"/products/red-potato"},
          {"title":"Patate Douce 1 kg","price":"13.10","url":"/products/patate-douce-1-kg"}
        ]}}}
        """.data(using: .utf8)!
        let quote = try XCTUnwrap(RetailPriceService.parse(response, food: food("Sweet potato", serving: "100 g")))
        XCTAssertEqual(quote.per100g, 1.31, accuracy: 0.001)
        XCTAssertEqual(quote.sourceURL.host, "www.mymarket.ma")
    }

    func testRetailerPriceRejectsDifferentProductAndMissingWeight() {
        let response = """
        {"resources":{"results":{"products":[
          {"title":"Pomme de Terre Rouge 1Kg","price":"8.50","url":"/products/red-potato"},
          {"title":"Patate Douce","price":"13.10","url":"/products/patate-douce"}
        ]}}}
        """.data(using: .utf8)!
        XCTAssertNil(RetailPriceService.parse(response, food: food("Sweet potato", serving: "100 g")))
    }

    func testAWeightFoodWithNoPrintedWeightGetsNoPrice() throws {
        let line = try XCTUnwrap(ReceiptParser.parseLine("RIZ 45,00"))
        let rice = food("White rice", serving: "100 g")
        XCTAssertNil(ReceiptMatcher.price(for: line, food: rice), "a weight price cannot be invented")
    }
}
