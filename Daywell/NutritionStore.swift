import SwiftUI

struct Food: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var brand: String = ""
    var serving: String
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double? = nil
    var sodium: Double? = nil
    var barcode: String? = nil
    var source: String? = nil
    var missingMacros: [String]? = nil

    var gramsPerServing: Double? {
        let pattern = #"([0-9]+(?:[.,][0-9]+)?)\s*g\b"#
        guard let range = serving.range(of: pattern, options: .regularExpression) else { return nil }
        let number = serving[range].replacingOccurrences(of: "g", with: "")
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        return Double(number)
    }
}

enum Meal: String, CaseIterable, Codable, Identifiable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case snacks = "Snacks"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snacks: "sparkles"
        }
    }
}

struct DiaryEntry: Identifiable, Codable {
    var id = UUID()
    var food: Food
    var meal: Meal
    var servings: Double
    var date: Date
    var loggedQuantity: Double? = nil
    var loggedUnit: String? = nil
    var planMealID: UUID? = nil
    /// Stable identity for records brought in from another tracker, so a repeated import
    /// updates nothing and duplicates nothing.
    var importFingerprint: String? = nil

    var calories: Int { Int((Double(food.calories) * servings).rounded()) }
    var protein: Double { food.protein * servings }
    var carbs: Double { food.carbs * servings }
    var fat: Double { food.fat * servings }
    var fiber: Double? { food.fiber.map { $0 * servings } }
    var sodium: Double? { food.sodium.map { $0 * servings } }
    var portionDescription: String {
        if let loggedQuantity, let loggedUnit {
            if loggedUnit == "serving" { return "\(loggedQuantity.formatted()) × \(food.serving)" }
            return "\(loggedQuantity.formatted()) \(loggedUnit)"
        }
        return "\(servings.formatted()) × \(food.serving)"
    }
}

struct NutritionGoals: Codable {
    var calories = 2000
    var protein = 120
    var carbs = 250
    var fat = 65

    var calculatedCarbs: Int? {
        let remaining = calories - 4 * protein - 9 * fat
        return remaining >= 0 ? remaining / 4 : nil
    }

    var balanced: NutritionGoals {
        var value = self
        if let calculatedCarbs { value.carbs = calculatedCarbs }
        return value
    }
}

struct RecipeIngredient: Codable, Identifiable {
    var id = UUID()
    var food: Food
    var servings: Double
}

struct SavedRecipe: Codable, Identifiable {
    var id = UUID()
    var name: String
    var portions: Int
    var ingredients: [RecipeIngredient]

    var asFood: Food {
        let count = Double(max(portions, 1))
        let energy = ingredients.reduce(0.0) { $0 + Double($1.food.calories) * $1.servings } / count
        let protein = ingredients.reduce(0.0) { $0 + $1.food.protein * $1.servings } / count
        let carbs = ingredients.reduce(0.0) { $0 + $1.food.carbs * $1.servings } / count
        let fat = ingredients.reduce(0.0) { $0 + $1.food.fat * $1.servings } / count
        let hasFiber = ingredients.allSatisfy { $0.food.fiber != nil }
        let hasSodium = ingredients.allSatisfy { $0.food.sodium != nil }
        return Food(name: name, serving: "1 recipe portion", calories: Int(energy.rounded()),
                    protein: protein, carbs: carbs, fat: fat,
                    fiber: hasFiber ? ingredients.reduce(0.0) { $0 + ($1.food.fiber ?? 0) * $1.servings } / count : nil,
                    sodium: hasSodium ? ingredients.reduce(0.0) { $0 + ($1.food.sodium ?? 0) * $1.servings } / count : nil,
                    source: "Your recipe",
                    missingMacros: Array(Set(ingredients.flatMap { $0.food.missingMacros ?? [] })).sorted())
    }
}

struct GroceryStock: Codable, Identifiable {
    var id = UUID()
    var food: Food
    var servings: Double
}

struct GroceryPlanPortion: Codable, Identifiable {
    var id = UUID()
    var stockID: UUID
    var food: Food
    var servings: Double
    var calories: Int { Int((Double(food.calories) * servings).rounded()) }
    var protein: Double { food.protein * servings }
    var carbs: Double { food.carbs * servings }
    var fat: Double { food.fat * servings }
}

struct GroceryPlanMeal: Codable, Identifiable {
    var id = UUID()
    var meal: Meal
    var title: String
    var portions: [GroceryPlanPortion]
    var calories: Int { portions.reduce(0) { $0 + $1.calories } }
}

struct GroceryPlanDay: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var meals: [GroceryPlanMeal]
    var calories: Int { meals.reduce(0) { $0 + $1.calories } }
    var protein: Double { meals.flatMap(\.portions).reduce(0) { $0 + $1.protein } }
    var carbs: Double { meals.flatMap(\.portions).reduce(0) { $0 + $1.carbs } }
    var fat: Double { meals.flatMap(\.portions).reduce(0) { $0 + $1.fat } }
}

struct GroceryPlan: Codable {
    var createdAt: Date
    var days: [GroceryPlanDay]
    var stockSnapshot: [GroceryStock]
}

struct GoalAdjustment: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var previousCalories: Int
    var newCalories: Int
    var reason: String
}

struct WeeklyReview {
    let loggedDays: Int
    let weightEntries: Int
    let trendChangeKg: Double?
    let averageCalories: Int?
    let estimatedExpenditure: Int?
    let suggestedCalories: Int?
    let reason: String
}

struct DailyTotals {
    var calories = 0
    var protein = 0.0
    var carbs = 0.0
    var fat = 0.0
    var fiber = 0.0
    var sodium = 0.0
    var fiberEntries = 0
    var sodiumEntries = 0
    var incompleteMacroEntries = 0
}

enum AppearanceMode: String, CaseIterable, Codable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    var id: String { rawValue }
}

struct PersonalProfile: Codable {
    var age: Int? = nil
    var heightCm: Double? = nil
    var targetWeightKg: Double? = nil
}

enum DietStyle: String, CaseIterable, Codable, Identifiable {
    case balanced = "Balanced"
    case mediterranean = "Mediterranean"
    case highProtein = "High protein"
    case lowerCarb = "Lower carb"
    case keto = "Keto"
    case intermittentFasting = "Intermittent fasting"
    var id: String { rawValue }
}

enum EnergyEquation: String, CaseIterable, Codable, Identifiable {
    case female = "Female equation"
    case male = "Male equation"
    var id: String { rawValue }
}

enum DietActivity: String, CaseIterable, Codable, Identifiable {
    case sedentary = "Mostly sitting"
    case light = "Lightly active"
    case moderate = "Moderately active"
    case veryActive = "Very active"
    var id: String { rawValue }
    var factor: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .veryActive: 1.725
        }
    }
}

enum DietDirection: String, CaseIterable, Codable, Identifiable {
    case automatic = "Use weight goal"
    case lose = "Lose weight"
    case maintain = "Maintain weight"
    case gain = "Gain weight"
    var id: String { rawValue }
}

struct DietPreferences: Codable {
    var style: DietStyle = .balanced
    var equation: EnergyEquation? = nil
    var activity: DietActivity? = nil
    var direction: DietDirection = .automatic
}

struct WeightEntry: Identifiable, Codable {
    var id = UUID()
    var date: Date = .now
    var kilograms: Double
    var healthSampleID: UUID? = nil
}

struct WaterEntry: Identifiable, Codable {
    var id = UUID()
    var date: Date = .now
    var milliliters: Int
}

struct WorkoutEntry: Identifiable, Codable {
    var id = UUID()
    var date: Date = .now
    var activity: String
    var minutes: Int
    var detail: String? = nil
    var challengeDayKey: String? = nil
    var challengeID: String? = nil
    var healthSampleID: UUID? = nil
}

struct StrengthRecord: Identifiable, Codable {
    var id = UUID()
    var exercise: String
    var kilograms: Double
    var reps: Int
    var date: Date
}

struct ChallengeQuest: Identifiable, Codable, Hashable {
    var id: String
    var category: String
    var title: String
    var detail: String
    var estimatedMinutes: Int
    var symbol: String
}

struct ChallengePlan: Codable {
    var title: String
    var blocks: [String]
    var estimatedMinutes: Int
    var symbol: String
    var quests: [ChallengeQuest]? = nil
    var difficulty: String? = nil
    var wasShuffled: Bool? = nil

    func activeQuests(for dayKey: String) -> [ChallengeQuest] {
        if let quests, !quests.isEmpty { return quests }
        return [ChallengeQuest(id: "legacy-\(dayKey)", category: "hybrid", title: title,
                               detail: blocks.joined(separator: " · "),
                               estimatedMinutes: estimatedMinutes, symbol: symbol)]
    }
}

struct LoggedMeal: Identifiable {
    let date: Date
    let meal: Meal
    let entries: [DiaryEntry]
    var id: String { "\(Calendar.current.startOfDay(for: date).timeIntervalSince1970)-\(meal.rawValue)" }
    var calories: Int { entries.reduce(0) { $0 + $1.calories } }
}

final class NutritionStore: ObservableObject {
    @Published private(set) var storageRecoveryNeeded = false
    @Published var entries: [DiaryEntry] = [] { didSet { persist("entries", entries) } }
    @Published var customFoods: [Food] = [] { didSet { persist("customFoods", customFoods) } }
    @Published var goals = NutritionGoals() { didSet { persist("goals", goals) } }
    @Published var profile = PersonalProfile() { didSet { persist("profile", profile) } }
    @Published var dietPreferences = DietPreferences() { didSet { persist("dietPreferences", dietPreferences) } }
    @Published var weights: [WeightEntry] = [] { didSet { persist("weights", weights) } }
    @Published var waterEntries: [WaterEntry] = [] { didSet { persist("waterEntries", waterEntries) } }
    @Published var waterGoalML = 2500 { didSet { persist("waterGoalML", waterGoalML) } }
    @Published var appearance = AppearanceMode.system { didSet { persist("appearance", appearance) } }
    @Published var creatineTakenDays: Set<String> = [] { didSet { persist("creatineTakenDays", creatineTakenDays) } }
    @Published var completedLoggingDays: Set<String> = [] { didSet { persist("completedLoggingDays", completedLoggingDays) } }
    @Published var workouts: [WorkoutEntry] = [] { didSet { persist("workouts", workouts) } }
    @Published var strengthRecords: [StrengthRecord] = [] { didSet { persist("strengthRecords", strengthRecords) } }
    @Published var challengePlans: [String: ChallengePlan] = [:] { didSet { persist("challengePlans", challengePlans) } }
    @Published var questSeenIDs: [String] = [] { didSet { persist("questSeenIDs", questSeenIDs) } }
    @Published var trophyNames: [String: String] = [:] { didSet { persist("trophyNames", trophyNames) } }
    @Published var goalAdjustments: [GoalAdjustment] = [] { didSet { persist("goalAdjustments", goalAdjustments) } }
    @Published var weekdayGoals: [Int: NutritionGoals] = [:] { didSet { persist("weekdayGoals", weekdayGoals) } }
    @Published var foodsToAvoid: [String] = [] { didSet { persist("foodsToAvoid", foodsToAvoid) } }
    @Published var savedRecipes: [SavedRecipe] = [] { didSet { persist("savedRecipes", savedRecipes) } }
    @Published var groceryStock: [GroceryStock] = [] { didSet { persist("groceryStock", groceryStock) } }
    @Published var groceryPlan: GroceryPlan? = nil { didSet { persist("groceryPlan", groceryPlan) } }
    /// Achievement carried over from another tracker. Never derived from diary entries.
    @Published var legacyStreak: LegacyStreak? = nil { didSet { persist("legacyStreak", legacyStreak) } }
    /// Highest streak NAGISEN has observed, so a later reset cannot erase the record.
    @Published var longestStreakRecorded = 0 { didSet { persist("longestStreakRecorded", longestStreakRecorded) } }
    @Published var loseItImports: [LoseItImportRecord] = [] { didSet { persist("loseItImports", loseItImports) } }

    private struct SavedData: Codable {
        var entries: [DiaryEntry]
        var customFoods: [Food]
        var goals: NutritionGoals
        var profile: PersonalProfile?
        var dietPreferences: DietPreferences?
        var weights: [WeightEntry]?
        var waterEntries: [WaterEntry]?
        var waterGoalML: Int?
        var appearance: AppearanceMode?
        var creatineTakenDays: Set<String>?
        var completedLoggingDays: Set<String>?
        var workouts: [WorkoutEntry]?
        var strengthRecords: [StrengthRecord]?
        var challengePlans: [String: ChallengePlan]?
        var questSeenIDs: [String]?
        var trophyNames: [String: String]?
        var goalAdjustments: [GoalAdjustment]?
        var weekdayGoals: [Int: NutritionGoals]?
        var foodsToAvoid: [String]?
        var savedRecipes: [SavedRecipe]?
        var groceryStock: [GroceryStock]?
        var groceryPlan: GroceryPlan?
        var legacyStreak: LegacyStreak?
        var longestStreakRecorded: Int?
        var loseItImports: [LoseItImportRecord]?
    }

    private let storageKey = "daywell.nutrition.v1"
    private let vault = NutritionVault()
    /// Unknown top-level keys from the last restored backup, echoed back on export.
    private var preservedUnknownBackupFields: Data?
    private var backupSchemaVersion = 2

    init() {
        if vault?.read("schemaReady", as: Bool.self) == true {
            guard let storedEntries: [DiaryEntry] = vault?.read("entries") else {
                storageRecoveryNeeded = true
                return
            }
            entries = storedEntries
            customFoods = vault?.read("customFoods") ?? []
            goals = vault?.read("goals") ?? NutritionGoals()
            profile = vault?.read("profile") ?? PersonalProfile()
            dietPreferences = vault?.read("dietPreferences") ?? DietPreferences()
            weights = vault?.read("weights") ?? []
            waterEntries = vault?.read("waterEntries") ?? []
            waterGoalML = vault?.read("waterGoalML") ?? 2500
            appearance = vault?.read("appearance") ?? .system
            creatineTakenDays = vault?.read("creatineTakenDays") ?? []
            completedLoggingDays = vault?.read("completedLoggingDays") ?? []
            workouts = vault?.read("workouts") ?? []
            strengthRecords = vault?.read("strengthRecords") ?? []
            challengePlans = vault?.read("challengePlans") ?? [:]
            questSeenIDs = vault?.read("questSeenIDs") ?? []
            trophyNames = vault?.read("trophyNames") ?? [:]
            goalAdjustments = vault?.read("goalAdjustments") ?? []
            weekdayGoals = vault?.read("weekdayGoals") ?? [:]
            foodsToAvoid = vault?.read("foodsToAvoid") ?? []
            savedRecipes = vault?.read("savedRecipes") ?? []
            groceryStock = vault?.read("groceryStock") ?? []
            groceryPlan = vault?.read("groceryPlan")
            legacyStreak = vault?.read("legacyStreak")
            longestStreakRecorded = vault?.read("longestStreakRecorded") ?? 0
            loseItImports = vault?.read("loseItImports") ?? []
            longestStreakRecorded = max(longestStreakRecorded, legacyStreak?.count ?? 0)
            return
        }
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode(SavedData.self, from: data) else {
            saveAllToVault()
            return
        }
        entries = saved.entries
        customFoods = saved.customFoods
        goals = saved.goals
        profile = saved.profile ?? PersonalProfile()
        dietPreferences = saved.dietPreferences ?? DietPreferences()
        weights = saved.weights ?? []
        waterEntries = saved.waterEntries ?? []
        waterGoalML = saved.waterGoalML ?? 2500
        appearance = saved.appearance ?? .system
        creatineTakenDays = saved.creatineTakenDays ?? []
        completedLoggingDays = saved.completedLoggingDays ?? []
        workouts = saved.workouts ?? []
        strengthRecords = saved.strengthRecords ?? []
        challengePlans = saved.challengePlans ?? [:]
        questSeenIDs = saved.questSeenIDs ?? []
        trophyNames = saved.trophyNames ?? [:]
        goalAdjustments = saved.goalAdjustments ?? []
        weekdayGoals = saved.weekdayGoals ?? [:]
        foodsToAvoid = saved.foodsToAvoid ?? []
        savedRecipes = saved.savedRecipes ?? []
        groceryStock = saved.groceryStock ?? []
        groceryPlan = saved.groceryPlan
        legacyStreak = saved.legacyStreak
        longestStreakRecorded = saved.longestStreakRecorded ?? 0
        loseItImports = saved.loseItImports ?? []
        longestStreakRecorded = max(longestStreakRecorded, legacyStreak?.count ?? 0)
        saveAllToVault()
    }

    private func persist<T: Encodable>(_ key: String, _ value: T) {
        if vault?.write(key, value: value) == true { return }
        saveLegacyFallback()
    }

    private func saveAllToVault() {
        guard let vault else { return }
        _ = vault.transaction {
            vault.write("entries", value: entries) &&
            vault.write("customFoods", value: customFoods) &&
            vault.write("goals", value: goals) &&
            vault.write("profile", value: profile) &&
            vault.write("dietPreferences", value: dietPreferences) &&
            vault.write("weights", value: weights) &&
            vault.write("waterEntries", value: waterEntries) &&
            vault.write("waterGoalML", value: waterGoalML) &&
            vault.write("appearance", value: appearance) &&
            vault.write("creatineTakenDays", value: creatineTakenDays) &&
            vault.write("completedLoggingDays", value: completedLoggingDays) &&
            vault.write("workouts", value: workouts) &&
            vault.write("strengthRecords", value: strengthRecords) &&
            vault.write("challengePlans", value: challengePlans) &&
            vault.write("questSeenIDs", value: questSeenIDs) &&
            vault.write("trophyNames", value: trophyNames) &&
            vault.write("goalAdjustments", value: goalAdjustments) &&
            vault.write("weekdayGoals", value: weekdayGoals) &&
            vault.write("foodsToAvoid", value: foodsToAvoid) &&
            vault.write("savedRecipes", value: savedRecipes) &&
            vault.write("groceryStock", value: groceryStock) &&
            vault.write("groceryPlan", value: groceryPlan) &&
            vault.write("legacyStreak", value: legacyStreak) &&
            vault.write("longestStreakRecorded", value: longestStreakRecorded) &&
            vault.write("loseItImports", value: loseItImports) &&
            vault.write("schemaReady", value: true)
        }
    }

    private func saveLegacyFallback() {
        let saved = SavedData(entries: entries, customFoods: customFoods, goals: goals,
                              profile: profile, dietPreferences: dietPreferences,
                              weights: weights, waterEntries: waterEntries,
                              waterGoalML: waterGoalML, appearance: appearance,
                              creatineTakenDays: creatineTakenDays,
                              completedLoggingDays: completedLoggingDays, workouts: workouts,
                              strengthRecords: strengthRecords,
                              challengePlans: challengePlans, questSeenIDs: questSeenIDs, trophyNames: trophyNames,
                              goalAdjustments: goalAdjustments, weekdayGoals: weekdayGoals,
                              foodsToAvoid: foodsToAvoid, savedRecipes: savedRecipes,
                              groceryStock: groceryStock, groceryPlan: groceryPlan,
                              legacyStreak: legacyStreak,
                              longestStreakRecorded: longestStreakRecorded,
                              loseItImports: loseItImports)
        guard let data = try? JSONEncoder().encode(saved) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    func entries(on date: Date, meal: Meal? = nil) -> [DiaryEntry] {
        entries.filter { Calendar.current.isDate($0.date, inSameDayAs: date) && (meal == nil || $0.meal == meal) }
    }

    func goals(on date: Date) -> NutritionGoals {
        (weekdayGoals[Calendar.current.component(.weekday, from: date)] ?? goals).balanced
    }

    func weeklyReview(asOf now: Date = .now) -> WeeklyReview {
        if let applied = goalAdjustments.first?.date, now.timeIntervalSince(applied) < 7 * 86_400 {
            return WeeklyReview(loggedDays: 0, weightEntries: 0, trendChangeKg: nil,
                                averageCalories: nil, estimatedExpenditure: nil, suggestedCalories: nil,
                                reason: "Your last adjustment was applied this week. Keep logging and check again next week.")
        }
        let calendar = Calendar.current
        let days = (0..<14).compactMap { calendar.date(byAdding: .day, value: -$0, to: now) }
        let logged = days.filter { entries(on: $0).count >= 2 }
        let recent = logged.filter {
            (calendar.dateComponents([.day], from: calendar.startOfDay(for: $0),
                                     to: calendar.startOfDay(for: now)).day ?? 99) < 7
        }
        let previous = logged.filter { !recent.contains($0) }
        let start = calendar.startOfDay(for: days.last ?? now)
        let weightsInWindow = weights.filter { $0.date >= start && $0.date <= now }
            .sorted { $0.date < $1.date }
        guard recent.count >= 5, previous.count >= 5, weightsInWindow.count >= 4,
              let first = weightsInWindow.first, let last = weightsInWindow.last,
              last.date.timeIntervalSince(first.date) >= 7 * 86_400 else {
            return WeeklyReview(loggedDays: logged.count, weightEntries: weightsInWindow.count,
                                trendChangeKg: nil, averageCalories: nil, estimatedExpenditure: nil,
                                suggestedCalories: nil,
                                reason: "Log at least two foods on five days in each of the last two weeks, and add four weigh-ins spanning at least a week. Partial days can distort an estimate.")
        }
        let slopes = weightsInWindow.enumerated().flatMap { i, earlier in
            weightsInWindow.dropFirst(i + 1).compactMap { later -> Double? in
                let span = later.date.timeIntervalSince(earlier.date) / 86_400
                guard span >= 2 else { return nil }
                return (later.kilograms - earlier.kilograms) / span
            }
        }.sorted()
        guard !slopes.isEmpty else {
            return WeeklyReview(loggedDays: logged.count, weightEntries: weightsInWindow.count,
                                trendChangeKg: nil, averageCalories: nil, estimatedExpenditure: nil,
                                suggestedCalories: nil, reason: "Add weigh-ins on more separate days to estimate a trend.")
        }
        let dailyChange = slopes[slopes.count / 2]
        let weeklyChange = dailyChange * 7
        let average = Int((Double(logged.reduce(0) { $0 + totals(on: $1).calories }) / Double(logged.count)).rounded())
        let expenditure = Int((Double(average) - dailyChange * 7700).rounded())
        guard (1200...6000).contains(expenditure) else {
            return WeeklyReview(loggedDays: logged.count, weightEntries: weightsInWindow.count,
                                trendChangeKg: weeklyChange, averageCalories: average, estimatedExpenditure: nil,
                                suggestedCalories: nil, reason: "The intake and weight trend do not support a reliable energy estimate yet. Check for partial food days or unusual weigh-ins.")
        }
        let direction: DietDirection
        if dietPreferences.direction == .automatic {
            if let target = profile.targetWeightKg {
                direction = target < last.kilograms - 0.5 ? .lose : target > last.kilograms + 0.5 ? .gain : .maintain
            } else { direction = .maintain }
        } else { direction = dietPreferences.direction }
        let desiredWeeklyChange: Double
        switch direction {
        case .lose: desiredWeeklyChange = -0.0035 * last.kilograms
        case .gain: desiredWeeklyChange = 0.002 * last.kilograms
        case .maintain, .automatic: desiredWeeklyChange = 0
        }
        let rawTarget = Double(expenditure) + desiredWeeklyChange * 7700 / 7
        let difference = rawTarget - Double(goals.calories)
        let step = abs(difference) < 75 ? 0 : (difference > 0 ? 100 : -100)
        let next = min(5000, max(1200, goals.calories + step))
        let reason = step == 0 ? "Your logged intake and weight trend support keeping your current target." :
            "Your weight trend is \(weeklyChange.formatted(.number.precision(.fractionLength(2)))) kg per week. This small change moves your target toward the estimated energy need for your goal."
        return WeeklyReview(loggedDays: logged.count, weightEntries: weightsInWindow.count,
                            trendChangeKg: weeklyChange, averageCalories: average,
                            estimatedExpenditure: expenditure, suggestedCalories: next, reason: reason)
    }

    func apply(_ review: WeeklyReview) {
        guard let suggested = review.suggestedCalories, suggested != goals.calories else { return }
        let previous = goals.calories
        goals.calories = suggested
        goalAdjustments.insert(GoalAdjustment(date: .now, previousCalories: previous,
                                               newCalories: suggested, reason: review.reason), at: 0)
    }

    func exportJSON() -> Data? {
        let saved = SavedData(entries: entries, customFoods: customFoods, goals: goals,
                              profile: profile, dietPreferences: dietPreferences,
                              weights: weights, waterEntries: waterEntries,
                              waterGoalML: waterGoalML, appearance: appearance,
                              creatineTakenDays: creatineTakenDays,
                              completedLoggingDays: completedLoggingDays, workouts: workouts,
                              strengthRecords: strengthRecords,
                              challengePlans: challengePlans, questSeenIDs: questSeenIDs, trophyNames: trophyNames,
                              goalAdjustments: goalAdjustments, weekdayGoals: weekdayGoals,
                              foodsToAvoid: foodsToAvoid, savedRecipes: savedRecipes,
                              groceryStock: groceryStock, groceryPlan: groceryPlan,
                              legacyStreak: legacyStreak,
                              longestStreakRecorded: longestStreakRecorded,
                              loseItImports: loseItImports)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let typed = try? encoder.encode(saved) else { return nil }
        return mergingPreservedBackupFields(into: typed)
    }

    /// Keys this build understands. Anything else in a restored file is kept verbatim and
    /// written back out, so a backup made by a newer build survives a round trip here.
    private static let knownBackupKeys: Set<String> = [
        "entries", "customFoods", "goals", "profile", "dietPreferences", "weights",
        "waterEntries", "waterGoalML", "appearance", "creatineTakenDays",
        "completedLoggingDays", "workouts", "strengthRecords", "challengePlans",
        "questSeenIDs", "trophyNames", "goalAdjustments", "weekdayGoals", "foodsToAvoid",
        "savedRecipes", "groceryStock", "groceryPlan", "legacyStreak",
        "longestStreakRecorded", "loseItImports", "schemaVersion"
    ]

    private func mergingPreservedBackupFields(into typed: Data) -> Data? {
        guard var object = try? JSONSerialization.jsonObject(with: typed) as? [String: Any] else { return typed }
        if let preserved = preservedUnknownBackupFields,
           let unknown = try? JSONSerialization.jsonObject(with: preserved) as? [String: Any] {
            for (key, value) in unknown where object[key] == nil { object[key] = value }
        }
        object["schemaVersion"] = backupSchemaVersion
        return try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private func capturePreservedBackupFields(from data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            preservedUnknownBackupFields = nil
            return
        }
        let unknown = root.filter { !Self.knownBackupKeys.contains($0.key) }
        preservedUnknownBackupFields = unknown.isEmpty
            ? nil
            : try? JSONSerialization.data(withJSONObject: unknown, options: [.sortedKeys])
        if let version = root["schemaVersion"] as? Int {
            backupSchemaVersion = max(2, version)
        } else {
            backupSchemaVersion = 2
        }
    }

    var latestAutomaticBackup: URL? {
        guard let folder = backupFolder,
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return nil }
        return files.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }.first
    }

    @discardableResult
    func backupNow() -> Bool {
        guard !storageRecoveryNeeded, let folder = backupFolder, let data = exportJSON() else { return false }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
            try data.write(to: folder.appendingPathComponent("NAGISEN-\(stamp).json"), options: .atomic)
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            for old in files.dropFirst(7) { try? FileManager.default.removeItem(at: old) }
            return true
        } catch { return false }
    }

    func restoreLatestAutomaticBackup() -> Bool {
        guard let url = latestAutomaticBackup, let data = try? Data(contentsOf: url) else { return false }
        return restoreJSON(data)
    }

    private var backupFolder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("NAGISEN/Backups", isDirectory: true)
    }

    func restoreJSON(_ data: Data) -> Bool {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let saved = try? decoder.decode(SavedData.self, from: data),
              (500...10_000).contains(saved.goals.calories),
              saved.entries.count < 100_000,
              (saved.weights?.count ?? 0) < 100_000 else { return false }
        // A malformed achievement invalidates the whole file rather than applying half of it.
        if let legacy = saved.legacyStreak, !legacy.isWellFormed { return false }
        _ = backupNow()
        entries = saved.entries
        customFoods = saved.customFoods
        goals = saved.goals
        profile = saved.profile ?? PersonalProfile()
        dietPreferences = saved.dietPreferences ?? DietPreferences()
        weights = saved.weights ?? []
        waterEntries = saved.waterEntries ?? []
        waterGoalML = saved.waterGoalML ?? 2500
        appearance = saved.appearance ?? .system
        creatineTakenDays = saved.creatineTakenDays ?? []
        completedLoggingDays = saved.completedLoggingDays ?? []
        workouts = saved.workouts ?? []
        strengthRecords = saved.strengthRecords ?? []
        challengePlans = saved.challengePlans ?? [:]
        questSeenIDs = saved.questSeenIDs ?? []
        trophyNames = saved.trophyNames ?? [:]
        goalAdjustments = saved.goalAdjustments ?? []
        weekdayGoals = saved.weekdayGoals ?? [:]
        foodsToAvoid = saved.foodsToAvoid ?? []
        savedRecipes = saved.savedRecipes ?? []
        groceryStock = saved.groceryStock ?? []
        groceryPlan = saved.groceryPlan
        legacyStreak = saved.legacyStreak
        longestStreakRecorded = max(saved.longestStreakRecorded ?? 0, saved.legacyStreak?.count ?? 0)
        loseItImports = saved.loseItImports ?? []
        capturePreservedBackupFields(from: data)
        storageRecoveryNeeded = false
        return true
    }

    func totals(on date: Date) -> DailyTotals {
        entries(on: date).reduce(into: DailyTotals()) { result, entry in
            result.calories += entry.calories
            result.protein += entry.protein
            result.carbs += entry.carbs
            result.fat += entry.fat
            if let value = entry.fiber { result.fiber += value; result.fiberEntries += 1 }
            if let value = entry.sodium { result.sodium += value; result.sodiumEntries += 1 }
            if !(entry.food.missingMacros ?? []).isEmpty { result.incompleteMacroEntries += 1 }
        }
    }

    func add(_ food: Food, to meal: Meal, servings: Double, on date: Date,
             quantity: Double? = nil, unit: String? = nil, planMealID: UUID? = nil) {
        entries.append(DiaryEntry(food: food, meal: meal, servings: servings, date: date,
                                  loggedQuantity: quantity, loggedUnit: unit, planMealID: planMealID))
    }

    func copyDay(from source: Date, to destination: Date) {
        let copied = entries(on: source).map { entry in
            DiaryEntry(food: entry.food, meal: entry.meal, servings: entry.servings,
                       date: destination, loggedQuantity: entry.loggedQuantity, loggedUnit: entry.loggedUnit)
        }
        entries.append(contentsOf: copied)
    }

    func importHealth(workouts healthWorkouts: [HealthWorkout], weights healthWeights: [HealthWeightSample]) -> (workouts: Int, weights: Int) {
        let knownWorkouts = Set(workouts.compactMap(\.healthSampleID))
        let newWorkouts = healthWorkouts.filter { sample in
            !knownWorkouts.contains(sample.id) && sample.minutes > 0 &&
            !workouts.contains { existing in
                existing.activity == sample.name && abs(existing.minutes - sample.minutes) <= 2 &&
                abs(existing.date.timeIntervalSince(sample.date)) < 5 * 60
            }
        }
            .map { WorkoutEntry(date: $0.date, activity: $0.name, minutes: $0.minutes,
                                detail: "Imported from Apple Health", healthSampleID: $0.id) }
        let knownWeights = Set(weights.compactMap(\.healthSampleID))
        let newWeights = healthWeights.filter { sample in
            !knownWeights.contains(sample.id) && (20...500).contains(sample.kilograms) &&
            !weights.contains { existing in
                abs(existing.kilograms - sample.kilograms) < 0.05 &&
                abs(existing.date.timeIntervalSince(sample.date)) < 60 * 60
            }
        }
            .map { WeightEntry(date: $0.date, kilograms: $0.kilograms, healthSampleID: $0.id) }
        if !newWorkouts.isEmpty { workouts.append(contentsOf: newWorkouts) }
        if !newWeights.isEmpty { weights.append(contentsOf: newWeights) }
        return (newWorkouts.count, newWeights.count)
    }

    func delete(_ entry: DiaryEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    func deleteMeal(_ meal: Meal, on date: Date) {
        entries.removeAll { $0.meal == meal && Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func waterTotal(on date: Date) -> Int {
        waterEntries.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
            .reduce(0) { $0 + $1.milliliters }
    }

    func addWater(_ milliliters: Int, on date: Date) {
        guard (1...5000).contains(milliliters) else { return }
        waterEntries.append(WaterEntry(date: date, milliliters: milliliters))
    }

    func deleteWater(_ entry: WaterEntry) {
        waterEntries.removeAll { $0.id == entry.id }
    }

    func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func isLoggingComplete(on date: Date) -> Bool {
        completedLoggingDays.contains(dayKey(date))
    }

    func setLoggingComplete(_ complete: Bool, on date: Date) {
        guard Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: .now) else { return }
        let key = dayKey(date)
        if complete { completedLoggingDays.insert(key) }
        else { completedLoggingDays.remove(key) }
        recordLongestStreak()
    }

    // MARK: - Streaks

    var entryFingerprints: Set<String> {
        Set(entries.compactMap(\.importFingerprint))
    }

    /// The single source of truth for every streak number shown in the app.
    func streakSnapshot(asOf date: Date) -> StreakSnapshot {
        StreakEngine.snapshot(completedDays: qualifyingLoggingDays,
                              legacy: legacyStreak,
                              viewedDay: date,
                              today: .now,
                              calendar: .current,
                              recordedLongest: longestStreakRecorded)
    }

    /// Days that keep the streak alive: anything recorded in the diary, plus days the user
    /// marked done by hand. Logging food is the act that counts, so the number moves on its
    /// own; the manual flag stays available for a day logged elsewhere.
    var qualifyingLoggingDays: Set<String> {
        var days = completedLoggingDays
        for entry in entries { days.insert(dayKey(entry.date)) }
        return days
    }

    func loggingStreak(asOf date: Date) -> Int {
        streakSnapshot(asOf: date).activeStreak
    }

    private func recordLongestStreak() {
        let current = streakSnapshot(asOf: .now).activeStreak
        if current > longestStreakRecorded { longestStreakRecorded = current }
    }

    /// Applies a user-confirmed achievement. Idempotent: importing the same migration twice
    /// changes nothing, and a confirmed achievement is never lowered.
    @discardableResult
    func applyLegacyStreak(_ incoming: LegacyStreak) -> Bool {
        guard incoming.isWellFormed else { return false }
        let merged = StreakEngine.merge(legacyStreak, with: incoming) ?? incoming
        if merged != legacyStreak { legacyStreak = merged }
        if merged.count > longestStreakRecorded { longestStreakRecorded = merged.count }
        return true
    }

    // MARK: - Lose It! migration

    enum LoseItImportOutcome: Equatable {
        case imported(entries: Int, weights: Int, legacyApplied: Bool)
        case nothingNew
        case backupFailed

        var message: String {
            switch self {
            case let .imported(entries, weights, legacyApplied):
                var parts: [String] = []
                if entries > 0 { parts.append("\(entries) food \(entries == 1 ? "entry" : "entries")") }
                if weights > 0 { parts.append("\(weights) weigh-in\(weights == 1 ? "" : "s")") }
                if legacyApplied { parts.append("your legacy streak") }
                if parts.isEmpty { return "Nothing new to import." }
                return "Imported " + parts.joined(separator: ", ") + "."
            case .nothingNew:
                return "Everything in this file is already in NAGISEN."
            case .backupFailed:
                return "NAGISEN could not write a safety backup, so nothing was imported."
            }
        }
    }

    /// Commits a reviewed preview. A timestamped backup is written first; if it fails the
    /// import is abandoned rather than applied without a way back.
    @discardableResult
    func importLoseIt(_ preview: LoseItImportPreview) -> LoseItImportOutcome {
        let known = entryFingerprints
        let newEntries = preview.entries.filter { entry in
            guard let fingerprint = entry.importFingerprint else { return false }
            return !known.contains(fingerprint)
        }
        let newWeights = preview.weights.filter { candidate in
            !weights.contains { existing in
                abs(existing.kilograms - candidate.kilograms) < 0.05 &&
                abs(existing.date.timeIntervalSince(candidate.date)) < 12 * 3600
            }
        }
        let mergedLegacy = preview.legacy.flatMap { StreakEngine.merge(legacyStreak, with: $0) }
        let legacyChanges = mergedLegacy != nil && mergedLegacy != legacyStreak
        guard !newEntries.isEmpty || !newWeights.isEmpty || legacyChanges else { return .nothingNew }
        guard backupNow() else { return .backupFailed }

        if !newEntries.isEmpty { entries.append(contentsOf: newEntries) }
        if !newWeights.isEmpty { weights.append(contentsOf: newWeights) }
        if let mergedLegacy, legacyChanges {
            legacyStreak = mergedLegacy
            longestStreakRecorded = max(longestStreakRecorded, mergedLegacy.count)
        }
        loseItImports.insert(LoseItImportRecord(
            importedAt: .now,
            sourceFiles: preview.sourceFiles,
            entryCount: newEntries.count,
            weightCount: newWeights.count,
            skippedCategories: preview.skipped.map(\.category),
            legacyCount: legacyChanges ? mergedLegacy?.count : nil), at: 0)
        if loseItImports.count > 20 { loseItImports.removeLast(loseItImports.count - 20) }
        return .imported(entries: newEntries.count, weights: newWeights.count, legacyApplied: legacyChanges)
    }

    /// Unused calories from logged days earlier in the same Monday–Sunday week.
    /// Over-goal days use the bank before any new bonus is available.
    func weeklyCalorieBonus(on date: Date) -> Int {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let selectedDay = calendar.startOfDay(for: date)
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: selectedDay)?.start else { return 0 }
        var day = weekStart
        var balance = 0
        while day < selectedDay {
            if !entries(on: day).isEmpty {
                balance += goals(on: day).calories - totals(on: day).calories
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return max(0, balance)
    }

    func creatineTaken(on date: Date) -> Bool {
        creatineTakenDays.contains(dayKey(date))
    }

    func setCreatineTaken(_ taken: Bool, on date: Date) {
        let key = dayKey(date)
        if taken { creatineTakenDays.insert(key) }
        else { creatineTakenDays.remove(key) }
    }

    var allFoods: [Food] { customFoods + Self.starterFoods }

    func recentFoods(for meal: Meal? = nil) -> [Food] {
        var seen = Set<String>()
        return entries.sorted { $0.date > $1.date }
            .filter { meal == nil || $0.meal == meal }
            .compactMap { entry in
                let key = "\(entry.food.name.lowercased())|\(entry.food.brand.lowercased())|\(entry.food.serving.lowercased())"
                return seen.insert(key).inserted ? entry.food : nil
            }
    }

    var loggedMeals: [LoggedMeal] {
        let groups = Dictionary(grouping: entries) { entry in
            "\(Calendar.current.startOfDay(for: entry.date).timeIntervalSince1970)|\(entry.meal.rawValue)"
        }
        return groups.values.compactMap { group in
            guard let first = group.first else { return nil }
            return LoggedMeal(date: first.date, meal: first.meal, entries: group)
        }.sorted { $0.date > $1.date }
    }

    static let starterFoods: [Food] = [
        Food(name: "Banana", serving: "1 medium (118 g)", calories: 105, protein: 1.3, carbs: 27, fat: 0.4),
        Food(name: "Apple", serving: "1 medium (182 g)", calories: 95, protein: 0.5, carbs: 25, fat: 0.3),
        Food(name: "Egg", serving: "1 large", calories: 72, protein: 6.3, carbs: 0.4, fat: 4.8),
        Food(name: "Greek yogurt, plain", serving: "170 g", calories: 100, protein: 17, carbs: 6, fat: 0.7),
        Food(name: "Oats, dry", serving: "40 g", calories: 150, protein: 5, carbs: 27, fat: 3),
        Food(name: "Whole wheat bread", serving: "1 slice", calories: 80, protein: 4, carbs: 14, fat: 1),
        Food(name: "Chicken breast, cooked", serving: "100 g", calories: 165, protein: 31, carbs: 0, fat: 3.6),
        Food(name: "Brown rice, cooked", serving: "1 cup", calories: 216, protein: 5, carbs: 45, fat: 1.8),
        Food(name: "White rice, cooked", serving: "1 cup", calories: 205, protein: 4.3, carbs: 45, fat: 0.4),
        Food(name: "Salmon, cooked", serving: "100 g", calories: 206, protein: 22, carbs: 0, fat: 12),
        Food(name: "Tuna, canned in water", serving: "100 g", calories: 116, protein: 26, carbs: 0, fat: 1),
        Food(name: "Lentils, cooked", serving: "1 cup", calories: 230, protein: 18, carbs: 40, fat: 0.8),
        Food(name: "Avocado", serving: "1/2 medium", calories: 160, protein: 2, carbs: 8.5, fat: 15),
        Food(name: "Almonds", serving: "28 g", calories: 164, protein: 6, carbs: 6, fat: 14),
        Food(name: "Peanut butter", serving: "2 tbsp", calories: 190, protein: 7, carbs: 7, fat: 16),
        Food(name: "Milk, 2%", serving: "1 cup", calories: 122, protein: 8, carbs: 12, fat: 5),
        Food(name: "Broccoli, cooked", serving: "1 cup", calories: 55, protein: 3.7, carbs: 11, fat: 0.6),
        Food(name: "Sweet potato, baked", serving: "1 medium", calories: 112, protein: 2, carbs: 26, fat: 0.1)
    ]
}
