import SwiftUI

private struct FeedDraft: Identifiable, Codable {
    var id = UUID()
    var text: String
    var createdAt = Date.now
}

struct SocialFeedView: View {
    @EnvironmentObject private var community: CommunityCloud
    @AppStorage("nagisen.feed.drafts") private var savedDrafts = Data()
    @AppStorage("nagisen.community.name") private var displayName = ""
    @State private var showingComposer = false
    @State private var text = ""
    @State private var deletingPost: CommunityPost?

    private var drafts: [FeedDraft] {
        (try? JSONDecoder().decode([FeedDraft].self, from: savedDrafts)) ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    NagisenPageHeading(kicker: "NAGISEN COMMUNITY", title: "Feed",
                                       subtitle: "The people who keep you moving.", accent: Theme.protein)
                    VStack(alignment: .leading, spacing: 14) {
                        Label(community.accountMessage, systemImage: "person.crop.circle")
                            .font(.subheadline)
                        if community.accountReady {
                            TextField("Name shown with your posts", text: $displayName)
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                                .onChange(of: displayName) { _, value in
                                    if value.count > 40 { displayName = String(value.prefix(40)) }
                                }
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
                        .disabled(!community.accountReady ||
                                  displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                        Text("Posts are public to NAGISEN members. Your food and workout history stays in your private iCloud backup.")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    .accentCardStyle(Theme.protein)

                    if let message = community.feedMessage {
                        Text(message).font(.subheadline).foregroundStyle(Theme.accentText)
                    }
                    if community.posts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("The first page is yours to write")
                                .font(.system(size: 23, design: .serif))
                            Text("Share a workout, a meal you made, or a small win.")
                                .font(.subheadline).foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accentCardStyle(Theme.slate)
                    } else {
                        ForEach(community.posts) { post in
                            VStack(alignment: .leading, spacing: 13) {
                                HStack {
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.title3).foregroundStyle(Theme.protein)
                                    Text(post.authorName).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(post.createdAt, style: .relative)
                                        .font(.caption).foregroundStyle(Theme.muted)
                                }
                                Text(post.text).font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: 20) {
                                    ShareLink(item: post.text) {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                    if community.isMine(post) {
                                        Button(role: .destructive) { deletingPost = post } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                                .font(.caption.weight(.medium))
                            }
                            .accentCardStyle(Theme.slate)
                        }
                        if community.canLoadMore {
                            Button("Load more posts") { Task { await community.loadMore() } }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accentText)
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
            .refreshable { await community.refreshFeed() }
            .task {
                await community.connect()
                await community.refreshFeed()
            }
            .scrollClipDisabled()
            .softTopScrollEdgeEffect()
            .background(NagisenBackdrop())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingComposer) { composer }
            .confirmationDialog("Delete this post for everyone?", isPresented: Binding(
                get: { deletingPost != nil }, set: { if !$0 { deletingPost = nil } }
            )) {
                Button("Delete post", role: .destructive) {
                    guard let post = deletingPost else { return }
                    deletingPost = nil
                    Task { await community.delete(post) }
                }
            }
        }
    }

    private var composer: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("What did you do today?")
                    .font(.system(size: 25, design: .serif))
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 170, maxHeight: 250)
                    .nagisenGlass(in: RoundedRectangle(cornerRadius: 15), tint: Theme.surface.opacity(0.18))
                Text("\(text.count)/1,000 · Visible to everyone in Feed.")
                    .font(.caption).foregroundStyle(Theme.muted)
                Button("Save private draft") { saveDraft() }
                    .font(.subheadline).foregroundStyle(Theme.accentText)
                Spacer()
            }
            .padding(20)
            .background(NagisenBackdrop())
            .navigationTitle("New post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingComposer = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        Task {
                            if await community.publish(text, as: displayName) {
                                let posted = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                savedDrafts = (try? JSONEncoder().encode(drafts.filter { $0.text != posted })) ?? savedDrafts
                                text = ""
                                showingComposer = false
                            }
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              text.count > 1000 || community.isBusy)
                }
            }
        }
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
