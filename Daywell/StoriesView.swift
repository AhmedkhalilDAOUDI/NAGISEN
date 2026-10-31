import AVFoundation
import PhotosUI
import SwiftUI

/// The row of story circles at the top of Feed: yours first (with + to add), then people you follow.
struct StoriesBar: View {
    @EnvironmentObject private var feed: FeedService
    @State private var opening: StoryStart?
    @State private var picked: PhotosPickerItem?
    @State private var preparing = false

    struct StoryStart: Identifiable { let index: Int; var id: Int { index } }

    private var myIndex: Int? { feed.storyGroups.firstIndex { feed.isMe($0.member) } }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                myCircle
                ForEach(Array(feed.storyGroups.enumerated()), id: \.element.id) { index, group in
                    if !feed.isMe(group.member) {
                        Button { opening = StoryStart(index: index) } label: {
                            circle(group.member, unseen: group.hasUnseen(feed.seenStories), label: group.member.username)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .fullScreenCover(item: $opening) { StoryViewer(groups: feed.storyGroups, startGroup: $0.index) }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task { await post(item) }
        }
    }

    @ViewBuilder
    private var myCircle: some View {
        let me = feed.me
        ZStack(alignment: .bottomTrailing) {
            if let myIndex {
                Button { opening = StoryStart(index: myIndex) } label: {
                    circle(me, unseen: feed.storyGroups[myIndex].hasUnseen(feed.seenStories), label: "Your story")
                }
                .buttonStyle(.plain)
            } else {
                PhotosPicker(selection: $picked, matching: .any(of: [.images, .videos])) {
                    circle(me, unseen: false, label: "Your story")
                }
            }
            PhotosPicker(selection: $picked, matching: .any(of: [.images, .videos])) {
                Group {
                    if preparing || feed.isBusy {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "plus").font(.caption.weight(.bold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 22, height: 22)
                .background(Theme.accent, in: Circle())
                .overlay(Circle().strokeBorder(Theme.paper, lineWidth: 2))
            }
            .offset(x: -4, y: -20)
            .accessibilityLabel("Add to your story")
        }
    }

    private func circle(_ member: FeedMember?, unseen: Bool, label: String) -> some View {
        VStack(spacing: 5) {
            AvatarView(url: feed.avatarURL(member?.avatarPath), username: member?.username ?? "",
                       tier: member?.borderTier ?? .none, special: member?.special, size: 60)
                .padding(4)
                .overlay {
                    Circle().strokeBorder(unseen
                        ? AnyShapeStyle(AngularGradient(colors: [Theme.red, Theme.accentText, Theme.red], center: .center))
                        : AnyShapeStyle(Theme.line), lineWidth: unseen ? 2.5 : 1)
                }
            Text(label).font(.caption2).lineLimit(1).frame(width: 72)
        }
        .foregroundStyle(Theme.ink)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(unseen ? "\(label), new story" : label)
    }

    private func post(_ item: PhotosPickerItem) async {
        preparing = true
        defer { preparing = false; picked = nil }
        do {
            let attachment: PostAttachment
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                guard let movie = try await item.loadTransferable(type: PickedMovie.self) else { throw PostMediaError.unreadable }
                defer { try? FileManager.default.removeItem(at: movie.url) }
                attachment = try await PostMedia.video(at: movie.url)
            } else {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw PostMediaError.unreadable }
                attachment = try PostMedia.photo(from: data)
            }
            _ = await feed.addStory(attachment)
            try? FileManager.default.removeItem(at: attachment.fileURL)
            if let poster = attachment.posterURL { try? FileManager.default.removeItem(at: poster) }
        } catch {
            feed.message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Full-screen stories: tap right for next, left for previous, hold to pause, swipe down to close.
struct StoryViewer: View {
    let groups: [StoryGroup]
    @EnvironmentObject private var feed: FeedService
    @Environment(\.dismiss) private var dismiss
    @State private var groupIndex: Int
    @State private var storyIndex: Int
    @State private var progress = 0.0
    @State private var paused = false
    @State private var dragOffset: CGFloat = 0
    @State private var showingViewers = false
    @State private var viewerCount: Int?
    @State private var reporting = false
    @State private var confirmingDelete = false

    /// How long a photo stays up.
    static let photoSeconds = 6.0

    init(groups: [StoryGroup], startGroup: Int) {
        self.groups = groups
        _groupIndex = State(initialValue: startGroup)
        _storyIndex = State(initialValue: 0)
    }

    private var group: StoryGroup? { groups.indices.contains(groupIndex) ? groups[groupIndex] : nil }
    private var story: FeedStory? {
        guard let group, group.stories.indices.contains(storyIndex) else { return nil }
        return group.stories[storyIndex]
    }
    private var isMine: Bool { story.map { feed.isMe($0.author) } ?? false }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let story, let url = feed.storyMediaURL(story) {
                Group {
                    if story.mediaKind == .video {
                        LoopingVideo(url: url, startsMuted: false)
                    } else {
                        RemoteImage(url: url, contentMode: .fit)
                    }
                }
                .id(story.id)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.top, 8)
            }
            tapZones
            VStack(spacing: 10) {
                bars
                header
                Spacer()
                if isMine { seenBy }
            }
            .padding(.horizontal, 10)
        }
        .offset(y: dragOffset)
        .gesture(DragGesture().onChanged { dragOffset = max(0, $0.translation.height) }
            .onEnded { $0.translation.height > 120 ? dismiss() : withAnimation(.smooth) { dragOffset = 0 } })
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onAppear { if let group { storyIndex = group.startIndex(feed.seenStories) } }
        .task(id: story?.id) { await play() }
        .sheet(isPresented: $showingViewers, onDismiss: { paused = false }) {
            if let story { PeopleListView(title: "Seen by") { await feed.viewers(of: story) } }
        }
        .confirmationDialog("Why are you reporting this story?", isPresented: $reporting, titleVisibility: .visible) {
            ForEach(FeedRules.reportReasons, id: \.self) { reason in
                Button(reason) { if let story { Task { await feed.reportStory(story, reason: reason); next() } } }
            }
        }
        .confirmationDialog("Delete this story?", isPresented: $confirmingDelete) {
            Button("Delete story", role: .destructive) {
                if let story { Task { await feed.deleteStory(story); dismiss() } }
            }
        }
        .onChange(of: reporting || confirmingDelete) { _, open in paused = open }
    }

    private var bars: some View {
        HStack(spacing: 4) {
            ForEach(Array((group?.stories ?? []).enumerated()), id: \.element.id) { index, _ in
                GeometryReader { geometry in
                    Capsule().fill(.white.opacity(0.3))
                        .overlay(alignment: .leading) {
                            Capsule().fill(.white)
                                .frame(width: geometry.size.width * (index < storyIndex ? 1 : index == storyIndex ? progress : 0))
                        }
                }
                .frame(height: 2.5)
            }
        }
        .padding(.top, 8)
        .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let story {
                AvatarView(url: feed.avatarURL(story.author.avatarPath), username: story.author.username,
                           tier: story.author.borderTier, special: story.author.special, size: 32)
                Text(story.author.username).font(.subheadline.weight(.semibold))
                Text(story.createdAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Menu {
                if isMine {
                    Button("Delete story", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                } else if let story {
                    Button("Report story", systemImage: "flag") { reporting = true }
                    Button("Block @\(story.author.username)", systemImage: "hand.raised", role: .destructive) {
                        Task { await feed.block(authorID: story.authorID); await feed.loadStories(); dismiss() }
                    }
                }
            } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44)
            }
            .accessibilityLabel("More for this story")
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
        }
        .foregroundStyle(.white)
    }

    private var seenBy: some View {
        Button { paused = true; showingViewers = true } label: {
            Label(viewerCount.map { "Seen by \($0)" } ?? "Seen by", systemImage: "eye")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).frame(height: 40)
                .background(.white.opacity(0.15), in: Capsule())
        }
        .padding(.bottom, 20)
    }

    /// Left third goes back, the rest goes forward; holding anywhere pauses.
    private var tapZones: some View {
        HStack(spacing: 0) {
            Color.clear.contentShape(Rectangle()).frame(maxWidth: .infinity)
                .onTapGesture { previous() }
                .onLongPressGesture(minimumDuration: 0.25, perform: {}, onPressingChanged: { paused = $0 })
                .accessibilityLabel("Previous story")
                .accessibilityAddTraits(.isButton)
            Color.clear.contentShape(Rectangle()).frame(maxWidth: .infinity).layoutPriority(1)
                .onTapGesture { next() }
                .onLongPressGesture(minimumDuration: 0.25, perform: {}, onPressingChanged: { paused = $0 })
                .accessibilityLabel("Next story")
                .accessibilityAddTraits(.isButton)
        }
    }

    private func play() async {
        guard let story else { return }
        progress = 0
        await feed.markSeen(story)
        if isMine { viewerCount = await feed.viewers(of: story).count }
        var seconds = Self.photoSeconds
        if story.mediaKind == .video, let url = feed.storyMediaURL(story),
           let duration = try? await AVURLAsset(url: url).load(.duration).seconds, duration.isFinite, duration > 0 {
            seconds = min(duration, PostMedia.maxVideoSeconds)
        }
        let step = 0.05
        while progress < 1 {
            try? await Task.sleep(for: .seconds(step))
            if Task.isCancelled { return }
            if !paused { progress = min(1, progress + step / seconds) }
        }
        next()
    }

    private func next() {
        guard let group else { return dismiss() }
        if storyIndex + 1 < group.stories.count {
            storyIndex += 1
        } else if groupIndex + 1 < groups.count {
            groupIndex += 1
            storyIndex = groups[groupIndex].startIndex(feed.seenStories)
        } else {
            dismiss()
        }
    }

    private func previous() {
        if storyIndex > 0 {
            storyIndex -= 1
        } else if groupIndex > 0 {
            groupIndex -= 1
            storyIndex = 0
        } else {
            progress = 0
        }
    }
}
