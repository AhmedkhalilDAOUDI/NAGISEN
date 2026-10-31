import Foundation
import Supabase

/// A post as Feed shows it, decoded from a `posts` row joined with its author's profile.
struct FeedPost: Identifiable, Decodable, Equatable {
    enum MediaKind: String, Codable { case photo, video }

    let id: UUID
    let authorID: UUID
    let body: String
    let mediaPath: String?
    let mediaKind: MediaKind?
    let createdAt: Date
    let username: String

    private struct Author: Decodable { let username: String }
    private enum CodingKeys: String, CodingKey {
        case id, body
        case authorID = "author_id"
        case mediaPath = "media_path"
        case mediaKind = "media_kind"
        case createdAt = "created_at"
        case author = "profiles"
    }

    init(id: UUID, authorID: UUID, body: String, mediaPath: String? = nil,
         mediaKind: MediaKind? = nil, createdAt: Date = .now, username: String) {
        self.id = id
        self.authorID = authorID
        self.body = body
        self.mediaPath = mediaPath
        self.mediaKind = mediaKind
        self.createdAt = createdAt
        self.username = username
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        authorID = try c.decode(UUID.self, forKey: .authorID)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        mediaPath = try c.decodeIfPresent(String.self, forKey: .mediaPath)
        mediaKind = try c.decodeIfPresent(MediaKind.self, forKey: .mediaKind)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        username = (try? c.decode(Author.self, forKey: .author).username) ?? "member"
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

    /// Lowercase letters, digits and underscores, 3 to 20 characters, as the database enforces.
    static func isValidUsername(_ name: String) -> Bool {
        (3...20).contains(name.count) &&
            name.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_").contains($0) }
    }

    static func normalizedUsername(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }
}

@MainActor
final class FeedService: ObservableObject {
    enum State: Equatable { case notConfigured, signedOut, needsUsername, ready }

    @Published private(set) var state: State
    @Published private(set) var username: String?
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
                              options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true)))
    }

    // MARK: - Account

    private func observeAuth() async {
        guard let client else { return }
        for await (_, session) in client.auth.authStateChanges {
            if let session, !session.isExpired {
                await signedIn(as: session.user.id)
            } else if session == nil {
                userID = nil
                username = nil
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
        struct Row: Decodable { let username: String }
        do {
            let rows: [Row] = try await client.from("profiles").select("username")
                .eq("id", value: id).limit(1).execute().value
            username = rows.first?.username
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
                                                        password: password)
            if case .user = response {
                message = "Check your inbox and confirm your email, then sign in."
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
            let files = try await client.storage.from(bucket).list(path: userID.uuidString)
            if !files.isEmpty {
                _ = try await client.storage.from(bucket).remove(paths: files.map { "\(userID.uuidString)/\($0.name)" })
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

    // MARK: - Feed

    private var feedQuery: String { "id, author_id, body, media_path, media_kind, created_at, profiles(username)" }

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
                let path = "\(userID.uuidString)/\(UUID().uuidString.lowercased()).\(attachment.fileExtension)"
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
        guard let client, !isMine(post) else { return }
        struct NewBlock: Encodable { let blocked_id: UUID }
        do {
            try await client.from("blocks").upsert(NewBlock(blocked_id: post.authorID),
                                                   onConflict: "blocker_id,blocked_id").execute()
            posts.removeAll { $0.authorID == post.authorID }
            blockedCount += 1
        } catch {
            message = Self.describe(error, doing: "block this member")
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
