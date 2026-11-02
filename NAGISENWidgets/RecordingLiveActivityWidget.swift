import ActivityKit
import SwiftUI
import WidgetKit

/// The recording on the Lock Screen and in the Dynamic Island: time, distance, pace.
struct RecordingLiveActivityWidget: Widget {
    private static let wine = Color(red: 0x8B / 255, green: 0x2B / 255, blue: 0x49 / 255)
    private static let ink = Color(red: 0xEC / 255, green: 0xE6 / 255, blue: 0xDA / 255)
    private static let muted = Color(red: 0x8A / 255, green: 0x85 / 255, blue: 0x7E / 255)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingAttributes.self) { context in
            HStack(alignment: .center, spacing: 14) {
                floatingMark(context.state, size: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.kindName.uppercased())
                        .font(.caption2.weight(.semibold)).foregroundStyle(Self.muted)
                    time(context.state).font(.system(size: 32, design: .serif)).monospacedDigit()
                }
                Spacer()
                stat(context.state.kilometres.formatted(.number.precision(.fractionLength(2))), "km")
                stat(context.state.pace, context.state.pausedSeconds == nil ? "" : String(localized: "paused"))
            }
            .foregroundStyle(Self.ink)
            .padding(18)
            .activityBackgroundTint(Color(red: 0.035, green: 0.03, blue: 0.035))
            .activitySystemActionForegroundColor(Self.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    time(context.state).font(.system(size: 24, design: .serif)).monospacedDigit().foregroundStyle(Self.ink)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.kilometres.formatted(.number.precision(.fractionLength(2)))) km")
                        .font(.system(size: 24, design: .serif)).monospacedDigit().foregroundStyle(Self.ink)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.pausedSeconds == nil ? context.state.pace : String(localized: "Paused"))
                        .font(.caption).foregroundStyle(Self.muted)
                }
            } compactLeading: {
                floatingMark(context.state, size: 22)
            } compactTrailing: {
                Text(context.state.kilometres.formatted(.number.precision(.fractionLength(1))))
                    .monospacedDigit().foregroundStyle(Self.ink)
            } minimal: {
                floatingMark(context.state, size: 20)
            }
        }
    }

    /// The NAGISEN sun drifting up and down between updates, glowing a little brighter at the top.
    private func floatingMark(_ state: RecordingAttributes.ContentState, size: CGFloat) -> some View {
        let up = state.frame % 2 == 0 && state.pausedSeconds == nil
        return NagisenMark(breath: up ? 1 : 0.2, ink: Self.ink, accent: Self.wine)
            .frame(width: size, height: size)
            .offset(y: up ? -size * 0.22 : size * 0.22)
            .animation(.easeInOut(duration: 2.2), value: state.frame)
    }

    @ViewBuilder
    private func time(_ state: RecordingAttributes.ContentState) -> some View {
        if let paused = state.pausedSeconds {
            let total = Int(paused)
            Text(total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
                 : String(format: "%d:%02d", total / 60, total % 60))
        } else {
            Text(timerInterval: state.timerStart...Date.distantFuture, countsDown: false)
        }
    }

    private func stat(_ value: String, _ unit: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value).font(.system(size: 22, design: .serif)).monospacedDigit()
            Text(unit).font(.caption2).foregroundStyle(Self.muted)
        }
    }
}
