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
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .background(NagisenBackdrop())
            .foregroundStyle(Theme.ink)
            .nagisenSheetBar(rulesAccepted ? "New post" : "Community rules",
                             onClose: { showingComposer = false },
                             actionTitle: rulesAccepted ? "Share" : nil, actionEnabled: canPost,
                             busy: feed.isBusy, onAction: rulesAccepted ? publish : nil)
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
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    AvatarView(url: feed.avatarURL(feed.avatarPath), username: feed.username ?? "",
                               tier: feed.borderTier, special: feed.specialBorder, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feed.username ?? "").font(.subheadline.weight(.semibold)).memberName(feed.specialBorder)
                        Text("Shared with NAGISEN members").font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("What did you do today?")
                            .font(.system(size: 22, design: .serif))
                            .foregroundStyle(Theme.muted.opacity(0.7))
                            .padding(.top, 8).padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(.system(size: 19, design: .serif))
                        .lineSpacing(3)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 140, maxHeight: 260)
                }
                HStack {
                    Rectangle().fill(Theme.ink.opacity(0.10)).frame(height: 0.5)
                    Text("\(text.count) / \(FeedRules.maxBodyLength.formatted())")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(text.count > FeedRules.maxBodyLength ? Theme.accentText : Theme.muted)
                        .fixedSize()
                }
                if let message = feed.message {
                    Text(message)
                        .font(.subheadline).foregroundStyle(Theme.accentText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                attachmentRow
                Button { saveDraft() } label: {
                    Label("Keep as a private draft", systemImage: "tray.and.arrow.down")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
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
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                case .video:
                    FeedVideo(url: attachment.fileURL)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                Button { clearAttachment() } label: {
                    Label("Remove \(attachment.kind == .photo ? "photo" : "video")", systemImage: "xmark")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
            }
        } else if preparingMedia {
            HStack(spacing: 10) {
                ProgressView()
                Text("Preparing…").font(.subheadline).foregroundStyle(Theme.muted)
            }
        } else {
            PhotosPicker(selection: $pickedItem, matching: .any(of: [.images, .videos])) {
                HStack(spacing: 14) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(Theme.accentText)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().strokeBorder(Theme.accentText.opacity(0.35), lineWidth: 0.5))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add a photo or video").font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                        Text("One photo, or a video up to 60 seconds").font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .nagisenPanel(cornerRadius: 18)
            }
            .buttonStyle(.plain)
        }
        if let mediaError {
            Text(mediaError).font(.caption).foregroundStyle(Theme.accentText)
        }
    }

    private var canPost: Bool {
        !(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachment == nil) &&
            text.count <= FeedRules.maxBodyLength && !feed.isBusy && !preparingMedia
    }

    private func publish() {
        Task {
            if await feed.publish(text, attachment: attachment) {
                let posted = text.trimmingCharacters(in: .whitespacesAndNewlines)
                savedDrafts = (try? JSONEncoder().encode(drafts.filter { $0.text != posted })) ?? savedDrafts
                text = ""
                showingComposer = false
            }
        }
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
