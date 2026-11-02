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
                draft.touch("protein", CardTouch(move: CGSize(width: 30, height: 0), location: CGPoint(x: 50, y: 50), ended: true), cardHeight: 450)
        draft.touch("protein", CardTouch(move: CGSize(width: 10, height: 5), pinch: 2, turn: .degrees(15), location: CGPoint(x: 60, y: 55)), cardHeight: 450)
        XCTAssertEqual(draft.layout.offsets["protein"], CGSize(width: 40, height: 5))
        XCTAssertEqual(draft.layout.sizes["protein"], 2)
        XCTAssertEqual(draft.layout.turns["protein"], .degrees(15))
        XCTAssertEqual(draft.holding, "protein")
        draft.touch("protein", CardTouch(move: CGSize(width: 10, height: 5), location: CGPoint(x: 60, y: 55), ended: true), cardHeight: 450)
        XCTAssertNil(draft.holding)

        draft.touch("protein", CardTouch(location: CGPoint(x: 175, y: 480)), cardHeight: 450)
        XCTAssertTrue(draft.overTrash)
        draft.touch("protein", CardTouch(location: CGPoint(x: 175, y: 480), ended: true), cardHeight: 450)
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

    func testAPinchWithoutADragResizesWithoutShowingTheBin() {
        var draft = CardDraft()
        draft.touch("Goal label", CardTouch(pinch: 1.5), cardHeight: 450)
        XCTAssertEqual(draft.layout.sizes["Goal label"], 1.5)
        XCTAssertNil(draft.holding)
        draft.touch("Goal label", CardTouch(pinch: 1.5, ended: true), cardHeight: 450)
        draft.touch("Goal label", CardTouch(pinch: 2), cardHeight: 450)
        XCTAssertEqual(draft.layout.sizes["Goal label"], 3, "a second pinch builds on the first")
    }

    func testEveryCaptionIsAPieceOfItsOwn() {
        XCTAssertEqual(CardLayout.labelField("protein"), "protein label")
        XCTAssertNotEqual(CardLayout.kickerField, CardLayout.quoteField)
    }

    func testSlightTiltsSnapLevelButRealTurnsStay() {
        XCTAssertEqual(CardDraft.straightened(.degrees(4)), .zero)
        XCTAssertEqual(CardDraft.straightened(.degrees(-358)), .zero)
        XCTAssertEqual(CardDraft.straightened(.degrees(20)), .degrees(20))
    }

    func testOnlyDroppingBelowTheCardRemovesAPiece() {
        var draft = CardDraft()
        draft.touch("water", CardTouch(move: CGSize(width: 0, height: 300), location: CGPoint(x: 180, y: 440), ended: true), cardHeight: 450)
        XCTAssertFalse(draft.hidden.contains("water"), "the card's own bottom edge is still the card")
    }

    func testNothingIsCroppedOrFilteredUnlessChosen() {
        let fresh = PhotoEdits()
        XCTAssertEqual(fresh.crop, .original)
        XCTAssertEqual(fresh.filter, .original)
        let photo = image(width: 1200, height: 900)
        XCTAssertEqual(PhotoEditor.apply(fresh, to: photo).size, CGSize(width: 1200, height: 900))
        var filtered = PhotoEdits(); filtered.filter = .noir; filtered.filterStrength = 0.4
        XCTAssertEqual(PhotoEditor.apply(filtered, to: photo).size, CGSize(width: 1200, height: 900), "a filter never changes the shape")
    }

    func testAChosenCropKeepsTheLargestFrameOfThatShape() {
        let photo = image(width: 1200, height: 900)
        var square = PhotoEdits(); square.crop = .square
        XCTAssertEqual(PhotoEditor.apply(square, to: photo).size, CGSize(width: 900, height: 900))
        var story = PhotoEdits(); story.crop = .story
        let tall = PhotoEditor.apply(story, to: photo).size
        XCTAssertEqual(tall.width / tall.height, 9.0 / 16, accuracy: 0.01)
        var turned = PhotoEdits(); turned.quarterTurns = 1
        XCTAssertEqual(PhotoEditor.apply(turned, to: photo).size, CGSize(width: 900, height: 1200))
    }

    func testTheCropFrameSlidesAndZoomsInsideThePhoto() {
        let extent = CGRect(x: 0, y: 0, width: 1200, height: 900)
        XCTAssertEqual(PhotoEditor.cropRect(in: extent, ratio: nil, zoom: 2, offset: .zero), extent, "Original keeps everything")
        XCTAssertEqual(PhotoEditor.cropRect(in: extent, ratio: 1, zoom: 1, offset: CGSize(width: 1, height: 0)).maxX, 1200)
        XCTAssertEqual(PhotoEditor.cropRect(in: extent, ratio: 1, zoom: 1, offset: CGSize(width: -5, height: 0)).minX, 0, "never past the edge")
        XCTAssertEqual(PhotoEditor.cropRect(in: extent, ratio: 1, zoom: 2, offset: .zero).width, 450)
    }

    func testAFreeCropKeepsExactlyTheFrameYouDrew() {
        var free = PhotoEdits(); free.crop = .free
        XCTAssertEqual(PhotoEditor.apply(free, to: image(width: 1200, height: 900)).size, CGSize(width: 1200, height: 900),
                       "picking Free alone cuts nothing")
        free.freeRect = CGRect(x: 0, y: 0, width: 0.5, height: 1)
        XCTAssertEqual(PhotoEditor.apply(free, to: image(width: 1200, height: 900)).size, CGSize(width: 600, height: 900))
        let extent = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertEqual(PhotoEditor.freeCropRect(in: extent, CGRect(x: 0, y: 0, width: 1, height: 0.25)),
                       CGRect(x: 0, y: 600, width: 1000, height: 200), "the top of the photo is the top of the frame")
    }

    func testTheFreeFrameStaysOnThePhotoAndNeverVanishes() {
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)
        let shrunk = PhotoEditor.adjusted(full, corner: .topLeft, by: CGSize(width: 0.3, height: 2))
        XCTAssertEqual(shrunk.minX, 0.3, accuracy: 0.0001)
        XCTAssertEqual(shrunk.height, 0.1, accuracy: 0.0001, "never smaller than a tenth")
        let half = CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
        let moved = PhotoEditor.adjusted(half, corner: nil, by: CGSize(width: 1, height: -1))
        XCTAssertEqual(moved.maxX, 1, accuracy: 0.0001)
        XCTAssertEqual(moved.minY, 0, accuracy: 0.0001)
        XCTAssertEqual(moved.size, half.size)
    }
}
