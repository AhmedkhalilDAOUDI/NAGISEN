import Foundation

/// The border a member earns around their profile picture.
enum BorderTier: Int, CaseIterable, Comparable {
    case none = 0, washi, hinoki, copper, bronze, silver, gold, sakura, indigo, jade, sumi, kintsugi

    /// Points needed to reach each border. Tune here; nothing else hard-codes them.
    /// Logging daily and hitting the calorie goal earns roughly 3–4 points a day.
    var threshold: Int {
        switch self {
        case .none: 0
        case .washi: 10
        case .hinoki: 30
        case .copper: 60
        case .bronze: 100
        case .silver: 160
        case .gold: 250
        case .sakura: 360
        case .indigo: 500
        case .jade: 680
        case .sumi: 900
        case .kintsugi: 1200
        }
    }

    var name: String {
        switch self {
        case .none: "No border yet"
        case .washi: "Washi"
        case .hinoki: "Hinoki"
        case .copper: "Copper"
        case .bronze: "Bronze"
        case .silver: "Silver"
        case .gold: "Gold"
        case .sakura: "Sakura"
        case .indigo: "Indigo"
        case .jade: "Jade"
        case .sumi: "Sumi"
        case .kintsugi: "Kintsugi"
        }
    }

    /// The highest borders slowly shimmer.
    var shimmers: Bool { self >= .jade }

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
    static let pointsPerCheckedDay = 1
    static let pointsPerGoalDay = 1
    static let pointsPerWeekStreak = 5
    static let pointsPerMonthStreak = 20
    static let pointsPerPack = 1
    static let pointsPerRecord = 1
    static let pointsPerMilestone = 2

    let checkedDays: Int
    let goalDays: Int
    let weekStreaks: Int
    let monthStreaks: Int
    let finishedPacks: Int
    let personalRecords: Int
    let milestones: Int

    var points: Int {
        checkedDays * Self.pointsPerCheckedDay + goalDays * Self.pointsPerGoalDay +
            weekStreaks * Self.pointsPerWeekStreak + monthStreaks * Self.pointsPerMonthStreak +
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

    init(checkedDays: Int = 0, goalDays: Int = 0, weekStreaks: Int = 0, monthStreaks: Int = 0,
         finishedPacks: Int = 0, personalRecords: Int = 0, milestones: Int = 0) {
        self.checkedDays = checkedDays
        self.goalDays = goalDays
        self.weekStreaks = weekStreaks
        self.monthStreaks = monthStreaks
        self.finishedPacks = finishedPacks
        self.personalRecords = personalRecords
        self.milestones = milestones
    }

    /// - Parameters:
    ///   - checkedDayKeys: days marked Done Logging in NAGISEN (imported days already removed).
    ///   - goalDayCount: days whose NAGISEN-logged calories landed within the goal band.
    init(workouts: [WorkoutEntry], plans: [String: ChallengePlan], lifts: [StrengthRecord],
         checkedDayKeys: Set<String> = [], goalDayCount: Int = 0, calendar: Calendar = .current) {
        let runs = Self.streakRuns(checkedDayKeys, calendar: calendar)
        self.init(checkedDays: checkedDayKeys.count,
                  goalDays: goalDayCount,
                  weekStreaks: runs.reduce(0) { $0 + $1 / 7 },
                  monthStreaks: runs.reduce(0) { $0 + $1 / 30 },
                  finishedPacks: Milestones.finishedPackDays(workouts: workouts, plans: plans).count,
                  personalRecords: Self.recordCount(lifts),
                  milestones: Milestones(workouts: workouts, plans: plans).earnedCount)
    }

    /// Lengths of each run of consecutive checked days.
    static func streakRuns(_ dayKeys: Set<String>, calendar: Calendar = .current) -> [Int] {
        let days = dayKeys.compactMap { StreakEngine.date(fromDayKey: $0, calendar: calendar) }.sorted()
        var runs: [Int] = []
        var length = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.dateComponents([.day], from: previous, to: day).day == 1 {
                length += 1
            } else {
                if length > 0 { runs.append(length) }
                length = 1
            }
            previous = day
        }
        if length > 0 { runs.append(length) }
        return runs
    }

    /// Days whose calories land within `tolerance` of that day's goal, counting only entries
    /// logged in NAGISEN (Lose It! imports carry an import fingerprint and are left out).
    static func goalDayCount(entries: [DiaryEntry], goal: (Date) -> Int, tolerance: Double = 0.10,
                             calendar: Calendar = .current) -> Int {
        let own = entries.filter { $0.importFingerprint == nil }
        let byDay = Dictionary(grouping: own) { calendar.startOfDay(for: $0.date) }
        return byDay.filter { day, dayEntries in
            let target = goal(day)
            guard target > 0 else { return false }
            let eaten = dayEntries.reduce(0) { $0 + $1.calories }
            return abs(Double(eaten - target)) <= Double(target) * tolerance
        }.count
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

extension PathProgress {
    /// Everything the Path counts, read from the store.
    init(store: NutritionStore) {
        let imported = Set(store.legacyStreak?.dayKeys() ?? [])
        self.init(workouts: store.workouts, plans: store.challengePlans, lifts: store.strengthRecords,
                  checkedDayKeys: store.completedLoggingDays.subtracting(imported),
                  goalDayCount: Self.goalDayCount(entries: store.entries,
                                                  goal: { store.goals(on: $0).calories }))
    }
}
