import CoreLocation
import Foundation

/// Records one outdoor activity with GPS. It keeps going with the screen locked (the `location`
/// background mode), and only listens to location while a recording is running.
@MainActor
final class ActivityRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum State: Equatable { case idle, waitingForGPS, recording, paused, denied }

    @Published private(set) var state = State.idle
    @Published private(set) var activity: RecordedActivity
    /// Speed over the last ~15 seconds, in metres per second.
    @Published private(set) var currentSpeed: Double?
    /// When the current stretch of recording began; moving time is everything before it plus now.
    @Published private(set) var stretchStart: Date?
    @Published private(set) var lastLocation: CLLocation?

    private let manager = CLLocationManager()
    private var segment = 0
    private var savedSeconds = 0.0

    init(kind: RecordedActivity.Kind) {
        activity = RecordedActivity(kind: kind, start: .now)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = kind == .ride ? .otherNavigation : .fitness
        manager.pausesLocationUpdatesAutomatically = false
    }

    /// Moving time, counting only recording stretches.
    func elapsed(at now: Date = .now) -> Double {
        savedSeconds + (stretchStart.map { now.timeIntervalSince($0) } ?? 0)
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            state = .waitingForGPS
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            state = .denied
        default:
            beginUpdates()
        }
    }

    func pause() {
        guard state == .recording else { return }
        savedSeconds = elapsed()
        stretchStart = nil
        segment += 1
        currentSpeed = nil
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        stretchStart = .now
        state = .recording
    }

    /// Stops listening and returns the finished activity.
    func finish() -> RecordedActivity {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        state = .idle
        stretchStart = nil
        return activity
    }

    private func beginUpdates() {
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        state = .waitingForGPS
        manager.startUpdatingLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                if state == .waitingForGPS { beginUpdates() }
            case .denied, .restricted:
                state = .denied
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in locations.forEach(add) }
    }

    private func add(_ location: CLLocation) {
        if state == .waitingForGPS {
            // The clock starts on the first precise fix, not on the button.
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 25 else { return }
            activity.start = location.timestamp
            stretchStart = location.timestamp
            state = .recording
        }
        guard state == .recording else { return }
        let previous = activity.points.last.flatMap { $0.segment == segment ? $0.location : nil }
        guard RecordedActivity.accepts(location, after: previous, kind: activity.kind) else { return }
        activity.points.append(.init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                     altitude: location.altitude, date: location.timestamp, segment: segment))
        lastLocation = location
        let recent = activity.points.suffix(6).filter { $0.segment == segment }
        if let first = recent.first, let last = recent.last, last.date > first.date {
            let meters = zip(recent, recent.dropFirst()).reduce(0) { $0 + $1.1.location.distance(from: $1.0.location) }
            currentSpeed = meters / last.date.timeIntervalSince(first.date)
        }
    }
}
