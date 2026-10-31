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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("@\(post.username)").font(.subheadline.weight(.semibold))
                        if !post.body.isEmpty {
                            Text(post.body).font(.subheadline).lineLimit(4)
                        } else {
                            Label(post.mediaKind == .video ? "Video" : "Photo",
                                  systemImage: post.mediaKind == .video ? "video" : "photo")
                                .font(.subheadline).foregroundStyle(Theme.muted)
                        }
                    }
                    .softCardStyle()

                    if loading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
                    } else if comments.isEmpty {
                        Text("No comments yet. Start the conversation.")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                    } else {
                        ForEach(comments) { comment in row(comment) }
                    }
                    if let message = feed.message {
                        Text(message).font(.subheadline).foregroundStyle(Theme.accentText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundStyle(Theme.ink)
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) { composerBar }
            .background(NagisenBackdrop())
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                feed.message = nil
                comments = await feed.comments(on: post) ?? []
                loading = false
            }
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

    private func row(_ comment: FeedComment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("@\(comment.username)").font(.caption.weight(.semibold))
                Text(comment.createdAt, style: .relative)
                    .font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                if feed.canDelete(comment, on: post) || !feed.isMine(comment) {
                    Menu {
                        if feed.canDelete(comment, on: post) {
                            Button("Delete comment", systemImage: "trash", role: .destructive) { deleting = comment }
                        }
                        if !feed.isMine(comment) {
                            Button("Report comment", systemImage: "flag") { reporting = comment }
                            Button("Block @\(comment.username)", systemImage: "hand.raised",
                                   role: .destructive) { blocking = comment }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption)
                            .frame(width: 30, height: 22)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("More for this comment")
                }
            }
            Text(comment.body).font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var composerBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Add a comment", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .font(.subheadline)
            Button {
                Task {
                    if let saved = await feed.addComment(text, to: post) {
                        comments.append(saved)
                        text = ""
                    }
                }
            } label: {
                if feed.isBusy {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                }
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                      text.count > FeedRules.maxCommentLength || feed.isBusy)
            .accessibilityLabel("Send comment")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .nagisenGlass(in: RoundedRectangle(cornerRadius: 22), tint: Theme.surface.opacity(0.18))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}
