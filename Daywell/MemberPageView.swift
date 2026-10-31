import SwiftUI

/// A member's profile: picture and border, counts, bio, Follow, and a grid of their posts.
/// Opened by tapping a name or picture anywhere in Feed.
struct MemberPageView: View {
    let member: FeedMember
    @EnvironmentObject private var feed: FeedService
    @Environment(\.dismiss) private var dismiss
    @State private var posts: [FeedPost] = []
    @State private var counts = ProfileCounts()
    @State private var loading = true
    @State private var opened: FeedPost?
    @State private var list: PeopleList?
    @State private var editing = false
    @State private var confirmingBlock = false

    private enum PeopleList: String, Identifiable { case followers = "Followers", following = "Following"; var id: String { rawValue } }

    private var isMe: Bool { feed.isMe(member) }
    /// Your own profile reflects edits made in Account right away.
    private var shown: FeedMember { isMe ? (feed.me ?? member) : member }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    grid
                    if let message = feed.message {
                        Text(message).font(.subheadline).foregroundStyle(Theme.accentText).padding(.horizontal, 16)
                    }
                }
                .foregroundStyle(Theme.ink)
                .padding(.vertical, 12)
            }
            .refreshable { await load() }
            .background(NagisenBackdrop())
            .navigationTitle(shown.username)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if !isMe {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Block @\(member.username)", systemImage: "hand.raised", role: .destructive) {
                                confirmingBlock = true
                            }
                        } label: { Image(systemName: "ellipsis") }
                        .accessibilityLabel("More for @\(member.username)")
                    }
                }
            }
            .task { feed.message = nil; await load() }
            .onChange(of: feed.isFollowing(member)) { _, _ in Task { counts = await feed.counts(for: member) } }
            .sheet(item: $opened) { PostDetailView(post: $0) }
            .sheet(item: $list) { which in
                PeopleListView(title: which.rawValue) {
                    which == .followers ? await feed.followers(of: member) : await feed.followedBy(member)
                }
            }
            .sheet(isPresented: $editing) { NavigationStack { AccountSettingsView(inSheet: true) } }
            .confirmationDialog("Block @\(member.username)?", isPresented: $confirmingBlock, titleVisibility: .visible) {
                Button("Block", role: .destructive) {
                    Task { if await feed.block(authorID: member.id) { dismiss() } }
                }
            } message: {
                Text("You won’t see their posts, comments or stories anymore. They aren’t told.")
            }
        }
    }

    private func load() async {
        async let fetched = feed.posts(by: member)
        async let numbers = feed.counts(for: member)
        posts = await fetched ?? []
        counts = await numbers
        loading = false
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 20) {
                AvatarView(url: feed.avatarURL(shown.avatarPath), username: shown.username,
                           tier: shown.borderTier, special: shown.special, size: 88)
                HStack(spacing: 0) {
                    stat(counts.posts, "posts", action: nil)
                    stat(counts.followers, counts.followers == 1 ? "follower" : "followers") { list = .followers }
                    stat(counts.following, "following") { list = .following }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(shown.username).font(.subheadline.weight(.semibold))
                if let special = shown.special {
                    Text("\(special.name.uppercased()) · \(special.title.uppercased())")
                        .font(.caption2.weight(.semibold)).tracking(1.6).foregroundStyle(Theme.accentText)
                } else if shown.borderTier != .none {
                    Text("\(shown.borderTier.name.uppercased()) BORDER")
                        .font(.caption2.weight(.semibold)).tracking(1.6).foregroundStyle(Theme.muted)
                }
                if !shown.bio.isEmpty {
                    Text(shown.bio).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            }
            if isMe {
                Button { editing = true } label: {
                    Text("Edit profile")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            } else {
                FollowButton(member: member)
            }
        }
        .padding(.horizontal, 16)
    }

    private func stat(_ value: Int, _ label: String, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            VStack(spacing: 2) {
                Text(value.formatted()).font(.headline)
                Text(label).font(.caption).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var grid: some View {
        if loading {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
        } else if posts.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "camera").font(.largeTitle.weight(.light)).foregroundStyle(Theme.muted)
                Text(isMe ? "Share your first moment" : "No posts yet")
                    .font(.system(.title3, design: .serif))
            }
            .frame(maxWidth: .infinity).padding(.top, 40)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                ForEach(posts) { post in
                    Button { opened = post } label: { tile(post) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func tile(_ post: FeedPost) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if post.mediaPath == nil {
                    QuoteCard(text: post.body, compact: true)
                } else {
                    RemoteImage(url: feed.thumbnailURL(for: post))
                }
            }
            .clipped()
            .overlay(alignment: .topTrailing) {
                if post.mediaKind == .video {
                    Image(systemName: "play.fill")
                        .font(.caption).foregroundStyle(.white)
                        .shadow(radius: 3).padding(7)
                }
            }
            .accessibilityLabel(post.mediaKind == .video ? "Video post" : post.mediaPath == nil ? "Text post" : "Photo post")
    }
}
