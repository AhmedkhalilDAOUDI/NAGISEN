import Foundation
import HealthKit

struct HealthWorkout: Identifiable {
    let id: UUID
    let name: String
    let date: Date
    let minutes: Int
    let calories: Int?
}

struct HealthWeightSample: Identifiable {
    let id: UUID
    let date: Date
    let kilograms: Double
    let source: String
}

struct HealthAccessorySource: Identifiable {
    let id: String
    let name: String
    let metrics: String
}

struct AccessoryHeartReading: Identifiable {
    let id: UUID
    let beatsPerMinute: Int
    let date: Date
    let source: String
    let device: String?

    var displaySource: String { device ?? source }
}

final class HealthManager: ObservableObject {
    @Published private(set) var hasRequestedAccess = UserDefaults.standard.bool(forKey: "daywell.health.requested")
    @Published private(set) var steps: Int?
    @Published private(set) var activeCalories: Int?
    @Published private(set) var exerciseMinutes: Int?
    @Published private(set) var distanceKilometers: Double?
    @Published private(set) var flightsClimbed: Int?
    @Published private(set) var heartRate: Int?
    @Published private(set) var restingHeartRate: Int?
    @Published private(set) var standHours: Int?
    @Published private(set) var weightKilograms: Double?
    @Published private(set) var workouts: [HealthWorkout] = []
    @Published private(set) var weightSamples: [HealthWeightSample] = []
    @Published private(set) var accessorySources: [HealthAccessorySource] = []
    @Published private(set) var recentHeartReadings: [AccessoryHeartReading] = []
    @Published var errorMessage: String?

    private let healthStore = HKHealthStore()
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        let identifiers: [HKQuantityTypeIdentifier] = [
            .stepCount, .activeEnergyBurned, .appleExerciseTime,
            .distanceWalkingRunning, .flightsClimbed, .heartRate, .restingHeartRate, .bodyMass
        ]
        return Set(identifiers.compactMap { HKObjectType.quantityType(forIdentifier: $0) } +
                   [HKObjectType.workoutType(), HKObjectType.categoryType(forIdentifier: .appleStandHour)!])
    }

    func requestAccess() {
        guard isAvailable else {
            errorMessage = "Apple Health is unavailable on this device."
            return
        }
        healthStore.requestAuthorization(toShare: [], read: readTypes) { [weak self] completed, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if completed {
                    self.hasRequestedAccess = true
                    UserDefaults.standard.set(true, forKey: "daywell.health.requested")
                    self.refresh()
                } else {
                    self.errorMessage = error?.localizedDescription ?? "Apple Health access was not completed."
                }
            }
        }
    }

    func refresh() {
        guard isAvailable, hasRequestedAccess else { return }
        let today = Calendar.current.startOfDay(for: .now)
        querySum(.stepCount, unit: .count(), since: today) { [weak self] in self?.steps = $0.map { Int($0.rounded()) } }
        querySum(.activeEnergyBurned, unit: .kilocalorie(), since: today) { [weak self] in self?.activeCalories = $0.map { Int($0.rounded()) } }
        querySum(.appleExerciseTime, unit: .minute(), since: today) { [weak self] in self?.exerciseMinutes = $0.map { Int($0.rounded()) } }
        querySum(.distanceWalkingRunning, unit: .meterUnit(with: .kilo), since: today) { [weak self] in self?.distanceKilometers = $0 }
        querySum(.flightsClimbed, unit: .count(), since: today) { [weak self] in self?.flightsClimbed = $0.map { Int($0.rounded()) } }
        queryLatest(.heartRate, unit: .count().unitDivided(by: .minute())) { [weak self] in self?.heartRate = $0.map { Int($0.rounded()) } }
        queryLatest(.restingHeartRate, unit: .count().unitDivided(by: .minute())) { [weak self] in self?.restingHeartRate = $0.map { Int($0.rounded()) } }
        queryLatest(.bodyMass, unit: .gramUnit(with: .kilo)) { [weak self] in self?.weightKilograms = $0 }
        queryStandHours(since: today)
        queryWorkouts()
        queryWeightSamples()
        queryAccessorySources()
        queryRecentHeartReadings()
    }

    func refreshAccessoryReadings() {
        guard isAvailable, hasRequestedAccess else { return }
        queryRecentHeartReadings()
    }

    private func queryStandHours(since start: Date) {
        guard let type = HKObjectType.categoryType(forIdentifier: .appleStandHour) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { [weak self] _, samples, _ in
            let hours = (samples as? [HKCategorySample] ?? []).filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }.count
            DispatchQueue.main.async { self?.standHours = hours }
        }
        healthStore.execute(query)
    }

    private func querySum(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, since start: Date, assign: @escaping (Double?) -> Void) {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            let value = result?.sumQuantity()?.doubleValue(for: unit)
            DispatchQueue.main.async { assign(value) }
        }
        healthStore.execute(query)
    }

    private func queryLatest(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, assign: @escaping (Double?) -> Void) {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return }
        let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, _ in
            let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
            DispatchQueue.main.async { assign(value) }
        }
        healthStore.execute(query)
    }

    private func queryWorkouts() {
        let query = HKSampleQuery(sampleType: .workoutType(), predicate: nil, limit: 12,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { [weak self] _, samples, _ in
            let items = (samples as? [HKWorkout] ?? []).map { workout in
                HealthWorkout(id: workout.uuid,
                              name: workout.workoutActivityType.daywellName,
                              date: workout.startDate,
                              minutes: Int((workout.duration / 60).rounded()),
                              calories: workout.totalEnergyBurned.map { Int($0.doubleValue(for: .kilocalorie()).rounded()) })
            }
            DispatchQueue.main.async { self?.workouts = items }
        }
        healthStore.execute(query)
    }

    private func queryWeightSamples() {
        guard let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return }
        let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 100,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { [weak self] _, samples, _ in
            let items = (samples as? [HKQuantitySample] ?? []).map {
                HealthWeightSample(id: $0.uuid, date: $0.endDate,
                                   kilograms: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)),
                                   source: $0.sourceRevision.source.name)
            }
            DispatchQueue.main.async { self?.weightSamples = items }
        }
        healthStore.execute(query)
    }

    private func queryAccessorySources() {
        let types: [(HKSampleType, String)] = [
            (HKObjectType.quantityType(forIdentifier: .heartRate)!, "Heart rate"),
            (HKObjectType.quantityType(forIdentifier: .stepCount)!, "Steps"),
            (HKObjectType.quantityType(forIdentifier: .bodyMass)!, "Weight"),
            (.workoutType(), "Workouts")
        ]
        for (type, metric) in types {
            let query = HKSourceQuery(sampleType: type, samplePredicate: nil) { [weak self] _, sources, _ in
                let names = (sources ?? []).map { $0.name }
                DispatchQueue.main.async {
                    guard let self else { return }
                    var mapped = Dictionary(uniqueKeysWithValues: self.accessorySources.map { ($0.id, $0) })
                    for name in names {
                        let key = name.lowercased()
                        let existing = mapped[key]?.metrics.components(separatedBy: ", ") ?? []
                        let metrics = Array(Set(existing + [metric])).sorted().joined(separator: ", ")
                        mapped[key] = HealthAccessorySource(id: key, name: name, metrics: metrics)
                    }
                    self.accessorySources = mapped.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                }
            }
            healthStore.execute(query)
        }
    }

    private func queryRecentHeartReadings() {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        let since = Date.now.addingTimeInterval(-24 * 60 * 60)
        let predicate = HKQuery.predicateForSamples(withStart: since, end: .now, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 60,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { [weak self] _, samples, _ in
            let readings = (samples as? [HKQuantitySample] ?? []).map { sample in
                AccessoryHeartReading(id: sample.uuid,
                                      beatsPerMinute: Int(sample.quantity.doubleValue(for: .count().unitDivided(by: .minute())).rounded()),
                                      date: sample.endDate,
                                      source: sample.sourceRevision.source.name,
                                      device: sample.device?.name ?? sample.device?.model)
            }
            DispatchQueue.main.async { self?.recentHeartReadings = readings }
        }
        healthStore.execute(query)
    }

}

private extension HKWorkoutActivityType {
    var daywellName: String {
        switch self {
        case .running: "Run"
        case .walking: "Walk"
        case .cycling: "Cycling"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Strength"
        case .boxing: "Boxing"
        case .stairClimbing: "Stair climbing"
        case .yoga: "Yoga"
        case .swimming: "Swim"
        case .hiking: "Hike"
        case .highIntensityIntervalTraining: "HIIT"
        default: "Workout"
        }
    }
}
