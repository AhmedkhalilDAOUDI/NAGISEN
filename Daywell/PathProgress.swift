import Foundation

/// The border a member earns around their profile picture.
enum BorderTier: Int, CaseIterable, Comparable {
    case none = 0, washi, copper, silver, gold, jade

    /// Points needed to reach each border. Tune here; nothing else hard-codes them.
    var threshold: Int {
        switch self {
        case .none: 0
        case .washi: 5
        case .copper: 15
        case .silver: 35
        case .gold: 70
        case .jade: 120
        }
    }

    var name: String {
        switch self {
        case .none: "No border yet"
        case .washi: "Washi"
        case .copper: "Copper"
        case .silver: "Silver"
        case .gold: "Gold"
        case .jade: "Jade"
        }
    }

    var next: BorderTier? { BorderTier(rawValue: rawValue + 1) }

    static func < (lhs: BorderTier, rhs: BorderTier) -> Bool { lhs.rawValue < rhs.rawValue }

    static func forPoints(_ points: Int) -> BorderTier {
        allCases.last { points >= $0.threshold } ?? .none
    }
}

/// Points toward the next border, counted from what NAGISEN already records.
/// Worked out on the phone and saved to the member's profile, so it can be faked by someone
/// determined to; it is a personal motivator, not a verified ranking.
struct PathProgress {
    static let pointsPerPack = 1
    static let pointsPerRecord = 1
    static let pointsPerMilestone = 2

    let finishedPacks: Int
    let personalRecords: Int
    let milestones: Int

    var points: Int {
        finishedPacks * Self.pointsPerPack + personalRecords * Self.pointsPerRecord +
            milestones * Self.pointsPerMilestone
    }
    var tier: BorderTier { BorderTier.forPoints(points) }
    var pointsToNext: Int? { tier.next.map { $0.threshold - points } }

    /// 0…1 progress from the current border to the next; 1 at the last border.
    var fractionToNext: Double {
        guard let next = tier.next else { return 1 }
        let span = next.threshold - tier.threshold
        return Double(points - tier.threshold) / Double(span)
    }

    init(finishedPacks: Int, personalRecords: Int, milestones: Int) {
        self.finishedPacks = finishedPacks
        self.personalRecords = personalRecords
        self.milestones = milestones
    }

    init(workouts: [WorkoutEntry], plans: [String: ChallengePlan], lifts: [StrengthRecord]) {
        let packs = Milestones.finishedPackDays(workouts: workouts, plans: plans)
        self.init(finishedPacks: packs.count,
                  personalRecords: Self.recordCount(lifts),
                  milestones: Milestones(workouts: workouts, plans: plans).earnedCount)
    }

    /// Lifts that beat the previous best for the same exercise: heavier, or the same weight for
    /// more reps (the comparison Personal records uses). An exercise's first lift is the baseline.
    static func recordCount(_ lifts: [StrengthRecord]) -> Int {
        var best: [String: StrengthRecord] = [:]
        var count = 0
        for lift in lifts.sorted(by: { $0.date < $1.date }) {
            let key = lift.exercise.trimmingCharacters(in: .whitespaces).lowercased()
            if let previous = best[key] {
                let heavier = lift.kilograms > previous.kilograms
                let moreReps = lift.kilograms == previous.kilograms && lift.reps > previous.reps
                if heavier || moreReps { count += 1; best[key] = lift }
            } else {
                best[key] = lift
            }
        }
        return count
    }
}

/// The workout trophies' rules, shared by the Workouts trophy shelf and the border Path.
struct Milestones {
    let firstWorkout: Bool
    let hundredMinutes: Bool
    let threeQuests: Bool
    let sevenWorkouts: Bool
    let fiveHundredMinutes: Bool
    let shuffledPack: Bool

    var earnedCount: Int {
        [firstWorkout, hundredMinutes, threeQuests, sevenWorkouts, fiveHundredMinutes, shuffledPack]
            .filter { $0 }.count
    }

    init(workouts: [WorkoutEntry], plans: [String: ChallengePlan]) {
        let minutes = workouts.reduce(0) { $0 + $1.minutes }
        let finished = Self.finishedPackDays(workouts: workouts, plans: plans)
        firstWorkout = !workouts.isEmpty
        hundredMinutes = minutes >= 100
        threeQuests = Self.completedQuestCount(workouts) >= 3
        sevenWorkouts = workouts.count >= 7
        fiveHundredMinutes = minutes >= 500
        shuffledPack = finished.contains { plans[$0]?.wasShuffled == true }
    }

    /// Distinct side quests logged, across all days.
    static func completedQuestCount(_ workouts: [WorkoutEntry]) -> Int {
        Set(workouts.compactMap { workout -> String? in
            guard let day = workout.challengeDayKey else { return nil }
            return "\(day)/\(workout.challengeID ?? "legacy")"
        }).count
    }

    /// Days whose whole challenge pack was logged.
    static func finishedPackDays(workouts: [WorkoutEntry], plans: [String: ChallengePlan]) -> Set<String> {
        Set(plans.compactMap { key, plan -> String? in
            let ids = plan.activeQuests(for: key).map(\.id)
            guard !ids.isEmpty else { return nil }
            let logged = Set(workouts.filter { $0.challengeDayKey == key }.compactMap(\.challengeID))
            return ids.allSatisfy { logged.contains($0) } ? key : nil
        })
    }
}
