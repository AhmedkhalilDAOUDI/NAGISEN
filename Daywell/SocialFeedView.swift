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
    @State private var viewingMember: FeedMember?
    @State private var showingActivity = false

    private var drafts: [FeedDraft] {
        (try? JSONDecoder().decode([FeedDraft].self, from: savedDrafts)) ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    topBar
                    if feed.state == .ready {
                        StoriesBar().padding(.vertical, 10)
                        modePicker
                        if let message = feed.message {
                            Text(message).font(.subheadline).foregroundStyle(Theme.accentText)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                        }
                        if feed.posts.isEmpty {
                            emptyFeed
                        } else {
                            ForEach(feed.posts) { post in
                                FeedPostView(post: post)
                                    .onAppear {
                                        if post.id == feed.posts.last?.id { Task { await feed.loadMore() } }
                                    }
                            }
                        }
                        draftsSection
                        if feed.blockedCount > 0 {
                            HStack {
                                Text(feed.blockedCount == 1 ? "1 person blocked" : "\(feed.blockedCount) people blocked")
                                Spacer()
                                Button("Unblock all") { Task { await feed.unblockEveryone() } }
                                    .foregroundStyle(Theme.accentText)
                            }
                            .font(.caption).foregroundStyle(Theme.muted)
                            .padding(16)
                        }
                    } else {
                        signedOutCard.padding(16)
                    }
                }
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 110)
            }
            .refreshable { await feed.refresh() }
            .task { await feed.refresh() }
            .onChange(of: feed.mode) { _, _ in Task { await feed.refresh() } }
            .softTopScrollEdgeEffect()
            .background(NagisenBackdrop())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingComposer, onDismiss: clearAttachment) {
                composer.onAppear { feed.message = nil }
            }
            .sheet(isPresented: $showingAccount) { FeedAccountView() }
            .sheet(item: $viewingMember) { MemberPageView(member: $0) }
            .sheet(isPresented: $showingActivity) { ActivityView() }
        }
    }

    // MARK: - Top

    private var topBar: some View {
        HStack(spacing: 4) {
            Text("Feed").font(.system(size: 30, design: .serif))
            Spacer()
            if feed.state == .ready {
                iconButton("plus.square", label: "New post") { showingComposer = true }
                iconButton("bell", label: feed.hasNewActivity ? "Activity, new" : "Activity") { showingActivity = true }
                    .overlay(alignment: .topTrailing) {
                        if feed.hasNewActivity {
                            Circle().fill(Theme.red).frame(width: 8, height: 8).offset(x: -10, y: 10)
                                .allowsHitTesting(false)
                        }
                    }
                Button { viewingMember = feed.me } label: {
                    AvatarView(url: feed.avatarURL(feed.avatarPath), username: feed.username ?? "",
                               tier: feed.borderTier, special: feed.specialBorder, size: 30)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Your profile")
            }
        }
        .padding(.leading, 16).padding(.trailing, 8).padding(.top, 8)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 21)).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(FeedService.FeedMode.allCases, id: \.self) { mode in
                Button { feed.mode = mode } label: {
                    VStack(spacing: 8) {
                        Text(mode.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(feed.mode == mode ? Theme.ink : Theme.muted)
                        Rectangle().fill(feed.mode == mode ? Theme.ink : Theme.line)
                            .frame(height: feed.mode == mode ? 1.5 : 0.5)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(feed.mode == mode ? .isSelected : [])
            }
        }
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var emptyFeed: some View {
        VStack(alignment: .leading, spacing: 10) {
            if feed.mode == .following {
                Text("Your feed is quiet")
                    .font(.system(size: 23, design: .serif))
                Text("Follow people to see their moments here, or share your own.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                NagisenPrimaryButton("Explore members") { feed.mode = .explore }
            } else {
                Text("The first page is yours to write")
                    .font(.system(size: 23, design: .serif))
                Text("Share a workout, a meal you made, or a small win.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                NagisenPrimaryButton("Share a moment") { showingComposer = true }
            }
        }
        .cardStyle()
        .padding(16)
    }

    private var signedOutCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if feed.state == .notConfigured {
                Label("Feed isn’t set up in this build.", systemImage: "person.crop.circle")
                    .font(.subheadline)
            } else {
                Text(feed.state == .signedOut ? "Create an account to share workouts, meals and small wins with NAGISEN members."
                                              : "Choose a username to finish setting up your account.")
                    .font(.subheadline)
                NagisenPrimaryButton(feed.state == .signedOut ? "Sign in or create an account" : "Choose a username") {
                    showingAccount = true
                }
            }
            Text("Posts are visible to signed-in NAGISEN members. Your food and workout history stays on this iPhone and in your private iCloud backup.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
        .cardStyle()
    }

    @ViewBuilder
    private var draftsSection: some View {
        if !drafts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
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
                    .softCardStyle()
                }
            }
            .padding(16)
        }
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
        if let poster = attachment?.posterURL { try? FileManager.default.removeItem(at: poster) }
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
