import SwiftUI

/// Comments and appreciations others left on your posts, newest first.
struct ActivityView: View {
    @EnvironmentObject private var feed: FeedService
    @Environment(\.dismiss) private var dismiss
    @State private var openingPost: FeedPost?
    @State private var viewingMember: FeedMember?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if feed.activity.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quiet for now")
                                .font(.system(size: 23, design: .serif))
                            Text("When members follow you, or like or comment on your posts, it shows here.")
                                .font(.subheadline).foregroundStyle(Theme.muted)
                        }
                    } else {
                        ForEach(feed.activity) { item in row(item) }
                    }
                    if let message = feed.message {
                        Text(message).font(.subheadline).foregroundStyle(Theme.accentText)
                    }
                }
                .foregroundStyle(Theme.ink)
                .padding(20)
            }
            .refreshable { await feed.loadActivity() }
            .background(NagisenBackdrop())
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                feed.message = nil
                await feed.loadActivity()
                feed.markActivitySeen()
            }
            .sheet(item: $openingPost) { PostDetailView(post: $0) }
            .sheet(item: $viewingMember) { MemberPageView(member: $0) }
        }
    }

    private func row(_ item: FeedActivity) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { viewingMember = item.member } label: {
                AvatarView(url: feed.avatarURL(item.member.avatarPath), username: item.member.username,
                           tier: item.member.borderTier, special: item.member.special, size: 38)
            }
            .buttonStyle(.plain)
            Button {
                if let postID = item.postID {
                    Task { openingPost = await feed.post(id: postID) }
                } else {
                    viewingMember = item.member
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    switch item.kind {
                    case .comment(let text):
                        (nameText("@\(item.member.username)", item.member.special).fontWeight(.semibold) + Text(" commented"))
                            .font(.subheadline)
                        Text(text).font(.subheadline).foregroundStyle(Theme.muted).lineLimit(2)
                    case .like:
                        (nameText("@\(item.member.username)", item.member.special).fontWeight(.semibold) + Text(" liked your post"))
                            .font(.subheadline)
                    case .follow:
                        (nameText("@\(item.member.username)", item.member.special).fontWeight(.semibold) + Text(" started following you"))
                            .font(.subheadline)
                    }
                    Text(item.date, style: .relative)
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
