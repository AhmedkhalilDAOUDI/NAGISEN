import Photos
import PhotosUI
import SwiftUI

/// A share card that can sit on one of your photos instead of the dark background.
protocol PhotoCard: View {
    func on(_ photo: UIImage?) -> Self
    /// The pieces of data on the card, by name, that can be left out or moved.
    var fields: [String] { get }
    func hiding(_ hidden: Set<String>) -> Self
    /// Where each piece has been dragged; `layout.onMove` is set only while editing in the share sheet.
    func arranged(_ layout: CardLayout) -> Self
}

/// How far each piece of a card has been moved from its place, and who to tell while it is dragged.
struct CardLayout {
    var offsets: [String: CGSize] = [:]
    var onMove: ((String, CGSize, Bool) -> Void)? = nil
}

private struct Movable: ViewModifier {
    let field: String
    let layout: CardLayout

    func body(content: Content) -> some View {
        content
            .offset(layout.offsets[field] ?? .zero)
            .highPriorityGesture(DragGesture(minimumDistance: 2)
                .onChanged { layout.onMove?(field, $0.translation, false) }
                .onEnded { layout.onMove?(field, $0.translation, true) },
                including: layout.onMove == nil ? .none : .all)
    }
}

extension View {
    /// Lets this piece of a share card be dragged, and keeps it where it was left.
    func movable(_ field: String, _ layout: CardLayout) -> some View { modifier(Movable(field: field, layout: layout)) }
}

/// The photo filling the card, darkened at the top and bottom so the numbers always read.
struct CardBackground: View {
    let photo: UIImage?

    var body: some View {
        if let photo {
            ZStack {
                Image(uiImage: photo).resizable().scaledToFill()
                    .frame(width: 360, height: 450).clipped()
                LinearGradient(stops: [.init(color: .black.opacity(0.55), location: 0), .init(color: .clear, location: 0.3),
                                       .init(color: .clear, location: 0.45), .init(color: .black.opacity(0.8), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
        } else {
            Color(red: 0.035, green: 0.03, blue: 0.035)
        }
    }
}

/// The image every share turns into: dark, quiet, the NAGISEN mark, one big number.
struct ShareCard: PhotoCard {
    let kicker: String
    var symbol: String? = nil
    let headline: String
    let value: String
    var caption: String = ""
    /// Optional trend line drawn under the number, like a weight curve.
    var series: [Double] = []
    var lines: [(String, String)] = []
    var photo: UIImage? = nil
    var hidden: Set<String> = []
    var layout = CardLayout()

    func on(_ photo: UIImage?) -> ShareCard { var card = self; card.photo = photo; return card }
    func arranged(_ layout: CardLayout) -> ShareCard { var card = self; card.layout = layout; return card }
    func hiding(_ hidden: Set<String>) -> ShareCard { var card = self; card.hidden = hidden; return card }

    private static let titleField = String(localized: "Title")
    private static let valueField = String(localized: "Main number")
    private static let captionField = String(localized: "Details")
    private static let seriesField = String(localized: "Trend")

    var fields: [String] {
        [Self.titleField] + (value.isEmpty ? [] : [Self.valueField]) + (series.count > 1 ? [Self.seriesField] : [])
            + lines.map(\.1) + (caption.isEmpty ? [] : [Self.captionField])
    }

    private func shows(_ field: String) -> Bool { !hidden.contains(field) }

    /// Softer greys disappear on a photo; there the small text goes near-white.
    private var quiet: Color { photo == nil ? Theme.muted : .white.opacity(0.8) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                NagisenMark(ink: Theme.ink, accent: Theme.accent).frame(width: 22, height: 22)
                Text("NAGISEN").font(.system(size: 13, weight: .semibold)).nagisenTracking(4)
                Spacer()
                Text(kicker.uppercased()).font(.system(size: 11, weight: .semibold)).nagisenTracking(2)
                    .foregroundStyle(quiet)
            }
            Spacer(minLength: 0)
            if shows(Self.titleField) {
                VStack(alignment: .leading, spacing: 12) {
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(Theme.accentText)
                    }
                    Text(headline).font(.system(size: 30, design: .serif)).lineLimit(2).minimumScaleFactor(0.7)
                }
                .movable(Self.titleField, layout)
            }
            if !value.isEmpty, shows(Self.valueField) {
                Text(value).font(.system(size: 54, design: .serif)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(Theme.ink)
                    .movable(Self.valueField, layout)
            }
            if series.count > 1, shows(Self.seriesField) {
                SeriesLine(values: series)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(height: 60)
                    .movable(Self.seriesField, layout)
            }
            let shownLines = lines.filter { shows($0.1) }
            if !shownLines.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    ForEach(Array(shownLines.enumerated()), id: \.offset) { _, line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.0).font(.system(size: 20, design: .serif)).monospacedDigit()
                            Text(line.1).font(.system(size: 11)).foregroundStyle(quiet)
                        }
                        .movable(line.1, layout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Spacer(minLength: 0)
            if !caption.isEmpty, shows(Self.captionField) {
                Text(caption).font(.system(size: 13)).foregroundStyle(quiet)
                    .movable(Self.captionField, layout)
            }
        }
        .padding(28)
        .frame(width: 360, height: 450, alignment: .leading)
        .background(CardBackground(photo: photo))
        .shadow(color: photo == nil ? .clear : .black.opacity(0.5), radius: 6)
        .foregroundStyle(Theme.ink)
        .environment(\.colorScheme, .dark)
    }
}

/// A line through values, scaled to fill its frame; no axes, so no exact numbers leak.
private struct SeriesLine: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        guard let low = values.min(), let high = values.max(), values.count > 1 else { return Path() }
        let span = max(high - low, 0.0001)
        var path = Path()
        for (index, value) in values.enumerated() {
            let point = CGPoint(x: rect.minX + rect.width * CGFloat(index) / CGFloat(values.count - 1),
                                y: rect.maxY - rect.height * CGFloat((value - low) / span))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// Preview a card, add a line, post it to the Feed as an image.
struct ShareCardSheet<Card: PhotoCard>: View {
    @EnvironmentObject private var feed: FeedService
    @Environment(\.dismiss) private var dismiss
    let card: Card
    @State private var photo: UIImage?
    @State private var original: UIImage?
    @State private var edits = PhotoEdits()
    @State private var editing = false
    @State private var picked: PhotosPickerItem?
    @State private var hidden: Set<String> = []
    @State private var offsets: [String: CGSize] = [:]
    @State private var placed: [String: CGSize] = [:]

    private var shown: Card { card.on(photo).hiding(hidden).arranged(CardLayout(offsets: offsets)) }

    /// The preview: the same card, but every piece answers to a drag.
    private var editable: Card {
        card.on(photo).hiding(hidden).arranged(CardLayout(offsets: offsets) { field, moved, ended in
            let start = placed[field] ?? .zero
            offsets[field] = CGSize(width: start.width + moved.width, height: start.height + moved.height)
            if ended { placed[field] = offsets[field]; saved = false }
        })
    }
    @State private var caption = ""
    @State private var posting = false
    @State private var failed = false
    @State private var saved = false
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    editable
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .scaleEffect(0.85)
                        .frame(height: 400)
                    HStack {
                        Text("Drag the numbers to place them anywhere.").font(.caption).foregroundStyle(Theme.muted)
                        Spacer()
                        if !offsets.isEmpty {
                            Button(String(localized: "Reset layout")) { offsets = [:]; placed = [:]; saved = false }
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.accentText)
                        }
                    }
                    HStack(spacing: 18) {
                        PhotosPicker(selection: $picked, matching: .images) {
                            Label(photo == nil ? String(localized: "Add a photo") : String(localized: "Change photo"), systemImage: "photo")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accentText).frame(minHeight: 44)
                        }
                        if original != nil {
                            Button { editing = true } label: {
                                Label(String(localized: "Edit photo"), systemImage: "slider.horizontal.3")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accentText).frame(minHeight: 44)
                            }
                        }
                        if photo != nil {
                            Button(String(localized: "No photo")) { photo = nil; original = nil; picked = nil }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted).frame(minHeight: 44)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SHOW").font(.caption2.weight(.semibold)).nagisenTracking(2).foregroundStyle(Theme.muted)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                            ForEach(card.fields, id: \.self) { field in
                                let on = !hidden.contains(field)
                                Button {
                                    if on { hidden.insert(field) } else { hidden.remove(field) }
                                } label: {
                                    Label(field, systemImage: on ? "checkmark" : "eye.slash")
                                        .font(.caption.weight(.semibold))
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                        .foregroundStyle(on ? Theme.ink : Theme.muted)
                                        .background(on ? Theme.accent.opacity(0.25) : Color.clear, in: Capsule())
                                        .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.16), lineWidth: 0.5))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
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
            .onChange(of: photo) { _, _ in saved = false }
            .onChange(of: hidden) { _, _ in saved = false }
            .onChange(of: picked) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        original = image
                        edits = PhotoEdits()
                        photo = PhotoEditor.render(edits, from: image)
                        editing = true
                    }
                }
            }
            .fullScreenCover(isPresented: $editing) {
                if let original {
                    PhotoEditorView(original: original, edits: edits) { rendered, chosen in
                        photo = rendered
                        edits = chosen
                    }
                }
            }
            .nagisenSheetBar(String(localized: "Share to Feed"), onClose: { dismiss() },
                             actionTitle: String(localized: "Post"), actionEnabled: feed.state == .ready && !posting,
                             busy: posting) { post() }
        }
    }

    /// The card exactly as previewed: photo, edits and the data left on.
    private var finished: UIImage? {
        let renderer = ImageRenderer(content: shown)
        renderer.scale = 3
        return renderer.uiImage
    }

    /// Keeps the finished card in the photo library, to post anywhere or just keep.
    private func save() {
        guard let image = finished else { return }
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
        guard let data = finished?.jpegData(compressionQuality: 0.9),
              let attachment = try? PostMedia.photo(from: data) else { failed = true; return }
        posting = true
        Task {
            if await feed.publish(caption, attachment: attachment) { dismiss() } else { failed = true }
            posting = false
        }
    }
}

/// A small share mark that opens the sheet for a card.
struct ShareCardButton<Card: PhotoCard>: View {
    let card: () -> Card
    @State private var sharing = false

    var body: some View {
        Button { sharing = true } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.accentText)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Share to Feed"))
        .sheet(isPresented: $sharing) { ShareCardSheet(card: card()) }
    }
}

// MARK: - The cards

enum ShareCards {
    static func trophy(title: String, subtitle: String, symbol: String) -> ShareCard {
        ShareCard(kicker: String(localized: "Trophy"), symbol: symbol, headline: title, value: "", caption: subtitle)
    }

    static func record(_ record: StrengthRecord) -> ShareCard {
        ShareCard(kicker: String(localized: "Personal record"), symbol: "medal", headline: record.exercise,
                  value: "\(record.kilograms.formatted(.number.precision(.fractionLength(0...1)))) kg × \(record.reps)",
                  caption: record.date.formatted(.dateTime.day().month(.wide).year()))
    }

    static func workout(_ workout: WorkoutEntry) -> ShareCard {
        ShareCard(kicker: String(localized: "Workout"), headline: workout.activity, value: "\(workout.minutes) min",
                  caption: [workout.detail?.isEmpty == false && workout.detail != "Imported from Apple Health" ? workout.detail : nil,
                            workout.date.formatted(.dateTime.weekday(.wide).day().month(.wide))].compactMap { $0 }.joined(separator: " · "))
    }

    /// The change and the shape of the curve, never the weight itself.
    static func weight(_ entries: [WeightEntry]) -> ShareCard? {
        let sorted = entries.sorted { $0.date < $1.date }
        guard let first = sorted.first, let last = sorted.last, sorted.count > 1 else { return nil }
        let change = last.kilograms - first.kilograms
        let sign = change > 0 ? "+" : change < 0 ? "−" : ""
        return ShareCard(kicker: String(localized: "Progress"), headline: String(localized: "Weight"),
                         value: "\(sign)\(abs(change).formatted(.number.precision(.fractionLength(1)))) kg",
                         caption: String(localized: "Since \(first.date.formatted(.dateTime.day().month(.wide).year()))"),
                         series: sorted.suffix(60).map(\.kilograms))
    }

    static func streak(days: Int, longest: Int) -> ShareCard {
        ShareCard(kicker: String(localized: "Streak"), symbol: "flame", headline: String(localized: "Showing up"),
                  value: String(localized: "\(days) days"),
                  caption: longest > days ? String(localized: "Longest: \(longest) days") : String(localized: "My longest yet"))
    }

    static func day(_ store: NutritionStore, on date: Date) -> ShareCard {
        let totals = store.totals(on: date), goals = store.goals(on: date)
        let minutes = store.workouts.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }.reduce(0) { $0 + $1.minutes }
        return ShareCard(kicker: String(localized: "My day"), headline: date.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                         value: "\(totals.calories.formatted()) kcal",
                         caption: String(localized: "Goal \(goals.calories.formatted()) kcal"),
                         lines: [("\(Int(totals.protein.rounded())) g", String(localized: "protein")),
                                 ("\((store.waterTotal(on: date)).formatted()) mL", String(localized: "water")),
                                 ("\(minutes) min", String(localized: "training"))])
    }
}

// MARK: - Share from NAGISEN

/// Everything you can share, in one list: your day, your streak, workouts, activities, records and weight.
struct ShareHubView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    @State private var choice: Choice?

    struct Choice: Identifiable {
        let id = UUID()
        var card: ShareCard?
        var activity: RecordedActivity?
    }

    var body: some View {
        let streak = store.streakSnapshot(asOf: .now)
        let activityWorkouts = Set(store.activities.compactMap(\.workoutID))
        let workouts = store.workouts.filter { !activityWorkouts.contains($0.id) }.sorted { $0.date > $1.date }.prefix(6)
        let records = Dictionary(grouping: store.strengthRecords, by: \.exercise)
            .compactMap { $0.value.max { $0.kilograms == $1.kilograms ? $0.reps < $1.reps : $0.kilograms < $1.kilograms } }
            .sorted { $0.date > $1.date }.prefix(5)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    NagisenSection("Today") {
                        row(String(localized: "My day"), detail: "\(store.totals(on: .now).calories.formatted()) kcal", symbol: "sun.horizon") {
                            choice = Choice(card: ShareCards.day(store, on: .now))
                        }
                        if streak.activeStreak > 0 {
                            Divider().overlay(Theme.line)
                            row(String(localized: "Streak"), detail: String(localized: "\(streak.activeStreak) days"), symbol: "flame") {
                                choice = Choice(card: ShareCards.streak(days: streak.activeStreak, longest: streak.longestStreak))
                            }
                        }
                    }
                    if !store.activities.isEmpty {
                        NagisenSection("Activities") {
                            ForEach(Array(store.activities.prefix(4).enumerated()), id: \.offset) { index, activity in
                                if index > 0 { Divider().overlay(Theme.line) }
                                row("\(activity.kind.name) · \(activity.start.formatted(.dateTime.day().month(.abbreviated)))",
                                    detail: activity.summary, symbol: activity.kind.symbol) { choice = Choice(activity: activity) }
                            }
                        }
                    }
                    if !workouts.isEmpty {
                        NagisenSection("Workouts") {
                            ForEach(Array(workouts.enumerated()), id: \.offset) { index, workout in
                                if index > 0 { Divider().overlay(Theme.line) }
                                row(workout.activity, detail: "\(workout.minutes) min · \(workout.date.formatted(.dateTime.day().month(.abbreviated)))",
                                    symbol: "figure.strengthtraining.traditional") { choice = Choice(card: ShareCards.workout(workout)) }
                            }
                        }
                    }
                    if !records.isEmpty || ShareCards.weight(store.weights) != nil {
                        NagisenSection("Progress") {
                            ForEach(Array(records.enumerated()), id: \.offset) { index, record in
                                if index > 0 { Divider().overlay(Theme.line) }
                                row(record.exercise, detail: "\(record.kilograms.formatted(.number.precision(.fractionLength(0...1)))) kg × \(record.reps)",
                                    symbol: "medal") { choice = Choice(card: ShareCards.record(record)) }
                            }
                            if let weight = ShareCards.weight(store.weights) {
                                if !records.isEmpty { Divider().overlay(Theme.line) }
                                row(String(localized: "Weight progress"), detail: weight.value, symbol: "chart.line.downtrend.xyaxis") {
                                    choice = Choice(card: weight)
                                }
                            }
                        }
                    }
                    Text("Trophies can be shared from the trophy shelf in Workouts.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                .foregroundStyle(Theme.ink)
                .padding(20)
            }
            .background(NagisenBackdrop())
            .nagisenSheetBar(String(localized: "Share from NAGISEN"), onClose: { dismiss() })
            .sheet(item: $choice) { choice in
                if let activity = choice.activity {
                    ShareCardSheet(card: RouteCard(activity: activity))
                } else if let card = choice.card {
                    ShareCardSheet(card: card)
                }
            }
        }
    }

    private func row(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).foregroundStyle(Theme.accentText).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "square.and.arrow.up").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            }
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
