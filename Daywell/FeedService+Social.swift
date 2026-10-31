import Foundation
import Supabase

/// Posts, followers and following for a profile header.
struct ProfileCounts: Equatable {
    var posts = 0
    var followers = 0
    var following = 0
}

extension FeedService {

    // MARK: - Likes

    /// Likes or unlikes a post (your own included, as on any photo feed). The screen updates
    /// first and is put back if the server refuses. Returns the post as it now stands.
    @discardableResult
    func toggleLike(_ post: FeedPost) async -> FeedPost {
        guard let client, let userID else { return post }
        var updated = post
        updated.likedByMe.toggle()
        updated.likeCount = max(0, post.likeCount + (updated.likedByMe ? 1 : -1))
        replace(updated)
        struct Like: Encodable { let post_id: UUID }
        do {
            if updated.likedByMe {
                try await client.from("appreciations").upsert(Like(post_id: post.id), onConflict: "post_id,member_id").execute()
            } else {
                try await client.from("appreciations").delete()
                    .eq("post_id", value: post.id).eq("member_id", value: userID).execute()
            }
            return updated
        } catch {
            replace(post)
            message = Self.describe(error, doing: updated.likedByMe ? "like the post" : "unlike the post")
            return post
        }
    }

    /// Double-tap only ever likes; it never takes a like back.
    @discardableResult
    func like(_ post: FeedPost) async -> FeedPost {
        post.likedByMe ? post : await toggleLike(post)
    }

    /// Everyone who liked a post, newest first.
    func likers(of post: FeedPost) async -> [FeedMember] {
        guard let client else { return [] }
        struct Row: Decodable { let member_id: UUID; let profiles: ProfileJoin? }
        do {
            let rows: [Row] = try await client.from("appreciations")
                .select("member_id, \(ProfileJoin.columns(via: "appreciations_member_id_fkey"))")
                .eq("post_id", value: post.id).order("created_at", ascending: false).limit(500)
                .execute().value
            return rows.map { Self.member($0.member_id, $0.profiles) }
        } catch {
            message = Self.describe(error, doing: "load the likes")
            return []
        }
    }

    private func replace(_ post: FeedPost) {
        if let index = posts.firstIndex(where: { $0.id == post.id }) { posts[index] = post }
    }

    // MARK: - Follows

    func isFollowing(_ member: FeedMember) -> Bool { following.contains(member.id) }

    func loadFollowing() async {
        guard let client, let userID else { return }
        struct Row: Decodable { let followee_id: UUID }
        do {
            let rows: [Row] = try await client.from("follows").select("followee_id")
                .eq("follower_id", value: userID).execute().value
            following = Set(rows.map(\.followee_id))
        } catch {
            // The feed falls back to your own posts; the next refresh tries again.
        }
    }

    func follow(_ member: FeedMember) async {
        guard let client, member.id != userID, !following.contains(member.id) else { return }
        following.insert(member.id)
        struct Follow: Encodable { let followee_id: UUID }
        do {
            try await client.from("follows").upsert(Follow(followee_id: member.id),
                                                    onConflict: "follower_id,followee_id").execute()
        } catch {
            following.remove(member.id)
            message = Self.describe(error, doing: "follow @\(member.username)")
        }
    }

    func unfollow(_ member: FeedMember) async {
        guard let client, let userID, following.contains(member.id) else { return }
        following.remove(member.id)
        do {
            try await client.from("follows").delete()
                .eq("follower_id", value: userID).eq("followee_id", value: member.id).execute()
            if mode == .following { posts.removeAll { $0.authorID == member.id } }
        } catch {
            following.insert(member.id)
            message = Self.describe(error, doing: "unfollow @\(member.username)")
        }
    }

    /// Posts, followers and following, counted on the server without downloading the rows.
    func counts(for member: FeedMember) async -> ProfileCounts {
        guard let client else { return ProfileCounts() }
        func count(_ table: String, _ column: String) async -> Int {
            (try? await client.from(table).select("*", head: true, count: .exact)
                .eq(column, value: member.id).execute().count) ?? 0
        }
        async let posts = count("posts", "author_id")
        async let followers = count("follows", "followee_id")
        async let following = count("follows", "follower_id")
        return await ProfileCounts(posts: posts, followers: followers, following: following)
    }

    func followers(of member: FeedMember) async -> [FeedMember] {
        guard let client else { return [] }
        struct Row: Decodable { let follower_id: UUID; let profiles: ProfileJoin? }
        do {
            let rows: [Row] = try await client.from("follows")
                .select("follower_id, \(ProfileJoin.columns(via: "follows_follower_id_fkey"))")
                .eq("followee_id", value: member.id).order("created_at", ascending: false).limit(500)
                .execute().value
            return rows.map { Self.member($0.follower_id, $0.profiles) }
        } catch {
            message = Self.describe(error, doing: "load followers")
            return []
        }
    }

    func followedBy(_ member: FeedMember) async -> [FeedMember] {
        guard let client else { return [] }
        struct Row: Decodable { let followee_id: UUID; let profiles: ProfileJoin? }
        do {
            let rows: [Row] = try await client.from("follows")
                .select("followee_id, \(ProfileJoin.columns(via: "follows_followee_id_fkey"))")
                .eq("follower_id", value: member.id).order("created_at", ascending: false).limit(500)
                .execute().value
            return rows.map { Self.member($0.followee_id, $0.profiles) }
        } catch {
            message = Self.describe(error, doing: "load who they follow")
            return []
        }
    }

    // MARK: - Uploads

    /// Uploads a photo or video into your folder (and a video's poster frame next to it).
    /// Returns the storage paths; removes what it uploaded if any part fails.
    func upload(_ attachment: PostAttachment, prefix: String) async throws -> (media: String, poster: String?) {
        guard let client, let userID else { throw URLError(.userAuthenticationRequired) }
        let base = "\(FeedRules.mediaFolder(for: userID))/\(prefix)\(UUID().uuidString.lowercased())"
        let mediaPath = "\(base).\(attachment.fileExtension)"
        try await client.storage.from(bucket).upload(mediaPath, fileURL: attachment.fileURL,
                                                     options: FileOptions(contentType: attachment.contentType))
        guard let posterURL = attachment.posterURL else { return (mediaPath, nil) }
        let posterPath = "\(base)-poster.jpg"
        do {
            try await client.storage.from(bucket).upload(posterPath, fileURL: posterURL,
                                                         options: FileOptions(contentType: "image/jpeg"))
            return (mediaPath, posterPath)
        } catch {
            _ = try? await client.storage.from(bucket).remove(paths: [mediaPath])
            throw error
        }
    }
}
