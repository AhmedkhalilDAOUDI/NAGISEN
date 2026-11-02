import Charts
import MapKit
import SwiftUI

// MARK: - Workouts card

/// Start a recording, and see the latest activities.
struct RecordCard: View {
    @EnvironmentObject private var store: NutritionStore
    @State private var recording: RecordedActivity.Kind?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "location.north.line").foregroundStyle(Theme.accentText)
                Text("RECORD")
                    .font(.caption2.weight(.semibold)).nagisenTracking(1.6)
                    .foregroundStyle(Theme.muted)
                Spacer()
                NavigationLink { ActivityRecordsView() } label: {
                    Text("Records").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accentText)
                }
            }
            Text("Go outside. NAGISEN draws the way.")
                .font(.system(size: 19, design: .serif))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach(RecordedActivity.Kind.allCases) { kind in
                    Button { recording = kind } label: {
                        Label(kind.name, systemImage: kind.symbol)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.16), lineWidth: 0.5))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            ForEach(store.activities.prefix(3)) { activity in
                NavigationLink { ActivityDetailView(activity: activity) } label: { ActivityRow(activity: activity) }
                    .buttonStyle(.plain)
            }
        }
        .foregroundStyle(Theme.ink)
        .softCardStyle()
        .fullScreenCover(item: $recording) { RecordActivityView(kind: $0) }
    }
}

struct ActivityRow: View {
    let activity: RecordedActivity

    var body: some View {
        HStack(spacing: 12) {
            RouteShape(points: activity.points)
                .stroke(Theme.accentText, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: 40, height: 40)
                .padding(6)
                .background(Theme.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(activity.kind.name) · \(activity.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                    .font(.subheadline.weight(.medium))
                Text(activity.summary).font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Recording

struct RecordActivityView: View {
    @EnvironmentObject private var store: NutritionStore
    @EnvironmentObject private var health: HealthManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder: ActivityRecorder
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var confirmingFinish = false
    @State private var saving = false

    init(kind: RecordedActivity.Kind) {
        _recorder = StateObject(wrappedValue: ActivityRecorder(kind: kind))
    }

    private var activity: RecordedActivity { recorder.activity }

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $camera) {
                UserAnnotation()
                ForEach(Array(segments(activity.points).enumerated()), id: \.offset) { _, line in
                    MapPolyline(coordinates: line).stroke(Theme.accent, lineWidth: 5)
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControls { }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                Button {
                    if activity.points.isEmpty { _ = recorder.finish(); dismiss() } else { confirmingFinish = true }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .medium))
                        .frame(width: 44, height: 44)
                        .nagisenGlass(in: Circle(), tint: Theme.surface.opacity(0.3))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.ink)
                .accessibilityLabel(String(localized: "Close"))
                .padding(.horizontal, 16).padding(.top, 58)
            }

            VStack(spacing: 22) {
                status
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(alignment: .firstTextBaseline) {
                        stat(RecordedActivity.durationText(recorder.elapsed(at: context.date)), String(localized: "time"))
                        stat((activity.distance / 1000).formatted(.number.precision(.fractionLength(2))), String(localized: "km"))
                        if activity.kind.showsSpeed {
                            stat(recorder.currentSpeed.map { ($0 * 3.6).formatted(.number.precision(.fractionLength(1))) } ?? "–",
                                 String(localized: "km/h"))
                        } else {
                            stat(recorder.currentSpeed.flatMap { $0 > 0.5 ? RecordedActivity.paceText(1000 / $0) : nil } ?? "–",
                                 String(localized: "/km now"))
                        }
                    }
                }
                controls
            }
            .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 28)
            .frame(maxWidth: .infinity)
            .background(Color(red: 0.035, green: 0.03, blue: 0.035))
        }
        .ignoresSafeArea(edges: .top)
        .foregroundStyle(Theme.ink)
        .background(Color(red: 0.035, green: 0.03, blue: 0.035).ignoresSafeArea())
        .onAppear { recorder.start() }
        .onDisappear { if recorder.state != .idle { _ = recorder.finish() } }
        .nagisenDialog("Finish this \(activity.kind.name.lowercased())?", isPresented: $confirmingFinish,
                       message: activity.summary) {
            [NagisenAction(title: String(localized: "Save")) { save() },
             NagisenAction(title: String(localized: "Discard"), destructive: true) { _ = recorder.finish(); dismiss() }]
        }
    }

    @ViewBuilder private var status: some View {
        switch recorder.state {
        case .waitingForGPS:
            Label("Finding GPS…", systemImage: "location").font(.subheadline).foregroundStyle(Theme.muted)
        case .denied:
            VStack(spacing: 8) {
                Text("Location is off for NAGISEN").font(.system(size: 19, design: .serif))
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accentText)
            }
        case .paused:
            Text("PAUSED").font(.caption2.weight(.semibold)).nagisenTracking(2).foregroundStyle(Theme.accentText)
        case .recording, .idle:
            Text(activity.kind.name.uppercased()).font(.caption2.weight(.semibold)).nagisenTracking(2).foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder private var controls: some View {
        switch recorder.state {
        case .recording:
            roundButton("pause.fill", label: String(localized: "Pause"), filled: true) { recorder.pause() }
        case .paused:
            HStack(spacing: 28) {
                roundButton("play.fill", label: String(localized: "Resume"), filled: true) { recorder.resume() }
                roundButton("flag.checkered", label: String(localized: "Finish"), filled: false) { confirmingFinish = true }
            }
        case .waitingForGPS, .denied, .idle:
            roundButton("pause.fill", label: String(localized: "Pause"), filled: false) { }
                .disabled(true).opacity(0.3)
        }
    }

    private func roundButton(_ symbol: String, label: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 24, weight: .medium))
                .frame(width: 76, height: 76)
                .background(filled ? Theme.red : Color.clear, in: Circle())
                .overlay(Circle().strokeBorder(Theme.ink.opacity(filled ? 0 : 0.3), lineWidth: 1))
                .foregroundStyle(filled ? .white : Theme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func stat(_ value: String, _ unit: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 34, design: .serif)).monospacedDigit()
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(unit).font(.caption).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func save() {
        guard !saving else { return }
        saving = true
        // Saved here first, so a slow or declined Health prompt can never lose the activity.
        let finished = recorder.finish()
        store.saveActivity(finished)
        dismiss()
        Task {
            if let uuid = await health.save(finished) { store.linkActivity(finished.id, toHealthWorkout: uuid) }
        }
    }
}

/// The route split at pauses, as map coordinates.
func segments(_ points: [RecordedActivity.RoutePoint]) -> [[CLLocationCoordinate2D]] {
    Dictionary(grouping: points, by: \.segment).sorted { $0.key < $1.key }
        .map { $0.value.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } }
        .filter { $0.count > 1 }
}

/// The route drawn as a plain line fitted into any rectangle: no map, so no street names.
struct RouteShape: Shape {
    let points: [RecordedActivity.RoutePoint]

    func path(in rect: CGRect) -> Path {
        guard let minLat = points.map(\.latitude).min(), let maxLat = points.map(\.latitude).max(),
              let minLon = points.map(\.longitude).min(), let maxLon = points.map(\.longitude).max() else { return Path() }
        // Longitude degrees shrink with latitude; scale them so the shape is not stretched.
        let squash = cos((minLat + maxLat) / 2 * .pi / 180)
        let width = max((maxLon - minLon) * squash, 1e-9), height = max(maxLat - minLat, 1e-9)
        let scale = min(rect.width / width, rect.height / height)
        let offsetX = rect.minX + (rect.width - width * scale) / 2
        let offsetY = rect.minY + (rect.height - height * scale) / 2
        var path = Path()
        var lastSegment: Int?
        for point in points {
            let p = CGPoint(x: offsetX + (point.longitude - minLon) * squash * scale,
                            y: offsetY + (maxLat - point.latitude) * scale)
            if point.segment != lastSegment { path.move(to: p) } else { path.addLine(to: p) }
            lastSegment = point.segment
        }
        return path
    }
}

// MARK: - Activity page

struct ActivityDetailView: View {
    @EnvironmentObject private var store: NutritionStore
    @EnvironmentObject private var health: HealthManager
    @EnvironmentObject private var feed: FeedService
    @Environment(\.dismiss) private var dismiss
    let activity: RecordedActivity
    @State private var heartRate: Int?
    @State private var confirmingDelete = false
    @State private var sharing = false

    var body: some View {
        let splits = activity.splits
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                NagisenHeader(activity.kind.name,
                              subtitle: activity.start.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()),
                              onBack: { dismiss() })
                Map(initialPosition: .automatic, interactionModes: [.pan, .zoom]) {
                    ForEach(Array(segments(activity.points).enumerated()), id: \.offset) { _, line in
                        MapPolyline(coordinates: line).stroke(Theme.accent, lineWidth: 4)
                    }
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    tile((activity.distance / 1000).formatted(.number.precision(.fractionLength(2))), String(localized: "km"))
                    tile(RecordedActivity.durationText(activity.movingSeconds), String(localized: "moving time"))
                    if activity.kind.showsSpeed {
                        tile(activity.speedKmh.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "–", String(localized: "km/h average"))
                    } else {
                        tile(activity.pace.map(RecordedActivity.paceText) ?? "–", String(localized: "/km average"))
                    }
                    tile("\(Int(activity.elevationGain.rounded())) m", String(localized: "climbed"))
                    if let heartRate { tile("\(heartRate)", String(localized: "bpm average")) }
                }

                if splits.count > 1 {
                    let fastest = splits.filter { $0.km >= 1 }.map(\.seconds).min()
                    NagisenSection("Splits") {
                        Chart(Array(splits.enumerated()), id: \.offset) { index, split in
                            BarMark(x: .value("km", index + 1), y: .value("pace", split.seconds / split.km / 60))
                                .foregroundStyle(split.km >= 1 && split.seconds == fastest ? Theme.accent : Theme.ink.opacity(0.25))
                        }
                        .chartYAxisLabel(String(localized: "min /km"))
                        .frame(height: 140)
                        .padding(.vertical, 12)
                        ForEach(Array(splits.enumerated()), id: \.offset) { index, split in
                            Divider().overlay(Theme.line)
                            HStack {
                                Text(split.km >= 1 ? "\(index + 1)" : "\(split.km.formatted(.number.precision(.fractionLength(2)))) km")
                                    .monospacedDigit()
                                Spacer()
                                Text("\(RecordedActivity.paceText(split.seconds / split.km)) /km").monospacedDigit()
                                    .foregroundStyle(split.km >= 1 && split.seconds == fastest ? Theme.accentText : Theme.muted)
                            }
                            .font(.subheadline)
                            .frame(minHeight: 40)
                        }
                    }
                }

                let profile = elevationProfile
                if profile.count > 2, activity.elevationGain >= 3 {
                    NagisenSection("Elevation") {
                        Chart(profile, id: \.km) { point in
                            AreaMark(x: .value("km", point.km), y: .value("m", point.altitude))
                                .foregroundStyle(Theme.accent.opacity(0.25))
                            LineMark(x: .value("km", point.km), y: .value("m", point.altitude))
                                .foregroundStyle(Theme.accentText)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 120)
                        .padding(.vertical, 12)
                    }
                }

                HStack(spacing: 12) {
                    Button { sharing = true } label: {
                        Label("Share to Feed", systemImage: "square.and.arrow.up")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(Theme.red, in: RoundedRectangle(cornerRadius: 15))
                            .foregroundStyle(.white)
                    }
                    Button { confirmingDelete = true } label: {
                        Image(systemName: "trash")
                            .frame(width: 52, height: 52)
                            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Theme.ink.opacity(0.16), lineWidth: 0.5))
                    }
                    .accessibilityLabel(String(localized: "Delete activity"))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 32)
        }
        .background(NagisenBackdrop())
        .toolbar(.hidden, for: .navigationBar)
        .task { heartRate = await health.averageHeartRate(from: activity.start, to: activity.end) }
        .sheet(isPresented: $sharing) { ShareActivityView(activity: activity) }
        .nagisenDialog("Delete this activity?", isPresented: $confirmingDelete,
                       message: String(localized: "It is removed from NAGISEN. A copy saved to Apple Health stays there.")) {
            [NagisenAction(title: String(localized: "Delete"), destructive: true) { store.deleteActivity(activity); dismiss() }]
        }
    }

    /// Altitude against distance, thinned to about 120 points so the chart stays light.
    private var elevationProfile: [(km: Double, altitude: Double)] {
        var result: [(Double, Double)] = []
        var covered = 0.0
        var previous: RecordedActivity.RoutePoint?
        let stride = max(1, activity.points.count / 120)
        for (index, point) in activity.points.enumerated() {
            if let previous, previous.segment == point.segment { covered += point.location.distance(from: previous.location) }
            previous = point
            if index % stride == 0 { result.append((covered / 1000, point.altitude)) }
        }
        return result
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 28, design: .serif)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCardStyle()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Records and totals

struct ActivityRecordsView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let activities = store.activities
        let weeks = ActivityRecords.weeklyKilometres(activities, weeks: 8)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                NagisenHeader("Records", subtitle: String(localized: "Every kilometre, kept."), onBack: { dismiss() })
                HStack(spacing: 12) {
                    total(ActivityRecords.kilometres(activities, in: .weekOfYear, of: .now), String(localized: "km this week"))
                    total(ActivityRecords.kilometres(activities, in: .month, of: .now), String(localized: "km this month"))
                }
                NagisenSection("Last 8 weeks") {
                    Chart(weeks, id: \.week) { week in
                        BarMark(x: .value("week", week.week, unit: .weekOfYear), y: .value("km", week.km))
                            .foregroundStyle(Calendar.current.isDate(week.week, equalTo: .now, toGranularity: .weekOfYear)
                                             ? Theme.accent : Theme.ink.opacity(0.25))
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                    .frame(height: 140)
                    .padding(.vertical, 12)
                }
                let efforts = ActivityRecords.bestEfforts(activities)
                NagisenSection("Fastest runs") {
                    if efforts.isEmpty {
                        Text("Record a run of 1 km or more to set your first record.")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                    }
                    ForEach(Array(efforts.enumerated()), id: \.offset) { index, effort in
                        if index > 0 { Divider().overlay(Theme.line) }
                        NavigationLink { ActivityDetailView(activity: effort.activity) } label: {
                            HStack {
                                Text(effort.name)
                                Spacer()
                                Text(RecordedActivity.durationText(effort.seconds)).monospacedDigit().foregroundStyle(Theme.accentText)
                            }
                            .font(.subheadline).frame(minHeight: 46).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                NagisenSection("Longest") {
                    ForEach([RecordedActivity.Kind.run, .walk, .ride, .hike], id: \.self) { kind in
                        if let longest = ActivityRecords.longest(activities, kind: kind) {
                            NavigationLink { ActivityDetailView(activity: longest) } label: {
                                HStack {
                                    Text(kind.name)
                                    Spacer()
                                    Text("\((longest.distance / 1000).formatted(.number.precision(.fractionLength(2)))) km")
                                        .monospacedDigit().foregroundStyle(Theme.muted)
                                }
                                .font(.subheadline).frame(minHeight: 46).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if activities.isEmpty {
                        Text("Nothing recorded yet.").font(.subheadline).foregroundStyle(Theme.muted).padding(.vertical, 12)
                    }
                }
                if !activities.isEmpty {
                    NagisenSection("All activities") {
                        ForEach(activities) { activity in
                            NavigationLink { ActivityDetailView(activity: activity) } label: { ActivityRow(activity: activity) }
                                .buttonStyle(.plain)
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 32)
        }
        .background(NagisenBackdrop())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func total(_ km: Double, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(km.formatted(.number.precision(.fractionLength(1)))).font(.system(size: 34, design: .serif)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCardStyle()
    }
}

// MARK: - Sharing

/// The image posted to the Feed: the route's shape and the numbers, never a map or an address.
struct RouteCard: View {
    let activity: RecordedActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Circle().fill(Theme.accent).frame(width: 8, height: 8)
                Text("NAGISEN").font(.system(size: 13, weight: .semibold)).nagisenTracking(4)
                Spacer()
                Text(activity.kind.name.uppercased()).font(.system(size: 11, weight: .semibold)).nagisenTracking(2)
                    .foregroundStyle(Theme.muted)
            }
            RouteShape(points: activity.points)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
            HStack(alignment: .firstTextBaseline) {
                number((activity.distance / 1000).formatted(.number.precision(.fractionLength(2))), String(localized: "km"))
                number(RecordedActivity.durationText(activity.movingSeconds), String(localized: "time"))
                if activity.kind.showsSpeed {
                    number(activity.speedKmh.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "–", String(localized: "km/h"))
                } else {
                    number(activity.pace.map(RecordedActivity.paceText) ?? "–", String(localized: "/km"))
                }
            }
        }
        .padding(28)
        .frame(width: 360, height: 450)
        .background(Color(red: 0.035, green: 0.03, blue: 0.035))
        .foregroundStyle(Theme.ink)
        .environment(\.colorScheme, .dark)
    }

    private func number(_ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 28, design: .serif)).monospacedDigit()
            Text(unit).font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ShareActivityView: View {
    @EnvironmentObject private var feed: FeedService
    @Environment(\.dismiss) private var dismiss
    let activity: RecordedActivity
    @State private var caption = ""
    @State private var posting = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    RouteCard(activity: activity)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .scaleEffect(0.85)
                        .frame(height: 400)
                    if feed.state == .ready {
                        TextField("Say something (optional)", text: $caption, axis: .vertical)
                            .lineLimit(1...4)
                            .padding(14)
                            .nagisenPanel()
                        if failed {
                            Text(feed.message ?? String(localized: "Couldn't post right now. Try again."))
                                .font(.caption).foregroundStyle(Theme.accentText)
                        }
                    } else {
                        Text("Join the community in Settings to share activities to the Feed.")
                            .font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    }
                }
                .padding(20)
            }
            .background(NagisenBackdrop())
            .nagisenSheetBar(String(localized: "Share to Feed"), onClose: { dismiss() },
                             actionTitle: String(localized: "Post"), actionEnabled: feed.state == .ready && !posting,
                             busy: posting) { post() }
        }
    }

    private func post() {
        let renderer = ImageRenderer(content: RouteCard(activity: activity))
        renderer.scale = 3
        guard let data = renderer.uiImage?.jpegData(compressionQuality: 0.9),
              let attachment = try? PostMedia.photo(from: data) else { failed = true; return }
        posting = true
        Task {
            if await feed.publish(caption, attachment: attachment) { dismiss() } else { failed = true }
            posting = false
        }
    }
}
