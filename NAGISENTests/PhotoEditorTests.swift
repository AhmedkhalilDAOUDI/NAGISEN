import XCTest
import SwiftUI
@testable import NAGISEN

final class PhotoEditorTests: XCTestCase {
    private func image(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
            UIColor.blue.setFill(); context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        }
    }

    func testEditsNeverCropOrChangeThePhotosShape() {
        var edits = PhotoEdits()
        for tool in PhotoEdits.Tool.allCases { edits[tool] = tool.range.upperBound * 0.6 }
        for (w, h) in [(1200.0, 900.0), (900.0, 1600.0), (1000.0, 1000.0)] {
            let result = PhotoEditor.apply(edits, to: image(width: w, height: h), maxEdge: 2400)
            XCTAssertEqual(result.size.width, w, accuracy: 1)
            XCTAssertEqual(result.size.height, h, accuracy: 1)
        }
    }

    func testLargePhotosKeepTheirProportionsWhenScaledDown() {
        let result = PhotoEditor.apply(PhotoEdits(), to: image(width: 4000, height: 3000), maxEdge: 2400)
        XCTAssertEqual(result.size.width / result.size.height, 4.0 / 3.0, accuracy: 0.01)
    }

    func testTheCardTakesThePhotosShape() {
        XCTAssertEqual(CardSize.of(image(width: 900, height: 1600)).height, 640, accuracy: 0.5)
        XCTAssertEqual(CardSize.of(nil), CGSize(width: 360, height: 450))
    }

    func testSettingAToolBackToZeroForgetsIt() {
        var edits = PhotoEdits()
        edits[.contrast] = 0.4
        edits[.contrast] = 0
        XCTAssertEqual(edits, PhotoEdits())
    }

    func testQuotesFitEveryCardAndNeverRepeatBackToBack() {
        XCTAssertEqual(Quotes.all.count, 200)
        XCTAssertEqual(Set(Quotes.all.map(\.text)).count, 200, "no duplicate lines")
        for theme in Quote.Theme.allCases {
            let first = Quotes.pick(for: theme)
            XCTAssertNotEqual(Quotes.pick(for: theme, after: first), first)
        }
    }

    func testAMealCardAddsUpItsFoodsAndLetsEachMacroBeHidden() {
        let eggs = Food(name: "Eggs", serving: "1", calories: 70, protein: 6, carbs: 0.5, fat: 5)
        let bread = Food(name: "Bread", serving: "1 slice", calories: 80, protein: 3, carbs: 15, fat: 1)
        let card = ShareCards.meal(.breakfast, [DiaryEntry(food: eggs, meal: .breakfast, servings: 2, date: .now),
                                                DiaryEntry(food: bread, meal: .breakfast, servings: 1, date: .now)])
        XCTAssertEqual(card.value, "220 kcal")
        XCTAssertEqual(card.lines.map(\.0), ["15 g", "16 g", "11 g"])
        XCTAssertEqual(card.caption, "Eggs · Bread")
        XCTAssertTrue(Set(["protein", "carbs", "fat"]).isSubset(of: Set(card.fields)))
    }

    func testPinchingAPieceGrowsFromWhereItWasAndStaysInBounds() {
        XCTAssertEqual(CardLayout.resized(1.5, by: 2), 3)
        XCTAssertEqual(CardLayout.resized(1, by: 0.1), 0.4)
        XCTAssertEqual(CardLayout.resized(1.2, by: 1.5), 1.8, accuracy: 0.0001)
    }

    func testGesturesBuildOnWhereThePieceWasAndTheBinRemovesIt() {
        var draft = CardDraft()
        let bin = CGPoint(x: 180, y: 390)
        draft.touch("protein", CardTouch(move: CGSize(width: 30, height: 0), location: CGPoint(x: 50, y: 50), ended: true), trash: bin)
        draft.touch("protein", CardTouch(move: CGSize(width: 10, height: 5), pinch: 2, turn: .degrees(15), location: CGPoint(x: 60, y: 55)), trash: bin)
        XCTAssertEqual(draft.layout.offsets["protein"], CGSize(width: 40, height: 5))
        XCTAssertEqual(draft.layout.sizes["protein"], 2)
        XCTAssertEqual(draft.layout.turns["protein"], .degrees(15))
        XCTAssertEqual(draft.holding, "protein")
        draft.touch("protein", CardTouch(move: CGSize(width: 10, height: 5), location: CGPoint(x: 60, y: 55), ended: true), trash: bin)
        XCTAssertNil(draft.holding)

        draft.touch("protein", CardTouch(location: CGPoint(x: 175, y: 385)), trash: bin)
        XCTAssertTrue(draft.overTrash)
        draft.touch("protein", CardTouch(location: CGPoint(x: 175, y: 385), ended: true), trash: bin)
        XCTAssertTrue(draft.hidden.contains("protein"), "data goes to hidden so it can come back")
        XCTAssertNil(draft.layout.offsets["protein"])
    }

    func testWordsYouTypeStayEditableAndLeaveWhenEmptiedOrBinned() {
        var draft = CardDraft()
        var words = CardText(text: "  Morning miles ")
        draft.commit(words)
        XCTAssertEqual(draft.layout.texts.map(\.text), ["Morning miles"])
        XCTAssertEqual(draft.layout.selected, words.field, "fresh words stay picked")
        draft.layout.selected = nil
        XCTAssertNil(draft.tap(words.field), "the first tap only selects")
        XCTAssertEqual(draft.tap(words.field)?.id, words.id, "a second tap opens it for typing")
        words.text = ""
        draft.commit(words)
        XCTAssertTrue(draft.layout.texts.isEmpty)

        draft.layout.quote = Quotes.pick(for: .day)
        draft.remove(CardLayout.quoteField)
        XCTAssertNil(draft.layout.quote)
        XCTAssertTrue(draft.hidden.isEmpty)
    }
}
