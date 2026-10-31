import Foundation
import Supabase

/// One story: a photo or video that stays up for 24 hours.
struct FeedStory: Identifiable, Decodable, Equatable {
    let id: UUID
    let authorID: UUID
    let mediaPath: String
    let mediaKind: FeedPost.MediaKind
    let posterPath: String?
    let createdAt: Date
    let expiresAt: Date
    let author: FeedMember

    private enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case mediaPath = "media_path"
        case mediaKind = "media_kind"
        case posterPath = "poster_path"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case author = "profiles"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        authorID = try c.decode(UUID.self, forKey: .authorID)
        mediaPath = try c.decode(String.self, forKey: .mediaPath)
        mediaKind = try c.decode(FeedPost.MediaKind.self, forKey: .mediaKind)
        posterPath = try c.decodeIfPresent(String.self, forKey: .posterPath)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        expiresAt = try c.decode(Date.self, forKey: .expiresAt)
        author = FeedService.member(authorID, try? c.decode(ProfileJoin.self, forKey: .author))
    }

    init(id: UUID = UUID(), authorID: UUID, mediaPath: String = "x.jpg", mediaKind: FeedPost.MediaKind = .photo,
         createdAt: Date, expiresAt: Date? = nil, username: String = "member") {
        self.id = id
        self.authorID = authorID
        self.mediaPath = mediaPath
        self.mediaKind = mediaKind
        self.posterPath = nil
        self.createdAt = createdAt
        self.expiresAt = expiresAt ?? createdAt.addingTimeInterval(24 * 3600)
        self.author = FeedMember(id: authorID, username: username, avatarPath: nil, borderTier: .none, bio: "")
    }
}

/// One member's live stories, oldest first, as the viewer plays them.
struct StoryGroup: Identifiable, Equatable {
    let member: FeedMember
    let stories: [FeedStory]
    var id: UUID { member.id }

    /// Your own circle first, then people with something you haven't seen, then the rest;
    /// within each, the most recent story first.
    static func grouped(_ stories: [FeedStory], me: UUID?, seen: Set<UUID>) -> [StoryGroup] {
        let groups = Dictionary(grouping: stories, by: \.authorID).compactMap { _, items -> StoryGroup? in
            guard let first = items.first else { return nil }
            return StoryGroup(member: first.author, stories: items.sorted { $0.createdAt < $1.createdAt })
        }
        return groups.sorted { left, right in
            if (left.id == me) != (right.id == me) { return left.id == me }
            let leftUnseen = left.hasUnseen(seen), rightUnseen = right.hasUnseen(seen)
            if leftUnseen != rightUnseen { return leftUnseen }
            return (left.stories.last?.createdAt ?? .distantPast) > (right.stories.last?.createdAt ?? .distantPast)
        }
    }

    func hasUnseen(_ seen: Set<UUID>) -> Bool { stories.contains { !seen.contains($0.id) } }

    /// Where to start playing: the first story you haven't seen, or the beginning.
    func startIndex(_ seen: Set<UUID>) -> Int { stories.firstIndex { !seen.contains($0.id) } ?? 0 }
}

extension FeedService {
    private var storyQuery: String {
        "id, author_id, media_path, media_kind, poster_path, created_at, expires_at, " +
            ProfileJoin.columns(via: "stories_author_id_fkey")
    }

    /// Live stories from you and the people you follow, with which ones you've already seen.
    func loadStories() async {
        guard let client, let userID else { return }
        struct Seen: Decodable { let story_id: UUID }
        do {
            let authors = Array(following.union([userID]))
            let rows: [FeedStory] = try await client.from("stories").select(storyQuery)
                .in("author_id", values: authors)
                .gt("expires_at", value: Date.now.ISO8601Format())
                .order("created_at", ascending: true).limit(300)
                .execute().value
            if !rows.isEmpty {
                let seen: [Seen] = try await client.from("story_views").select("story_id")
                    .eq("viewer_id", value: userID).in("story_id", values: rows.map(\.id))
                    .execute().value
                seenStories = Set(seen.map(\.story_id))
            }
            storyGroups = StoryGroup.grouped(rows, me: userID, seen: seenStories)
        } catch {
            // Stories are an extra row; the feed below still loads.
        }
    }

    func markSeen(_ story: FeedStory) async {
        guard let client, !seenStories.contains(story.id) else { return }
        seenStories.insert(story.id)
        struct View: Encodable { let story_id: UUID }
        _ = try? await client.from("story_views").upsert(View(story_id: story.id),
                                                          onConflict: "story_id,viewer_id").execute()
    }

    /// Who has seen one of your stories, newest first.
    func viewers(of story: FeedStory) async -> [FeedMember] {
        guard let client, story.authorID == userID else { return [] }
        struct Row: Decodable { let viewer_id: UUID; let profiles: ProfileJoin? }
        do {
            let rows: [Row] = try await client.from("story_views")
                .select("viewer_id, \(ProfileJoin.columns(via: "story_views_viewer_id_fkey"))")
                .eq("story_id", value: story.id).neq("viewer_id", value: story.authorID)
                .order("created_at", ascending: false).limit(500)
                .execute().value
            return rows.map { Self.member($0.viewer_id, $0.profiles) }
        } catch {
            message = Self.describe(error, doing: "load who saw your story")
            return []
        }
    }

    func addStory(_ attachment: PostAttachment) async -> Bool {
        guard let client, state == .ready else { return false }
        isBusy = true
        defer { isBusy = false }
        var uploaded: (media: String, poster: String?)?
        do {
            let files = try await upload(attachment, prefix: "story-")
            uploaded = files
            struct NewStory: Encodable { let media_path: String; let media_kind: String; let poster_path: String? }
            try await client.from("stories").insert(NewStory(media_path: files.media,
                                                             media_kind: attachment.kind.rawValue,
                                                             poster_path: files.poster)).execute()
            await loadStories()
            message = nil
            return true
        } catch {
            if let uploaded {
                _ = try? await client.storage.from(bucket).remove(paths: [uploaded.media] + [uploaded.poster].compactMap { $0 })
            }
            message = Self.describe(error, doing: "share your story")
            return false
        }
    }

    func deleteStory(_ story: FeedStory) async {
        guard let client, story.authorID == userID else { return }
        do {
            try await client.from("stories").delete().eq("id", value: story.id).execute()
            _ = try? await client.storage.from(bucket).remove(paths: [story.mediaPath] + [story.posterPath].compactMap { $0 })
            await loadStories()
        } catch {
            message = Self.describe(error, doing: "delete the story")
        }
    }

    func reportStory(_ story: FeedStory, reason: String) async {
        guard let client, story.authorID != userID else { return }
        struct NewReport: Encodable { let story_id: UUID; let reason: String }
        do {
            try await client.from("reports").insert(NewReport(story_id: story.id, reason: reason)).execute()
            message = "Thanks. The story has been sent for review."
        } catch {
            message = Self.describe(error, doing: "send the report")
        }
    }

    /// Deletes your own stories older than 24 hours, files included. Nobody can see them by
    /// then; this just frees the storage.
    func cleanUpExpiredStories() async {
        guard let client, let userID else { return }
        struct Old: Decodable { let id: UUID; let media_path: String; let poster_path: String? }
        guard let old: [Old] = try? await client.from("stories").select("id, media_path, poster_path")
            .eq("author_id", value: userID).lt("expires_at", value: Date.now.ISO8601Format())
            .execute().value, !old.isEmpty else { return }
        _ = try? await client.storage.from(bucket).remove(paths: old.flatMap { [$0.media_path] + [$0.poster_path].compactMap { $0 } })
        _ = try? await client.from("stories").delete().in("id", values: old.map(\.id)).execute()
    }

    func storyMediaURL(_ story: FeedStory) -> URL? { publicURL(story.mediaPath) }
}
