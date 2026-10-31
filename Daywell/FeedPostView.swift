import AVFoundation
import SwiftUI
import UIKit

// MARK: - Images

/// Loads a remote image once per launch and keeps it, so scrolling back doesn't refetch.
@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    func image(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> UIImage? {
        if let cached = image(for: url) { return cached }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// A remote photo that knows its own shape once loaded.
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Theme.surface.opacity(0.35))
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            }
        }
        .task(id: url) {
            guard let url else { return }
            image = ImageCache.shared.image(for: url)
            if image == nil { image = await ImageCache.shared.load(url) }
        }
    }
}

// MARK: - Video

/// A muted, looping video without controls, as posts play in a feed. Tap toggles the sound.
struct LoopingVideo: View {
    let url: URL
    var startsMuted = true
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var muted = true

    var body: some View {
        PlayerLayerView(player: player)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.45), in: Circle())
                    .padding(10)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                muted.toggle()
                player?.isMuted = muted
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(muted ? "Video, muted. Tap for sound" : "Video with sound. Tap to mute")
            .onAppear {
                if player == nil {
                    let queue = AVQueuePlayer()
                    looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
                    muted = startsMuted
                    queue.isMuted = muted
                    player = queue
                }
                player?.play()
            }
            .onDisappear { player?.pause() }
    }
}

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer?

    final class LayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        view.playerLayer.player = player
    }
}

// MARK: - Post

/// A post the way a photo feed shows it: who, the media full width, then likes and caption.
struct FeedPostView: View {
    @EnvironmentObject private var feed: FeedService
    @State private var post: FeedPost
    @State private var photo: UIImage?
    @State private var heartVisible = false
    @State private var showingComments = false
    @State private var showingLikers = false
    @State private var viewingMember: FeedMember?
    @State private var confirmingDelete = false
    @State private var editing = false
    @State private var showingActions = false
    @State private var reporting = false
    @State private var confirmingBlock = false
    @State private var captionExpanded = false
    var onRemoved: (() -> Void)?

    init(post: FeedPost, onRemoved: (() -> Void)? = nil) {
        _post = State(initialValue: post)
        self.onRemoved = onRemoved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            media
            VStack(alignment: .leading, spacing: 7) {
                actions
                if post.likeCount > 0 {
                    Button { showingLikers = true } label: {
                        Text(post.likeCount == 1 ? "1 like" : "\(post.likeCount.formatted()) likes")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                }
                if !post.body.isEmpty && post.mediaPath != nil { caption }
                if post.commentCount > 0 {
                    Button { showingComments = true } label: {
                        Text(post.commentCount == 1 ? "View 1 comment" : "View all \(post.commentCount) comments")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                }
                Text(post.createdAt, format: .relative(presentation: .named))
                    .font(.caption2).foregroundStyle(Theme.muted)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
        }
        .foregroundStyle(Theme.ink)
        .padding(.bottom, 18)
        .onChange(of: feed.posts.first { $0.id == post.id }) { _, latest in
            if let latest { post = latest }
        }
        .sheet(isPresented: $showingComments) { PostCommentsView(post: post) }
        .sheet(isPresented: $showingLikers) {
            PeopleListView(title: "Likes") { await feed.likers(of: post) }
        }
        .sheet(item: $viewingMember) { MemberPageView(member: $0) }
        .sheet(isPresented: $editing) { EditPostView(post: post) { post = $0 } }
        .confirmationDialog("Delete this post?", isPresented: $confirmingDelete) {
            Button("Delete post", role: .destructive) {
                Task { await feed.delete(post); onRemoved?() }
            }
        }
        .confirmationDialog("Why are you reporting this post?", isPresented: $reporting, titleVisibility: .visible) {
            ForEach(FeedRules.reportReasons, id: \.self) { reason in
                Button(reason) { Task { await feed.report(post, reason: reason); onRemoved?() } }
            }
        } message: {
            Text("The post will be hidden from your feed and sent for review.")
        }
        .confirmationDialog("Block @\(post.username)?", isPresented: $confirmingBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) { Task { await feed.block(post); onRemoved?() } }
        } message: {
            Text("You won’t see their posts, comments or stories anymore. They aren’t told.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { viewingMember = post.author } label: {
                HStack(spacing: 10) {
                    AvatarView(url: feed.avatarURL(post.author.avatarPath), username: post.username,
                               tier: post.author.borderTier, special: post.author.special, size: 34)
                    Text(post.username).font(.subheadline.weight(.semibold)).memberName(post.author.special)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button { showingActions = true } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More for this post")
            .nagisenActions(isPresented: $showingActions, title: feed.isMine(post) ? "Your post" : "@\(post.username)") {
                if feed.isMine(post) {
                    return [NagisenAction(title: "Edit post", symbol: "pencil") { editing = true },
                            NagisenAction(title: "Delete post", symbol: "trash", destructive: true) { confirmingDelete = true }]
                }
                var actions: [NagisenAction] = []
                if feed.isFollowing(post.author) {
                    actions.append(NagisenAction(title: "Unfollow", symbol: "person.badge.minus") {
                        Task { await feed.unfollow(post.author) }
                    })
                }
                actions.append(NagisenAction(title: "Report post", symbol: "flag") { reporting = true })
                actions.append(NagisenAction(title: "Block", symbol: "hand.raised", destructive: true) { confirmingBlock = true })
                return actions
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var media: some View {
        Group {
            if let url = feed.mediaURL(for: post), post.mediaKind == .video {
                LoopingVideo(url: url)
                    .aspectRatio(4.0 / 5.0, contentMode: .fit)
            } else if let url = feed.mediaURL(for: post) {
                ZStack {
                    Rectangle().fill(Theme.surface.opacity(0.35))
                    if let photo { Image(uiImage: photo).resizable().scaledToFill() }
                }
                .aspectRatio(photo.map { PostMedia.feedAspectRatio(width: $0.size.width, height: $0.size.height) } ?? 4.0 / 5.0,
                             contentMode: .fit)
                .clipped()
                .task(id: url) {
                    photo = ImageCache.shared.image(for: url)
                    if photo == nil { photo = await ImageCache.shared.load(url) }
                }
                .accessibilityLabel("Photo by @\(post.username)")
            } else {
                // Text on the page itself, set like the comments view, rather than a card.
                Text(post.body)
                    .font(.system(size: 19, design: .serif))
                    .lineSpacing(3)
                    .lineLimit(captionExpanded ? nil : 10)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 4).padding(.bottom, 6)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.smooth(duration: 0.2)) { captionExpanded = true } }
            }
        }
        .frame(maxWidth: .infinity)
        .overlay {
            Image(systemName: "heart.fill")
                .font(.system(size: 92))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.25), radius: 12)
                .scaleEffect(heartVisible ? 1 : 0.4)
                .opacity(heartVisible ? 1 : 0)
                .allowsHitTesting(false)
        }
        .onTapGesture(count: 2) { doubleTapLike() }
        .accessibilityAction(named: "Like") { doubleTapLike() }
    }

    private var actions: some View {
        HStack(spacing: 18) {
            Button { Task { post = await feed.toggleLike(post) } } label: {
                Image(systemName: post.likedByMe ? "heart.fill" : "heart")
                    .foregroundStyle(post.likedByMe ? Theme.red : Theme.ink)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(post.likedByMe ? "Unlike" : "Like")
            .sensoryFeedback(.impact(weight: .light), trigger: post.likedByMe)
            Button { showingComments = true } label: { Image(systemName: "bubble.right") }
                .accessibilityLabel("Comments")
            ShareLink(item: feed.mediaURL(for: post)?.absoluteString ?? post.body) {
                Image(systemName: "paperplane")
            }
            .accessibilityLabel("Share")
            Spacer()
        }
        .font(.system(size: 22))
        .buttonStyle(.plain)
        .frame(minHeight: 40)
    }

    private var caption: some View {
        (nameText(post.username, post.author.special).fontWeight(.semibold) + Text(" ") + Text(post.body))
            .font(.subheadline)
            .lineLimit(captionExpanded ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
            .onTapGesture { withAnimation(.smooth(duration: 0.2)) { captionExpanded = true } }
    }

    private func doubleTapLike() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { heartVisible = true }
        Task {
            post = await feed.like(post)
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeOut(duration: 0.25)) { heartVisible = false }
        }
    }
}

/// A text-only post as a profile grid tile, the same shape as photos so the grid stays even.
struct QuoteCard: View {
    let text: String
    var compact = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.surface, Theme.paper], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(text)
                .font(.system(compact ? .caption : .title2, design: .serif))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(compact ? 5 : 12)
                .minimumScaleFactor(0.7)
                .padding(compact ? 10 : 32)
        }
    }
}

/// Edits the text of one of your posts. Photos and videos stay as posted.
struct EditPostView: View {
    let post: FeedPost
    let onSaved: (FeedPost) -> Void
    @EnvironmentObject private var feed: FeedService
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(post: FeedPost, onSaved: @escaping (FeedPost) -> Void) {
        self.post = post
        self.onSaved = onSaved
        _text = State(initialValue: post.body)
    }

    private var canSave: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed != post.body && trimmed.count <= FeedRules.maxBodyLength &&
            (!trimmed.isEmpty || post.mediaPath != nil) && !feed.isBusy
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TextEditor(text: $text)
                        .font(.system(size: 19, design: .serif))
                        .lineSpacing(3)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 180, maxHeight: 360)
                    HStack {
                        Rectangle().fill(Theme.ink.opacity(0.10)).frame(height: 0.5)
                        Text("\(text.count) / \(FeedRules.maxBodyLength.formatted())")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(text.count > FeedRules.maxBodyLength ? Theme.accentText : Theme.muted)
                            .fixedSize()
                    }
                    if post.mediaPath != nil {
                        Text("The \(post.mediaKind == .video ? "video" : "photo") stays as posted.")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    if let message = feed.message {
                        Text(message).font(.subheadline).foregroundStyle(Theme.accentText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 22).padding(.top, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(NagisenBackdrop())
            .nagisenSheetBar("Edit post", onClose: { dismiss() }, actionTitle: "Save", actionEnabled: canSave,
                             busy: feed.isBusy) {
                Task {
                    if let saved = await feed.edit(post, text: text) { onSaved(saved); dismiss() }
                }
            }
            .onAppear { feed.message = nil }
        }
    }
}

/// One post on its own screen, opened from a profile grid or Activity.
struct PostDetailView: View {
    let post: FeedPost
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                FeedPostView(post: post, onRemoved: { dismiss() })
            }
            .background(NagisenBackdrop())
            .nagisenSheetBar("Post", onClose: { dismiss() })
        }
    }
}
