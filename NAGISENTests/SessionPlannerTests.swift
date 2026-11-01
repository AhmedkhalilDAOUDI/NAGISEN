import XCTest
@testable import NAGISEN

final class SessionPlannerTests: XCTestCase {

    func testEverySessionAddsUpAndIsWellFormed() {
        var rng = SystemRandomNumberGenerator()
        for type in SessionType.allCases {
            for minutes in SessionPlanner.lengths {
                for _ in 0..<20 {
                    let plan = SessionPlanner.make(type, minutes: minutes, using: &rng)
                    XCTAssertEqual(plan.blocks.map(\.minutes).reduce(0, +), minutes, "\(type) \(minutes)")
                    XCTAssertEqual(plan.blocks.first?.title, "Warm-up")
                    XCTAssertEqual(plan.blocks.last?.title, "Cool-down")
                    XCTAssertEqual(plan.blocks.contains { $0.title == "Finisher" }, minutes >= 45)
                    let main = plan.blocks.first { $0.title == "Main" }
                    XCTAssertFalse(main?.moves.isEmpty ?? true, "\(type) \(minutes)")
                    for block in plan.blocks {
                        XCTAssertEqual(Set(block.moves.map(\.name)).count, block.moves.count, "repeat in \(type) \(block.title)")
                        XCTAssertTrue(block.moves.allSatisfy { !$0.dose.isEmpty })
                    }
                }
            }
        }
    }

    func testLongerSessionsGetMoreWork() {
        var rng = SystemRandomNumberGenerator()
        for type in [SessionType.strength, .bodybuilding, .boxing] {
            let short = SessionPlanner.make(type, minutes: 30, using: &rng).blocks.first { $0.title == "Main" }!
            let long = SessionPlanner.make(type, minutes: 60, using: &rng).blocks.first { $0.title == "Main" }!
            XCTAssertGreaterThan(long.moves.count, short.moves.count, "\(type)")
        }
    }

    func testBodybuildingKeepsTheChosenFocus() {
        var rng = SystemRandomNumberGenerator()
        let plan = SessionPlanner.make(.bodybuilding, minutes: 45, focus: "Back & arms", using: &rng)
        let backAndArms = BodybuildingExerciseCatalog.groups.first { $0.0 == "Back & arms" }!.1
        XCTAssertEqual(plan.focus, "Back & arms")
        XCTAssertTrue(plan.blocks.first { $0.title == "Main" }!.moves.allSatisfy { backAndArms.contains($0.name) })
    }
}
