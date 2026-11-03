import SwiftUI

/// How the familiar is doing. It grows with every day you show up (logging food, finishing a day or
/// training) and never loses a stage; the last seven days set its mood. What you ate never counts
/// against it.
enum Familiar {
    struct State: Equatable {
        var stage: FamiliarCat.Stage
        var mood: FamiliarCat.Mood
        /// Days that have counted toward growing, ever.
        var days: Int
        /// Active days among today and the six before it.
        var lastWeek: Int
        /// Days needed for the next stage; nil once it is an elder.
        var nextStageAt: Int?
    }

    static let stageDays = [0, 7, 30, 100]

    /// `lastWeek` holds the day keys of today and the six days before it.
    static func state(activeDays: Set<String>, longestStreak: Int, lastWeek: [String]) -> State {
        let days = max(activeDays.count, longestStreak)
        let stage = FamiliarCat.Stage(rawValue: stageDays.lastIndex { days >= $0 } ?? 0) ?? .kitten
        let recent = lastWeek.filter(activeDays.contains).count
        let mood: FamiliarCat.Mood = recent >= 4 ? .bright : recent >= 2 ? .calm : .resting
        let next = stage == .elder ? nil : stageDays[stage.rawValue + 1]
        return State(stage: stage, mood: mood, days: days, lastWeek: recent, nextStageAt: next)
    }

    static let nameKey = "familiarName"
    static let defaultName = "Kuro"

    static func stageName(_ stage: FamiliarCat.Stage) -> String {
        switch stage {
        case .kitten: String(localized: "Kitten")
        case .young: String(localized: "Young cat")
        case .grown: String(localized: "Grown cat")
        case .elder: String(localized: "Elder")
        }
    }

    static func moodLine(_ mood: FamiliarCat.Mood, name: String) -> String {
        switch mood {
        case .bright: String(localized: "\(name) is bright and awake.")
        case .calm: String(localized: "\(name) is calm. A few more active days and the eyes open wide.")
        case .resting: String(localized: "\(name) is resting. Log a meal or a workout to wake the cat.")
        }
    }
}

extension NutritionStore {
    var familiar: Familiar.State {
        var days = completedLoggingDays
        for entry in entries { days.insert(dayKey(entry.date)) }
        for workout in workouts { days.insert(dayKey(workout.date)) }
        let week = (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: .now) }.map(dayKey)
        return Familiar.state(activeDays: days, longestStreak: streakSnapshot(asOf: .now).longestStreak, lastWeek: week)
    }
}

/// Kuro as the 3D model draws it, on its small night background.
struct KuroStill: View {
    let state: Familiar.State

    var body: some View {
        Image(uiImage: KuroPortrait.image(state.stage, state.mood))
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityLabel(FamiliarCat.describe(state.stage, state.mood))
    }
}

struct FamiliarCard: View {
    @EnvironmentObject private var store: NutritionStore
    @AppStorage(Familiar.nameKey) private var name = Familiar.defaultName
    @State private var showingDetails = false

    var body: some View {
        let state = store.familiar
        Button { showingDetails = true } label: {
            HStack(spacing: 16) {
                KuroStill(state: state).frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 5) {
                    Text("FAMILIAR").font(.caption2.weight(.semibold)).nagisenTracking(2).foregroundStyle(Theme.accentText)
                    Text(name).font(.system(size: 24, design: .serif))
                    Text(Familiar.moodLine(state.mood, name: name))
                        .font(.caption).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardStyle()
        .accessibilityHint("Shows how \(name) grows")
        .sheet(isPresented: $showingDetails) { FamiliarView() }
    }
}

struct FamiliarView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Familiar.nameKey) private var name = Familiar.defaultName
    @State private var showingDojo = false

    var body: some View {
        let state = store.familiar
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    KuroStill(state: state)
                        .frame(maxWidth: 300)
                        .frame(maxWidth: .infinity)
                    Button { showingDojo = true } label: {
                        Label("Visit \(name)’s dojo", systemImage: "arrow.right")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Theme.accent, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Name", text: $name)
                            .font(.system(size: 30, design: .serif))
                            .submitLabel(.done)
                            .onSubmit { if name.trimmingCharacters(in: .whitespaces).isEmpty { name = Familiar.defaultName } }
                        Text(Familiar.moodLine(state.mood, name: name)).font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(Familiar.stageName(state.stage).uppercased())
                                .font(.caption2.weight(.semibold)).nagisenTracking(2).foregroundStyle(Theme.accentText)
                            Spacer()
                            if let next = state.nextStageAt {
                                Text("\(state.days.formatted()) of \(next.formatted()) days")
                                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                            } else {
                                Text("\(state.days.formatted()) days").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                            }
                        }
                        if let next = state.nextStageAt {
                            let from = Familiar.stageDays[state.stage.rawValue]
                            ProgressView(value: Double(state.days - from), total: Double(next - from)).tint(Theme.red)
                        }
                        Text("This week: \(state.lastWeek) of 7 days active")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    .cardStyle()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How \(name) grows").font(.system(size: 20, design: .serif))
                        Text("Every day you log food, finish your log or train counts once. Growth is never lost: \(name) becomes a young cat at 7 days, grown at 30 and an elder at 100.")
                        Text("The last seven days set the mood: four active days or more and \(name) is bright, two or three and calm, fewer and asleep. Sleeping is only resting; one active day starts waking the cat.")
                        Text("What you eat never counts against \(name). Only showing up does.")
                    }
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .foregroundStyle(Theme.ink)
            .background(NagisenBackdrop())
            .nagisenSheetBar(String(localized: "Familiar"), onClose: { dismiss() })
        }
        .fullScreenCover(isPresented: $showingDojo) { DojoView() }
    }
}
