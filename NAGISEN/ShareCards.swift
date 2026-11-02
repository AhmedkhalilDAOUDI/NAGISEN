import Photos
import PhotosUI
import SwiftUI

/// A share card that can sit on one of your photos instead of the dark background.
protocol PhotoCard: View {
    func on(_ photo: UIImage?) -> Self
    /// The pieces of data on the card, by name, that can be left out or moved.
    var fields: [String] { get }
    func hiding(_ hidden: Set<String>) -> Self
    /// Where each piece has been dragged, the lettering, and any quote or text of your own.
    func arranged(_ layout: CardLayout) -> Self
    /// Which quotes fit this card.
    var quoteTheme: Quote.Theme { get }
}

/// The lettering for everything written on a card.
enum CardFont: String, CaseIterable, Identifiable {
    case serif, sans, rounded, mono, didot, futura, avenir
    var id: String { rawValue }

    var name: String {
        switch self {
        case .serif: String(localized: "Serif")
        case .sans: String(localized: "Sans")
        case .rounded: String(localized: "Rounded")
        case .mono: String(localized: "Mono")
        case .didot: "Didot"
        case .futura: "Futura"
        case .avenir: "Avenir"
        }
    }

    func font(_ size: CGFloat) -> Font {
        switch self {
        case .serif: .system(size: size, design: .serif)
        case .sans: .system(size: size, weight: .medium)
        case .rounded: .system(size: size, design: .rounded)
        case .mono: .system(size: size * 0.9, design: .monospaced)
        case .didot: .custom("Didot", size: size)
        case .futura: .custom("Futura-Medium", size: size)
        case .avenir: .custom("AvenirNext-Medium", size: size)
        }
    }
}

/// A line of your own writing on a card.
struct CardText: Identifiable, Equatable {
    var id = UUID()
    var text: String
    var field: String { "text:\(id.uuidString)" }
}

/// One moment of fingers on a piece while editing: how far it moved, pinched and turned, and where the finger is.
struct CardTouch {
    var move: CGSize?
    var pinch: CGFloat?
    var turn: Angle?
    var location: CGPoint?
    var ended = false
}

/// Everything the editor adds to a card: where each piece sits, its size, angle, lettering and colour,
/// plus a quote and your own words.
struct CardLayout {
    var offsets: [String: CGSize] = [:]
    var sizes: [String: CGFloat] = [:]
    var turns: [String: Angle] = [:]
    var fonts: [String: CardFont] = [:]
    var colors: [String: Color] = [:]
    /// The lettering for every piece that has none of its own.
    var font = CardFont.serif
    var quote: Quote? = nil
    var texts: [CardText] = []
    /// While editing: the piece last touched, outlined on the card.
    var selected: String? = nil
    var onTouch: ((String, CardTouch) -> Void)? = nil
    var onTap: ((String) -> Void)? = nil

    /// Lettering for the big words and numbers of one piece.
    func font(_ size: CGFloat, _ field: String) -> Font { (fonts[field] ?? font).font(size) }
    /// Small labels keep a plain face unless their piece was given one.
    func label(_ size: CGFloat, _ field: String? = nil, weight: Font.Weight = .regular) -> Font {
        field.flatMap { fonts[$0] }?.font(size) ?? .system(size: size, weight: weight)
    }
    func color(_ field: String, _ fallback: Color) -> Color { colors[field] ?? fallback }

    /// A pinch from a starting size, kept between tiny and huge so a piece never vanishes.
    static func resized(_ start: CGFloat, by pinch: CGFloat) -> CGFloat { min(max(start * pinch, 0.4), 3) }

    static let quoteField = String(localized: "Quote")
    /// The small word in the card's top corner, like "My day".
    static let kickerField = String(localized: "Card label")
    /// The small word under a number is a piece of its own.
    static func labelField(_ field: String) -> String { String(localized: "\(field) label") }
    /// The card's own coordinates, so a drag means the same distance however big the card is drawn.
    static let space = "card"
    /// The app's own colours, offered for any piece.
    static let palette: [Color] = [Theme.ink, .white, .black, Theme.accentText, Theme.accent, Theme.protein, Theme.carbs, Theme.fat]
}

/// A card is as wide as always and as tall as its photo needs, so the whole photo shows.
enum CardSize {
    static func of(_ photo: UIImage?) -> CGSize {
        guard let photo, photo.size.width > 0 else { return CGSize(width: 360, height: 450) }
        return CGSize(width: 360, height: (360 * photo.size.height / photo.size.width).rounded())
    }
}

/// The quote and the words you wrote, set on any card and moved like the rest.
struct CardWords: View {
    let layout: CardLayout
    let quiet: Color

    var body: some View {
        if let quote = layout.quote {
            let field = CardLayout.quoteField
            VStack(alignment: .leading, spacing: 6) {
                Text("\u{201C}\(quote.text)\u{201D}").font(layout.font(22, field)).italic().lineLimit(4).minimumScaleFactor(0.6)
                    .foregroundStyle(layout.color(field, Theme.ink))
                if let author = quote.author {
                    Text("— \(author)").font(layout.label(11, field)).foregroundStyle(quiet)
                }
            }
            .movable(field, layout)
        }
        ForEach(layout.texts) { piece in
            Text(piece.text).font(layout.font(24, piece.field)).foregroundStyle(layout.color(piece.field, Theme.ink))
                .lineLimit(6).minimumScaleFactor(0.5)
                .movable(piece.field, layout)
        }
    }
}

private struct Movable: ViewModifier {
    let field: String
    let layout: CardLayout

    func body(content: Content) -> some View {
        content
            .padding(6)
            .overlay {
                if layout.selected == field {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.75), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .padding(-6)
            .scaleEffect(layout.sizes[field] ?? 1)
            .rotationEffect(layout.turns[field] ?? .zero)
            .offset(layout.offsets[field] ?? .zero)
            .highPriorityGesture(DragGesture(minimumDistance: 2, coordinateSpace: .named(CardLayout.space))
                .simultaneously(with: MagnifyGesture()).simultaneously(with: RotateGesture())
                .onChanged { report($0, ended: false) }
                .onEnded { report($0, ended: true) },
                including: layout.onTouch == nil ? .none : .all)
            .simultaneousGesture(TapGesture().onEnded { layout.onTap?(field) }, including: layout.onTap == nil ? .none : .all)
    }

    private func report(_ value: SimultaneousGesture<SimultaneousGesture<DragGesture, MagnifyGesture>, RotateGesture>.Value, ended: Bool) {
        layout.onTouch?(field, CardTouch(move: value.first?.first?.translation, pinch: value.first?.second?.magnification,
                                         turn: value.second?.rotation, location: value.first?.first?.location, ended: ended))
    }
}

extension View {
    /// Lets this piece of a share card be moved, pinched, turned and tapped while editing.
    func movable(_ field: String, _ layout: CardLayout) -> some View { modifier(Movable(field: field, layout: layout)) }
}

/// The photo filling the card, darkened at the top and bottom so the numbers always read.
struct CardBackground: View {
    let photo: UIImage?

    var body: some View {
        if let photo {
            ZStack {
                // The card already has the photo's shape, so the whole photo fits with nothing cut.
                Image(uiImage: photo).resizable()
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
    var theme = Quote.Theme.any
    var symbol: String? = nil
    let headline: String
    let value: String
    var caption: String = ""
    /// Optional trend line drawn under the number, like a weight curve.
    var series: [Double] = []
    /// Value, name, and the colour the app gives it (protein, carbs, fat), if any.
    var lines: [(String, String, Color?)] = []
    var photo: UIImage? = nil
    var hidden: Set<String> = []
    var layout = CardLayout()

    var quoteTheme: Quote.Theme { theme }

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
                if shows(CardLayout.kickerField) {
                    Text(kicker.uppercased()).font(layout.label(11, CardLayout.kickerField, weight: .semibold)).nagisenTracking(2)
                        .foregroundStyle(layout.color(CardLayout.kickerField, quiet))
                        .movable(CardLayout.kickerField, layout)
                }
            }
            CardWords(layout: layout, quiet: quiet)
            Spacer(minLength: 0)
            if shows(Self.titleField) {
                VStack(alignment: .leading, spacing: 12) {
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(Theme.accentText)
                    }
                    Text(headline).font(layout.font(30, Self.titleField)).lineLimit(2).minimumScaleFactor(0.7)
                        .foregroundStyle(layout.color(Self.titleField, Theme.ink))
                }
                .movable(Self.titleField, layout)
            }
            if !value.isEmpty, shows(Self.valueField) {
                Text(value).font(layout.font(54, Self.valueField)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(layout.color(Self.valueField, Theme.ink))
                    .movable(Self.valueField, layout)
            }
            if series.count > 1, shows(Self.seriesField) {
                SeriesLine(values: series)
                    .stroke(layout.color(Self.seriesField, Theme.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(height: 60)
                    .movable(Self.seriesField, layout)
            }
            let shownLines = lines.filter { shows($0.1) }
            if !shownLines.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    ForEach(Array(shownLines.enumerated()), id: \.offset) { _, line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.0).font(layout.font(20, line.1)).monospacedDigit()
                                .foregroundStyle(layout.color(line.1, line.2 ?? Theme.ink))
                            let label = CardLayout.labelField(line.1)
                            if shows(label) {
                                Text(line.1).font(layout.label(11, label)).foregroundStyle(layout.color(label, quiet))
                                    .movable(label, layout)
                            }
                        }
                        .movable(line.1, layout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Spacer(minLength: 0)
            if !caption.isEmpty, shows(Self.captionField) {
                Text(caption).font(layout.label(13, Self.captionField)).foregroundStyle(layout.color(Self.captionField, quiet))
                    .movable(Self.captionField, layout)
            }
        }
        .padding(28)
        .frame(width: CardSize.of(photo).width, height: CardSize.of(photo).height, alignment: .leading)
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
        .fullScreenCover(isPresented: $sharing) { ShareCardSheet(card: card()) }
    }
}

// MARK: - The cards

enum ShareCards {
    static func trophy(title: String, subtitle: String, symbol: String) -> ShareCard {
        ShareCard(kicker: String(localized: "Trophy"), theme: .trophy, symbol: symbol, headline: title, value: "", caption: subtitle)
    }

    static func record(_ record: StrengthRecord) -> ShareCard {
        ShareCard(kicker: String(localized: "Personal record"), theme: .strength, symbol: "medal", headline: record.exercise,
                  value: "\(record.kilograms.formatted(.number.precision(.fractionLength(0...1)))) kg × \(record.reps)",
                  caption: record.date.formatted(.dateTime.day().month(.wide).year()))
    }

    static func workout(_ workout: WorkoutEntry) -> ShareCard {
        ShareCard(kicker: String(localized: "Workout"), theme: .strength, headline: workout.activity, value: "\(workout.minutes) min",
                  caption: [workout.detail?.isEmpty == false && workout.detail != "Imported from Apple Health" ? workout.detail : nil,
                            workout.date.formatted(.dateTime.weekday(.wide).day().month(.wide))].compactMap { $0 }.joined(separator: " · "))
    }

    /// The change and the shape of the curve, never the weight itself.
    static func weight(_ entries: [WeightEntry]) -> ShareCard? {
        let sorted = entries.sorted { $0.date < $1.date }
        guard let first = sorted.first, let last = sorted.last, sorted.count > 1 else { return nil }
        let change = last.kilograms - first.kilograms
        let sign = change > 0 ? "+" : change < 0 ? "−" : ""
        return ShareCard(kicker: String(localized: "Progress"), theme: .weight, headline: String(localized: "Weight"),
                         value: "\(sign)\(abs(change).formatted(.number.precision(.fractionLength(1)))) kg",
                         caption: String(localized: "Since \(first.date.formatted(.dateTime.day().month(.wide).year()))"),
                         series: sorted.suffix(60).map(\.kilograms))
    }

    static func streak(days: Int, longest: Int) -> ShareCard {
        ShareCard(kicker: String(localized: "Streak"), theme: .streak, symbol: "flame", headline: String(localized: "Showing up"),
                  value: String(localized: "\(days) days"),
                  caption: longest > days ? String(localized: "Longest: \(longest) days") : String(localized: "My longest yet"))
    }

    /// One meal: its calories as the big number, each macro as a line you can hide or move.
    static func meal(_ meal: Meal, _ items: [DiaryEntry]) -> ShareCard {
        let grams = { (value: Double) in "\(Int(value.rounded())) g" }
        let names = items.map(\.food.name)
        return ShareCard(kicker: String(localized: "Meal"), theme: .day, headline: meal.rawValue,
                         value: "\(items.reduce(0) { $0 + $1.calories }.formatted()) kcal",
                         caption: names.prefix(3).joined(separator: " · ") + (names.count > 3 ? " +\(names.count - 3)" : ""),
                         lines: [(grams(items.reduce(0) { $0 + $1.protein }), String(localized: "protein"), Theme.protein),
                                 (grams(items.reduce(0) { $0 + $1.carbs }), String(localized: "carbs"), Theme.carbs),
                                 (grams(items.reduce(0) { $0 + $1.fat }), String(localized: "fat"), Theme.fat)])
    }

    static func day(_ store: NutritionStore, on date: Date) -> ShareCard {
        let totals = store.totals(on: date), goals = store.goals(on: date)
        let minutes = store.workouts.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }.reduce(0) { $0 + $1.minutes }
        return ShareCard(kicker: String(localized: "My day"), theme: .day, headline: date.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                         value: "\(totals.calories.formatted()) kcal",
                         caption: String(localized: "Goal \(goals.calories.formatted()) kcal"),
                         lines: [("\(Int(totals.protein.rounded())) g", String(localized: "protein"), Theme.protein),
                                 ("\((store.waterTotal(on: date)).formatted()) mL", String(localized: "water"), nil),
                                 ("\(minutes) min", String(localized: "training"), nil)])
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
                        ForEach(Meal.allCases) { meal in
                            let items = store.entries(on: .now, meal: meal)
                            if !items.isEmpty {
                                Divider().overlay(Theme.line)
                                row(meal.rawValue, detail: "\(items.reduce(0) { $0 + $1.calories }.formatted()) kcal", symbol: meal.symbol) {
                                    choice = Choice(card: ShareCards.meal(meal, items))
                                }
                            }
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
            .fullScreenCover(item: $choice) { choice in
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
