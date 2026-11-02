import Charts
import MapKit
import SwiftUI

private let darkMap = MapStyle.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll)

// MARK: - Routes

/// Tap the map to lay down a way; it is saved as a route you can follow while recording.
struct RouteDrawView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    @State private var coordinates: [RouteCoordinate] = []
    @State private var name = ""
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)

    private var route: SavedRoute { SavedRoute(name: name, coordinates: coordinates) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MapReader { proxy in
                    Map(position: $camera) {
                        UserAnnotation()
                        if coordinates.count > 1 {
                            MapPolyline(coordinates: coordinates.map(\.coordinate)).stroke(Theme.accent, lineWidth: 4)
                        }
                        ForEach(Array(coordinates.enumerated()), id: \.offset) { index, point in
                            Annotation("", coordinate: point.coordinate) {
                                Circle().fill(index == 0 ? Theme.accent : Theme.ink).frame(width: 8, height: 8)
                            }
                        }
                    }
                    .mapStyle(darkMap)
                    .onTapGesture { position in
                        if let coordinate = proxy.convert(position, from: .local) {
                            coordinates.append(.init(latitude: coordinate.latitude, longitude: coordinate.longitude))
                        }
                    }
                }
                VStack(spacing: 14) {
                    HStack {
                        Text(coordinates.count < 2 ? String(localized: "Tap the map to draw your way.")
                             : "\((route.distance / 1000).formatted(.number.precision(.fractionLength(2)))) km")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                        Spacer()
                        Button(String(localized: "Undo")) { _ = coordinates.popLast() }
                            .disabled(coordinates.isEmpty)
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accentText)
                    }
                    TextField("Name this route", text: $name)
                        .padding(14).nagisenPanel()
                }
                .padding(20)
            }
            .foregroundStyle(Theme.ink)
            .background(NagisenBackdrop())
            .nagisenSheetBar(String(localized: "Draw a route"), onClose: { dismiss() }, actionTitle: String(localized: "Save"),
                             actionEnabled: coordinates.count > 1 && !name.trimmingCharacters(in: .whitespaces).isEmpty) {
                store.savedRoutes.insert(route, at: 0)
                dismiss()
            }
        }
    }
}

struct RouteDetailView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    let route: SavedRoute
    @State private var confirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                NagisenHeader(route.name, subtitle: "\((route.distance / 1000).formatted(.number.precision(.fractionLength(2)))) km",
                              onBack: { dismiss() })
                Map(initialPosition: .automatic) {
                    MapPolyline(coordinates: route.coordinates.map(\.coordinate)).stroke(Theme.accent, lineWidth: 4)
                }
                .mapStyle(darkMap)
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                Text("Start a recording and choose this route to see it on the map while you go.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                Button(String(localized: "Delete route"), role: .destructive) { confirmingDelete = true }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.danger)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 32)
        }
        .background(NagisenBackdrop())
        .toolbar(.hidden, for: .navigationBar)
        .nagisenDialog("Delete \(route.name)?", isPresented: $confirmingDelete) {
            [NagisenAction(title: String(localized: "Delete"), destructive: true) {
                store.savedRoutes.removeAll { $0.id == route.id }; dismiss()
            }]
        }
    }
}

// MARK: - Personal segments

/// Pick the start and end of a stretch on an activity's route; every later pass is timed against it.
struct MarkSegmentView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    let activity: RecordedActivity
    @State private var first = 0.1
    @State private var last = 0.6
    @State private var name = ""

    private var indices: (Int, Int) {
        let top = Double(max(activity.points.count - 1, 1))
        let a = Int((min(first, last) * top).rounded()), b = Int((max(first, last) * top).rounded())
        return (a, b)
    }

    private var segment: PersonalSegment? {
        PersonalSegment(name: name, activity: activity, from: indices.0, to: indices.1)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    let (a, b) = indices
                    Map(initialPosition: .automatic) {
                        MapPolyline(coordinates: activity.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                            .stroke(Theme.ink.opacity(0.3), lineWidth: 3)
                        if b > a {
                            MapPolyline(coordinates: activity.points[a...b].map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                                .stroke(Theme.accent, lineWidth: 5)
                        }
                    }
                    .mapStyle(darkMap)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    NagisenSection("Stretch") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Start").font(.caption).foregroundStyle(Theme.muted)
                            Slider(value: $first, in: 0...1)
                            Text("End").font(.caption).foregroundStyle(Theme.muted)
                            Slider(value: $last, in: 0...1)
                        }
                        .padding(.vertical, 10)
                        Divider().overlay(Theme.line)
                        LabeledContent("Length", value: segment.map { "\(($0.length / 1000).formatted(.number.precision(.fractionLength(2)))) km" }
                                       ?? String(localized: "At least 100 m"))
                            .frame(minHeight: 48)
                    }
                    TextField("Name it, like \"Seafront\" or \"The hill\"", text: $name)
                        .padding(14).nagisenPanel()
                    Text("Only your own passes are compared. Nobody else's times are ever shown.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                .foregroundStyle(Theme.ink)
                .tint(Theme.accentText)
                .padding(20)
            }
            .background(NagisenBackdrop())
            .nagisenSheetBar(String(localized: "Mark a segment"), onClose: { dismiss() }, actionTitle: String(localized: "Save"),
                             actionEnabled: segment != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty) {
                if let segment { store.segments.insert(segment, at: 0) }
                dismiss()
            }
        }
    }
}

struct SegmentDetailView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    let segment: PersonalSegment
    @State private var confirmingDelete = false

    var body: some View {
        let efforts = segment.efforts(store.activities)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                NagisenHeader(segment.name, subtitle: "\((segment.length / 1000).formatted(.number.precision(.fractionLength(2)))) km · "
                              + String(localized: "you against you"), onBack: { dismiss() })
                if let best = efforts.first {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(RecordedActivity.durationText(best.seconds)).font(.system(size: 44, design: .serif)).monospacedDigit()
                        Text("Your best · \(best.activity.start.formatted(.dateTime.day().month(.abbreviated).year()))")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    .softCardStyle()
                }
                NagisenSection("Every pass") {
                    if efforts.isEmpty {
                        Text("No pass recorded yet.").font(.subheadline).foregroundStyle(Theme.muted).padding(.vertical, 12)
                    }
                    ForEach(Array(efforts.enumerated()), id: \.offset) { index, effort in
                        if index > 0 { Divider().overlay(Theme.line) }
                        HStack {
                            Text(effort.activity.start.formatted(.dateTime.day().month(.abbreviated).year()))
                            Spacer()
                            Text(RecordedActivity.durationText(effort.seconds)).monospacedDigit()
                                .foregroundStyle(index == 0 ? Theme.accentText : Theme.muted)
                        }
                        .font(.subheadline).frame(minHeight: 44)
                    }
                }
                Button(String(localized: "Delete segment"), role: .destructive) { confirmingDelete = true }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.danger)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 32)
        }
        .background(NagisenBackdrop())
        .toolbar(.hidden, for: .navigationBar)
        .nagisenDialog("Delete \(segment.name)?", isPresented: $confirmingDelete,
                       message: String(localized: "Your activities stay; only the segment and its times go.")) {
            [NagisenAction(title: String(localized: "Delete"), destructive: true) {
                store.segments.removeAll { $0.id == segment.id }; dismiss()
            }]
        }
    }
}

/// On an activity page: each of your segments this activity passed through, and how it compares.
struct ActivitySegmentsSection: View {
    @EnvironmentObject private var store: NutritionStore
    let activity: RecordedActivity

    var body: some View {
        let passes = store.segments.compactMap { segment -> (PersonalSegment, Double, Int, Int)? in
            guard let time = segment.time(in: activity) else { return nil }
            let efforts = segment.efforts(store.activities)
            let rank = (efforts.firstIndex { $0.activity.id == activity.id } ?? efforts.count) + 1
            return (segment, time, rank, efforts.count)
        }
        if !passes.isEmpty {
            NagisenSection("Your segments") {
                ForEach(Array(passes.enumerated()), id: \.offset) { index, pass in
                    if index > 0 { Divider().overlay(Theme.line) }
                    NavigationLink { SegmentDetailView(segment: pass.0) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pass.0.name)
                                Text(pass.2 == 1 ? String(localized: "Your best") : String(localized: "\(pass.2) of \(pass.3) passes"))
                                    .font(.caption).foregroundStyle(pass.2 == 1 ? Theme.accentText : Theme.muted)
                            }
                            Spacer()
                            Text(RecordedActivity.durationText(pass.1)).monospacedDigit()
                        }
                        .font(.subheadline).frame(minHeight: 50).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Goals, training load, heatmap

struct GoalsSection: View {
    @EnvironmentObject private var store: NutritionStore
    @State private var adding = false

    var body: some View {
        NagisenSection("Goals") {
            if store.activityGoals.isEmpty {
                Text("Set a weekly or monthly target, like 20 km a week or 3 runs a week.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
            }
            ForEach(store.activityGoals) { goal in
                let done = goal.progress(store.activities)
                HStack(spacing: 14) {
                    ZStack {
                        Circle().stroke(Theme.line, lineWidth: 5)
                        Circle().trim(from: 0, to: min(done / max(goal.target, 0.001), 1))
                            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.title).font(.subheadline.weight(.medium))
                        Text(done >= goal.target ? String(localized: "Done for this \(goal.period == .week ? "week" : "month")")
                             : "\(done.formatted(.number.precision(.fractionLength(0...1)))) / \(goal.target.formatted(.number.precision(.fractionLength(0...1))))")
                            .font(.caption).foregroundStyle(done >= goal.target ? Theme.accentText : Theme.muted)
                    }
                    Spacer()
                    Button { store.activityGoals.removeAll { $0.id == goal.id } } label: {
                        Image(systemName: "minus.circle").foregroundStyle(Theme.muted).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Remove goal"))
                }
                .frame(minHeight: 56)
            }
            Divider().overlay(Theme.line)
            Button(String(localized: "Add a goal")) { adding = true }
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accentText).frame(minHeight: 48)
        }
        .sheet(isPresented: $adding) { AddGoalView() }
    }
}

private struct AddGoalView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    @State private var measure = ActivityGoal.Measure.kilometres
    @State private var period = ActivityGoal.Period.week
    @State private var target = "20"
    @State private var kind: RecordedActivity.Kind? = .run

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    NagisenSection("Goal") {
                        NagisenPicker("Count", selection: $measure,
                                      options: [(.kilometres, String(localized: "Kilometres")), (.activities, String(localized: "Activities"))])
                            .frame(minHeight: 52)
                        Divider().overlay(Theme.line)
                        NagisenTextRow("Target", placeholder: "20", unit: measure == .kilometres ? "km" : "×", text: $target, keyboard: .decimalPad)
                        Divider().overlay(Theme.line)
                        NagisenPicker("Every", selection: $period,
                                      options: [(.week, String(localized: "Week")), (.month, String(localized: "Month"))])
                            .frame(minHeight: 52)
                        Divider().overlay(Theme.line)
                        NagisenPicker("Kind", selection: $kind,
                                      options: [(nil, String(localized: "Any"))] + RecordedActivity.Kind.allCases.map { (Optional($0), $0.name) })
                            .frame(minHeight: 52)
                    }
                }
                .foregroundStyle(Theme.ink)
                .padding(20)
            }
            .background(NagisenBackdrop())
            .nagisenSheetBar(String(localized: "Add a goal"), onClose: { dismiss() }, actionTitle: String(localized: "Save"),
                             actionEnabled: (Double(target.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0) {
                if let value = Double(target.replacingOccurrences(of: ",", with: ".")), value > 0 {
                    store.activityGoals.append(ActivityGoal(measure: measure, period: period, target: value, kind: kind))
                }
                dismiss()
            }
        }
    }
}

struct TrainingLoadSection: View {
    @EnvironmentObject private var store: NutritionStore

    var body: some View {
        let days = TrainingLoad.history(store.workouts, days: 90)
        NagisenSection("Fitness and fatigue") {
            VStack(alignment: .leading, spacing: 10) {
                if let today = days.last { Text(TrainingLoad.formText(today)).font(.subheadline) }
                Chart {
                    ForEach(days, id: \.date) { day in
                        LineMark(x: .value("day", day.date), y: .value("load", day.fitness), series: .value("line", "Fitness"))
                            .foregroundStyle(Theme.accent)
                        LineMark(x: .value("day", day.date), y: .value("load", day.fatigue), series: .value("line", "Fatigue"))
                            .foregroundStyle(Theme.ink.opacity(0.35))
                    }
                }
                .chartForegroundStyleScale(["Fitness": Theme.accent, "Fatigue": Theme.ink.opacity(0.35)])
                .chartLegend(position: .bottom)
                .frame(height: 150)
                Text("Every logged workout counts: minutes times how hard that kind of work is. Fitness follows the last six weeks, fatigue the last week.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 12)
        }
    }
}

/// Every route ever recorded, on one dark map.
struct HeatmapView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Map(initialPosition: .automatic) {
                ForEach(store.activities) { activity in
                    ForEach(Array(segments(activity.points).enumerated()), id: \.offset) { _, line in
                        MapPolyline(coordinates: line).stroke(Theme.accent.opacity(0.35), lineWidth: 3)
                    }
                }
            }
            .mapStyle(darkMap)
            .ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .medium))
                    .frame(width: 44, height: 44)
                    .nagisenGlass(in: Circle(), tint: Theme.surface.opacity(0.3))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.ink)
            .accessibilityLabel(String(localized: "Back"))
            .padding(16)
        }
        .overlay(alignment: .bottom) {
            Text("\(store.activities.count) activities · \((store.activities.reduce(0) { $0 + $1.distance } / 1000).formatted(.number.precision(.fractionLength(0)))) km")
                .font(.subheadline).foregroundStyle(Theme.ink)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .nagisenGlass(in: Capsule(), tint: Theme.surface.opacity(0.3))
                .padding(.bottom, 30)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
