import CoreLocation
import MapKit
import SwiftUI

/// Finds gyms and fitness centers near the iPhone: Google Places when a key is set up, Apple Maps
/// otherwise. The location goes only to that search; NAGISEN neither stores it nor sends it elsewhere.
@MainActor
final class GymFinder: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum State: Equatable { case idle, locating, searching, done, denied, failed(String) }

    struct Gym: Identifiable {
        let id: String
        let name: String
        let address: String
        let coordinate: CLLocationCoordinate2D
        let meters: CLLocationDistance
        let rating: Double?
        /// Opens Google Maps (the app when installed, the website otherwise) with directions.
        var directions: URL? {
            var parts = URLComponents(string: "https://www.google.com/maps/dir/")
            parts?.queryItems = [URLQueryItem(name: "api", value: "1"),
                                 URLQueryItem(name: "destination", value: "\(coordinate.latitude),\(coordinate.longitude)")]
            if !id.hasPrefix("apple-") { parts?.queryItems?.append(URLQueryItem(name: "destination_place_id", value: id)) }
            return parts?.url
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var gyms: [Gym] = []
    private let manager = CLLocationManager()

    /// How far around you to look: 5 km covers a city neighborhood without listing the whole region.
    static let radius: CLLocationDistance = 5_000

    static var googleKey: String? {
        (Bundle.main.object(forInfoDictionaryKey: "GooglePlacesKey") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            state = .locating
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            state = .denied
        default:
            state = .locating
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                if state == .locating { manager.requestLocation() }
            case .denied, .restricted:
                state = .denied
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in await search(around: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            state = .failed(String(localized: "Couldn't find where you are. Check that Location Services are on and try again."))
        }
    }

    private func search(around location: CLLocation) async {
        state = .searching
        do {
            let found: [Gym]
            if let key = Self.googleKey {
                found = try await Self.google(around: location, key: key)
            } else {
                found = try await Self.apple(around: location)
            }
            gyms = found.sorted { $0.meters < $1.meters }
            state = .done
        } catch {
            state = .failed(String(localized: "The gym search didn't work right now. Try again in a moment."))
        }
    }

    /// Google Places (New) Nearby Search for gyms and fitness centers, nearest first.
    private static func google(around location: CLLocation, key: String) async throws -> [Gym] {
        struct Body: Encodable {
            struct Circle: Encodable { let center: [String: Double]; let radius: Double }
            struct Restriction: Encodable { let circle: Circle }
            let includedTypes = ["gym", "fitness_center"]
            let maxResultCount = 20
            let rankPreference = "DISTANCE"
            let languageCode: String
            let locationRestriction: Restriction
        }
        struct Reply: Decodable {
            struct Place: Decodable {
                struct Name: Decodable { let text: String }
                struct Point: Decodable { let latitude: Double; let longitude: Double }
                let id: String
                let displayName: Name?
                let formattedAddress: String?
                let location: Point
                let rating: Double?
            }
            let places: [Place]?
        }
        var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchNearby")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(Bundle.main.bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.setValue("places.id,places.displayName,places.formattedAddress,places.location,places.rating",
                         forHTTPHeaderField: "X-Goog-FieldMask")
        let center = ["latitude": location.coordinate.latitude, "longitude": location.coordinate.longitude]
        request.httpBody = try JSONEncoder().encode(Body(languageCode: Locale.current.language.languageCode?.identifier ?? "en",
                                                         locationRestriction: .init(circle: .init(center: center, radius: radius))))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return (try JSONDecoder().decode(Reply.self, from: data).places ?? []).map { place in
            let point = CLLocation(latitude: place.location.latitude, longitude: place.location.longitude)
            return Gym(id: place.id, name: place.displayName?.text ?? String(localized: "Gym"),
                       address: place.formattedAddress ?? "", coordinate: point.coordinate,
                       meters: location.distance(from: point), rating: place.rating)
        }
    }

    /// Apple Maps points of interest, used when no Google key is set up.
    private static func apple(around location: CLLocation) async throws -> [Gym] {
        let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: radius)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.fitnessCenter])
        do {
            return try await MKLocalSearch(request: request).start().mapItems.enumerated().map { index, item in
                let point = CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
                return Gym(id: "apple-\(index)", name: item.name ?? String(localized: "Gym"),
                           address: [item.placemark.thoroughfare, item.placemark.locality].compactMap { $0 }.joined(separator: ", "),
                           coordinate: point.coordinate, meters: location.distance(from: point), rating: nil)
            }
        } catch let error as MKError where error.code == .placemarkNotFound {
            // Apple Maps answers "nothing nearby" with an error; that's an empty list, not a failure.
            return []
        }
    }
}

/// The Workouts card that opens the nearby gyms.
struct GymsNearbyCard: View {
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.title3)
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text("NEARBY")
                        .font(.caption2.weight(.semibold)).nagisenTracking(1.6)
                        .foregroundStyle(Theme.muted)
                    Text("Find a gym near you")
                        .font(.subheadline)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.ink)
            .softCardStyle()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showing) { GymsNearbyView() }
    }
}

struct GymsNearbyView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var finder = GymFinder()
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch finder.state {
                    case .idle, .locating:
                        status("Finding where you are…")
                    case .searching:
                        status("Looking for gyms nearby…")
                    case .denied:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Location is off for NAGISEN")
                                .font(.system(size: 21, design: .serif))
                            Text("Allow location while using the app in iPhone Settings to see gyms near you.")
                                .font(.subheadline).foregroundStyle(Theme.muted)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accentText)
                        }
                    case .failed(let message):
                        VStack(alignment: .leading, spacing: 10) {
                            Text(message).font(.subheadline).foregroundStyle(Theme.accentText)
                            Button("Try again") { finder.start() }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accentText)
                        }
                    case .done:
                        results
                    }
                    Text(GymFinder.googleKey == nil
                         ? "Your location is used only for this search, through Apple Maps. NAGISEN doesn't store it."
                         : "Your location is sent to Google only for this search. Directions open in Google Maps. NAGISEN doesn't store your location.")
                        .font(.caption).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
            }
            .background(NagisenBackdrop())
            .nagisenSheetBar("Gyms near you", onClose: { dismiss() })
            .onAppear { finder.start() }
        }
    }

    private func status(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(text).font(.subheadline).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    @ViewBuilder
    private var results: some View {
        if finder.gyms.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No gyms within 5 km")
                    .font(.system(size: 21, design: .serif))
                Text("The map has no gyms or fitness centers listed close to you.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
            }
        } else {
            Map(position: $camera) {
                UserAnnotation()
                ForEach(finder.gyms.prefix(15)) { gym in
                    Marker(gym.name, systemImage: "dumbbell.fill", coordinate: gym.coordinate)
                        .tint(Theme.accent)
                }
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.ink.opacity(0.10), lineWidth: 0.5))

            VStack(spacing: 0) {
                ForEach(Array(finder.gyms.prefix(15).enumerated()), id: \.element.id) { index, gym in
                    if index > 0 { Divider().overlay(Theme.ink.opacity(0.08)) }
                    row(gym)
                }
            }
            .padding(.horizontal, 18)
            .nagisenPanel()
        }
    }

    private func row(_ gym: GymFinder.Gym) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(gym.name).font(.body.weight(.medium)).lineLimit(2)
                Text(gym.address.isEmpty ? distance(gym.meters) : "\(distance(gym.meters)) · \(gym.address)")
                    .font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                if let rating = gym.rating {
                    Label(rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                        .font(.caption2).foregroundStyle(Theme.accentText)
                }
            }
            Spacer(minLength: 8)
            Button {
                if let url = gym.directions { UIApplication.shared.open(url) }
            } label: {
                Image(systemName: "arrow.triangle.turn.up.right.diamond")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Directions to \(gym.name)"))
        }
        .padding(.vertical, 8)
    }

    private func distance(_ meters: CLLocationDistance) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}
