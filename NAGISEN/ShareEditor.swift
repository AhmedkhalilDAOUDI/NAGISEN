import AVFoundation
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

    /// Moves, pinches and turns a piece; let go below the card, over the bin, and it leaves the card.
    mutating func touch(_ field: String, _ touch: CardTouch, cardHeight: CGFloat) {
        if grip?.field != field {
            grip = (field, layout.offsets[field] ?? .zero, layout.sizes[field] ?? 1, layout.turns[field] ?? .zero)
            layout.selected = field
        }
        guard let grip else { return }
        if let move = touch.move {
            layout.offsets[field] = CGSize(width: grip.offset.width + move.width, height: grip.offset.height + move.height)
        }
        if let pinch = touch.pinch { layout.sizes[field] = CardLayout.resized(grip.size, by: pinch) }
        if let turn = touch.turn { layout.turns[field] = Self.straightened(grip.turn + turn) }
        overTrash = touch.location.map { $0.y > cardHeight + 12 } ?? overTrash
        if touch.move != nil { holding = field }
        if touch.ended { holding = nil }
        if touch.ended {
            if overTrash { remove(field) }
            self.grip = nil
            overTrash = false
        }
    }

    /// A slight tilt snaps back to level, so pinching never leaves a piece crooked by accident.
    static func straightened(_ angle: Angle) -> Angle {
        var degrees = angle.degrees.truncatingRemainder(dividingBy: 360)
        if degrees > 180 { degrees -= 360 } else if degrees < -180 { degrees += 360 }
        return abs(degrees) < 6 ? .zero : angle
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
    @State private var choosingPhoto = false
    @State private var showingCamera = false
    @State private var editAfterCamera = false
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
    @State private var music: CardMusic?
    @State private var player: AVAudioPlayer?
    @State private var making = false
    @State private var videoFailed = false

    private static var dark: Color { Color(red: 0.035, green: 0.03, blue: 0.035) }
    private var size: CGSize { CardSize.of(photo) }

    private var shown: Card {
        var plain = draft.layout
        plain.selected = nil
        return card.on(photo).hiding(draft.hidden).arranged(plain)
    }

    private var editable: Card {
        var live = draft.layout
        live.onTouch = { field, touch in draft.touch(field, touch, cardHeight: size.height) }
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
                        use(image)
                        adjusting = true
                    }
                }
            }
            .photosPicker(isPresented: $choosingPhoto, selection: $picked, matching: .images)
            .fullScreenCover(isPresented: $showingCamera, onDismiss: {
                // The photo editor can only open once the camera has gone.
                if editAfterCamera { editAfterCamera = false; adjusting = true }
            }) {
                Camera { shot in
                    if let image = shot?.image { use(image); editAfterCamera = true }
                    showingCamera = false
                }
                .ignoresSafeArea()
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

    /// A new photo always starts whole and untouched.
    private func use(_ image: UIImage) {
        original = image
        edits = PhotoEdits()
        photo = PhotoEditor.apply(edits, to: image)
    }

    // MARK: Editor

    private var tools: some View {
        HStack(spacing: 2) {
            toolButton("xmark", String(localized: "Close")) { dismiss() }
            Spacer()
            Menu {
                Button { showingCamera = true } label: { Label(String(localized: "Take a photo"), systemImage: "camera") }
                Button { choosingPhoto = true } label: { Label(String(localized: "Choose from library"), systemImage: "photo.on.rectangle") }
            } label: { toolIcon("photo") }
                .buttonStyle(.plain)
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
            editable
            .frame(width: size.width, height: size.height)
            .coordinateSpace(name: CardLayout.space)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
            // Anywhere on the card, one finger moves the chosen piece and two resize and turn it, however small it is.
            .gesture(DragGesture(minimumDistance: 2).simultaneously(with: MagnifyGesture()).simultaneously(with: RotateGesture())
                .onChanged { handleSelected($0, ended: false) }
                .onEnded { handleSelected($0, ended: true) })
            .onTapGesture {
                // A tap on a piece can reach the card too; only a tap on empty space clears the choice.
                if Date.now.timeIntervalSince(lastTap) > 0.3 { draft.layout.selected = nil }
            }
            .scaleEffect(fit)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(.horizontal, 10)
    }

    private func handleSelected(_ value: SimultaneousGesture<SimultaneousGesture<DragGesture, MagnifyGesture>, RotateGesture>.Value,
                                ended: Bool) {
        guard let field = draft.layout.selected else { return }
        draft.touch(field, CardTouch(move: value.first?.first?.translation, pinch: value.first?.second?.magnification,
                                     turn: value.second?.rotation, location: value.first?.first?.location, ended: ended),
                    cardHeight: size.height)
    }

    private func name(of field: String) -> String {
        draft.layout.texts.contains { $0.field == field } ? String(localized: "Your text") : field
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if draft.holding != nil {
                // While a piece is held, the bin waits here, below the card, never on top of it.
                VStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 56, height: 56)
                        .background(draft.overTrash ? Theme.accent : Color.white.opacity(0.08), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(draft.overTrash ? 0.9 : 0.3), lineWidth: 1))
                        .scaleEffect(draft.overTrash ? 1.15 : 1)
                        .animation(.easeOut(duration: 0.15), value: draft.overTrash)
                    Text(draft.overTrash ? String(localized: "Let go to remove") : String(localized: "Drag below the card to remove"))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
            } else if let field = draft.layout.selected {
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
                Text("Tap any word or number. Then drag, pinch or twist anywhere on the card to move, resize or turn it.")
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
                        // Captions taken off in the bin come back here too.
                        ForEach(card.fields + draft.hidden.subtracting(card.fields).sorted(), id: \.self) { field in
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
                musicRow
                Button(action: save) {
                    Label(making ? String(localized: "Making the video…") : saved ? String(localized: "Saved to Photos") : String(localized: "Save to Photos"),
                          systemImage: saved ? "checkmark" : music == nil ? "arrow.down.to.line" : "film")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.ink.opacity(0.16), lineWidth: 0.5))
                        .foregroundStyle(saved ? Theme.accentText : Theme.ink)
                }
                .buttonStyle(.plain)
                .disabled(making || posting)
                if videoFailed {
                    Text("The video couldn't be made. Try again, or choose No music.")
                        .font(.caption).foregroundStyle(Theme.accentText)
                }
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
        .onAppear { preview(music) }
        .onDisappear { preview(nil) }
        .nagisenSheetBar(String(localized: "Share"), closeSymbol: "chevron.left", onClose: { finishing = false },
                         actionTitle: String(localized: "Post"), actionEnabled: feed.state == .ready && !posting && !making,
                         busy: posting) { post() }
    }

    /// The card exactly as edited: photo, adjustments and every piece where you left it.
    private var finished: UIImage? {
        let renderer = ImageRenderer(content: shown)
        renderer.scale = 3
        return renderer.uiImage
    }

    private var musicRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MUSIC").font(.caption2.weight(.semibold)).nagisenTracking(2).foregroundStyle(Theme.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    musicChip(nil)
                    ForEach(CardMusic.allCases) { musicChip($0) }
                }
            }
            Text(music == nil ? String(localized: "Saves and posts as a photo.")
                              : String(localized: "Saves and posts as a \(Int(PostMedia.cardVideoSeconds))-second video with this music."))
                .font(.caption).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func musicChip(_ choice: CardMusic?) -> some View {
        Button {
            music = choice
            saved = false
            videoFailed = false
            preview(choice)
        } label: {
            Label(choice?.title ?? String(localized: "No music"), systemImage: choice == nil ? "speaker.slash" : "music.note")
                .font(.subheadline)
                .padding(.horizontal, 14).frame(height: 36)
                .foregroundStyle(music == choice ? Theme.ink : Theme.muted)
                .background(music == choice ? Theme.accent.opacity(0.35) : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.16), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(making || posting)
        .accessibilityAddTraits(music == choice ? .isSelected : [])
    }

    /// Plays the chosen track on a loop while you decide; nil stops it and hands the sound back.
    private func preview(_ choice: CardMusic?) {
        player?.stop()
        player = nil
        let audio = AVAudioSession.sharedInstance()
        guard let url = choice?.url else {
            try? audio.setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        try? audio.setCategory(.playback)
        try? audio.setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1
        player?.play()
    }

    /// The card as a video under the chosen music; nil with no music, or when making it failed (which says so).
    private func video(of image: UIImage) async -> URL? {
        guard let url = music?.url else { return nil }
        making = true
        defer { making = false }
        do { return try await PostMedia.cardVideo(image, music: url) } catch { videoFailed = true; return nil }
    }

    /// Keeps the finished card in the photo library, to post anywhere or just keep.
    private func save() {
        guard let image = finishedImage ?? finished else { return }
        saveFailed = false
        videoFailed = false
        Task {
            let video = await video(of: image)
            if music != nil && video == nil { return }
            defer { if let video { try? FileManager.default.removeItem(at: video) } }
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else { saveFailed = true; return }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    if let video {
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: video)
                    } else {
                        PHAssetChangeRequest.creationRequestForAsset(from: image)
                    }
                }
                saved = true
            } catch {
                saveFailed = true
            }
        }
    }

    private func post() {
        guard let image = finishedImage ?? finished else { failed = true; return }
        failed = false
        videoFailed = false
        posting = true
        Task {
            defer { posting = false }
            let attachment: PostAttachment?
            if music != nil {
                guard let video = await video(of: image) else { return }
                defer { try? FileManager.default.removeItem(at: video) }
                var made = try? await PostMedia.video(at: video)
                made?.music = music
                attachment = made
            } else {
                attachment = image.jpegData(compressionQuality: 0.9).flatMap { try? PostMedia.photo(from: $0) }
            }
            guard let attachment else { failed = true; return }
            if await feed.publish(caption, attachment: attachment) { dismiss() } else { failed = true }
        }
    }
}

/// The app's own short tracks, made by tools/make_card_music.py, so a card can carry music it is free to use.
enum CardMusic: String, CaseIterable, Identifiable {
    case still, dusk, pulse, tide, lantern, steps, ember, atlas, sunrise, rain, run, breath, night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .still: String(localized: "Still")
        case .dusk: String(localized: "Dusk")
        case .pulse: String(localized: "Pulse")
        case .tide: String(localized: "Tide")
        case .lantern: String(localized: "Lantern")
        case .steps: String(localized: "Steps")
        case .ember: String(localized: "Ember")
        case .atlas: String(localized: "Atlas")
        case .sunrise: String(localized: "Sunrise")
        case .rain: String(localized: "Rain")
        case .run: String(localized: "Run")
        case .breath: String(localized: "Breath")
        case .night: String(localized: "Night")
        }
    }

    var url: URL? { Bundle.main.url(forResource: "card_\(rawValue)", withExtension: "m4a") }

    // shortcut: the track rides in the posted file's name ("…-music-dusk.mp4") because posts have no music
    // column; add one to the posts table if posts ever need more than the track's name.
    static let pathMarker = "-music-"

    static func named(inPath path: String?) -> CardMusic? {
        guard let name = path?.split(separator: "/").last, let marker = name.range(of: pathMarker) else { return nil }
        return CardMusic(rawValue: String(name[marker.upperBound...].prefix { $0.isLetter }))
    }
}
