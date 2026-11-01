import XCTest
@testable import Daywell

final class RestGameTests: XCTestCase {
    private func play(seed: UInt64, follow: Bool) -> EmberGame {
        var game = EmberGame(seed: seed)
        while !game.isOver {
            // A perfect player sits in the gap of the next line still above the ember.
            if follow, let next = game.veils.filter({ !$0.resolved && $0.y < EmberGame.emberY }).max(by: { $0.y < $1.y }) {
                game.x = next.gapCenter
            }
            game.step(1.0 / 60)
        }
        return game
    }

    func testARestLastsExactlyThreeMinutesAndThenStops() {
        var game = play(seed: 7, follow: false)
        XCTAssertEqual(game.remaining, 0)
        let score = game.score
        game.step(1)
        XCTAssertEqual(game.score, score, "nothing moves after the rest is over")
    }

    func testThreadingTheGapsScoresAndBuildsAStreak() {
        let game = play(seed: 7, follow: true)
        XCTAssertGreaterThan(game.bestStreak, 50, "a perfect run passes every line")
        XCTAssertGreaterThan(game.score, game.bestStreak)
    }

    func testHittingALineBreaksTheStreakButNeverEndsTheGame() {
        var game = EmberGame(seed: 3)
        game.x = 0.0
        for _ in 0..<(60 * 20) { game.step(1.0 / 60) }
        XCTAssertFalse(game.isOver)
        XCTAssertLessThan(game.bestStreak, 3, "sitting at the edge mostly hits the lines")
        XCTAssertGreaterThan(game.remaining, 150)
    }

    func testLongPausesAreCappedPerStep() {
        var game = EmberGame(seed: 1)
        game.step(30)
        XCTAssertEqual(game.elapsed, 0.05, accuracy: 0.0001)
    }
}
