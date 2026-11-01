import SwiftUI
import HealthKit

@available(iOS 26.0, *)
private final class LiveAccessoryWorkout: NSObject, ObservableObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    static let shared = LiveAccessoryWorkout()
    @Published var isRunning = false
    @Published var isPreparing = false
    @Published var heartRate: Int?
    @Published var startedAt: Date?
    @Published var activityName = "Workout"
    @Published var error: String?
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    func start(_ activity: HKWorkoutActivityType, name: String) {
        guard session == nil, HKHealthStore.isHealthDataAvailable() else { return }
        activityName = name
        heartRate = nil
        error = nil
        startedAt = nil
        let read: Set<HKObjectType> = [HKObjectType.quantityType(forIdentifier: .heartRate)!, .workoutType()]
        healthStore.requestAuthorization(toShare: [.workoutType()], read: read) { [weak self] allowed, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard allowed else { self.error = error?.localizedDescription ?? String(localized: "Allow workout access in Apple Health to start."); return }
                self.begin(activity)
            }
        }
    }

    private func begin(_ activity: HKWorkoutActivityType) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity
        configuration.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            let dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) {
                dataSource.enableCollection(for: heartRate, predicate: nil)
            }
            builder.dataSource = dataSource
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            isPreparing = true
            session.prepare()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.session === session else { return }
                let start = Date.now
                self.startedAt = start
                session.startActivity(with: start)
                builder.beginCollection(withStart: start) { [weak self] success, error in
                    DispatchQueue.main.async {
                        self?.isPreparing = false
                        self?.isRunning = success
                        if !success {
                            self?.error = error?.localizedDescription ?? String(localized: "The workout could not start.")
                            session.end()
                            self?.session = nil
                            self?.builder = nil
                        }
                    }
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stop() {
        guard let session else { return }
        if isPreparing {
            session.end()
            self.session = nil
            builder = nil
            isPreparing = false
            return
        }
        session.stopActivity(with: .now)
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .stopped, let builder else { return }
        builder.endCollection(withEnd: date) { [weak self] success, error in
            guard success else {
                DispatchQueue.main.async { self?.error = error?.localizedDescription ?? String(localized: "Could not finish the workout.") }
                return
            }
            builder.finishWorkout { [weak self] _, error in
                workoutSession.end()
                DispatchQueue.main.async {
                    self?.error = error?.localizedDescription
                    self?.isRunning = false
                    self?.isPreparing = false
                    self?.session = nil
                    self?.builder = nil
                }
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.error = error.localizedDescription
            self.isRunning = false
            self.isPreparing = false
            self.session = nil
            self.builder = nil
        }
    }

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate), collectedTypes.contains(type),
              let quantity = workoutBuilder.statistics(for: type)?.mostRecentQuantity() else { return }
        let value = Int(quantity.doubleValue(for: .count().unitDivided(by: .minute())).rounded())
        DispatchQueue.main.async { self.heartRate = value }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) { }
}

@available(iOS 26.0, *)
private struct LiveAccessoryWorkoutView: View {
    @EnvironmentObject private var health: HealthManager
    @ObservedObject private var workout = LiveAccessoryWorkout.shared
    @State private var activity = 0
    private let liveRefresh = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private let activities: [(String, HKWorkoutActivityType)] = [
        ("Walking", .walking), ("Running", .running), ("Strength", .traditionalStrengthTraining),
        ("Cycling", .cycling), ("Stairs", .stairClimbing)
    ]

    private var freshHealthReading: AccessoryHeartReading? {
        guard let started = workout.startedAt,
              let reading = health.recentHeartReadings.first,
              reading.date >= started,
              Date.now.timeIntervalSince(reading.date) < 20 else { return nil }
        return reading
    }

    var body: some View {
        NagisenSection("Live workout") {
            if workout.isRunning || workout.isPreparing {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(workout.isPreparing ? String(localized: "Preparing sensors…") : workout.activityName)
                            .font(.headline)
                        Text(workout.heartRate.map { "\($0) bpm" } ??
                             freshHealthReading.map { "\($0.beatsPerMinute) bpm" } ?? "Waiting for heart rate")
                            .font(.subheadline).foregroundStyle(Theme.accentText)
                        if workout.heartRate == nil, let reading = freshHealthReading {
                            Text("From Health · \(reading.displaySource)")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    Spacer()
                    if let started = workout.startedAt, workout.isRunning {
                        Text(started, style: .timer).monospacedDigit()
                    }
                }.frame(minHeight: 60)
                if workout.isRunning && workout.heartRate == nil && freshHealthReading == nil {
                    Text("No live reading yet. Check that your device is worn snugly, is sharing heart rate with Apple Health, and that NAGISEN has Heart Rate access in Health.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Divider()
                Button(workout.isPreparing ? "Cancel" : "End workout") { workout.stop() }
                    .foregroundStyle(Theme.accentText).frame(minHeight: 48)
            } else {
                NagisenPicker("Activity", selection: $activity, options: activities.indices.map { ($0, activities[$0].0) })
                    .frame(minHeight: 52)
                Divider()
                Button("Start with heart rate") { workout.start(activities[activity].1, name: activities[activity].0) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentText).frame(minHeight: 52)
            }
            if let error = workout.error {
                Divider()
                Text(error).font(.caption).foregroundStyle(Theme.accentText)
            }
        }
        .onChange(of: workout.isRunning) { wasRunning, isRunning in
            if wasRunning && !isRunning { health.refresh() }
        }
        .onReceive(liveRefresh) { _ in
            if workout.isRunning { health.refreshAccessoryReadings() }
        }
    }
}

/// Heart rate per device, a live workout, and importing Health workouts and weight. Shown inside HealthView.
private struct HealthDevicesSections: View {
    @EnvironmentObject private var health: HealthManager
    @EnvironmentObject private var store: NutritionStore
    @AppStorage("nagisen.health.autoImport") private var autoImport = false
    @State private var importStatus: String?
    private let refresh = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    /// The newest reading from each device: a watch, ring, band, chest strap or earbuds.
    private var latestByDevice: [AccessoryHeartReading] {
        var seen = Set<String>()
        return health.recentHeartReadings.filter { seen.insert($0.displaySource).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            NagisenSection("Heart rate by device") {
                if latestByDevice.isEmpty {
                    Text("Wear anything that saves heart rate to Apple Health: Apple Watch, Garmin, Oura, Whoop, Polar, AirPods Pro or another watch, ring, band or strap. Most apps share with Health from their own settings; some brands need a separate sync app.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                }
                ForEach(latestByDevice) { reading in
                    HStack {
                        Label(reading.displaySource, systemImage: "heart.fill")
                            .font(.subheadline)
                        Spacer()
                        Text("\(reading.beatsPerMinute) bpm").font(.subheadline.weight(.semibold))
                        Text(reading.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    .frame(minHeight: 48)
                    if reading.id != latestByDevice.last?.id { Divider() }
                }
            }
            if #available(iOS 26.0, *) { LiveAccessoryWorkoutView() }
            NagisenSection("Keep your log together") {
                Toggle("Import Health workouts & weight", isOn: $autoImport)
                    .tint(Theme.red).frame(minHeight: 54)
                Divider()
                Button("Import available data now") { importAvailable() }
                    .font(.subheadline.weight(.medium)).frame(minHeight: 52)
                if let importStatus {
                    Divider()
                    Text(importStatus).font(.caption).foregroundStyle(Theme.muted)
                }
            }
        }
        .onReceive(refresh) { _ in health.refreshAccessoryReadings() }
        .onReceive(health.$workouts) { _ in if autoImport { importAvailable() } }
        .onReceive(health.$weightSamples) { _ in if autoImport { importAvailable() } }
        .onChange(of: autoImport) { _, enabled in if enabled { importAvailable() } }
    }

    private func importAvailable() {
        let count = store.importHealth(workouts: health.workouts, weights: health.weightSamples)
        importStatus = count.workouts + count.weights == 0 ? String(localized: "Everything available is already in your log.") :
            "Added \(count.workouts) workout(s) and \(count.weights) weigh-in(s)."
    }
}

struct HealthView: View {
    @EnvironmentObject private var health: HealthManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Theme.accentText)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apple Health").font(.system(size: 29, design: .serif))
                        Text("Your activity, together in NAGISEN")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                    }
                }
                if !health.hasRequestedAccess {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Connect your Health data")
                            .font(.headline)
                        Text("See steps, activity, heart rate, body weight and recent workouts. Your data stays on this iPhone. Choose what to share in Apple's permission sheet.")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                        Button("Connect Apple Health") { health.requestAccess() }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.red)
                            .disabled(!health.isAvailable)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                } else {
                    Text("TODAY'S ACTIVITY")
                        .font(.caption.weight(.bold)).nagisenTracking(2).foregroundStyle(Theme.muted)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        metric(String(localized: "Steps"), value: health.steps.map { $0.formatted() }, unit: "steps", symbol: "figure.walk")
                        metric(String(localized: "Move"), value: health.activeCalories.map { $0.formatted() }, unit: "kcal", symbol: "flame")
                        metric("Exercise", value: health.exerciseMinutes.map { $0.formatted() }, unit: "min", symbol: "figure.run")
                        metric(String(localized: "Distance"), value: health.distanceKilometers.map { String(format: "%.1f", $0) }, unit: "km", symbol: "point.topleft.down.to.point.bottomright.curvepath")
                        metric(String(localized: "Flights"), value: health.flightsClimbed.map { $0.formatted() }, unit: "flights", symbol: "figure.stairs")
                        metric(String(localized: "Stand"), value: health.standHours.map { $0.formatted() }, unit: "hours", symbol: "figure.stand")
                        metric(String(localized: "Heart rate"), value: health.heartRate.map { $0.formatted() }, unit: "bpm · latest", symbol: "heart")
                        metric(String(localized: "Resting pulse"), value: health.restingHeartRate.map { $0.formatted() }, unit: "bpm · latest", symbol: "waveform.path.ecg")
                        metric(String(localized: "Body weight"), value: health.weightKilograms.map { String(format: "%.1f", $0) }, unit: "kg · latest", symbol: "scalemass")
                    }
                    Text("RECENT WORKOUTS")
                        .font(.caption.weight(.bold)).nagisenTracking(2).foregroundStyle(Theme.muted)
                    if health.workouts.isEmpty {
                        Text("No workouts available yet. Check the types you allowed in Apple Health.")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardStyle()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(health.workouts) { workout in
                                HStack {
                                    Image(systemName: "figure.run.circle.fill")
                                        .font(.title2).foregroundStyle(Theme.accentText)
                                    VStack(alignment: .leading) {
                                        Text(workout.name).font(.subheadline.weight(.semibold))
                                        Text(workout.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                                            .font(.caption).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    Text("\(workout.minutes) min")
                                        .font(.subheadline)
                                }
                                .padding(.vertical, 12)
                                if workout.id != health.workouts.last?.id { Divider() }
                            }
                        }
                        .cardStyle()
                    }
                    HealthDevicesSections()
                    Button("Refresh Health data") { health.refresh() }
                        .font(.subheadline.weight(.medium))
                        .tint(Theme.red)
                    Text("Values may be unavailable if access was not granted. Change access in Apple Health → profile → Apps → NAGISEN. NAGISEN reads Health data on this device and doesn't send it anywhere, except today's step count to the coach when you turn that on.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(24)
        }
        .background(NagisenBackdrop())
        .navigationTitle("Health")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { health.refresh() }
        .nagisenDialog("Apple Health", isPresented: Binding(get: { health.errorMessage != nil }, set: { if !$0 { health.errorMessage = nil } }),
                       message: health.errorMessage, cancelTitle: "OK")
    }

    private func metric(_ title: String, value: String?, unit: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Theme.accentText)
            Text(value ?? "—").font(.system(size: 27, weight: .semibold, design: .rounded))
            Text("\(title) · \(unit)").font(.caption).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 106, alignment: .leading)
        .cardStyle()
    }
}
