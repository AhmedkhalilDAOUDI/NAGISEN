import XCTest
@testable import NAGISEN

final class PhotoEditorTests: XCTestCase {
    private func image(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
            UIColor.blue.setFill(); context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        }
    }

    func testTheResultAlwaysFitsTheCard() {
        let rendered = PhotoEditor.render(PhotoEdits(), from: image(width: 4000, height: 3000))
        XCTAssertEqual(rendered.size, PhotoEditor.cardSize)
    }

    func testAQuarterTurnSwapsWidthAndHeight() {
        var edits = PhotoEdits(); edits.quarterTurns = 1
        let turned = PhotoEditor.apply(edits, to: image(width: 400, height: 200), maxEdge: 400)
        XCTAssertEqual(turned.size.width, 200, accuracy: 1)
        XCTAssertEqual(turned.size.height, 400, accuracy: 1)
    }

    func testThePhotoCanNeverSlidePastTheCardEdge() {
        var edits = PhotoEdits(); edits.offset = CGSize(width: 5, height: -5); edits.zoom = 1.5
        let card = CGSize(width: 1080, height: 1350)
        let frame = PhotoEditor.frame(for: CGSize(width: 3000, height: 3000), in: card, edits: edits)
        XCTAssertLessThanOrEqual(frame.minX, 0)
        XCTAssertGreaterThanOrEqual(frame.maxX, card.width)
        XCTAssertLessThanOrEqual(frame.minY, 0)
        XCTAssertGreaterThanOrEqual(frame.maxY, card.height)
    }

    func testEveryFilterAndToolProducesAnImage() {
        let source = image(width: 300, height: 300)
        for filter in PhotoEdits.Filter.allCases {
            var edits = PhotoEdits(); edits.filter = filter
            for tool in PhotoEdits.Tool.allCases { edits[tool] = tool.range.upperBound * 0.5 }
            XCTAssertGreaterThan(PhotoEditor.apply(edits, to: source).size.width, 0, filter.name)
        }
    }

    func testSettingAToolBackToZeroForgetsIt() {
        var edits = PhotoEdits()
        edits[.contrast] = 0.4
        edits[.contrast] = 0
        XCTAssertEqual(edits, PhotoEdits())
    }
}
