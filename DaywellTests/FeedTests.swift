import Supabase
import UIKit
import XCTest
@testable import Daywell

final class FeedTests: XCTestCase {

    // MARK: - Usernames

    func testUsernamesFollowTheDatabaseRule() {
        XCTAssertTrue(FeedRules.isValidUsername("khalil"))
        XCTAssertTrue(FeedRules.isValidUsername("run_2026"))
        XCTAssertFalse(FeedRules.isValidUsername("ab"), "too short")
        XCTAssertFalse(FeedRules.isValidUsername(String(repeating: "a", count: 21)), "too long")
        XCTAssertFalse(FeedRules.isValidUsername("Khalil"), "uppercase")
        XCTAssertFalse(FeedRules.isValidUsername("kha lil"), "space")
        XCTAssertFalse(FeedRules.isValidUsername("khalil!"), "symbol")
        XCTAssertFalse(FeedRules.isValidUsername("nagisén"), "accent")
    }

    func testUsernamesAreTrimmedAndLowercasedBeforeChecking() {
        XCTAssertEqual(FeedRules.normalizedUsername("  Khalil_D "), "khalil_d")
    }

    func testTheMediaFolderMatchesTheLowercaseIDTheStoragePolicyChecks() {
        let id = UUID(uuidString: "1B9D6BCD-BBFD-4B2D-9B5D-AB8DFBBD4BED")!
        XCTAssertEqual(FeedRules.mediaFolder(for: id), "1b9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4bed")
    }

    // MARK: - Decoding rows

    private func decode(_ json: String) throws -> FeedPost {
        try PostgrestClient.Configuration.jsonDecoder.decode(FeedPost.self, from: Data(json.utf8))
    }

    func testAPhotoPostRowDecodesWithItsAuthor() throws {
        let post = try decode("""
        {"id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d", "author_id": "1b9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4bed",
         "body": "Leg day", "media_path": "1b9d6bcd/abc.jpg", "media_kind": "photo",
         "created_at": "2026-10-31T09:15:00.123456+00:00", "profiles": {"username": "khalil"}}
        """)
        XCTAssertEqual(post.body, "Leg day")
        XCTAssertEqual(post.mediaKind, .photo)
        XCTAssertEqual(post.mediaPath, "1b9d6bcd/abc.jpg")
        XCTAssertEqual(post.username, "khalil")
    }

    func testATextPostRowHasNoMedia() throws {
        let post = try decode("""
        {"id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d", "author_id": "1b9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4bed",
         "body": "Rest day", "media_path": null, "media_kind": null,
         "created_at": "2026-10-31T09:15:00+00:00", "profiles": {"username": "khalil"}}
        """)
        XCTAssertNil(post.mediaKind)
        XCTAssertNil(post.mediaPath)
    }

    func testAMissingAuthorFallsBackToMember() throws {
        let post = try decode("""
        {"id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d", "author_id": "1b9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4bed",
         "body": "", "media_path": "x/y.mp4", "media_kind": "video",
         "created_at": "2026-10-31T09:15:00+00:00", "profiles": null}
        """)
        XCTAssertEqual(post.username, "member")
        XCTAssertEqual(post.mediaKind, .video)
    }

    func testAPostCarriesItsCommentCount() throws {
        let post = try decode("""
        {"id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d", "author_id": "1b9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4bed",
         "body": "Leg day", "media_path": null, "media_kind": null,
         "created_at": "2026-10-31T09:15:00+00:00", "profiles": {"username": "khalil"},
         "comments": [{"count": 3}]}
        """)
        XCTAssertEqual(post.commentCount, 3)
    }

    func testAPostWithoutCountShowsNoComments() throws {
        let post = try decode("""
        {"id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d", "author_id": "1b9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4bed",
         "body": "Rest day", "created_at": "2026-10-31T09:15:00+00:00", "profiles": {"username": "khalil"}}
        """)
        XCTAssertEqual(post.commentCount, 0)
    }

    func testACommentRowDecodesWithItsAuthor() throws {
        let comment = try PostgrestClient.Configuration.jsonDecoder.decode(FeedComment.self, from: Data("""
        {"id": "3f2504e0-4f89-41d3-9a0c-0305e82c3301", "post_id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
         "author_id": "1b9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4bed", "body": "Strong work",
         "created_at": "2026-10-31T10:00:00.5+00:00", "profiles": {"username": "sara_runs"}}
        """.utf8))
        XCTAssertEqual(comment.body, "Strong work")
        XCTAssertEqual(comment.username, "sara_runs")
        XCTAssertEqual(comment.postID, UUID(uuidString: "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d"))
    }

    func testAPostCarriesItsAuthorsPictureBorderAndBio() throws {
        let post = try decode("""
        {"id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d", "author_id": "1b9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4bed",
         "body": "Leg day", "created_at": "2026-10-31T09:15:00+00:00",
         "profiles": {"username": "khalil", "avatar_path": "1b9d6bcd/avatar-x.jpg", "border_tier": 5, "bio": "Lifting slowly"}}
        """)
        XCTAssertEqual(post.author.avatarPath, "1b9d6bcd/avatar-x.jpg")
        XCTAssertEqual(post.author.borderTier, .silver)
        XCTAssertEqual(post.author.bio, "Lifting slowly")
        XCTAssertEqual(post.author.id, post.authorID)
    }

    func testAnUnknownBorderFromTheServerShowsNoBorder() throws {
        let post = try decode("""
        {"id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d", "author_id": "1b9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4bed",
         "body": "x", "created_at": "2026-10-31T09:15:00+00:00",
         "profiles": {"username": "khalil", "avatar_path": null, "border_tier": 40, "bio": null}}
        """)
        XCTAssertEqual(post.author.borderTier, .none)
        XCTAssertEqual(post.author.bio, "")
    }

    func testAGrantedBorderIsReadWithTheProfile() throws {
        let post = try decode("""
        {"id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d", "author_id": "1b9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4bed",
         "body": "x", "created_at": "2026-10-31T09:15:00+00:00",
         "profiles": {"username": "khalil", "avatar_path": null, "border_tier": 2, "bio": "", "special_border": "enji"}}
        """)
        XCTAssertEqual(post.author.special, .enji)
        XCTAssertEqual(post.author.borderTier, .hinoki, "the earned border is still known")
    }

    func testAnUnknownGrantedBorderIsIgnored() throws {
        let post = try decode("""
        {"id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d", "author_id": "1b9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4bed",
         "body": "x", "created_at": "2026-10-31T09:15:00+00:00",
         "profiles": {"username": "someone", "special_border": "rainbow"}}
        """)
        XCTAssertNil(post.author.special)
    }

    func testTheAppreciationCountComesWithThePost() throws {
        let post = try decode("""
        {"id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d", "author_id": "1b9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4bed",
         "body": "Leg day", "created_at": "2026-10-31T09:15:00+00:00", "profiles": {"username": "khalil"},
         "comments": [{"count": 2}], "appreciations": [{"count": 5}]}
        """)
        XCTAssertEqual(post.appreciationCount, 5)
        XCTAssertEqual(post.commentCount, 2)
    }

    // MARK: - Media limits

    func testVideosUpToAMinuteAreAccepted() throws {
        XCTAssertNoThrow(try PostMedia.checkDuration(30))
        XCTAssertNoThrow(try PostMedia.checkDuration(60.3))
        XCTAssertThrowsError(try PostMedia.checkDuration(75)) { error in
            XCTAssertEqual(error as? PostMediaError, .videoTooLong(seconds: 75))
        }
    }

    func testFilesOverFiftyMegabytesAreRefused() {
        XCTAssertNoThrow(try PostMedia.checkSize(50 * 1024 * 1024))
        XCTAssertThrowsError(try PostMedia.checkSize(50 * 1024 * 1024 + 1))
    }

    func testLargePhotosShrinkToTheLongEdgeLimit() {
        XCTAssertEqual(PostMedia.scaledSize(CGSize(width: 4032, height: 3024)), CGSize(width: 2048, height: 1536))
        XCTAssertEqual(PostMedia.scaledSize(CGSize(width: 3024, height: 4032)), CGSize(width: 1536, height: 2048))
    }

    func testSmallPhotosKeepTheirSize() {
        XCTAssertEqual(PostMedia.scaledSize(CGSize(width: 1200, height: 800)), CGSize(width: 1200, height: 800))
    }

    func testAPhotoBecomesAJPEGFileWithinTheLimit() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1000)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3000, height: 1000))
        }
        let attachment = try PostMedia.photo(from: try XCTUnwrap(image.pngData()))
        defer { try? FileManager.default.removeItem(at: attachment.fileURL) }
        XCTAssertEqual(attachment.kind, .photo)
        XCTAssertEqual(attachment.contentType, "image/jpeg")
        let saved = try XCTUnwrap(UIImage(contentsOfFile: attachment.fileURL.path))
        XCTAssertEqual(max(saved.size.width, saved.size.height), 2048)
    }

    func testAvatarsAreTheCenteredSquare() {
        XCTAssertEqual(PostMedia.centerSquare(of: CGSize(width: 4000, height: 3000)),
                       CGRect(x: 500, y: 0, width: 3000, height: 3000))
        XCTAssertEqual(PostMedia.centerSquare(of: CGSize(width: 900, height: 1600)),
                       CGRect(x: 0, y: 350, width: 900, height: 900))
    }

    func testAnAvatarIsA512PixelSquareJPEG() throws {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
        }
        let jpeg = try PostMedia.avatar(from: try XCTUnwrap(photo.pngData()))
        let avatar = try XCTUnwrap(UIImage(data: jpeg))
        XCTAssertEqual(avatar.size.width * avatar.scale, 512)
        XCTAssertEqual(avatar.size.height * avatar.scale, 512)
    }

    func testAnUnreadableFileIsReportedNotGuessed() {
        XCTAssertThrowsError(try PostMedia.photo(from: Data("not an image".utf8))) { error in
            XCTAssertEqual(error as? PostMediaError, .unreadable)
        }
    }

    // MARK: - Configuration

    @MainActor
    func testAMissingSupabaseConfigLeavesFeedNotConfigured() {
        // The test bundle has no SupabaseURL key, like a build without Config/Secrets.xcconfig.
        XCTAssertEqual(FeedService(bundle: Bundle(for: FeedTests.self)).state, .notConfigured)
    }
}
