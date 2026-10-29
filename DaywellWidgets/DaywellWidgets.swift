import SwiftUI
import WidgetKit

private enum Palette {
    static let background = Color(red: 0.12, green: 0.12, blue: 0.13)
    static let surface = Color(red: 0.18, green: 0.18, blue: 0.19)
    static let burgundy = Color(red: 0.54, green: 0.16, blue: 0.28)
    static let rose = Color(red: 0.76, green: 0.38, blue: 0.47)
    static let beige = Color(red: 0.91, green: 0.83, blue: 0.72)
    static let muted = Color(red: 0.67, green: 0.66, blue: 0.67)
}

private struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: DaywellWidgetSnapshot
}

private struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date.now
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
        completion(Timeline(entries: [SnapshotEntry(date: now, snapshot: .load())], policy: .after(next)))
    }
}

private struct Ring: View {
    let fraction: Double
    let color: Color
    let icon: String

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: 11)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if !icon.isEmpty {
                Image(systemName: icon).font(.title2).foregroundStyle(color)
            }
        }
    }
}

private struct WaterWidgetView: View {
    let value: DaywellWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: "drop.fill").foregroundStyle(Palette.rose)
                Spacer()
                Text("水 · WATER").font(.system(size: 10, weight: .bold)).tracking(1.1)
                    .foregroundStyle(Palette.beige)
            }
            Spacer(minLength: 0)
            Text(value.water.formatted())
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.7).lineLimit(1)
            Text("of \(value.waterGoal.formatted()) mL")
                .font(.caption).foregroundStyle(Palette.muted)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.rose.opacity(0.2))
                    Capsule().fill(Palette.rose)
                        .frame(width: geometry.size.width * min(CGFloat(value.water) / CGFloat(max(value.waterGoal, 1)), 1))
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .foregroundStyle(.white)
        .containerBackground(Palette.background, for: .widget)
    }
}

private struct BalanceWidgetView: View {
    let value: DaywellWidgetSnapshot

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 9) {
                Text("NAGISEN · BALANCE")
                    .font(.system(size: 10, weight: .bold)).tracking(1.5)
                    .foregroundStyle(Palette.beige)
                ZStack {
                    Ring(fraction: Double(value.calories) / Double(max(value.calorieGoal, 1)),
                         color: Palette.rose, icon: "")
                    VStack(spacing: 0) {
                        Text(abs(value.calorieGoal - value.calories).formatted())
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text(value.calories <= value.calorieGoal ? "LEFT" : "OVER")
                            .font(.system(size: 9, weight: .bold)).tracking(1)
                    }
                }
                .frame(width: 95, height: 95)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 9) {
                Text("LAST 7 DAYS")
                    .font(.system(size: 10, weight: .bold)).tracking(1)
                    .foregroundStyle(Palette.muted)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(0..<7, id: \.self) { index in
                        let calories = index < value.weekCalories.count ? value.weekCalories[index] : nil
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(calories == nil ? Palette.muted.opacity(0.2) : Palette.burgundy)
                                .frame(maxWidth: .infinity)
                                .frame(height: calories.map { max(8, 68 * CGFloat(min($0, value.calorieGoal)) / CGFloat(max(value.calorieGoal, 1))) } ?? 8)
                            Text(dayLetter(index))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Palette.muted)
                        }
                    }
                }
                .frame(height: 85, alignment: .bottom)
                Text("\(value.calories.formatted()) eaten · \(value.calorieGoal.formatted()) goal")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
        }
        .padding(17)
        .foregroundStyle(.white)
        .containerBackground(Palette.background, for: .widget)
    }

    private func dayLetter(_ index: Int) -> String {
        let day = Calendar.current.date(byAdding: .day, value: index - 6, to: .now) ?? .now
        return day.formatted(.dateTime.weekday(.narrow))
    }
}

private struct MacroWidgetView: View {
    let value: DaywellWidgetSnapshot

    var body: some View {
        let total = max(value.protein + value.carbs + value.fat, 1)
        VStack(alignment: .leading, spacing: 8) {
            Text("NUTRITION")
                .font(.system(size: 10, weight: .bold)).tracking(1.5)
                .foregroundStyle(Palette.beige)
            HStack {
                Spacer()
                ZStack {
                    Circle().stroke(Palette.surface, lineWidth: 14)
                    segment(start: 0, amount: value.protein, total: total, color: Palette.rose)
                    segment(start: value.protein, amount: value.carbs, total: total, color: Palette.beige)
                    segment(start: value.protein + value.carbs, amount: value.fat, total: total, color: Palette.muted)
                }
                .frame(width: 63, height: 63)
                Spacer()
            }
            macro("P", value.protein, Palette.rose)
            macro("C", value.carbs, Palette.beige)
            macro("F", value.fat, Palette.muted)
        }
        .padding(15)
        .foregroundStyle(.white)
        .containerBackground(Palette.background, for: .widget)
    }

    private func segment(start: Int, amount: Int, total: Int, color: Color) -> some View {
        Circle().trim(from: CGFloat(start) / CGFloat(total), to: CGFloat(start + amount) / CGFloat(total))
            .stroke(color, lineWidth: 14).rotationEffect(.degrees(-90))
    }

    private func macro(_ label: String, _ grams: Int, _ color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption2.weight(.bold))
            Spacer()
            Text("\(grams)g").font(.caption.weight(.semibold))
        }
    }
}

private struct ActivityWidgetView: View {
    let value: DaywellWidgetSnapshot

    var body: some View {
        HStack(spacing: 18) {
            Ring(fraction: Double(value.moveCalories ?? 0) / Double(max(value.moveGoalCalories ?? 1, 1)),
                 color: Palette.rose, icon: "figure.run")
                .frame(width: 105, height: 105)
            VStack(alignment: .leading, spacing: 9) {
                Text("MOVEMENT")
                    .font(.system(size: 10, weight: .bold)).tracking(1.5)
                    .foregroundStyle(Palette.beige)
                activity("MOVE", value.moveCalories.map { "\($0) / \(value.moveGoalCalories.map { String($0) } ?? "—") kcal" } ?? "—")
                activity("STEPS", value.steps.map { $0.formatted() } ?? "—")
                activity("DISTANCE", value.distanceKilometers.map { String(format: "%.1f km", $0) } ?? "—")
            }
            Spacer(minLength: 0)
        }
        .padding(17)
        .foregroundStyle(.white)
        .containerBackground(Palette.background, for: .widget)
    }

    private func activity(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.muted)
            Text(value).font(.system(size: 16, weight: .semibold, design: .rounded))
        }
    }
}

private struct WaterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DaywellWater", provider: SnapshotProvider()) { WaterWidgetView(value: $0.snapshot) }
            .configurationDisplayName("NAGISEN Water")
            .description("Today's water against your target.")
            .supportedFamilies([.systemSmall])
    }
}

private struct BalanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DaywellBalance", provider: SnapshotProvider()) { BalanceWidgetView(value: $0.snapshot) }
            .configurationDisplayName("NAGISEN Balance")
            .description("Calories and the last seven logged days.")
            .supportedFamilies([.systemMedium])
    }
}

private struct MacroWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DaywellMacros", provider: SnapshotProvider()) { MacroWidgetView(value: $0.snapshot) }
            .configurationDisplayName("NAGISEN Nutrition")
            .description("Your logged protein, carbs, and fat.")
            .supportedFamilies([.systemSmall])
    }
}

private struct ActivityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DaywellActivity", provider: SnapshotProvider()) { ActivityWidgetView(value: $0.snapshot) }
            .configurationDisplayName("NAGISEN Movement")
            .description("Move calories, steps, and distance from Apple Health.")
            .supportedFamilies([.systemMedium])
    }
}

@main
struct DaywellWidgets: WidgetBundle {
    var body: some Widget {
        BalanceWidget()
        WaterWidget()
        MacroWidget()
        ActivityWidget()
    }
}
