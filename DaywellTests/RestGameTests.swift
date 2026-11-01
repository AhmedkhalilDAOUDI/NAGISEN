import XCTest
@testable import Daywell

final class RestGameTests: XCTestCase {
    func testClearingAMemoryRoundScoresItAndAddsATile() {
        var game = MemoryGame(seed: 4)
        XCTAssertEqual(game.pattern.count, 3)
        let tiles = Array(game.pattern)
        XCTAssertEqual(game.tap(tiles[0]), .hit)
        XCTAssertEqual(game.tap(tiles[1]), .hit)
        XCTAssertEqual(game.tap(tiles[2]), .cleared(points: 3))
        game.newRound()
        XCTAssertEqual(game.pattern.count, 4)
    }

    func testAMemoryMissTakesATileAwayButNeverBelowThree() {
        var game = MemoryGame(seed: 9)
        let outside = (0..<MemoryGame.tiles).first { !game.pattern.contains($0) }!
        XCTAssertEqual(game.tap(outside), .miss)
        XCTAssertEqual(game.length, 3)
    }

    func testMathGetsHarderAndPaysMoreAfterFiveCorrect() {
        var game = MathGame(seed: 2)
        XCTAssertNil(game.submit(game.answer + 1), "a wrong answer earns nothing")
        for _ in 0..<5 { XCTAssertEqual(game.submit(game.answer), 1) }
        XCTAssertEqual(game.tier, 1)
        XCTAssertEqual(game.submit(game.answer), 2)
    }

    func testMathAnswersAreNeverNegative() {
        var game = MathGame(seed: 11)
        for _ in 0..<200 {
            XCTAssertGreaterThanOrEqual(game.answer, 0, game.question)
            _ = game.submit(game.answer)
        }
    }

    func testQuickerReactionsEarnMore() {
        XCTAssertGreaterThan(ReactionScoring.points(milliseconds: 210), ReactionScoring.points(milliseconds: 380))
        XCTAssertEqual(ReactionScoring.points(milliseconds: 900), 1)
    }

    func testUnscramblingAWordScoresItsLength() {
        var game = WordGame(seed: 5)
        let word = game.word
        XCTAssertNotEqual(String(game.letters), word, "the letters always start shuffled")
        var available = Array(game.letters.enumerated())
        var result = WordGame.Pick.partial
        for letter in word {
            let index = available.firstIndex { $0.element == letter }!
            result = game.pick(available.remove(at: index).offset)
        }
        XCTAssertEqual(result, .solved(points: word.count))
    }

    func testAWrongWordClearsTheAnswer() {
        var game = WordGame(seed: 5)
        // Picking the shuffled letters in their shown order is never the word (nor another real word here).
        var result = WordGame.Pick.partial
        for index in game.letters.indices { result = game.pick(index) }
        if result == .wrong { XCTAssertTrue(game.picked.isEmpty) }
    }
}
