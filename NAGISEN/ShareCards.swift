import SwiftUI

/// The image every share turns into: dark, quiet, the NAGISEN mark, one big number.
struct ShareCard: View {
    let kicker: String
    var symbol: String? = nil
    let headline: String
    let value: String
    var caption: String = ""
    /// Optional trend line drawn under the number, like a weight curve.
    var series: [Double] = []
    var lines: [(String, String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                NagisenMark(ink: Theme.ink, accent: Theme.accent).frame(width: 22, height: 22)
                Text("NAGISEN").font(.system(size: 13, weight: .semibold)).nagisenTracking(4)
                Spacer()
                Text(kicker.uppercased()).font(.system(size: 11, weight: .semibold)).nagisenTracking(2)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            if let symbol {
                Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(Theme.accentText)
            }
            Text(headline).font(.system(size: 30, design: .serif)).lineLimit(2).minimumScaleFactor(0.7)
            if !value.isEmpty {
                Text(value).font(.system(size: 54, design: .serif)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(Theme.ink)
            }
            if series.count > 1 {
                SeriesLine(values: series)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(height: 60)
            }
            if !lines.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.0).font(.system(size: 20, design: .serif)).monospacedDigit()
                            Text(line.1).font(.system(size: 11)).foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Spacer(minLength: 0)
            if !caption.isEmpty {
                Text(caption).font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
        }
        .padding(28)
        .frame(width: 360, height: 450, alignment: .leading)
        .background(Color(red: 0.035, green: 0.03, blue: 0.035))
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
struct ShareCardSheet<Card: View>: View {
    @EnvironmentObject private var feed: FeedService
    @Environment(\.dismiss) private var dismiss
    let card: Card
    @State private var caption = ""
    @State private var posting = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    card
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .scaleEffect(0.85)
                        .frame(height: 400)
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
            .nagisenSheetBar(String(localized: "Share to Feed"), onClose: { dismiss() },
                             actionTitle: String(localized: "Post"), actionEnabled: feed.state == .ready && !posting,
                             busy: posting) { post() }
        }
    }

    private func post() {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let data = renderer.uiImage?.jpegData(compressionQuality: 0.9),
              let attachment = try? PostMedia.photo(from: data) else { failed = true; return }
        posting = true
        Task {
            if await feed.publish(caption, attachment: attachment) { dismiss() } else { failed = true }
            posting = false
        }
    }
}

/// A small share mark that opens the sheet for a card.
struct ShareCardButton<Card: View>: View {
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
