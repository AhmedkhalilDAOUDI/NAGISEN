import SwiftUI

/// The kind of session someone feels like doing today. Raw values double as the logged activity name.
enum SessionType: String, CaseIterable, Identifiable {
    case cardio = "Cardio"
    case calisthenics = "Calisthenics"
    case strength = "Strength"
    case boxing = "Boxing"
    case bodybuilding = "Bodybuilding"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .cardio: "figure.run"
        case .calisthenics: "figure.core.training"
        case .strength: "dumbbell"
        case .boxing: "figure.boxing"
        case .bodybuilding: "figure.strengthtraining.traditional"
        }
    }
}

struct SessionMove: Hashable {
    /// English, translated when shown, like the other exercise names.
    let name: String
    /// Already in the reader's language.
    let dose: String
}

struct SessionBlock: Identifiable {
    var id: String { title }
    let title: String
    let minutes: Int
    var note: String? = nil
    let moves: [SessionMove]
}

struct SessionPlan {
    let type: SessionType
    let minutes: Int
    let focus: String?
    let blocks: [SessionBlock]

    /// What the workout log keeps: the focus and the main moves.
    var summary: String {
        let main = blocks.filter { $0.title == "Main" }.flatMap(\.moves).map { ui($0.name) }
        return ([focus.map(ui)].compactMap { $0 } + [main.joined(separator: ", ")]).joined(separator: " · ")
    }
}

/// Builds a full session from a curated library: warm-up, main work, an optional finisher and a cool-down,
/// adding up to the chosen length.
enum SessionPlanner {
    static let lengths = [30, 45, 60]
    static var bodybuildingFocuses: [String] { BodybuildingExerciseCatalog.groups.map(\.0) }

    static func make<R: RandomNumberGenerator>(_ type: SessionType, minutes: Int, focus: String? = nil,
                                               using rng: inout R) -> SessionPlan {
        let warm = 5, cool = 5
        let finisher = minutes >= 45 ? 5 : 0
        let main = minutes - warm - cool - finisher
        var blocks = [SessionBlock(title: "Warm-up", minutes: warm,
                                   moves: pick(type == .boxing ? boxingWarmUp : warmUp, 3, &rng).map { minute($0) })]
        var chosenFocus: String?

        switch type {
        case .strength:
            let patterns = Array(strengthPatterns.shuffled(using: &rng).prefix(minutes / 15))
            let scheme = ["5 × 5", "4 × 6", "5 × 3"].randomElement(using: &rng)!
            blocks.append(SessionBlock(title: "Main", minutes: main,
                                       note: String(localized: "Rest 2–3 min between sets. Warm up each lift with two lighter sets."),
                                       moves: patterns.map { SessionMove(name: $0.randomElement(using: &rng)!, dose: scheme) }))
        case .bodybuilding:
            let groups = BodybuildingExerciseCatalog.groups
            let group = groups.first { $0.0 == focus } ?? groups.randomElement(using: &rng)!
            chosenFocus = group.0
            let count = min(group.1.count, minutes / 10 + 1)
            // The catalog lists compound lifts first; keep that order so heavy work comes before isolation.
            let chosen = Set(group.1.shuffled(using: &rng).prefix(count))
            let moves = group.1.filter(chosen.contains).enumerated().map { index, name in
                SessionMove(name: name, dose: index == 0 ? sets(4, 8) : sets(3, [10, 12].randomElement(using: &rng)!))
            }
            blocks.append(SessionBlock(title: "Main", minutes: main,
                                       note: String(localized: "Rest 60–90 s. Lower the weight slowly."), moves: moves))
        case .calisthenics:
            let rounds = minutes / 15 + 1
            var moves = calisthenics.map { pool in pool.randomElement(using: &rng)! }
            if minutes >= 60 { moves.append(calisthenicsExtra.randomElement(using: &rng)!) }
            blocks.append(SessionBlock(title: "Main", minutes: main,
                                       note: String(localized: "\(rounds) rounds. Rest 90 s between rounds."),
                                       moves: moves.map { SessionMove(name: $0.0, dose: $0.1) }))
        case .boxing:
            let rounds = main / 4
            let combos = pick(boxingCombos, rounds - 1, &rng) + ["Power round: everything you have"]
            blocks.append(SessionBlock(title: "Main", minutes: main,
                                       note: String(localized: "3-min rounds, 1 min rest. Heavy bag or shadow."),
                                       moves: combos.enumerated().map { SessionMove(name: $1, dose: String(localized: "Round \($0 + 1)")) }))
        case .cardio:
            let machines = pick(cardioMachines, main >= 40 ? 2 : 1, &rng)
            let share = main / machines.count
            let firstIntervals = Bool.random(using: &rng)
            let moves = machines.enumerated().map { index, machine in
                let intervals = (index == 0) == firstIntervals
                return SessionMove(name: machine, dose: intervals
                    ? String(localized: "\(share / 2) × 1 min hard, 1 min easy")
                    : String(localized: "\(share) min steady, able to talk"))
            }
            blocks.append(SessionBlock(title: "Main", minutes: main, moves: moves))
        }

        if finisher > 0 {
            let pool = type == .boxing ? boxingFinisher : core
            blocks.append(SessionBlock(title: "Finisher", minutes: finisher,
                                       moves: pick(pool, 2, &rng).map { SessionMove(name: $0.0, dose: $0.1) }))
        }
        blocks.append(SessionBlock(title: "Cool-down", minutes: cool, moves: pick(coolDown, 3, &rng).map { minute($0) }))
        return SessionPlan(type: type, minutes: minutes, focus: chosenFocus, blocks: blocks)
    }

    private static func pick<T, R: RandomNumberGenerator>(_ pool: [T], _ count: Int, _ rng: inout R) -> [T] {
        Array(pool.shuffled(using: &rng).prefix(count))
    }

    private static func minute(_ name: String) -> SessionMove { SessionMove(name: name, dose: String(localized: "1 min")) }
    private static func sets(_ sets: Int, _ reps: Int) -> String { "\(sets) × \(reps)" }
    private static func reps(_ count: Int) -> String { String(localized: "\(count) reps") }
    private static func hold(_ seconds: Int) -> String { String(localized: "\(seconds) s") }

    private static let warmUp = ["Jumping jacks", "Arm circles", "Hip openers", "Bodyweight squats",
                                 "Inchworms", "World's greatest stretch", "Jump rope", "Band pull-aparts"]
    private static let boxingWarmUp = ["Jump rope", "Shadow boxing, light", "Arm circles", "Footwork drill"]
    private static let coolDown = ["Child's pose", "Hamstring stretch", "Hip flexor stretch", "Chest opener",
                                   "Lat stretch", "Box breathing", "Calf stretch", "Thread the needle"]
    private static let strengthPatterns = [["Back squat", "Front squat"], ["Deadlift", "Romanian deadlift"],
                                           ["Bench press", "Overhead press"], ["Barbell row", "Weighted pull-up"]]
    private static var calisthenics: [[(String, String)]] {
        [[("Pull-ups", reps(8)), ("Inverted rows", reps(12)), ("Chin-ups", reps(8))],
         [("Push-ups", reps(15)), ("Dips", reps(10)), ("Pike push-ups", reps(10))],
         [("Jump squats", reps(15)), ("Walking lunges", reps(20)), ("Assisted pistol squats", reps(8))],
         [("Hollow hold", hold(30)), ("Hanging leg raises", reps(10)), ("L-sit", hold(20))]]
    }
    private static var calisthenicsExtra: [(String, String)] { [("Burpees", reps(10)), ("Mountain climbers", hold(40))] }
    private static let boxingCombos = ["Jab–cross", "Jab–cross–hook", "Double jab–cross", "Jab–cross–slip–cross",
                                       "Hook–uppercut–hook", "Body jab–head cross", "Slip, roll and counter",
                                       "Jab–cross–body hook–head hook", "Footwork and jab", "Uppercuts in close"]
    private static let cardioMachines = ["Treadmill", "Rower", "Assault bike", "StairMaster", "Bike"]
    private static var core: [(String, String)] {
        [("Plank", hold(45)), ("Hanging knee raises", reps(12)), ("Russian twists", reps(20)),
         ("Dead bug", reps(12)), ("Side plank", hold(30))]
    }
    private static var boxingFinisher: [(String, String)] {
        [("Bag sprints", String(localized: "8 × 20 s all out")), ("Burpees", reps(10)),
         ("Plank", hold(45)), ("Russian twists", reps(20))]
    }
}

// MARK: - Views

/// Workouts card: choose the kind of session, then get a full one.
struct SessionPickerCard: View {
    let onPick: (SessionType) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TODAY'S SESSION")
                .font(.caption2.weight(.semibold)).nagisenTracking(1.6)
                .foregroundStyle(Theme.muted)
            Text("What do you feel like doing?")
                .font(.system(size: 19, design: .serif))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                ForEach(SessionType.allCases) { type in
                    Button { onPick(type) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: type.symbol).frame(width: 22)
                            Text(ui: type.rawValue).lineLimit(1).minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 14).frame(height: 44)
                        .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.16), lineWidth: 0.5))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .cardStyle()
    }
}

struct SessionView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    @State private var type: SessionType
    @AppStorage("nagisen.session.minutes") private var minutes = 45
    @State private var focus: String?
    @State private var plan: SessionPlan?

    init(type: SessionType) { _type = State(initialValue: type) }

    /// Bodybuilding follows today's split when it names a muscle group.
    private var splitFocus: String? {
        let today = store.workoutSplit?.focus(on: .now).lowercased() ?? ""
        let match = ["push": "Chest & shoulders", "chest": "Chest & shoulders", "pull": "Back & arms",
                     "back": "Back & arms", "leg": "Legs & core", "lower": "Legs & core"]
        return match.first { today.contains($0.key) }?.value
    }

    private func build() {
        var rng = SystemRandomNumberGenerator()
        plan = SessionPlanner.make(type, minutes: minutes, focus: type == .bodybuilding ? focus : nil, using: &rng)
        focus = plan?.focus
    }

    private func log() {
        guard let plan else { return }
        store.workouts.insert(WorkoutEntry(date: .now, activity: plan.type.rawValue, minutes: plan.minutes,
                                           detail: plan.summary), at: 0)
        dismiss()
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(ui: title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 14).frame(height: 36)
                .foregroundStyle(selected ? Color.white : Theme.ink)
                .background(selected ? Theme.accent : Color.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.ink.opacity(selected ? 0 : 0.16), lineWidth: 0.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                NagisenHeader(type.rawValue, subtitle: String(localized: "A full session, ready to go."),
                              symbol: "xmark", onBack: { dismiss() })

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SessionType.allCases) { option in
                            chip(option.rawValue, selected: option == type) { type = option; focus = nil; build() }
                        }
                    }
                }
                .scrollClipDisabled()

                HStack(spacing: 8) {
                    ForEach(SessionPlanner.lengths, id: \.self) { length in
                        chip(String(localized: "\(length) min"), selected: length == minutes) { minutes = length; build() }
                    }
                }

                if type == .bodybuilding {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(SessionPlanner.bodybuildingFocuses, id: \.self) { option in
                                chip(option, selected: option == focus) { focus = option; build() }
                            }
                        }
                    }
                    .scrollClipDisabled()
                }

                if let plan {
                    ForEach(plan.blocks) { block in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(ui: block.title).textCase(.uppercase)
                                    .font(.caption2.weight(.semibold)).nagisenTracking(1.6)
                                    .foregroundStyle(Theme.muted)
                                Spacer()
                                Text("\(block.minutes) min").font(.caption).foregroundStyle(Theme.muted)
                            }
                            ForEach(block.moves, id: \.self) { move in
                                Rectangle().fill(Theme.line).frame(height: 1)
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text(ui: move.name).font(.headline)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 8)
                                    Text(move.dose).font(.subheadline).foregroundStyle(Theme.accentText)
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                            if let note = block.note {
                                Text(note).font(.footnote).foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .cardStyle()
                    }

                    RestGameCard()

                    HStack(spacing: 12) {
                        Button { withAnimation(.easeInOut(duration: 0.25)) { build() } } label: {
                            Label("Shuffle", systemImage: "shuffle")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity).frame(height: 52)
                                .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Theme.ink.opacity(0.16), lineWidth: 0.5))
                        }
                        Button(action: log) {
                            Label("Log session", systemImage: "checkmark")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity).frame(height: 52)
                                .background(Theme.red, in: RoundedRectangle(cornerRadius: 15))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(24)
        }
        .background(NagisenBackdrop())
        .tint(Theme.accentText)
        .onAppear {
            if focus == nil { focus = splitFocus }
            if plan == nil { build() }
        }
    }
}
