import ConfettiSwiftUI
import AVFoundation
import SwiftUI
import UIKit

private enum ChallengeFactory {
    private struct Catalog: Decodable { let quests: [ChallengeQuest] }

    enum Difficulty: String, CaseIterable, Identifiable {
        case light = "Light"
        case balanced = "Balanced"
        case hard = "Hard"
        var id: String { rawValue }

        func accepts(_ quest: ChallengeQuest) -> Bool {
            switch self {
            case .light: ChallengeFactory.lightIDs.contains(quest.id)
            case .balanced: !ChallengeFactory.lightIDs.contains(quest.id) && !ChallengeFactory.hardIDs.contains(quest.id)
            case .hard: ChallengeFactory.hardIDs.contains(quest.id)
            }
        }
    }

    private static let lightIDs: Set<String> = [
        "c08", "c12", "c14", "c17", "c23", "c24", "s13", "s17", "s18", "s21", "s24",
        "k05", "k06", "k07", "k08", "k11", "k14", "k17", "k24", "k25",
        "h05", "h08", "h14", "h18", "h22", "b01", "b03", "b06", "b10"
    ]
    private static let hardIDs: Set<String> = [
        "c04", "c06", "c07", "c09", "c15", "c25", "s02", "s03", "s06", "s08", "s19", "s22",
        "k02", "k03", "k09", "k13", "k19", "k22", "h01", "h03", "h06", "h09", "h15", "h17", "h25",
        "b04", "b05", "b09", "b11", "b12"
    ]

    static let catalog: [ChallengeQuest] = {
        guard let url = Bundle.main.url(forResource: "QuestCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Catalog.self, from: data) else { return [] }
        return decoded.quests
    }()

    static func make(recentPlans: [ChallengePlan], recentWorkouts: [WorkoutEntry],
                     seenIDs: [String], locked: [ChallengeQuest] = [], count: Int = 3,
                     difficulty: Difficulty = .balanced, shuffled: Bool = false) -> ChallengePlan {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        let previousMinutes = recentWorkouts.filter { Calendar.current.isDate($0.date, inSameDayAs: yesterday) }
            .reduce(0) { $0 + $1.minutes }
        let lighterDay = previousMinutes >= 50
        let recentIDs = Set(recentPlans.suffix(7).flatMap { $0.quests ?? [] }.map(\.id))
            .union(locked.map(\.id))
        let seen = Set(seenIDs)
        var selected = locked
        var categories = ["hybrid", "cardio", "strength", "skill", "boxing"].shuffled()
        categories.removeAll { selected.map(\.category).contains($0) }

        for category in categories where selected.count < min(max(count, 1), 5) {
            let all = catalog.filter { $0.category == category && !selected.map(\.id).contains($0.id) }
            let tier = all.filter { difficulty.accepts($0) }
            let adapted = lighterDay && difficulty == .balanced ? tier.filter { $0.estimatedMinutes <= 20 } : tier
            let pool = adapted.isEmpty ? (tier.isEmpty ? all : tier) : adapted
            let unseen = pool.filter { !seen.contains($0.id) && !recentIDs.contains($0.id) }
            let notRecent = pool.filter { !recentIDs.contains($0.id) }
            let choice: ChallengeQuest?
            if !unseen.isEmpty {
                choice = unseen.randomElement()
            } else if !notRecent.isEmpty {
                // Once a category has cycled, use its least recently shown quests first.
                let oldest = notRecent.sorted { left, right in
                    (seenIDs.firstIndex(of: left.id) ?? -1) < (seenIDs.firstIndex(of: right.id) ?? -1)
                }
                choice = Array(oldest.prefix(5)).randomElement()
            } else {
                choice = pool.randomElement()
            }
            if let choice { selected.append(choice) }
        }
        // Keep an older install usable if its bundled catalog is unavailable.
        if selected.isEmpty {
            selected = [ChallengeQuest(id: "fallback-walk", category: "cardio", title: "Open Road Ticket",
                                       detail: "Walk briskly for 20 min.", estimatedMinutes: 20,
                                       symbol: "figure.walk")]
        }
        selected.shuffle()
        return ChallengePlan(title: "Today's side quests", blocks: selected.map(\.detail),
                             estimatedMinutes: selected.reduce(0) { $0 + $1.estimatedMinutes },
                             symbol: "bolt.heart", quests: selected,
                             difficulty: difficulty.rawValue, wasShuffled: shuffled)
    }
}

private struct Trophy: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let earned: Bool
}

private struct DominoIcon: View {
    var body: some View {
        HStack(spacing: 3) {
            Circle().frame(width: 4, height: 4)
            Rectangle().frame(width: 1, height: 15).opacity(0.55)
            VStack(spacing: 3) {
                Circle().frame(width: 4, height: 4)
                Circle().frame(width: 4, height: 4)
            }
        }
        .frame(width: 31, height: 22)
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(lineWidth: 1.5))
        .accessibilityHidden(true)
    }
}

struct WorkoutMusicView: View {
    @EnvironmentObject private var store: NutritionStore
    @AppStorage("nagisen.sideQuest.leftDay") private var leftQuestDay = ""
    @State private var showingAdd = false
    @State private var selectedQuest: ChallengeQuest?
    @State private var observedEarnedIDs: Set<String>?
    @State private var pendingAwards: [Trophy] = []
    @State private var activeAward: Trophy?
    @State private var showingShuffle = false
    @State private var requestedCount = 3
    @State private var requestedDifficulty = ChallengeFactory.Difficulty.balanced

    private var todayWorkouts: [WorkoutEntry] {
        store.workouts.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var todayMinutes: Int { todayWorkouts.reduce(0) { $0 + $1.minutes } }
    private var challenge: ChallengePlan? { store.challengePlans[store.dayKey(.now)] }
    private var todaysQuests: [ChallengeQuest] {
        challenge?.activeQuests(for: store.dayKey(.now)) ?? []
    }
    private var completedQuestIDs: Set<String> {
        let key = store.dayKey(.now)
        var ids = Set(todayWorkouts.filter { $0.challengeDayKey == key }.compactMap(\.challengeID))
        if todayWorkouts.contains(where: { $0.challengeDayKey == key && $0.challengeID == nil }),
           let legacy = todaysQuests.first(where: { $0.id.hasPrefix("legacy-") }) {
            ids.insert(legacy.id)
        }
        return ids
    }
    private var challengeComplete: Bool { !todaysQuests.isEmpty && todaysQuests.allSatisfy { completedQuestIDs.contains($0.id) } }
    private var leftQuestsToday: Bool { leftQuestDay == store.dayKey(.now) }
    private var recent: [WorkoutEntry] { store.workouts.sorted { $0.date > $1.date } }

    private func shufflePack() {
        let key = store.dayKey(.now)
        let previous = store.challengePlans.keys.sorted().filter { $0 < key }
            .suffix(7).compactMap { store.challengePlans[$0] }
        let recentPlans = previous + [store.challengePlans[key]].compactMap { $0 }
        let next = ChallengeFactory.make(recentPlans: recentPlans, recentWorkouts: store.workouts,
                                         seenIDs: store.questSeenIDs, count: requestedCount,
                                         difficulty: requestedDifficulty, shuffled: true)
        store.challengePlans[key] = next
        remember(next.quests ?? [])
        leftQuestDay = ""
        showingShuffle = false
    }

    private var completedQuestCount: Int {
        Set(store.workouts.compactMap { workout -> String? in
            guard let day = workout.challengeDayKey else { return nil }
            return "\(day)/\(workout.challengeID ?? "legacy")"
        }).count
    }

    private var trophies: [Trophy] {
        let totalMinutes = store.workouts.reduce(0) { $0 + $1.minutes }
        let dailyNames = ["Koi Current", "Moonlit Bell", "Crimson Crane", "Quiet Thunder", "Iron Lantern",
                          "Silver Fox", "Rising Cedar", "Tidal Fox", "Golden Heron", "Storm Ink",
                          "Foxfire", "Night Bloom", "Mountain Echo", "Paper Tiger", "Sunrise Koi"]
        let daily = store.challengePlans.keys.sorted(by: >).compactMap { key -> Trophy? in
            guard let plan = store.challengePlans[key] else { return nil }
            let questIDs = plan.activeQuests(for: key).map(\.id)
            guard !questIDs.isEmpty else { return nil }
            let logged = Set(store.workouts.filter { $0.challengeDayKey == key }.compactMap(\.challengeID))
            let earned = questIDs.allSatisfy { logged.contains($0) }
            let nameIndex = key.utf8.reduce(0) { ($0 * 31 + Int($1)) % dailyNames.count }
            return Trophy(id: "daily-\(key)", title: "\(dailyNames[nameIndex]) · \(key.suffix(5))",
                          subtitle: "Finish the day's pack", symbol: "medal", earned: earned)
        }
        let shuffledPackEarned = store.challengePlans.contains { pair in
            let (key, plan) = pair
            guard plan.wasShuffled == true else { return false }
            let ids = plan.activeQuests(for: key).map(\.id)
            let logged = Set(store.workouts.filter { $0.challengeDayKey == key }.compactMap(\.challengeID))
            return !ids.isEmpty && ids.allSatisfy { logged.contains($0) }
        }
        return daily + [
            Trophy(id: "domino", title: "Domino Dealer", subtitle: "Finish a shuffled pack", symbol: "die.face.5", earned: shuffledPackEarned),
            Trophy(id: "first", title: store.trophyNames["first"] ?? "First spark", subtitle: "Log a workout", symbol: "figure.walk", earned: !store.workouts.isEmpty),
            Trophy(id: "century", title: store.trophyNames["century"] ?? "Sweat legend", subtitle: "Move 100 minutes", symbol: "flame", earned: totalMinutes >= 100),
            Trophy(id: "hunter", title: store.trophyNames["hunter"] ?? "Quest goblin", subtitle: "Finish 3 side quests", symbol: "bolt", earned: completedQuestCount >= 3),
            Trophy(id: "seven", title: store.trophyNames["seven"] ?? "Seven strong", subtitle: "Log 7 workouts", symbol: "7.circle", earned: store.workouts.count >= 7),
            Trophy(id: "long", title: store.trophyNames["long"] ?? "Moon mover", subtitle: "Move 500 minutes", symbol: "crown", earned: totalMinutes >= 500)
        ]
    }

    private func prepareMotivation() {
        let key = store.dayKey(.now)
        let previousPlans = store.challengePlans.keys.sorted().filter { $0 < key }
            .suffix(7).compactMap { store.challengePlans[$0] }
        if let old = store.challengePlans[key], old.quests == nil {
            let legacy = old.activeQuests(for: key)
            let plan = ChallengeFactory.make(recentPlans: previousPlans, recentWorkouts: store.workouts,
                                             seenIDs: store.questSeenIDs, locked: legacy)
            store.challengePlans[key] = plan
            remember(plan.quests ?? [])
        } else if store.challengePlans[key] == nil {
            let plan = ChallengeFactory.make(recentPlans: previousPlans, recentWorkouts: store.workouts,
                                             seenIDs: store.questSeenIDs)
            store.challengePlans[key] = plan
            remember(plan.quests ?? [])
        }
        let names: [String: [String]] = [
            "first": ["First spark", "Tiny thunder", "The starter kit"],
            "century": ["Sweat legend", "Century samurai", "100-minute hero"],
            "hunter": ["Quest goblin", "Side quest master", "Challenge collector"],
            "seven": ["Seven strong", "Lucky seven", "Week warrior"],
            "long": ["Moon mover", "Halfway to Mars", "The long game"]
        ]
        for (id, choices) in names where store.trophyNames[id] == nil {
            store.trophyNames[id] = choices.randomElement()!
        }
        if observedEarnedIDs == nil {
            observedEarnedIDs = Set(trophies.filter(\.earned).map(\.id))
        }
    }

    private func remember(_ quests: [ChallengeQuest]) {
        var history = store.questSeenIDs
        for quest in quests where !quest.id.hasPrefix("legacy-") {
            history.removeAll { $0 == quest.id }
            history.append(quest.id)
        }
        store.questSeenIDs = Array(history.suffix(100))
    }

    private func completeTodaysQuests() {
        let key = store.dayKey(.now)
        let newEntries = todaysQuests.filter { !completedQuestIDs.contains($0.id) }.map { quest in
            WorkoutEntry(date: .now, activity: "\(quest.category.capitalized) quest",
                         minutes: quest.estimatedMinutes, detail: quest.detail,
                         challengeDayKey: key, challengeID: quest.id)
        }
        guard !newEntries.isEmpty else { return }
        store.workouts.insert(contentsOf: newEntries, at: 0)
    }

    private func checkForNewAwards() {
        let current = Set(trophies.filter(\.earned).map(\.id))
        guard let previous = observedEarnedIDs else {
            observedEarnedIDs = current
            return
        }
        let newlyEarned = current.subtracting(previous)
        observedEarnedIDs = current
        pendingAwards += trophies.filter { newlyEarned.contains($0.id) }
        if !showingAdd { showNextAward() }
    }

    private func showNextAward() {
        guard activeAward == nil, !pendingAwards.isEmpty else { return }
        activeAward = pendingAwards.removeFirst()
    }

    private func dismissAward() {
        activeAward = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showNextAward() }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    NagisenPageHeading(kicker: "NAGISEN MOVE", title: "Keep moving",
                                       subtitle: Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()),
                                       accent: Theme.workout)

                    SpotifyMusicCard()

                    HStack(spacing: 23) {
                        ActivityRings(move: min(CGFloat(todayMinutes) / 30, 1),
                                      session: min(CGFloat(todayWorkouts.count), 1),
                                      challenge: CGFloat(completedQuestIDs.count) / CGFloat(max(todaysQuests.count, 1)))
                            .frame(width: 150, height: 150)
                        VStack(alignment: .leading, spacing: 14) {
                            ringLabel("MOVE", value: "\(todayMinutes) / 30 min", color: Theme.workout)
                            ringLabel("SESSIONS", value: "\(todayWorkouts.count) / 1", color: Theme.gold)
                            ringLabel("SIDE QUESTS", value: "\(completedQuestIDs.count) / \(todaysQuests.count)", color: Theme.slate)
                        }
                    }
                    .accentCardStyle(Theme.workout)

                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Label("TODAY'S SIDE QUESTS", systemImage: "bolt.heart")
                                .font(.caption2.weight(.semibold)).tracking(1.5)
                                .foregroundStyle(Theme.muted)
                            Spacer()
                            if challengeComplete {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.gold)
                            }
                            Button { showingShuffle = true } label: { DominoIcon() }
                                .foregroundStyle(Theme.accentText)
                                .accessibilityLabel("Shuffle side quests")
                        }
                        if leftQuestsToday {
                            HStack {
                                Text("Left for today").foregroundStyle(Theme.muted)
                                Spacer()
                                Button("Show set") { leftQuestDay = "" }
                                    .foregroundStyle(Theme.accentText)
                            }
                            .font(.subheadline)
                        } else {
                            ForEach(todaysQuests) { quest in
                                Rectangle().fill(Theme.line).frame(height: 1)
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: quest.symbol)
                                        .font(.title3).foregroundStyle(Theme.accentText)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(quest.category.uppercased())
                                            .font(.caption2.weight(.semibold)).tracking(1.5)
                                            .foregroundStyle(Theme.muted)
                                        Text(quest.title).font(.headline)
                                        Text(quest.detail)
                                            .font(.subheadline).foregroundStyle(Theme.muted)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                    if completedQuestIDs.contains(quest.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Theme.workout)
                                    }
                                }
                            }
                            HStack(spacing: 20) {
                                Button(challengeComplete ? "Done" : "Did all \(todaysQuests.count)") { completeTodaysQuests() }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.accentText)
                                    .disabled(challengeComplete || todaysQuests.isEmpty)
                                Button("Leave for today") { leftQuestDay = store.dayKey(.now) }
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.muted)
                                    .disabled(challengeComplete)
                            }
                        }
                    }
                    .accentCardStyle(Theme.gold)

                    Button { selectedQuest = nil; showingAdd = true } label: {
                        Label("Log a workout", systemImage: "plus")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Theme.red, in: RoundedRectangle(cornerRadius: 15))
                            .foregroundStyle(.white)
                    }

                    NavigationLink {
                        PersonalRecordsView()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "dumbbell.fill")
                                .font(.title2).foregroundStyle(Theme.workout)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Personal records")
                                    .font(.system(size: 22, design: .serif))
                                Text(store.strengthRecords.isEmpty ? "Track your best lifts" :
                                     "\(Set(store.strengthRecords.map { $0.exercise.lowercased() }).count) lifts tracked")
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                        }
                        .cardStyle()
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Text("TROPHY SHELF")
                                .font(.caption2.weight(.semibold)).tracking(2)
                                .foregroundStyle(Theme.muted)
                            Spacer()
                            Text("\(trophies.filter(\.earned).count) / \(trophies.count)")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 11) {
                                ForEach(trophies) { trophy in
                                    Button {
                                        if trophy.earned { activeAward = trophy }
                                    } label: {
                                    VStack(spacing: 7) {
                                        JapaneseTrophySeal(symbol: trophy.symbol, earned: trophy.earned, size: 60)
                                        Text(trophy.title).font(.caption.weight(.semibold)).lineLimit(1)
                                        Text(trophy.subtitle).font(.caption2).foregroundStyle(Theme.muted)
                                            .lineLimit(2).multilineTextAlignment(.center)
                                    }
                                    .frame(width: 110, height: 118)
                                    .opacity(trophy.earned ? 1 : 0.65)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!trophy.earned)
                                    .accessibilityLabel(trophy.earned ? "Replay \(trophy.title) trophy" : "\(trophy.title) trophy locked")
                                }
                            }
                        }
                    }
                    .accentCardStyle(Theme.gold)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("RECENT WORKOUTS")
                            .font(.caption2.weight(.semibold)).tracking(2)
                            .foregroundStyle(Theme.muted)
                        if recent.isEmpty {
                            Text("Log your first workout to start earning trophies.")
                                .font(.subheadline).foregroundStyle(Theme.muted)
                        } else {
                            ScrollView(.vertical) {
                                LazyVStack(spacing: 0) {
                                    ForEach(recent) { workout in
                                        Divider().overlay(Theme.line)
                                        HStack(spacing: 10) {
                                            Image(systemName: "figure.run").foregroundStyle(Theme.accentText)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(workout.activity)
                                                if let detail = workout.detail, !detail.isEmpty {
                                                    Text(detail).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                                                }
                                                Text(workout.date.formatted(date: .abbreviated, time: .omitted))
                                                    .font(.caption).foregroundStyle(Theme.muted)
                                            }
                                            Spacer(minLength: 4)
                                            Text("\(workout.minutes) min").foregroundStyle(Theme.muted)
                                            Button(role: .destructive) {
                                                store.workouts.removeAll { $0.id == workout.id }
                                            } label: { Image(systemName: "trash").font(.caption) }
                                                .accessibilityLabel("Delete \(workout.activity) workout")
                                        }
                                        .frame(height: 88)
                                    }
                                }
                            }
                            .frame(height: CGFloat(min(recent.count, 3)) * 88)
                            .scrollIndicators(recent.count > 3 ? .visible : .hidden)
                        }
                    }
                    .cardStyle()

                    NavigationLink {
                        HealthView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "heart.text.square.fill")
                                .font(.title2).foregroundStyle(Theme.accentText)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Apple Health").font(.subheadline.weight(.semibold))
                                Text("Steps, activity & workouts")
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }
                        .cardStyle()
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(Theme.ink)
                .padding(24)
                .padding(.bottom, 100)
            }
            .scrollClipDisabled()
            .softTopScrollEdgeEffect()
            .background(NagisenBackdrop())
            .tint(Theme.accentText)
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $showingAdd, onDismiss: {
                checkForNewAwards()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { showNextAward() }
            }) {
                NavigationStack { AddWorkoutView(challenge: selectedQuest) }
            }
            .fullScreenCover(item: $activeAward) { trophy in
                TrophyCelebrationView(trophy: trophy, onDismiss: dismissAward)
            }
            .sheet(isPresented: $showingShuffle) {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 12) {
                        DominoIcon().foregroundStyle(Theme.accentText)
                        Text("New quest pack").font(.system(size: 25, design: .serif))
                    }
                    Stepper("\(requestedCount) \(requestedCount == 1 ? "exercise" : "exercises")",
                            value: $requestedCount, in: 1...5)
                        .font(.headline)
                    Picker("Difficulty", selection: $requestedDifficulty) {
                        ForEach(ChallengeFactory.Difficulty.allCases) { difficulty in
                            Text(difficulty.rawValue).tag(difficulty)
                        }
                    }
                    .pickerStyle(.segmented)
                    Button("Shuffle pack") { shufflePack() }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(.white)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(24)
                .background(NagisenBackdrop())
                .foregroundStyle(Theme.ink)
                .presentationDetents([.height(315)])
            }
            .onChange(of: store.workouts.count) { _, _ in checkForNewAwards() }
            .onAppear(perform: prepareMotivation)
        }
    }

    private func ringLabel(_ name: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted)
                Text(value).font(.subheadline.weight(.medium))
            }
        }
    }
}

private struct TrophyCelebrationView: View {
    let trophy: Trophy
    let onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    @State private var confettiTrigger = 0
    @State private var soundPlayer: AVAudioPlayer?

    var body: some View {
        ZStack {
            JapanesePrintBackdrop()
                .ignoresSafeArea()

            SakuraPetalRain()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(spacing: 20) {
                Spacer()
                JapaneseTrophySeal(symbol: trophy.symbol, earned: true, size: 228)
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 11)
                .frame(height: 270)
                .scaleEffect(revealed ? 1 : 0.3)
                .rotation3DEffect(.degrees(reduceMotion ? 0 : (revealed ? 0 : -70)), axis: (x: 0, y: 1, z: 0))
                .opacity(revealed ? 1 : 0)
                .confettiCannon(trigger: $confettiTrigger,
                                num: 28,
                                confettis: [.sfSymbol(symbolName: "leaf.fill"), .shape(.circle)],
                                colors: [Theme.gold, Theme.red, Theme.moss],
                                confettiSize: 10,
                                rainHeight: 600,
                                openingAngle: .degrees(0),
                                closingAngle: .degrees(360),
                                radius: 280,
                                repetitions: 1,
                                repetitionInterval: 0.35,
                                hapticFeedback: false)

                Text(trophy.title)
                    .font(.custom("Baskerville", size: 43, relativeTo: .largeTitle))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(red: 0.99, green: 0.94, blue: 0.83))
                    .shadow(color: .black.opacity(0.85), radius: 9)
                    .opacity(revealed ? 1 : 0)
                Text(trophy.subtitle)
                    .font(.custom("AvenirNext-Medium", size: 17, relativeTo: .subheadline))
                    .foregroundStyle(Color(red: 0.94, green: 0.84, blue: 0.67))
                    .shadow(color: .black.opacity(0.85), radius: 8)
                    .opacity(revealed ? 1 : 0)
                Spacer()
                Button(action: onDismiss) {
                    Text("Keep moving")
                        .font(.custom("AvenirNext-DemiBold", size: 16, relativeTo: .body))
                        .foregroundStyle(Color(red: 0.25, green: 0.13, blue: 0.16))
                        .padding(.horizontal, 29)
                        .frame(height: 48)
                        .background(Color(red: 0.98, green: 0.92, blue: 0.82), in: Capsule())
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                }
                .padding(.bottom, 26)
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            playCelebration()
            withAnimation(reduceMotion ? .none : .spring(response: 0.85, dampingFraction: 0.68)) {
                revealed = true
            }
            if !reduceMotion {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { confettiTrigger += 1 }
            }
        }
    }

    private func playCelebration() {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.prepare()
        feedback.impactOccurred(intensity: 0.55)
        guard let url = Bundle.main.url(forResource: "trophy_koto", withExtension: "wav") else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            soundPlayer = try AVAudioPlayer(contentsOf: url)
            soundPlayer?.prepareToPlay()
            soundPlayer?.play()
        } catch {
            // The visual and haptic celebration still work when audio is unavailable.
        }
    }
}

private struct JapanesePrintBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            Image(colorScheme == .dark ? "TrophyPrintNight" : "TrophyPrintDay")
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
        .accessibilityHidden(true)
    }
}

private struct JapaneseWavePattern: View {
    let color: Color
    let radius: CGFloat

    var body: some View {
        Canvas { context, size in
            let rowHeight = radius * 0.87
            let rows = Int(size.height / rowHeight) + 2
            let columns = Int(size.width / (radius * 2)) + 3
            for row in 0..<rows {
                for column in 0..<columns {
                    let x = CGFloat(column) * radius * 2 + (row.isMultiple(of: 2) ? 0 : radius) - radius
                    let y = CGFloat(row) * rowHeight
                    for inset in [CGFloat.zero, radius * 0.34, radius * 0.68] {
                        var wave = Path()
                        wave.addArc(center: CGPoint(x: x, y: y), radius: radius - inset,
                                    startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                        context.stroke(wave, with: .color(color), lineWidth: 1)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct JapaneseTrophySeal: View {
    @Environment(\.colorScheme) private var colorScheme
    let symbol: String
    let earned: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(earned ? Theme.red : Theme.line)
            JapaneseWavePattern(color: (earned ? Theme.gold : Theme.muted).opacity(0.23), radius: size * 0.11)
                .clipShape(Circle())
            ForEach(0..<12, id: \.self) { ray in
                Rectangle()
                    .fill(earned ? Theme.gold.opacity(0.7) : Theme.muted.opacity(0.3))
                    .frame(width: max(1, size * 0.006), height: size * 0.11)
                    .offset(y: -size * 0.37)
                    .rotationEffect(.degrees(Double(ray) * 30))
            }
            Circle()
                .fill(earned ? Theme.paper : Theme.surface)
                .frame(width: size * 0.64, height: size * 0.64)
                .overlay {
                    Circle().strokeBorder(earned ? Theme.gold : Theme.muted.opacity(0.5), lineWidth: max(1, size * 0.012))
                }
            Circle()
                .fill(earned ? Theme.gold.opacity(0.18) : Theme.line)
                .frame(width: size * 0.52, height: size * 0.52)
            Image(systemName: symbol)
                .font(.system(size: size * 0.31, weight: .light))
                .foregroundStyle(earned ? (colorScheme == .dark ? Theme.gold : Theme.red) : Theme.muted)
                .symbolRenderingMode(.hierarchical)
            Circle()
                .strokeBorder(earned ? Theme.gold : Theme.muted.opacity(0.5), lineWidth: max(1, size * 0.013))
            Circle()
                .strokeBorder(Theme.paper.opacity(0.8), lineWidth: max(1, size * 0.006))
                .padding(size * 0.035)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct SakuraPetalRain: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                Canvas { context, size in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    for index in 0..<16 {
                        let progress = (time / (7.5 + Double(index % 4)) + Double(index) / 16).truncatingRemainder(dividingBy: 1)
                        let x = size.width * CGFloat(Double((index * 37 + 9) % 100) / 100) + CGFloat(sin(time + Double(index)) * 21)
                        let y = CGFloat(progress) * (size.height + 30) - 15
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: y - 5))
                        path.addQuadCurve(to: CGPoint(x: x, y: y + 6), control: CGPoint(x: x + 8, y: y))
                        path.addQuadCurve(to: CGPoint(x: x, y: y - 5), control: CGPoint(x: x - 6, y: y))
                        context.fill(path, with: .color(index.isMultiple(of: 3) ? Theme.gold.opacity(0.50) : Theme.red.opacity(0.65)))
                    }
                }
            }
        }
    }
}

private struct ActivityRings: View {
    let move: CGFloat
    let session: CGFloat
    let challenge: CGFloat

    var body: some View {
        ZStack {
            ring(move, color: Theme.workout, size: 150)
            ring(session, color: Theme.gold, size: 112)
            ring(challenge, color: Theme.slate, size: 74)
            Image(systemName: "figure.run")
                .font(.title3)
                .foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity rings")
    }

    private func ring(_ progress: CGFloat, color: Color, size: CGFloat) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: 11)
            Circle().trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

private struct SpotifyMusicCard: View {
    @EnvironmentObject private var spotify: SpotifyManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MUSIC")
                .font(.caption2.weight(.semibold)).tracking(2.2)
                .foregroundStyle(Theme.muted)
            HStack(spacing: 12) {
                trackButton("backward.end.fill", label: "Previous Spotify song") {
                    spotify.previousTrack()
                }
                .frame(maxWidth: .infinity)
                Group {
                    if let artwork = spotify.artwork {
                        Image(uiImage: artwork).resizable().scaledToFill()
                    } else {
                        Image(systemName: "music.note")
                            .font(.title)
                            .foregroundStyle(Theme.accentText)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.surface.opacity(0.4))
                    }
                }
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 17))
                .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(Theme.line, lineWidth: 1))
                trackButton("forward.end.fill", label: "Next Spotify song") {
                    spotify.nextTrack()
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 4) {
                Text(spotify.trackName ?? "Spotify")
                    .font(.system(size: 20, design: .serif))
                    .lineLimit(2)
                Text(spotify.artistName ?? spotify.status)
                    .font(.caption).foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            HStack {
                if !spotify.isConnected {
                    Button(spotify.hasSavedAuthorization ? "Reconnect Spotify" : "Connect Spotify") {
                        if spotify.hasSavedAuthorization { spotify.authorizeAgain() }
                        else { spotify.connect() }
                    }
                        .font(.subheadline.weight(.semibold))
                        .disabled(!spotify.isConfigured)
                } else {
                    Label(spotify.status, systemImage: "waveform")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Link("Open Spotify", destination: URL(string: "https://open.spotify.com/")!)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .cardStyle()
        .onAppear { spotify.connectIfAuthorized() }
    }

    private func trackButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(width: 48, height: 48)
                .nagisenGlass(in: Circle(), tint: Theme.surface.opacity(0.08))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .disabled(!spotify.isConnected)
        .opacity(spotify.isConnected ? 1 : 0.4)
    }
}

private enum BodybuildingExerciseCatalog {
    static let groups: [(String, [String])] = [
        ("Chest & shoulders", ["Bench press", "Incline dumbbell press", "Cable fly", "Overhead press", "Lateral raise"]),
        ("Back & arms", ["Pull-up", "Lat pulldown", "Barbell row", "Seated cable row", "Biceps curl", "Triceps pushdown"]),
        ("Legs & core", ["Squat", "Romanian deadlift", "Leg press", "Split squat", "Leg curl", "Calf raise", "Plank"])
    ]
    static let all = groups.flatMap { $0.1 }
}

private struct PersonalRecordsView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingAdd = false

    private var exerciseNames: [String] {
        Array(Set(store.strengthRecords.map(\.exercise))).sorted()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                NagisenHeader("Personal records", subtitle: "Your strongest lifts, over time.", onBack: { dismiss() })
                Button { showingAdd = true } label: {
                    Label("Add a lift", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(.white)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                if exerciseNames.isEmpty {
                    Text("Log a lift with its weight and reps to start tracking your best.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                        .cardStyle()
                }
                ForEach(exerciseNames, id: \.self) { exercise in
                    let history = store.strengthRecords.filter { $0.exercise == exercise }
                        .sorted { $0.date > $1.date }
                    if let best = history.max(by: { left, right in
                        left.kilograms == right.kilograms ? left.reps < right.reps : left.kilograms < right.kilograms
                    }) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(exercise).font(.system(size: 23, design: .serif))
                                Spacer()
                                Image(systemName: "medal.fill").foregroundStyle(Theme.gold)
                            }
                            Text("\(best.kilograms.formatted(.number.precision(.fractionLength(0...1)))) kg × \(best.reps) reps")
                                .font(.title3.weight(.semibold))
                            Text("Best recorded lift · \(best.date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(Theme.muted)
                            DisclosureGroup("History · \(history.count)") {
                                ForEach(history) { record in
                                    HStack {
                                        Text(record.date.formatted(date: .abbreviated, time: .omitted))
                                        Spacer()
                                        Text("\(record.kilograms.formatted(.number.precision(.fractionLength(0...1)))) kg × \(record.reps)")
                                        Button(role: .destructive) {
                                            store.strengthRecords.removeAll { $0.id == record.id }
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .accessibilityLabel("Delete \(exercise) record")
                                    }
                                    .font(.caption)
                                    .padding(.top, 8)
                                }
                            }
                            .font(.subheadline)
                        }
                        .cardStyle()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 100)
        }
        .background(NagisenBackdrop())
        .foregroundStyle(Theme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingAdd) {
            RecordLiftView()
                .environmentObject(store)
        }
    }
}

private struct RecordLiftView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    @State private var exercise = "Bench press"
    @State private var customExercise = ""
    @State private var kilograms = ""
    @State private var reps = ""
    @State private var date = Date.now

    private var validRecord: StrengthRecord? {
        let name = (exercise == "Custom exercise" ? customExercise : exercise)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80,
              let weight = Double(kilograms.replacingOccurrences(of: ",", with: ".")),
              let repetitions = Int(reps), (0...1000).contains(weight),
              (1...100).contains(repetitions) else { return nil }
        return StrengthRecord(exercise: name, kilograms: weight, reps: repetitions, date: date)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                NagisenHeader("Log a lift", subtitle: "Weight and reps are saved on this iPhone.",
                              symbol: "xmark", onBack: { dismiss() })
                NagisenSection("Exercise") {
                    Picker("Exercise", selection: $exercise) {
                        ForEach(BodybuildingExerciseCatalog.all + ["Custom exercise"], id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .frame(minHeight: 50)
                    if exercise == "Custom exercise" {
                        TextField("Exercise name", text: $customExercise)
                            .frame(minHeight: 50)
                    }
                }
                NagisenSection("Lift") {
                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField("kg", text: $kilograms)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("kg").foregroundStyle(Theme.muted)
                    }
                    .frame(minHeight: 50)
                    Divider()
                    HStack {
                        Text("Reps")
                        Spacer()
                        TextField("1", text: $reps)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                    .frame(minHeight: 50)
                    Divider()
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                        .frame(minHeight: 50)
                }
                Button("Save lift") {
                    guard let record = validRecord else { return }
                    store.strengthRecords.insert(record, at: 0)
                    dismiss()
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(.white)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                .disabled(validRecord == nil)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(NagisenBackdrop())
        .foregroundStyle(Theme.ink)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
}

private struct AddWorkoutView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    let challenge: ChallengeQuest?
    @State private var activity: String
    @State private var minutes: String
    @State private var detail: String
    @State private var date = Date.now
    @State private var selectedBodybuildingExercises: Set<String> = []
    @State private var liftWeights: [String: String] = [:]
    @State private var liftReps: [String: String] = [:]

    init(challenge: ChallengeQuest? = nil) {
        self.challenge = challenge
        _activity = State(initialValue: challenge == nil ? "Walking" : "Hybrid quest")
        _minutes = State(initialValue: String(challenge?.estimatedMinutes ?? 30))
        _detail = State(initialValue: challenge?.detail ?? "")
    }

    private let activities: [(String, String)] = [
        ("Walking", "figure.walk"), ("Running", "figure.run"),
        ("Strength", "dumbbell"), ("Bodybuilding", "figure.strengthtraining.traditional"),
        ("Treadmill", "figure.run.treadmill"),
        ("StairMaster", "figure.stairs"), ("Boxing", "figure.boxing"),
        ("Cycling", "bicycle"), ("Yoga", "figure.yoga"),
        ("Swimming", "figure.pool.swim"), ("Hybrid quest", "bolt.heart"),
        ("Other", "figure.mixed.cardio")
    ]

    private func recordedLift(for exercise: String) -> StrengthRecord? {
        guard let weight = Double((liftWeights[exercise] ?? "").replacingOccurrences(of: ",", with: ".")),
              let reps = Int(liftReps[exercise] ?? ""),
              (0...1000).contains(weight), (1...100).contains(reps) else { return nil }
        return StrengthRecord(exercise: exercise, kilograms: weight, reps: reps, date: date)
    }

    private var hasInvalidLift: Bool {
        selectedBodybuildingExercises.contains { exercise in
            let weight = liftWeights[exercise] ?? ""
            let reps = liftReps[exercise] ?? ""
            return (!weight.isEmpty || !reps.isEmpty) && recordedLift(for: exercise) == nil
        }
    }

    private var validMinutes: Int? {
        guard let value = Int(minutes), (1...1440).contains(value),
              activity != "Bodybuilding" || (!selectedBodybuildingExercises.isEmpty && !hasInvalidLift) else { return nil }
        return value
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                NagisenHeader("Log workout", subtitle: "A session worth remembering.", symbol: "xmark", onBack: { dismiss() })
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: challenge?.symbol ?? "figure.run")
                        .font(.system(size: 27)).foregroundStyle(Theme.accentText)
                        .frame(width: 54, height: 54)
                        .background(Theme.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 13))
                    Text(challenge?.title ?? "Make it count")
                        .font(.system(size: 25, design: .serif))
                    Text(challenge == nil ? "Every session adds to your rings and trophies." : "Finish the quest, then save your session to earn the ring.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                NagisenSection("Choose your move") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
                        ForEach(activities, id: \.0) { item in
                            Button { activity = item.0 } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: item.1).frame(width: 20)
                                    Text(item.0).lineLimit(1).minimumScaleFactor(0.8)
                                    Spacer(minLength: 2)
                                    if activity == item.0 { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                                }
                                .font(.subheadline.weight(activity == item.0 ? .semibold : .regular))
                                .foregroundStyle(activity == item.0 ? Theme.accentText : Theme.ink)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .padding(.horizontal, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if activity == "Bodybuilding" {
                    NagisenSection("Pick your exercises") {
                        Text("Add kg and reps to track a personal record.")
                            .font(.caption).foregroundStyle(Theme.muted)
                        ForEach(BodybuildingExerciseCatalog.groups.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(BodybuildingExerciseCatalog.groups[index].0.uppercased())
                                    .font(.caption2.weight(.semibold)).tracking(1.5)
                                    .foregroundStyle(Theme.muted)
                                ForEach(BodybuildingExerciseCatalog.groups[index].1, id: \.self) { exercise in
                                    Button {
                                        if selectedBodybuildingExercises.contains(exercise) {
                                            selectedBodybuildingExercises.remove(exercise)
                                        } else {
                                            selectedBodybuildingExercises.insert(exercise)
                                        }
                                    } label: {
                                        HStack {
                                            Text(exercise)
                                            Spacer()
                                            Image(systemName: selectedBodybuildingExercises.contains(exercise) ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(selectedBodybuildingExercises.contains(exercise) ? Theme.accentText : Theme.muted)
                                        }
                                        .font(.subheadline)
                                        .frame(minHeight: 42)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    if selectedBodybuildingExercises.contains(exercise) {
                                        HStack(spacing: 12) {
                                            TextField("Weight (kg)", text: Binding(
                                                get: { liftWeights[exercise] ?? "" },
                                                set: { liftWeights[exercise] = $0 }
                                            ))
                                            .keyboardType(.decimalPad)
                                            TextField("Reps", text: Binding(
                                                get: { liftReps[exercise] ?? "" },
                                                set: { liftReps[exercise] = $0 }
                                            ))
                                            .keyboardType(.numberPad)
                                        }
                                        .textFieldStyle(.roundedBorder)
                                    }
                                }
                            }
                        }
                    }
                }

                NagisenSection("Session details") {
                    HStack {
                        Image(systemName: "timer").foregroundStyle(Theme.accentText)
                        Text("Minutes")
                        Spacer()
                        TextField("30", text: $minutes)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .frame(width: 70)
                    }
                    .frame(minHeight: 54)
                    Divider()
                    TextField("Reps, weight, incline, rounds…", text: $detail, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(.vertical, 15)
                    Divider()
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                        .frame(minHeight: 54)
                        .disabled(challenge != nil)
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 100)
        }
        .background(NagisenBackdrop())
        .scrollDismissesKeyboard(.interactively)
        .tint(Theme.accentText)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            NagisenPrimaryButton(challenge == nil ? "Save workout" : "Finish quest", enabled: validMinutes != nil) {
                guard let value = validMinutes else { return }
                let note = detail.trimmingCharacters(in: .whitespacesAndNewlines)
                let exerciseList = activity == "Bodybuilding" ? selectedBodybuildingExercises.sorted().joined(separator: ", ") : ""
                let savedDetail = [exerciseList, note].filter { !$0.isEmpty }.joined(separator: " · ")
                if activity == "Bodybuilding" {
                    let records = selectedBodybuildingExercises.sorted().compactMap(recordedLift(for:))
                    store.strengthRecords.insert(contentsOf: records, at: 0)
                }
                store.workouts.insert(WorkoutEntry(date: date, activity: activity, minutes: value,
                                                   detail: savedDetail,
                                                   challengeDayKey: challenge == nil ? nil : store.dayKey(.now),
                                                   challengeID: challenge?.id), at: 0)
                dismiss()
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Theme.paper)
        }
    }
}
