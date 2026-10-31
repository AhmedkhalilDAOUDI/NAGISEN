import AVKit
import PhotosUI
import SwiftUI

private struct FeedDraft: Identifiable, Codable {
    var id = UUID()
    var text: String
    var createdAt = Date.now
}

struct SocialFeedView: View {
    @EnvironmentObject private var feed: FeedService
    @AppStorage("nagisen.feed.drafts") private var savedDrafts = Data()
    @AppStorage("nagisen.community.rulesAccepted") private var rulesAccepted = false
    @State private var showingComposer = false
    @State private var showingAccount = false
    @State private var text = ""
    @State private var pickedItem: PhotosPickerItem?
    @State private var attachment: PostAttachment?
    @State private var preparingMedia = false
    @State private var mediaError: String?
    @State private var deletingPost: FeedPost?
    @State private var reportingPost: FeedPost?
    @State private var blockingPost: FeedPost?
    @State private var commentingPost: FeedPost?
    @State private var viewingMember: FeedMember?

    private var drafts: [FeedDraft] {
        (try? JSONDecoder().decode([FeedDraft].self, from: savedDrafts)) ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    NagisenPageHeading(kicker: "NAGISEN COMMUNITY", title: "Feed",
                                       subtitle: "The people who keep you moving.", accent: Theme.protein)
                    accountCard

                    if let message = feed.message {
                        Text(message).font(.subheadline).foregroundStyle(Theme.accentText)
                    }
                    if feed.state == .ready {
                        if feed.posts.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("The first page is yours to write")
                                    .font(.system(size: 23, design: .serif))
                                Text("Share a workout, a meal you made, or a small win.")
                                    .font(.subheadline).foregroundStyle(Theme.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accentCardStyle(Theme.slate)
                        } else {
                            ForEach(feed.posts) { post in postCard(post) }
                            if feed.canLoadMore {
                                Button("Load more posts") { Task { await feed.loadMore() } }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.accentText)
                            }
                        }
                    }
                    if !drafts.isEmpty {
                        Text("YOUR PRIVATE DRAFTS")
                            .font(.caption2.weight(.semibold)).tracking(2)
                            .foregroundStyle(Theme.muted)
                        ForEach(drafts) { draft in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(draft.text).font(.subheadline)
                                HStack(spacing: 22) {
                                    Button("Edit") { text = draft.text; showingComposer = true }
                                    Button("Delete", role: .destructive) { deleteDraft(draft) }
                                }
                                .font(.caption.weight(.semibold))
                            }
                            .accentCardStyle(Theme.slate)
                        }
                    }
                }
                .foregroundStyle(Theme.ink)
                .padding(18)
                .padding(.bottom, 100)
            }
            .refreshable { await feed.refresh() }
            .task { await feed.refresh() }
            .scrollClipDisabled()
            .softTopScrollEdgeEffect()
            .background(NagisenBackdrop())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingComposer, onDismiss: clearAttachment) {
                composer.onAppear { feed.message = nil }
            }
            .sheet(isPresented: $showingAccount) {
                if feed.state == .ready {
                    NavigationStack { AccountSettingsView(inSheet: true) }
                } else {
                    FeedAccountView()
                }
            }
            .sheet(item: $commentingPost) { PostCommentsView(post: $0) }
            .sheet(item: $viewingMember) { MemberCardView(member: $0) }
            .confirmationDialog("Delete this post for everyone?", isPresented: Binding(
                get: { deletingPost != nil }, set: { if !$0 { deletingPost = nil } }
            )) {
                Button("Delete post", role: .destructive) {
                    guard let post = deletingPost else { return }
                    deletingPost = nil
                    Task { await feed.delete(post) }
                }
            }
            .confirmationDialog("Why are you reporting this post?", isPresented: Binding(
                get: { reportingPost != nil }, set: { if !$0 { reportingPost = nil } }
            ), titleVisibility: .visible) {
                ForEach(FeedRules.reportReasons, id: \.self) { reason in
                    Button(reason) {
                        guard let post = reportingPost else { return }
                        reportingPost = nil
                        Task { await feed.report(post, reason: reason) }
                    }
                }
            } message: {
                Text("The post will be hidden from your feed and sent for review.")
            }
            .confirmationDialog("Block @\(blockingPost?.username ?? "member")?", isPresented: Binding(
                get: { blockingPost != nil }, set: { if !$0 { blockingPost = nil } }
            ), titleVisibility: .visible) {
                Button("Block", role: .destructive) {
                    guard let post = blockingPost else { return }
                    blockingPost = nil
                    Task { await feed.block(post) }
                }
            } message: {
                Text("You won’t see their posts anymore. They aren’t told.")
            }
        }
    }

    // MARK: - Account card

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch feed.state {
            case .notConfigured:
                Label("Feed isn’t set up in this build.", systemImage: "person.crop.circle")
                    .font(.subheadline)
            case .signedOut, .needsUsername:
                Text(feed.state == .signedOut ? "Create an account to share workouts, meals and small wins with NAGISEN members."
                                              : "Choose a username to finish setting up your account.")
                    .font(.subheadline)
                NagisenPrimaryButton(feed.state == .signedOut ? "Sign in or create an account" : "Choose a username") {
                    showingAccount = true
                }
            case .ready:
                HStack {
                    Label("@\(feed.username ?? "")", systemImage: "person.crop.circle")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Account") { showingAccount = true }
                        .font(.subheadline).foregroundStyle(Theme.accentText)
                }
                Button { showingComposer = true } label: {
                    HStack {
                        Text("Share a moment")
                        Spacer()
                        Image(systemName: "square.and.pencil")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                if feed.blockedCount > 0 {
                    HStack {
                        Text(feed.blockedCount == 1 ? "1 person blocked" : "\(feed.blockedCount) people blocked")
                        Spacer()
                        Button("Unblock all") { Task { await feed.unblockEveryone() } }
                            .foregroundStyle(Theme.accentText)
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                }
            }
            Text("Posts are visible to signed-in NAGISEN members. Your food and workout history stays on this iPhone and in your private iCloud backup.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
        .accentCardStyle(Theme.protein)
    }

    // MARK: - Posts

    private func postCard(_ post: FeedPost) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Button { viewingMember = post.author } label: {
                    HStack(spacing: 10) {
                        AvatarView(url: feed.avatarURL(post.author.avatarPath), username: post.username,
                                   tier: post.author.borderTier, special: post.author.special, size: 34)
                        Text("@\(post.username)").font(.subheadline.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Text(post.createdAt, style: .relative)
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            if !post.body.isEmpty {
                Text(post.body).font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url = feed.mediaURL(for: post) {
                switch post.mediaKind {
                case .photo:
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        case .failure:
                            Label("Photo unavailable", systemImage: "photo")
                                .font(.caption).foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity, minHeight: 120)
                        default:
                            ProgressView().frame(maxWidth: .infinity, minHeight: 220)
                        }
                    }
                    .frame(maxHeight: 460)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                case .video:
                    FeedVideo(url: url)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                case nil:
                    EmptyView()
                }
            }
            HStack(spacing: 20) {
                Button { commentingPost = post } label: {
                    Label(post.commentCount == 0 ? "Comment" : "\(post.commentCount)", systemImage: "bubble.left")
                }
                .accessibilityLabel(post.commentCount == 1 ? "1 comment" : "\(post.commentCount) comments")
                if !post.body.isEmpty {
                    ShareLink(item: post.body) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                if feed.isMine(post) {
                    Button(role: .destructive) { deletingPost = post } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } else {
                    Spacer()
                    Menu {
                        Button("Report post", systemImage: "flag") { reportingPost = post }
                        Button("Block @\(post.username)", systemImage: "hand.raised",
                               role: .destructive) { blockingPost = post }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 32, height: 24)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("More for this post")
                }
            }
            .font(.caption.weight(.medium))
        }
        .accentCardStyle(Theme.slate)
    }

    // MARK: - Composer

    private var composer: some View {
        NavigationStack {
            Group {
                if rulesAccepted { composerForm } else { communityRules }
            }
            .padding(20)
            .background(NagisenBackdrop())
            .navigationTitle(rulesAccepted ? "New post" : "Community rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingComposer = false }
                }
                if rulesAccepted {
                    ToolbarItem(placement: .confirmationAction) { postButton }
                }
            }
        }
    }

    private var communityRules: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Before your first post")
                .font(.system(size: 25, design: .serif))
            Text("Feed is shared with every NAGISEN member. There is no tolerance for abusive, hateful, sexual, violent or spam content. Posts that break these rules are removed, and people who post them can be blocked from the community.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Text("You can report any post or block anyone from the menu on their post.")
                .font(.caption).foregroundStyle(Theme.muted)
            Button { rulesAccepted = true } label: {
                Text("I agree")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    private var composerForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("What did you do today?")
                    .font(.system(size: 25, design: .serif))
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 130, maxHeight: 220)
                    .nagisenGlass(in: RoundedRectangle(cornerRadius: 15), tint: Theme.surface.opacity(0.18))
                Text("\(text.count)/1,000 · Visible to signed-in members in Feed.")
                    .font(.caption).foregroundStyle(Theme.muted)
                if let message = feed.message {
                    Text(message)
                        .font(.subheadline).foregroundStyle(Theme.accentText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                attachmentRow
                Button("Save private draft") { saveDraft() }
                    .font(.subheadline).foregroundStyle(Theme.accentText)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task { await prepare(item) }
        }
    }

    @ViewBuilder
    private var attachmentRow: some View {
        if let attachment {
            VStack(alignment: .leading, spacing: 10) {
                switch attachment.kind {
                case .photo:
                    if let image = UIImage(contentsOfFile: attachment.fileURL.path) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                case .video:
                    FeedVideo(url: attachment.fileURL)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Button("Remove \(attachment.kind == .photo ? "photo" : "video")", role: .destructive) {
                    clearAttachment()
                }
                .font(.subheadline)
            }
        } else if preparingMedia {
            HStack(spacing: 10) {
                ProgressView()
                Text("Preparing…").font(.subheadline).foregroundStyle(Theme.muted)
            }
        } else {
            PhotosPicker(selection: $pickedItem, matching: .any(of: [.images, .videos])) {
                Label("Add a photo or video", systemImage: "photo.on.rectangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
            }
            Text("One photo, or one video up to 60 seconds.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
        if let mediaError {
            Text(mediaError).font(.caption).foregroundStyle(Theme.accentText)
        }
    }

    @ViewBuilder
    private var postButton: some View {
        if feed.isBusy {
            ProgressView()
        } else {
            sendButton
        }
    }

    private var sendButton: some View {
        Button("Post") {
            Task {
                if await feed.publish(text, attachment: attachment) {
                    let posted = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    savedDrafts = (try? JSONEncoder().encode(drafts.filter { $0.text != posted })) ?? savedDrafts
                    text = ""
                    showingComposer = false
                }
            }
        }
        .disabled((text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachment == nil) ||
                  text.count > FeedRules.maxBodyLength || feed.isBusy || preparingMedia)
    }

    private func prepare(_ item: PhotosPickerItem) async {
        preparingMedia = true
        mediaError = nil
        defer { preparingMedia = false; pickedItem = nil }
        do {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                    throw PostMediaError.unreadable
                }
                defer { try? FileManager.default.removeItem(at: movie.url) }
                attachment = try await PostMedia.video(at: movie.url)
            } else {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw PostMediaError.unreadable
                }
                attachment = try PostMedia.photo(from: data)
            }
        } catch {
            mediaError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func clearAttachment() {
        if let attachment { try? FileManager.default.removeItem(at: attachment.fileURL) }
        attachment = nil
        mediaError = nil
    }

    private func saveDraft() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        savedDrafts = (try? JSONEncoder().encode([FeedDraft(text: trimmed)] +
                    drafts.filter { $0.text != trimmed })) ?? savedDrafts
        text = ""
        showingComposer = false
    }

    private func deleteDraft(_ draft: FeedDraft) {
        savedDrafts = (try? JSONEncoder().encode(drafts.filter { $0.id != draft.id })) ?? savedDrafts
    }
}

/// A video that plays only when tapped and stops when it scrolls away.
private struct FeedVideo: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear { if player == nil { player = AVPlayer(url: url) } }
            .onDisappear { player?.pause() }
    }
}
