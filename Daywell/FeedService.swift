import Foundation
import Supabase

/// A member as others see them: name, picture, earned border and bio.
struct FeedMember: Identifiable, Equatable {
    let id: UUID
    let username: String
    let avatarPath: String?
    let borderTier: BorderTier
    let bio: String
    /// A hand-granted border shown instead of the earned one.
    var special: SpecialBorder? = nil
}

/// The `profiles(...)` part of a post or comment row.
struct ProfileJoin: Decodable {
    let username: String
    let avatar_path: String?
    let border_tier: Int?
    let bio: String?
    let special_border: String?

    func member(_ id: UUID) -> FeedMember {
        FeedMember(id: id, username: username, avatarPath: avatar_path,
                   borderTier: BorderTier(rawValue: border_tier ?? 0) ?? .none, bio: bio ?? "",
                   special: special_border.flatMap(SpecialBorder.init(rawValue:)))
    }

    static let fields = "username, avatar_path, border_tier, bio, special_border"
    static let columns = "profiles(\(fields))"
}

/// A post as Feed shows it, decoded from a `posts` row joined with its author's profile.
struct FeedPost: Identifiable, Decodable, Equatable {
    enum MediaKind: String, Codable { case photo, video }

    let id: UUID
    let authorID: UUID
    let body: String
    let mediaPath: String?
    let mediaKind: MediaKind?
    let createdAt: Date
    let author: FeedMember
    var commentCount: Int

    var username: String { author.username }

    private struct Count: Decodable { let count: Int }
    private enum CodingKeys: String, CodingKey {
        case id, body, comments
        case authorID = "author_id"
        case mediaPath = "media_path"
        case mediaKind = "media_kind"
        case createdAt = "created_at"
        case author = "profiles"
    }

    init(id: UUID, authorID: UUID, body: String, mediaPath: String? = nil,
         mediaKind: MediaKind? = nil, createdAt: Date = .now, username: String, commentCount: Int = 0) {
        self.id = id
        self.authorID = authorID
        self.body = body
        self.mediaPath = mediaPath
        self.mediaKind = mediaKind
        self.createdAt = createdAt
        self.author = FeedMember(id: authorID, username: username, avatarPath: nil, borderTier: .none, bio: "")
        self.commentCount = commentCount
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        authorID = try c.decode(UUID.self, forKey: .authorID)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        mediaPath = try c.decodeIfPresent(String.self, forKey: .mediaPath)
        mediaKind = try c.decodeIfPresent(MediaKind.self, forKey: .mediaKind)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        author = (try? c.decode(ProfileJoin.self, forKey: .author))?.member(authorID) ??
            FeedMember(id: authorID, username: "member", avatarPath: nil, borderTier: .none, bio: "")
        // PostgREST returns `comments(count)` as a one-element array.
        commentCount = (try? c.decode([Count].self, forKey: .comments).first?.count) ?? 0
    }
}

/// A comment on a post, decoded from a `comments` row joined with its author's profile.
struct FeedComment: Identifiable, Decodable, Equatable {
    let id: UUID
    let postID: UUID
    let authorID: UUID
    let body: String
    let createdAt: Date
    let author: FeedMember

    var username: String { author.username }

    private enum CodingKeys: String, CodingKey {
        case id, body
        case postID = "post_id"
        case authorID = "author_id"
        case createdAt = "created_at"
        case author = "profiles"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        postID = try c.decode(UUID.self, forKey: .postID)
        authorID = try c.decode(UUID.self, forKey: .authorID)
        body = try c.decode(String.self, forKey: .body)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        author = (try? c.decode(ProfileJoin.self, forKey: .author))?.member(authorID) ??
            FeedMember(id: authorID, username: "member", avatarPath: nil, borderTier: .none, bio: "")
    }
}

/// A photo or video ready to upload, produced by `PostMedia`.
struct PostAttachment {
    let kind: FeedPost.MediaKind
    let fileURL: URL

    var contentType: String { kind == .photo ? "image/jpeg" : "video/mp4" }
    var fileExtension: String { kind == .photo ? "jpg" : "mp4" }
}

enum FeedRules {
    static let maxBodyLength = 1000
    static let maxCommentLength = 500
    static let maxBioLength = 150
    static let reportReasons = ["Spam", "Harassment or hate", "Sexual or violent content", "Something else"]

    /// Lowercase letters, digits and underscores, 3 to 20 characters, as the database enforces.
    static func isValidUsername(_ name: String) -> Bool {
        (3...20).contains(name.count) &&
            name.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_").contains($0) }
    }

    static func normalizedUsername(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// The member's storage folder. Lowercase, because the storage policy compares it with
    /// `auth.uid()::text` and Swift's `uuidString` is uppercase.
    static func mediaFolder(for user: UUID) -> String {
        user.uuidString.lowercased()
    }
}

@MainActor
final class FeedService: ObservableObject {
    enum State: Equatable { case notConfigured, signedOut, needsUsername, ready }

    @Published private(set) var state: State
    @Published private(set) var username: String?
    @Published private(set) var avatarPath: String?
    @Published private(set) var bio = ""
    @Published private(set) var borderTier: BorderTier = .none
    @Published private(set) var specialBorder: SpecialBorder?
    @Published private(set) var email: String?
    @Published private(set) var posts: [FeedPost] = []
    @Published private(set) var canLoadMore = false
    @Published private(set) var blockedCount = 0
    @Published private(set) var isBusy = false
    @Published var message: String?

    private let client: SupabaseClient?
    private let pageSize = 20
    private let bucket = "post-media"
    private var userID: UUID?

    init(bundle: Bundle = .main) {
        client = Self.makeClient(bundle)
        state = client == nil ? .notConfigured : .signedOut
        if client != nil { Task { await observeAuth() } }
    }

    /// Reads the Supabase URL and anon key that Config/Secrets.xcconfig puts in Info.plist.
    private static func makeClient(_ bundle: Bundle) -> SupabaseClient? {
        guard let raw = bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String,
              let key = bundle.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
              !key.isEmpty, !key.contains("$("),
              let parsed = URL(string: raw), parsed.scheme == "https", let host = parsed.host,
              // Dashboards sometimes show the REST endpoint (…/rest/v1/); the client wants the bare project URL.
              let url = URL(string: "https://\(host)") else { return nil }
        return SupabaseClient(supabaseURL: url, supabaseKey: key,
                              options: SupabaseClientOptions(auth: .init(redirectToURL: authRedirect,
                                                                         emitLocalSessionAsInitialSession: true)))
    }

    /// Where email links (sign-up confirmation) send the member: back into the app.
    /// Must also be listed under Authentication → URL Configuration → Redirect URLs in Supabase.
    static let authRedirect = URL(string: "nagisen://auth-callback")!

    /// Finishes sign-in when a confirmation link opens the app.
    func handle(url: URL) {
        guard let client, url.scheme == Self.authRedirect.scheme, url.host == Self.authRedirect.host else { return }
        Task {
            do {
                _ = try await client.auth.session(from: url)
                message = nil
            } catch {
                // The link was opened on another device, or already used: the email is still confirmed.
                message = "Your email is confirmed. Sign in with your email and password."
            }
        }
    }

    // MARK: - Account

    private func observeAuth() async {
        guard let client else { return }
        for await (_, session) in client.auth.authStateChanges {
            if let session, !session.isExpired {
                email = session.user.email
                await signedIn(as: session.user.id)
            } else if session == nil {
                userID = nil
                username = nil
                avatarPath = nil
                bio = ""
                borderTier = .none
                specialBorder = nil
                email = nil
                posts = []
                blockedCount = 0
                state = .signedOut
            }
            // An expired stored session is refreshed by the client, which then emits again.
        }
    }

    private func signedIn(as id: UUID) async {
        guard let client else { return }
        userID = id
        do {
            let rows: [ProfileJoin] = try await client.from("profiles").select(ProfileJoin.fields)
                .eq("id", value: id).limit(1).execute().value
            let me = rows.first?.member(id)
            username = me?.username
            avatarPath = me?.avatarPath
            bio = me?.bio ?? ""
            borderTier = me?.borderTier ?? .none
            specialBorder = me?.special
            state = username == nil ? .needsUsername : .ready
            if state == .ready { await refresh() }
        } catch {
            message = Self.describe(error, doing: "load your account")
        }
    }

    /// Returns true when the account exists but the email still has to be confirmed.
    func signUp(email: String, password: String) async -> Bool {
        guard let client else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            let response = try await client.auth.signUp(email: email.trimmingCharacters(in: .whitespaces),
                                                        password: password, redirectTo: Self.authRedirect)
            if case .user = response {
                message = "Check your inbox and tap the confirmation link on this iPhone. It opens NAGISEN and signs you in."
                return true
            }
            message = nil
        } catch {
            message = Self.describe(error, doing: "create the account")
        }
        return false
    }

    func signIn(email: String, password: String) async {
        guard let client else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await client.auth.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
            message = nil
        } catch {
            message = Self.describe(error, doing: "sign in")
        }
    }

    /// `nonce` is the raw value whose SHA-256 was sent with the Apple request.
    func signInWithApple(idToken: String, nonce: String) async {
        guard let client else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce))
            message = nil
        } catch {
            message = Self.describe(error, doing: "sign in with Apple")
        }
    }

    func claimUsername(_ raw: String) async -> Bool {
        guard let client, let userID else { return false }
        let name = FeedRules.normalizedUsername(raw)
        guard FeedRules.isValidUsername(name) else {
            message = "Use 3 to 20 lowercase letters, numbers or underscores."
            return false
        }
        isBusy = true
        defer { isBusy = false }
        struct NewProfile: Encodable { let id: UUID; let username: String }
        do {
            try await client.from("profiles").insert(NewProfile(id: userID, username: name)).execute()
            username = name
            state = .ready
            message = nil
            await refresh()
            return true
        } catch let error as PostgrestError where error.code == "23505" {
            message = "That username is taken. Try another."
        } catch {
            message = Self.describe(error, doing: "save the username")
        }
        return false
    }

    func signOut() async {
        guard let client else { return }
        do { try await client.auth.signOut() } catch {
            message = Self.describe(error, doing: "sign out")
        }
    }

    /// Removes the member's media, then the account; the database cascades to their
    /// profile, posts, reports and blocks.
    func deleteAccount() async -> Bool {
        guard let client, let userID else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            let folder = FeedRules.mediaFolder(for: userID)
            let files = try await client.storage.from(bucket).list(path: folder)
            if !files.isEmpty {
                _ = try await client.storage.from(bucket).remove(paths: files.map { "\(folder)/\($0.name)" })
            }
            try await client.rpc("delete_my_account").execute()
            try? await client.auth.signOut(scope: .local)
            message = "Your account and everything you posted have been deleted."
            return true
        } catch {
            message = Self.describe(error, doing: "delete the account")
            return false
        }
    }

    // MARK: - Profile

    var me: FeedMember? {
        guard let userID, let username else { return nil }
        return FeedMember(id: userID, username: username, avatarPath: avatarPath, borderTier: borderTier, bio: bio,
                          special: specialBorder)
    }

    func avatarURL(_ path: String?) -> URL? {
        guard let client, let path else { return nil }
        return try? client.storage.from(bucket).getPublicURL(path: path)
    }

    /// Saves a new username and bio. Usernames follow the same rules as at sign-up.
    func updateProfile(username raw: String, bio rawBio: String) async -> Bool {
        guard let client, let userID else { return false }
        let name = FeedRules.normalizedUsername(raw)
        let newBio = rawBio.trimmingCharacters(in: .whitespacesAndNewlines)
        guard FeedRules.isValidUsername(name) else {
            message = "Use 3 to 20 lowercase letters, numbers or underscores."
            return false
        }
        guard newBio.count <= FeedRules.maxBioLength else {
            message = "Bios can be up to \(FeedRules.maxBioLength) characters."
            return false
        }
        isBusy = true
        defer { isBusy = false }
        struct Change: Encodable { let username: String; let bio: String }
        do {
            try await client.from("profiles").update(Change(username: name, bio: newBio))
                .eq("id", value: userID).execute()
            username = name
            bio = newBio
            message = nil
            await refresh()
            return true
        } catch let error as PostgrestError where error.code == "23505" {
            message = "That username is taken. Try another."
        } catch {
            message = Self.describe(error, doing: "save your profile")
        }
        return false
    }

    /// Uploads a square JPEG from `PostMedia.avatar(from:)` and replaces the previous picture.
    func setAvatar(_ jpeg: Data) async -> Bool {
        guard let client, let userID else { return false }
        isBusy = true
        defer { isBusy = false }
        let path = "\(FeedRules.mediaFolder(for: userID))/avatar-\(UUID().uuidString.lowercased()).jpg"
        do {
            try await client.storage.from(bucket).upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg"))
            struct Change: Encodable { let avatar_path: String }
            try await client.from("profiles").update(Change(avatar_path: path)).eq("id", value: userID).execute()
            if let old = avatarPath { _ = try? await client.storage.from(bucket).remove(paths: [old]) }
            avatarPath = path
            message = nil
            await refresh()
            return true
        } catch {
            _ = try? await client.storage.from(bucket).remove(paths: [path])
            message = Self.describe(error, doing: "change your picture")
            return false
        }
    }

    func removeAvatar() async {
        guard let client, let userID, let old = avatarPath else { return }
        struct Change: Encodable { let avatar_path: String? }
        do {
            try await client.from("profiles").update(Change(avatar_path: nil)).eq("id", value: userID).execute()
            _ = try? await client.storage.from(bucket).remove(paths: [old])
            avatarPath = nil
            await refresh()
        } catch {
            message = Self.describe(error, doing: "remove your picture")
        }
    }

    /// Supabase emails a confirmation link; the address changes once it is opened.
    func changeEmail(to raw: String) async -> Bool {
        guard let client else { return false }
        let address = raw.trimmingCharacters(in: .whitespaces)
        guard address.contains("@"), address != email else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await client.auth.update(user: UserAttributes(email: address), redirectTo: Self.authRedirect)
            message = "Check your inbox to confirm the change. Your sign-in email stays the same until you do."
            return true
        } catch {
            message = Self.describe(error, doing: "change your email")
            return false
        }
    }

    func changePassword(to password: String) async -> Bool {
        guard let client else { return false }
        guard password.count >= 8 else {
            message = "Choose a longer password (at least 8 characters)."
            return false
        }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await client.auth.update(user: UserAttributes(password: password))
            message = "Password changed."
            return true
        } catch {
            message = Self.describe(error, doing: "change your password")
            return false
        }
    }

    /// Saves the border earned on this iPhone to the profile, so other members see it.
    /// Only writes when it changed.
    func syncBorder(_ tier: BorderTier) async {
        guard let client, let userID, state == .ready, tier != borderTier else { return }
        struct Change: Encodable { let border_tier: Int }
        do {
            try await client.from("profiles").update(Change(border_tier: tier.rawValue)).eq("id", value: userID).execute()
            borderTier = tier
            await refresh()
        } catch {
            // Not worth interrupting the member; the next change retries.
        }
    }

    // MARK: - Feed

    private var feedQuery: String {
        "id, author_id, body, media_path, media_kind, created_at, \(ProfileJoin.columns), comments(count)"
    }

    func refresh() async {
        guard let client, state == .ready else { return }
        do {
            let page: [FeedPost] = try await client.from("posts").select(feedQuery)
                .order("created_at", ascending: false).range(from: 0, to: pageSize - 1)
                .execute().value
            posts = page
            canLoadMore = page.count == pageSize
            struct Block: Decodable { let blocked_id: UUID }
            let blocks: [Block] = try await client.from("blocks").select("blocked_id").execute().value
            blockedCount = blocks.count
        } catch {
            message = Self.describe(error, doing: "load the feed")
        }
    }

    func loadMore() async {
        guard let client, state == .ready, canLoadMore else { return }
        do {
            let page: [FeedPost] = try await client.from("posts").select(feedQuery)
                .order("created_at", ascending: false)
                .range(from: posts.count, to: posts.count + pageSize - 1)
                .execute().value
            posts.append(contentsOf: page.filter { new in !posts.contains { $0.id == new.id } })
            canLoadMore = page.count == pageSize
        } catch {
            message = Self.describe(error, doing: "load more posts")
        }
    }

    func isMine(_ post: FeedPost) -> Bool { post.authorID == userID }

    func mediaURL(for post: FeedPost) -> URL? {
        guard let client, let path = post.mediaPath else { return nil }
        return try? client.storage.from(bucket).getPublicURL(path: path)
    }

    func publish(_ text: String, attachment: PostAttachment?) async -> Bool {
        guard let client, let userID, state == .ready else { return false }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard body.count <= FeedRules.maxBodyLength, !body.isEmpty || attachment != nil else {
            message = "Write something or add a photo or video."
            return false
        }
        isBusy = true
        defer { isBusy = false }
        var uploadedPath: String?
        do {
            if let attachment {
                let path = "\(FeedRules.mediaFolder(for: userID))/\(UUID().uuidString.lowercased()).\(attachment.fileExtension)"
                try await client.storage.from(bucket).upload(path, fileURL: attachment.fileURL,
                                                             options: FileOptions(contentType: attachment.contentType))
                uploadedPath = path
            }
            struct NewPost: Encodable {
                let author_id: UUID
                let body: String
                let media_path: String?
                let media_kind: String?
            }
            let saved: FeedPost = try await client.from("posts")
                .insert(NewPost(author_id: userID, body: body, media_path: uploadedPath,
                                media_kind: attachment?.kind.rawValue))
                .select(feedQuery).single().execute().value
            posts.insert(saved, at: 0)
            message = nil
            return true
        } catch {
            if let uploadedPath { _ = try? await client.storage.from(bucket).remove(paths: [uploadedPath]) }
            message = Self.describe(error, doing: "share the post")
            return false
        }
    }

    func delete(_ post: FeedPost) async {
        guard let client, isMine(post) else { return }
        do {
            try await client.from("posts").delete().eq("id", value: post.id).execute()
            if let path = post.mediaPath { _ = try? await client.storage.from(bucket).remove(paths: [path]) }
            posts.removeAll { $0.id == post.id }
        } catch {
            message = Self.describe(error, doing: "delete the post")
        }
    }

    /// Files a report for review and hides the post here right away.
    func report(_ post: FeedPost, reason: String) async {
        guard let client, !isMine(post) else { return }
        posts.removeAll { $0.id == post.id }
        struct NewReport: Encodable { let post_id: UUID; let reason: String }
        do {
            try await client.from("reports").insert(NewReport(post_id: post.id, reason: reason)).execute()
            message = "Thanks. The post is hidden and has been sent for review."
        } catch {
            message = Self.describe(error, doing: "send the report")
        }
    }

    func block(_ post: FeedPost) async {
        guard !isMine(post) else { return }
        await block(authorID: post.authorID)
    }

    /// Blocks a member: their posts and comments disappear for this account on every device.
    @discardableResult
    func block(authorID: UUID) async -> Bool {
        guard let client, authorID != userID else { return false }
        struct NewBlock: Encodable { let blocked_id: UUID }
        do {
            try await client.from("blocks").upsert(NewBlock(blocked_id: authorID),
                                                   onConflict: "blocker_id,blocked_id").execute()
            posts.removeAll { $0.authorID == authorID }
            blockedCount += 1
            return true
        } catch {
            message = Self.describe(error, doing: "block this member")
            return false
        }
    }

    func unblockEveryone() async {
        guard let client, let userID else { return }
        do {
            try await client.from("blocks").delete().eq("blocker_id", value: userID).execute()
            blockedCount = 0
            await refresh()
        } catch {
            message = Self.describe(error, doing: "unblock")
        }
    }

    // MARK: - Comments

    private var commentQuery: String { "id, post_id, author_id, body, created_at, \(ProfileJoin.columns)" }

    /// The oldest 200 comments on a post, oldest first.
    func comments(on post: FeedPost) async -> [FeedComment]? {
        guard let client, state == .ready else { return nil }
        do {
            let rows: [FeedComment] = try await client.from("comments").select(commentQuery)
                .eq("post_id", value: post.id).order("created_at", ascending: true).limit(200)
                .execute().value
            if rows.count < 200 { setCommentCount(rows.count, on: post.id) }
            return rows
        } catch {
            message = Self.describe(error, doing: "load the comments")
            return nil
        }
    }

    func addComment(_ text: String, to post: FeedPost) async -> FeedComment? {
        guard let client, let userID, state == .ready else { return nil }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= FeedRules.maxCommentLength else {
            message = "Comments can be up to \(FeedRules.maxCommentLength) characters."
            return nil
        }
        isBusy = true
        defer { isBusy = false }
        struct NewComment: Encodable { let post_id: UUID; let author_id: UUID; let body: String }
        do {
            let saved: FeedComment = try await client.from("comments")
                .insert(NewComment(post_id: post.id, author_id: userID, body: body))
                .select(commentQuery).single().execute().value
            adjustCommentCount(by: 1, on: post.id)
            message = nil
            return saved
        } catch {
            message = Self.describe(error, doing: "add the comment")
            return nil
        }
    }

    func isMine(_ comment: FeedComment) -> Bool { comment.authorID == userID }

    /// Your own comments, and any comment on your own post.
    func canDelete(_ comment: FeedComment, on post: FeedPost) -> Bool { isMine(comment) || isMine(post) }

    func deleteComment(_ comment: FeedComment, on post: FeedPost) async -> Bool {
        guard let client, canDelete(comment, on: post) else { return false }
        do {
            try await client.from("comments").delete().eq("id", value: comment.id).execute()
            adjustCommentCount(by: -1, on: post.id)
            return true
        } catch {
            message = Self.describe(error, doing: "delete the comment")
            return false
        }
    }

    func report(_ comment: FeedComment, reason: String) async {
        guard let client, !isMine(comment) else { return }
        struct NewReport: Encodable { let comment_id: UUID; let reason: String }
        do {
            try await client.from("reports").insert(NewReport(comment_id: comment.id, reason: reason)).execute()
            message = "Thanks. The comment is hidden and has been sent for review."
        } catch {
            message = Self.describe(error, doing: "send the report")
        }
    }

    private func adjustCommentCount(by delta: Int, on postID: UUID) {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        posts[index].commentCount = max(0, posts[index].commentCount + delta)
    }

    private func setCommentCount(_ count: Int, on postID: UUID) {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        posts[index].commentCount = count
    }

    // MARK: - Errors

    static func describe(_ error: any Error, doing action: String) -> String {
        if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
            return "You're offline. Couldn't \(action)."
        }
        if let auth = error as? AuthError {
            switch auth.errorCode {
            case .invalidCredentials: return "That email and password don't match."
            case .emailNotConfirmed: return "Confirm your email first, using the link we sent."
            case .userAlreadyExists, .emailExists: return "An account with that email already exists. Sign in instead."
            case .weakPassword: return "Choose a longer password (at least 8 characters)."
            case .overEmailSendRateLimit: return "Too many emails sent. Try again in a little while."
            default: return "Couldn't \(action). \(auth.message)"
            }
        }
        return "Couldn't \(action). \(error.localizedDescription)"
    }
}
