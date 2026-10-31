import CloudKit
import XCTest
@testable import Daywell

@MainActor
final class CommunityModerationTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "CommunityModerationTests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func post(_ name: String, by author: String?) -> CommunityPost {
        CommunityPost(id: CKRecord.ID(recordName: name), authorName: "Member", authorID: author, text: name)
    }

    func testEveryPostIsVisibleBeforeAnyModeration() {
        let cloud = CommunityCloud(defaults: defaults)
        let posts = [post("a", by: "u1"), post("b", by: nil)]
        XCTAssertEqual(cloud.visible(posts).map(\.id.recordName), ["a", "b"])
    }

    func testAHiddenPostStaysHiddenAfterRelaunch() {
        CommunityCloud(defaults: defaults).hide(post("a", by: "u1"))
        let relaunched = CommunityCloud(defaults: defaults)
        let shown = relaunched.visible([post("a", by: "u1"), post("b", by: "u1")])
        XCTAssertEqual(shown.map(\.id.recordName), ["b"])
    }

    func testBlockingHidesEveryPostByThatAuthorOnly() {
        let cloud = CommunityCloud(defaults: defaults)
        cloud.block(post("a", by: "u1"))
        let shown = cloud.visible([post("b", by: "u1"), post("c", by: "u2"), post("d", by: nil)])
        XCTAssertEqual(shown.map(\.id.recordName), ["c", "d"])
        XCTAssertEqual(CommunityCloud(defaults: defaults).blockedAuthors, ["u1"])
    }

    func testAPostWithoutAnAuthorCannotBeBlocked() {
        let cloud = CommunityCloud(defaults: defaults)
        cloud.block(post("a", by: nil))
        XCTAssertTrue(cloud.blockedAuthors.isEmpty)
    }

    func testUnblockingEveryoneShowsTheirPostsAgain() async {
        let cloud = CommunityCloud(defaults: defaults)
        cloud.block(post("a", by: "u1"))
        await cloud.unblockEveryone()
        XCTAssertTrue(cloud.blockedAuthors.isEmpty)
        XCTAssertEqual(cloud.visible([post("b", by: "u1")]).count, 1)
        XCTAssertTrue(CommunityCloud(defaults: defaults).blockedAuthors.isEmpty)
    }
}
