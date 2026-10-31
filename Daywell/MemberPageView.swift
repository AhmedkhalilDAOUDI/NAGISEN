import SwiftUI

/// A member's page: picture with their border, username, bio and their posts.
/// Opened by tapping a name or picture in Feed, in comments or in Activity.
struct MemberPageView: View {
    let member: FeedMember
    @EnvironmentObject private var feed: FeedService
    @Environment(\.dismiss) private var dismiss
    @State private var posts: [FeedPost] = []
    @State private var loading = true
    @State private var commentingPost: FeedPost?
    @State private var confirmingBlock = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 12) {
                        AvatarView(url: feed.avatarURL(member.avatarPath), username: member.username,
                                   tier: member.borderTier, special: member.special, size: 112)
                        Text("@\(member.username)")
                            .font(.system(size: 27, design: .serif))
                        if let special = member.special {
                            Text("\(special.name.uppercased()) · \(special.title.uppercased())")
                                .font(.caption2.weight(.semibold)).tracking(2)
                                .foregroundStyle(Theme.accentText)
                        } else if member.borderTier != .none {
                            Text("\(member.borderTier.name.uppercased()) BORDER")
                                .font(.caption2.weight(.semibold)).tracking(2)
                                .foregroundStyle(Theme.muted)
                        }
                        Text(member.bio.isEmpty ? "No bio yet." : member.bio)
                            .font(.subheadline)
                            .foregroundStyle(member.bio.isEmpty ? Theme.muted : Theme.ink)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)

                    if loading {
                        ProgressView().padding(.top, 20)
                    } else if posts.isEmpty {
                        Text(feed.isMe(member) ? "You haven't posted yet." : "No posts yet.")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("POSTS")
                                .font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(Theme.muted)
                            ForEach(posts) { post in postRow(post) }
                        }
                    }
                    if let message = feed.message {
                        Text(message).font(.subheadline).foregroundStyle(Theme.accentText)
                    }
                }
                .foregroundStyle(Theme.ink)
                .padding(20)
            }
            .background(NagisenBackdrop())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if !feed.isMe(member) {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Block @\(member.username)", systemImage: "hand.raised", role: .destructive) {
                                confirmingBlock = true
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("More for @\(member.username)")
                    }
                }
            }
            .task {
                feed.message = nil
                posts = await feed.posts(by: member) ?? []
                loading = false
            }
            .sheet(item: $commentingPost) { PostCommentsView(post: $0) }
            .confirmationDialog("Block @\(member.username)?", isPresented: $confirmingBlock,
                                titleVisibility: .visible) {
                Button("Block", role: .destructive) {
                    Task { if await feed.block(authorID: member.id) { dismiss() } }
                }
            } message: {
                Text("You won’t see their posts or comments anymore. They aren’t told.")
            }
        }
    }

    private func postRow(_ post: FeedPost) -> some View {
        Button { commentingPost = post } label: {
            VStack(alignment: .leading, spacing: 10) {
                if !post.body.isEmpty {
                    Text(post.body).font(.subheadline).lineLimit(5)
                        .multilineTextAlignment(.leading)
                }
                if let url = feed.mediaURL(for: post) {
                    switch post.mediaKind {
                    case .photo:
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFill()
                            } else {
                                Rectangle().fill(Theme.surface.opacity(0.4))
                            }
                        }
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    case .video:
                        Label("Video", systemImage: "play.rectangle")
                            .font(.caption).foregroundStyle(Theme.muted)
                    case nil:
                        EmptyView()
                    }
                }
                HStack(spacing: 14) {
                    Text(post.createdAt, style: .relative)
                    Label("\(post.commentCount)", systemImage: "bubble.left")
                    Spacer()
                }
                .font(.caption).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .softCardStyle()
    }
}
