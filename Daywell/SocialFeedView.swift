import SwiftUI

private struct FeedDraft: Identifiable, Codable {
    var id = UUID()
    var text: String
    var createdAt = Date.now
}

struct SocialFeedView: View {
    @AppStorage("nagisen.feed.drafts") private var savedDrafts = Data()
    @State private var showingComposer = false
    @State private var text = ""

    private var drafts: [FeedDraft] {
        (try? JSONDecoder().decode([FeedDraft].self, from: savedDrafts)) ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    NagisenPageHeading(kicker: "NAGISEN COMMUNITY", title: "Feed",
                                       subtitle: "The people who keep you moving.", accent: Theme.protein)

                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "person.3.sequence.fill")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(Theme.accentText)
                        Text("A place to move together")
                            .font(.system(size: 25, design: .serif))
                        Text("Share meals, workouts and small wins with other NAGISEN members. Your posts are drafts on this iPhone until community accounts are connected.")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Button { showingComposer = true } label: {
                            HStack {
                                Text("Write a post")
                                Spacer()
                                Image(systemName: "square.and.pencil")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(16)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    .accentCardStyle(Theme.protein)

                    if !drafts.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("YOUR DRAFTS")
                                .font(.caption2.weight(.semibold)).tracking(2)
                                .foregroundStyle(Theme.muted)
                            ForEach(drafts) { draft in
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack {
                                        Image(systemName: "person.crop.circle.fill")
                                            .font(.title3).foregroundStyle(Theme.accentText)
                                        Text("You").font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text(draft.createdAt, style: .date)
                                            .font(.caption).foregroundStyle(Theme.muted)
                                    }
                                    Text(draft.text)
                                        .font(.subheadline)
                                        .fixedSize(horizontal: false, vertical: true)
                                    HStack(spacing: 20) {
                                        ShareLink(item: draft.text) {
                                            Label("Share", systemImage: "square.and.arrow.up")
                                        }
                                        Button(role: .destructive) { delete(draft) } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .font(.caption.weight(.medium))
                                }
                                .accentCardStyle(Theme.slate)
                            }
                        }
                    }
                }
                .foregroundStyle(Theme.ink)
                .padding(18)
                .padding(.bottom, 100)
            }
            .scrollClipDisabled()
            .softTopScrollEdgeEffect()
            .background(NagisenBackdrop())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingComposer) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("What did you do today?")
                            .font(.system(size: 25, design: .serif))
                        TextEditor(text: $text)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(minHeight: 170, maxHeight: 250)
                            .nagisenGlass(in: RoundedRectangle(cornerRadius: 15), tint: Theme.surface.opacity(0.18))
                        Text("Drafts stay on this iPhone. Share uses your iPhone's share sheet until the NAGISEN community is online.")
                            .font(.caption).foregroundStyle(Theme.muted)
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
                            Button("Save draft") { save() }
                                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
        }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        savedDrafts = (try? JSONEncoder().encode([FeedDraft(text: trimmed)] + drafts)) ?? savedDrafts
        text = ""
        showingComposer = false
    }

    private func delete(_ draft: FeedDraft) {
        savedDrafts = (try? JSONEncoder().encode(drafts.filter { $0.id != draft.id })) ?? savedDrafts
    }
}
