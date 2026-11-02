import Photos
import PhotosUI
import SwiftUI

/// What the editor has done to a card so far, kept apart from the screen so it can be tested.
struct CardDraft {
    var layout = CardLayout()
    var hidden: Set<String> = []
    /// Where the held piece was when the fingers came down, so every gesture builds on it.
    private var grip: (field: String, offset: CGSize, size: CGFloat, turn: Angle)?
    /// The piece being held right now, and whether it is over the bin.
    private(set) var holding: String?
    private(set) var overTrash = false

    /// Moves, pinches and turns a piece; let go over the bin and it leaves the card.
    mutating func touch(_ field: String, _ touch: CardTouch, trash: CGPoint) {
        if grip?.field != field {
            grip = (field, layout.offsets[field] ?? .zero, layout.sizes[field] ?? 1, layout.turns[field] ?? .zero)
            layout.selected = field
        }
        guard let grip else { return }
        if let move = touch.move {
            layout.offsets[field] = CGSize(width: grip.offset.width + move.width, height: grip.offset.height + move.height)
        }
        if let pinch = touch.pinch { layout.sizes[field] = CardLayout.resized(grip.size, by: pinch) }
        if let turn = touch.turn { layout.turns[field] = grip.turn + turn }
        overTrash = touch.location.map { hypot($0.x - trash.x, $0.y - trash.y) < 48 } ?? overTrash
        holding = touch.ended ? nil : field
        if touch.ended {
            if overTrash { remove(field) }
            self.grip = nil
            overTrash = false
        }
    }

    /// Takes a piece off the card: a quote or your own words go, data is hidden and can come back.
    mutating func remove(_ field: String) {
        if field == CardLayout.quoteField {
            layout.quote = nil
        } else if let index = layout.texts.firstIndex(where: { $0.field == field }) {
            layout.texts.remove(at: index)
        } else {
            hidden.insert(field)
        }
        layout.offsets[field] = nil
        layout.sizes[field] = nil
        layout.turns[field] = nil
        if layout.selected == field { layout.selected = nil }
    }

    /// The first tap picks a piece; a second tap on your own words opens them for typing.
    mutating func tap(_ field: String) -> CardText? {
        defer { layout.selected = field }
        guard layout.selected == field else { return nil }
        return layout.texts.first { $0.field == field }
    }

    /// Keeps typed words on the card, or takes them off when left empty.
    mutating func commit(_ text: CardText) {
        var text = text
        text.text = text.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let index = layout.texts.firstIndex { $0.id == text.id }
        if text.text.isEmpty {
            if index != nil { remove(text.field) }
            return
        }
        if let index { layout.texts[index] = text } else { layout.texts.append(text) }
        layout.selected = text.field
    }

    /// Puts one piece back where, how big and how straight it started.
    mutating func reset(_ field: String) {
        layout.offsets[field] = nil
        layout.sizes[field] = nil
        layout.turns[field] = nil
        layout.fonts[field] = nil
        layout.colors[field] = nil
    }
}

/// Full-screen editor: the card fills the screen, tools along the top, the selected piece's lettering and
/// colour along the bottom. Next leads to the caption, Post and Save.
struct ShareCardSheet<Card: PhotoCard>: View {
    @EnvironmentObject private var feed: FeedService
    @Environment(\.dismiss) private var dismiss
    let card: Card
    @State private var draft = CardDraft()
    @State private var photo: UIImage?
    @State private var original: UIImage?
    @State private var edits = PhotoEdits()
    @State private var adjusting = false
    @State private var picked: PhotosPickerItem?
    @State private var typing: CardText?
    @FocusState private var typingFocused: Bool
    @State private var showingData = false
    @State private var lastTap = Date.distantPast
    @State private var finishing = false
    @State private var finishedImage: UIImage?
    @State private var caption = ""
    @State private var posting = false
    @State private var failed = false
    @State private var saved = false
    @State private var saveFailed = false

    private static var dark: Color { Color(red: 0.035, green: 0.03, blue: 0.035) }
    private var size: CGSize { CardSize.of(photo) }
    private var trash: CGPoint { CGPoint(x: size.width / 2, y: size.height - 60) }

    private var shown: Card {
        var plain = draft.layout
        plain.selected = nil
        return card.on(photo).hiding(draft.hidden).arranged(plain)
    }

    private var editable: Card {
        var live = draft.layout
        live.onTouch = { field, touch in draft.touch(field, touch, trash: trash) }
        live.onTap = { field in
            lastTap = .now
            if let text = draft.tap(field) { typing = text }
        }
        return card.on(photo).hiding(draft.hidden).arranged(live)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                tools.opacity(typing == nil ? 1 : 0)
                canvas.opacity(typing == nil ? 1 : 0.3)
                bottomBar.opacity(typing == nil ? 1 : 0)
            }
            .padding(.bottom, 8)
            .ignoresSafeArea(.keyboard)
            .foregroundStyle(Theme.ink)
            .tint(Theme.accentText)
            .background(Self.dark.ignoresSafeArea())
            .overlay { if typing != nil { typingLayer } }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $finishing) { finishView }
            .onChange(of: picked) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        original = image
                        edits = PhotoEdits()
                        photo = PhotoEditor.apply(edits, to: image)
                        adjusting = true
                    }
                }
            }
            .fullScreenCover(isPresented: $adjusting) {
                if let original {
                    PhotoEditorView(original: original, edits: edits) { rendered, chosen in
                        photo = rendered
                        edits = chosen
                    }
                }
            }
            .sheet(isPresented: $showingData) { dataSheet }
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: Editor

    private var tools: some View {
        HStack(spacing: 2) {
            toolButton("xmark", String(localized: "Close")) { dismiss() }
            Spacer()
            PhotosPicker(selection: $picked, matching: .images) { toolIcon("photo") }
                .accessibilityLabel(photo == nil ? String(localized: "Add a photo") : String(localized: "Change photo"))
            if original != nil {
                toolButton("slider.horizontal.3", String(localized: "Edit photo")) { adjusting = true }
            }
            toolButton("textformat", String(localized: "Add text")) { typing = CardText(text: "") }
            toolButton("sparkles", draft.layout.quote == nil ? String(localized: "Add a quote") : String(localized: "Another quote")) {
                draft.layout.quote = Quotes.pick(for: card.quoteTheme, after: draft.layout.quote)
                draft.layout.selected = CardLayout.quoteField
            }
            toolButton("eye", String(localized: "Choose the data")) { showingData = true }
            Button {
                finishedImage = finished
                saved = false
                saveFailed = false
                finishing = true
            } label: {
                Text("Next").font(.subheadline.weight(.semibold))
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 14).frame(height: 38)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    private func toolIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .frame(width: 38, height: 38)
            .background(Color.white.opacity(0.08), in: Circle())
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private func toolButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { toolIcon(symbol) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }

    private var canvas: some View {
        GeometryReader { geo in
            let fit = min(geo.size.width / size.width, geo.size.height / size.height)
            ZStack(alignment: .bottom) {
                editable
                if draft.holding != nil {
                    Image(systemName: "trash")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 56, height: 56)
                        .background(draft.overTrash ? Theme.accent : Color.black.opacity(0.45), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                        .scaleEffect(draft.overTrash ? 1.2 : 1)
                        .animation(.easeOut(duration: 0.15), value: draft.overTrash)
                        .padding(.bottom, 32)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: size.width, height: size.height)
            .coordinateSpace(name: CardLayout.space)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                // A tap on a piece can reach the card too; only a tap on empty space clears the choice.
                if Date.now.timeIntervalSince(lastTap) > 0.3 { draft.layout.selected = nil }
            }
            .scaleEffect(fit)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(.horizontal, 10)
    }

    private func name(of field: String) -> String {
        draft.layout.texts.contains { $0.field == field } ? String(localized: "Your text") : field
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let field = draft.layout.selected {
                HStack {
                    Text(name(of: field).uppercased()).font(.caption2.weight(.semibold)).nagisenTracking(2).foregroundStyle(Theme.muted)
                    Spacer()
                    if let text = draft.layout.texts.first(where: { $0.field == field }) {
                        Button(String(localized: "Edit text")) { typing = text }
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.accentText)
                    }
                    Button(String(localized: "Reset")) { draft.reset(field) }
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.accentText)
                        .padding(.leading, 12)
                }
                .frame(minHeight: 28)
                fontChips(selected: draft.layout.fonts[field] ?? draft.layout.font) { draft.layout.fonts[field] = $0 }
                colorSwatches(field)
            } else {
                Text("Tap a piece to change its lettering and colour. Pinch to resize, twist to turn, drag to the bin to remove.")
                    .font(.caption).foregroundStyle(Theme.muted)
                    .frame(minHeight: 28, alignment: .leading)
                fontChips(selected: draft.layout.font) { draft.layout.font = $0 }
                Text("Lettering for everything").font(.caption2).foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 150, alignment: .top)
    }

    private func fontChips(selected: CardFont, choose: @escaping (CardFont) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CardFont.allCases) { choice in
                    Button { choose(choice) } label: {
                        Text(choice.name).font(choice.font(15))
                            .padding(.horizontal, 14).frame(height: 36)
                            .foregroundStyle(selected == choice ? Theme.ink : Theme.muted)
                            .background(selected == choice ? Theme.accent.opacity(0.35) : .clear, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.16), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected == choice ? .isSelected : [])
                }
            }
        }
    }

    private func colorSwatches(_ field: String) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(CardLayout.palette.enumerated()), id: \.offset) { index, color in
                let chosen = draft.layout.colors[field] == color
                Button { draft.layout.colors[field] = color } label: {
                    Circle().fill(color)
                        .frame(width: 26, height: 26)
                        .overlay(Circle().strokeBorder(.white.opacity(chosen ? 1 : 0.3), lineWidth: chosen ? 2 : 1))
                        .frame(width: 34, height: 34)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Colour \(index + 1)"))
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }

    private var typingLayer: some View {
        let field = typing?.field ?? ""
        return ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { finishTyping() }
            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Button(String(localized: "Done")) { finishTyping() }
                        .font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                        .frame(minHeight: 44)
                }
                Spacer()
                TextField("", text: Binding(get: { typing?.text ?? "" }, set: { typing?.text = $0 }),
                          prompt: Text("Write anything").foregroundStyle(.white.opacity(0.4)), axis: .vertical)
                    .font(draft.layout.font(30, field))
                    .foregroundStyle(draft.layout.color(field, Theme.ink))
                    .multilineTextAlignment(.center)
                    .lineLimit(1...6)
                    .focused($typingFocused)
                Spacer()
                fontChips(selected: draft.layout.fonts[field] ?? draft.layout.font) { draft.layout.fonts[field] = $0 }
                colorSwatches(field)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .onAppear { typingFocused = true }
    }

    private func finishTyping() {
        if let typing { draft.commit(typing) }
        typing = nil
    }

    private var dataSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                        ForEach(card.fields, id: \.self) { field in
                            let on = !draft.hidden.contains(field)
                            Button {
                                if on { draft.remove(field) } else { draft.hidden.remove(field) }
                            } label: {
                                Label(field, systemImage: on ? "checkmark" : "eye.slash")
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .foregroundStyle(on ? Theme.ink : Theme.muted)
                                    .background(on ? Theme.accent.opacity(0.25) : Color.clear, in: Capsule())
                                    .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.16), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    if photo != nil {
                        Button(String(localized: "Remove photo")) { photo = nil; original = nil; picked = nil; showingData = false }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted).frame(minHeight: 44)
                    }
                }
                .padding(20)
            }
            .foregroundStyle(Theme.ink)
            .background(NagisenBackdrop())
            .nagisenSheetBar(String(localized: "On the card"), onClose: { showingData = false })
        }
        .presentationDetents([.medium])
    }

    // MARK: Share

    private var finishView: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let finishedImage {
                    Image(uiImage: finishedImage).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .frame(maxHeight: 440)
                }
                Button(action: save) {
                    Label(saved ? String(localized: "Saved to Photos") : String(localized: "Save to Photos"),
                          systemImage: saved ? "checkmark" : "arrow.down.to.line")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.ink.opacity(0.16), lineWidth: 0.5))
                        .foregroundStyle(saved ? Theme.accentText : Theme.ink)
                }
                .buttonStyle(.plain)
                if saveFailed {
                    Text("NAGISEN can't save to Photos. Allow it in iPhone Settings → NAGISEN → Photos.")
                        .font(.caption).foregroundStyle(Theme.accentText)
                }
                if feed.state == .ready {
                    TextField("Say something (optional)", text: $caption, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(14)
                        .nagisenPanel()
                    if failed {
                        Text(feed.message ?? String(localized: "Couldn't post right now. Try again."))
                            .font(.caption).foregroundStyle(Theme.accentText)
                    }
                } else {
                    Text("Join the community in Settings to share to the Feed.")
                        .font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(20)
        }
        .background(NagisenBackdrop())
        .nagisenSheetBar(String(localized: "Share"), closeSymbol: "chevron.left", onClose: { finishing = false },
                         actionTitle: String(localized: "Post"), actionEnabled: feed.state == .ready && !posting,
                         busy: posting) { post() }
    }

    /// The card exactly as edited: photo, adjustments and every piece where you left it.
    private var finished: UIImage? {
        let renderer = ImageRenderer(content: shown)
        renderer.scale = 3
        return renderer.uiImage
    }

    /// Keeps the finished card in the photo library, to post anywhere or just keep.
    private func save() {
        guard let image = finishedImage ?? finished else { return }
        saveFailed = false
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in saveFailed = true }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, _ in
                Task { @MainActor in if success { saved = true } else { saveFailed = true } }
            }
        }
    }

    private func post() {
        guard let data = (finishedImage ?? finished)?.jpegData(compressionQuality: 0.9),
              let attachment = try? PostMedia.photo(from: data) else { failed = true; return }
        posting = true
        Task {
            if await feed.publish(caption, attachment: attachment) { dismiss() } else { failed = true }
            posting = false
        }
    }
}
