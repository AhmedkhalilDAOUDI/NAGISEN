import SwiftUI

/// A list of members (who liked, followers, following, story viewers) with Follow buttons.
struct PeopleListView: View {
    let title: String
    let load: () async -> [FeedMember]
    @EnvironmentObject private var feed: FeedService
    @Environment(\.dismiss) private var dismiss
    @State private var people: [FeedMember] = []
    @State private var loading = true
    @State private var viewing: FeedMember?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if loading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                    } else if people.isEmpty {
                        Text("No one here yet.")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity).padding(.top, 30)
                    }
                    ForEach(people) { member in row(member) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(NagisenBackdrop())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task {
                people = await load()
                loading = false
            }
            .sheet(item: $viewing) { MemberPageView(member: $0) }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ member: FeedMember) -> some View {
        HStack(spacing: 12) {
            Button { viewing = member } label: {
                HStack(spacing: 12) {
                    AvatarView(url: feed.avatarURL(member.avatarPath), username: member.username,
                               tier: member.borderTier, special: member.special, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.username).font(.subheadline.weight(.semibold)).memberName(member.special)
                        if !member.bio.isEmpty {
                            Text(member.bio).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !feed.isMe(member) {
                FollowButton(member: member, compact: true)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.vertical, 6)
    }
}

/// Follow / Following, kept in step with every other Follow button through FeedService.
struct FollowButton: View {
    let member: FeedMember
    var compact = false
    @EnvironmentObject private var feed: FeedService

    var body: some View {
        let following = feed.isFollowing(member)
        Button {
            Task { following ? await feed.unfollow(member) : await feed.follow(member) }
        } label: {
            Text(following ? "Following" : "Follow")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(following ? Theme.ink : .white)
                .padding(.horizontal, compact ? 16 : 0)
                .frame(maxWidth: compact ? nil : .infinity)
                .frame(height: compact ? 34 : 38)
                .background(following ? Theme.surface.opacity(0.6) : Theme.accent,
                            in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: following)
        .accessibilityLabel(following ? "Following @\(member.username). Tap to unfollow" : "Follow @\(member.username)")
    }
}
