import SwiftUI
import UIKit
import UserNotifications

/// Ember: a one-thumb game that fills exactly one rest between sets. Slide the ember through the
/// gaps in the falling lines and catch the motes. A hit never ends it; it only breaks the streak.
/// Positions are fractions of the screen (x 0…1 left to right, y 0…1 top to bottom).
struct EmberGame {
    static let restSeconds: Double = 180
    static let emberY = 0.78
    static let emberRadius = 0.022

    struct Veil { var y: Double; var gapCenter: Double; var gapWidth: Double; var resolved = false }
    struct Mote { var x: Double; var y: Double }

    private(set) var elapsed: Double = 0
    private(set) var veils: [Veil] = []
    private(set) var motes: [Mote] = []
    private(set) var score = 0
    private(set) var streak = 0
    private(set) var bestStreak = 0
    /// Seconds left of the dimmed glow after a hit.
    private(set) var hurt: Double = 0
    var x = 0.5

    private var untilVeil = 0.6
    private var untilMote = 1.8
    private var random: SeededRandom

    init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        random = SeededRandom(seed: seed)
    }

    var remaining: Double { max(0, Self.restSeconds - elapsed) }
    var isOver: Bool { elapsed >= Self.restSeconds }
    /// 0 at the start, 1 at the end: the lines fall faster and the gaps narrow as rest goes on.
    private var pace: Double { min(elapsed / Self.restSeconds, 1) }

    mutating func step(_ dt: Double) {
        guard !isOver, dt > 0 else { return }
        let dt = min(dt, 0.05)
        elapsed += dt
        hurt = max(0, hurt - dt)
        let speed = 0.24 + 0.2 * pace

        untilVeil -= dt
        if untilVeil <= 0 {
            let width = 0.30 - 0.1 * pace
            veils.append(Veil(y: -0.02, gapCenter: random.next(in: width / 2 + 0.04...(1 - width / 2 - 0.04)), gapWidth: width))
            untilVeil = 1.7 - 0.7 * pace
        }
        untilMote -= dt
        if untilMote <= 0 {
            motes.append(Mote(x: random.next(in: 0.08...0.92), y: -0.02))
            untilMote = random.next(in: 1.6...3.2)
        }

        for index in veils.indices {
            let before = veils[index].y
            veils[index].y += speed * dt
            guard !veils[index].resolved, before < Self.emberY, veils[index].y >= Self.emberY else { continue }
            veils[index].resolved = true
            let half = veils[index].gapWidth / 2 - Self.emberRadius
            if abs(x - veils[index].gapCenter) <= half {
                streak += 1
                bestStreak = max(bestStreak, streak)
                score += 1 + streak / 5
            } else {
                streak = 0
                hurt = 0.6
            }
        }
        veils.removeAll { $0.y > 1.05 }

        for index in motes.indices { motes[index].y += speed * 0.8 * dt }
        let before = motes.count
        motes.removeAll { abs($0.x - x) < 0.06 && abs($0.y - Self.emberY) < 0.05 }
        score += (before - motes.count) * 2
        motes.removeAll { $0.y > 1.05 }
    }
}

/// A small deterministic generator, so a seeded game plays the same way in tests.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
    mutating func next(in range: ClosedRange<Double>) -> Double {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return range.lowerBound + Double(state % 1_000_000) / 1_000_000 * (range.upperBound - range.lowerBound)
    }
}

/// Holds the running game outside SwiftUI's diffing; the timeline redraws it every frame.
private final class EmberRun {
    var game = EmberGame()
    let started = Date.now
    var lastFrame = Date.now

    func advance(to now: Date) {
        // Rest is real time: if the phone sleeps, the clock keeps going and the game skips ahead.
        let target = now.timeIntervalSince(started)
        game.step(now.timeIntervalSince(lastFrame))
        if target - game.elapsed > 0.5 { while game.elapsed < target && !game.isOver { game.step(0.05) } }
        lastFrame = now
    }
}

struct RestGameView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("nagisen.rest.best") private var best = 0
    @State private var run = EmberRun()
    @State private var finished = false
    @State private var dragStartX: Double?

    private static let notificationID = "nagisen.rest.over"

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            TimelineView(.animation(paused: finished)) { context in
                let _ = run.advance(to: context.date)
                let game = run.game
                ZStack {
                    Canvas { canvas, _ in draw(game, in: canvas, size: size) }
                    hud(game)
                    if finished { endCard(game) }
                }
                .onChange(of: game.isOver) { _, over in if over { finish(game) } }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStartX == nil { dragStartX = run.game.x }
                    run.game.x = min(max((dragStartX ?? 0.5) + value.translation.width / max(size.width, 1) * 1.15, 0.03), 0.97)
                }
                .onEnded { _ in dragStartX = nil })
        }
        .background(Color(red: 0.035, green: 0.03, blue: 0.035).ignoresSafeArea())
        .statusBarHidden()
        .onAppear(perform: scheduleReminder)
        .onDisappear { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID]) }
        .accessibilityElement(children: .contain)
    }

    private func draw(_ game: EmberGame, in canvas: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        for veil in game.veils {
            let y = veil.y * h
            let left = (veil.gapCenter - veil.gapWidth / 2) * w
            let right = (veil.gapCenter + veil.gapWidth / 2) * w
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: left, y: y))
            path.move(to: CGPoint(x: right, y: y)); path.addLine(to: CGPoint(x: w, y: y))
            canvas.stroke(path, with: .color(Theme.ink.opacity(veil.resolved ? 0.12 : 0.42)), lineWidth: 1)
        }
        for mote in game.motes {
            let point = CGPoint(x: mote.x * w, y: mote.y * h)
            canvas.fill(Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)),
                        with: .color(Theme.ink.opacity(0.75)))
        }
        let center = CGPoint(x: game.x * w, y: EmberGame.emberY * h)
        let glow = game.hurt > 0 ? 0.15 : 0.35
        let radius = EmberGame.emberRadius * w
        canvas.fill(Path(ellipseIn: CGRect(x: center.x - radius * 3, y: center.y - radius * 3, width: radius * 6, height: radius * 6)),
                    with: .radialGradient(Gradient(colors: [Theme.accent.opacity(glow), .clear]), center: center,
                                          startRadius: 0, endRadius: radius * 3))
        canvas.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(game.hurt > 0 ? Theme.accent.opacity(0.45) : Theme.accent))
    }

    private func hud(_ game: EmberGame) -> some View {
        VStack(spacing: 0) {
            GeometryReader { bar in
                Rectangle().fill(Theme.accent)
                    .frame(width: bar.size.width * game.remaining / EmberGame.restSeconds, height: 2)
            }
            .frame(height: 2)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("REST").font(.caption2.weight(.semibold)).nagisenTracking(2).foregroundStyle(Theme.muted)
                    Text(Duration.seconds(game.remaining.rounded(.up)).formatted(.time(pattern: .minuteSecond)))
                        .font(.system(size: 34, design: .serif)).monospacedDigit()
                        .accessibilityLabel(String(localized: "Rest left"))
                        .accessibilityValue(Duration.seconds(game.remaining.rounded(.up)).formatted(.units(allowed: [.minutes, .seconds])))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(game.score)").font(.system(size: 34, design: .serif)).monospacedDigit()
                    Text(game.streak > 1 ? String(localized: "\(game.streak) in a row") : String(localized: "Best \(best)"))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, 22).padding(.top, 14)
            Spacer()
            if game.elapsed < 4 && !finished {
                Text("Slide anywhere to guide the ember through the gaps.")
                    .font(.footnote).foregroundStyle(Theme.muted)
                    .transition(.opacity)
            }
            Button("End rest") { dismiss() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .frame(minWidth: 44, minHeight: 44)
                .padding(.bottom, 12)
        }
        .foregroundStyle(Theme.ink)
    }

    private func endCard(_ game: EmberGame) -> some View {
        VStack(spacing: 14) {
            Text("Rest is over").font(.system(size: 34, design: .serif))
            Text("\(game.score) points · \(game.bestStreak) in a row at best")
                .font(.subheadline).foregroundStyle(Theme.muted)
            Button { dismiss() } label: {
                Text("Next set")
                    .font(.body.weight(.semibold))
                    .frame(width: 220, height: 52)
                    .background(Theme.red, in: RoundedRectangle(cornerRadius: 15))
                    .foregroundStyle(.white)
            }
            .padding(.top, 8)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.55))
        .foregroundStyle(Theme.ink)
    }

    private func finish(_ game: EmberGame) {
        guard !finished else { return }
        finished = true
        best = max(best, game.score)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }

    /// If the phone is put down mid-rest, a notification still says when rest is over. Only when
    /// notifications are already allowed: rest is no moment for a permission prompt.
    private func scheduleReminder() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Rest is over")
            content.body = String(localized: "Next set.")
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: EmberGame.restSeconds, repeats: false)
            center.add(UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger))
        }
    }
}

/// The Workouts card that starts a rest.
struct RestGameCard: View {
    @State private var resting = false

    var body: some View {
        Button { resting = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "hourglass")
                    .font(.title3)
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text("REST · 3:00")
                        .font(.caption2.weight(.semibold)).nagisenTracking(1.6)
                        .foregroundStyle(Theme.muted)
                    Text("A small game while your muscles recover")
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
        .fullScreenCover(isPresented: $resting) { RestGameView() }
    }
}
