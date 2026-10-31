import SwiftUI

/// The comments on one post, with a field to add one. Opened from the comment button on a post.
struct PostCommentsView: View {
    let post: FeedPost
    @EnvironmentObject private var feed: FeedService
    @Environment(\.dismiss) private var dismiss
    @State private var comments: [FeedComment] = []
    @State private var loading = true
    @State private var text = ""
    @State private var deleting: FeedComment?
    @State private var reporting: FeedComment?
    @State private var blocking: FeedComment?
    @State private var viewingMember: FeedMember?
    @State private var actionsFor: FeedComment?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    original

                    if loading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
                    } else if comments.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No comments yet")
                                .font(.system(size: 21, design: .serif))
                            Text("Say something kind to start the conversation.")
                                .font(.subheadline).foregroundStyle(Theme.muted)
                        }
                        .padding(.top, 4)
                    } else {
                        ForEach(comments) { comment in row(comment) }
                    }
                    if let message = feed.message {
                        Text(message).font(.subheadline).foregroundStyle(Theme.accentText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { composerBar }
            .background(NagisenBackdrop())
            .nagisenSheetBar("Comments", onClose: { dismiss() })
            .task {
                feed.message = nil
                comments = await feed.comments(on: post) ?? []
                loading = false
            }
            .sheet(item: $viewingMember) { MemberPageView(member: $0) }
            .confirmationDialog("Delete this comment?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            )) {
                Button("Delete comment", role: .destructive) {
                    guard let comment = deleting else { return }
                    deleting = nil
                    Task {
                        if await feed.deleteComment(comment, on: post) {
                            comments.removeAll { $0.id == comment.id }
                        }
                    }
                }
            }
            .confirmationDialog("Why are you reporting this comment?", isPresented: Binding(
                get: { reporting != nil }, set: { if !$0 { reporting = nil } }
            ), titleVisibility: .visible) {
                ForEach(FeedRules.reportReasons, id: \.self) { reason in
                    Button(reason) {
                        guard let comment = reporting else { return }
                        reporting = nil
                        comments.removeAll { $0.id == comment.id }
                        Task { await feed.report(comment, reason: reason) }
                    }
                }
            } message: {
                Text("The comment will be hidden for you and sent for review.")
            }
            .confirmationDialog("Block @\(blocking?.username ?? "member")?", isPresented: Binding(
                get: { blocking != nil }, set: { if !$0 { blocking = nil } }
            ), titleVisibility: .visible) {
                Button("Block", role: .destructive) {
                    guard let comment = blocking else { return }
                    blocking = nil
                    Task {
                        guard await feed.block(authorID: comment.authorID) else { return }
                        comments.removeAll { $0.authorID == comment.authorID }
                        // Blocking the post's author hides the post itself.
                        if comment.authorID == post.authorID { dismiss() }
                    }
                }
            } message: {
                Text("You won’t see their posts or comments anymore. They aren’t told.")
            }
        }
    }

    /// The post being discussed, set like a quotation above the thread.
    private var original: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                AvatarView(url: feed.avatarURL(post.author.avatarPath), username: post.username,
                           tier: post.author.borderTier, special: post.author.special, size: 30)
                Text(post.username).font(.subheadline.weight(.semibold)).memberName(post.author.special)
                Text(post.createdAt.formatted(.relative(presentation: .numeric, unitsStyle: .narrow)))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            if !post.body.isEmpty {
                Text(post.body)
                    .font(.system(size: 19, design: .serif))
                    .lineSpacing(3)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(post.mediaKind == .video ? "A video" : "A photo",
                      systemImage: post.mediaKind == .video ? "video" : "photo")
                    .font(.subheadline).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 12) {
                Text(comments.isEmpty ? "THE THREAD" : "\(comments.count) \(comments.count == 1 ? "COMMENT" : "COMMENTS")")
                    .font(.caption2.weight(.semibold)).tracking(2.2)
                    .foregroundStyle(Theme.muted)
                    .fixedSize()
                Rectangle().fill(Theme.ink.opacity(0.12)).frame(height: 0.5)
            }
            .padding(.top, 8)
        }
    }

    private func row(_ comment: FeedComment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { viewingMember = comment.author } label: {
                AvatarView(url: feed.avatarURL(comment.author.avatarPath), username: comment.username,
                           tier: comment.author.borderTier, special: comment.author.special, size: 34)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Button { viewingMember = comment.author } label: {
                        Text(comment.username).font(.footnote.weight(.semibold)).memberName(comment.author.special)
                    }
                    .buttonStyle(.plain)
                    Text(comment.createdAt.formatted(.relative(presentation: .numeric, unitsStyle: .narrow)))
                        .font(.caption).foregroundStyle(Theme.muted)
                    Spacer(minLength: 0)
                }
                Text(comment.body).font(.subheadline)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if feed.canDelete(comment, on: post) || !feed.isMine(comment) {
                Button { actionsFor = comment } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .frame(width: 32, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More for this comment")
                .nagisenActions(isPresented: Binding(get: { actionsFor?.id == comment.id },
                                                     set: { if !$0 { actionsFor = nil } }),
                                title: "Comment") {
                    var actions: [NagisenAction] = []
                    if !feed.isMine(comment) {
                        actions.append(NagisenAction(title: "Report comment", symbol: "flag") { reporting = comment })
                        actions.append(NagisenAction(title: "Block @\(comment.username)", symbol: "hand.raised",
                                                 destructive: true) { blocking = comment })
                    }
                    if feed.canDelete(comment, on: post) {
                        actions.append(NagisenAction(title: "Delete comment", symbol: "trash", destructive: true) { deleting = comment })
                    }
                    return actions
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            text.count <= FeedRules.maxCommentLength && !feed.isBusy
    }

    private var composerBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.ink.opacity(0.10)).frame(height: 0.5)
            HStack(alignment: .center, spacing: 12) {
                AvatarView(url: feed.avatarURL(feed.avatarPath), username: feed.username ?? "",
                           tier: feed.borderTier, special: feed.specialBorder, size: 32)
                TextField("Add a comment…", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .font(.subheadline)
                    .padding(.vertical, 10)
                Button {
                    Task {
                        if let saved = await feed.addComment(text, to: post) {
                            withAnimation(.smooth(duration: 0.25)) { comments.append(saved) }
                            text = ""
                        }
                    }
                } label: {
                    Group {
                        if feed.isBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up").font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Theme.accent, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(canSend || feed.isBusy ? 1 : 0)
                .animation(.smooth(duration: 0.2), value: canSend)
                .disabled(!canSend)
                .accessibilityLabel("Send comment")
            }
            .padding(.leading, 20).padding(.trailing, 10)
            .padding(.vertical, 4)
        }
        .foregroundStyle(Theme.ink)
        .background(Theme.paper)
    }
}
