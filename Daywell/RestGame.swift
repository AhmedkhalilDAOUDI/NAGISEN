import SwiftUI
import UserNotifications

/// Four small games, each filling exactly one rest between sets. Every game scores "higher is
/// better" so the shared rest screen can keep one best score per game.
enum RestGame: String, CaseIterable, Identifiable {
    case memory, odd, reaction, words

    static let restSeconds: Double = 180
    var id: String { rawValue }

    var name: String {
        switch self {
        case .memory: String(localized: "Memory grid")
        case .odd: String(localized: "Odd one out")
        case .reaction: String(localized: "Reaction")
        case .words: String(localized: "Unscramble")
        }
    }

    var symbol: String {
        switch self {
        case .memory: "square.grid.3x3"
        case .odd: "circle.grid.3x3"
        case .reaction: "bolt"
        case .words: "textformat.abc"
        }
    }
}

/// A small deterministic generator, so a seeded game plays the same way in tests.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
    mutating func int(_ range: ClosedRange<Int>) -> Int {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return range.lowerBound + Int(state % UInt64(range.count))
    }
    mutating func double(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + Double(int(0...999_999)) / 999_999 * (range.upperBound - range.lowerBound)
    }
}

// MARK: - Game rules

/// Tiles light up together; tap them all. Clearing a round adds a tile, a wrong tap removes one.
struct MemoryGame {
    static let tiles = 16
    enum Tap: Equatable { case hit, miss, cleared(points: Int) }

    private(set) var length = 3
    private(set) var pattern: Set<Int> = []
    private(set) var found: Set<Int> = []
    private var random: SeededRandom

    init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        random = SeededRandom(seed: seed)
        newRound()
    }

    mutating func newRound() {
        var picked = Set<Int>()
        while picked.count < length { picked.insert(random.int(0...Self.tiles - 1)) }
        pattern = picked
        found = []
    }

    mutating func tap(_ tile: Int) -> Tap {
        guard pattern.contains(tile) else {
            length = max(3, length - 1)
            return .miss
        }
        found.insert(tile)
        guard found == pattern else { return .hit }
        let points = pattern.count
        length = min(length + 1, 12)
        return .cleared(points: points)
    }
}

/// One circle in the grid is a slightly different shade. Each find makes the grid bigger and the
/// difference subtler; a wrong tap steps back one level.
struct OddOneOutGame {
    private(set) var level = 0
    private(set) var odd = 0
    /// Brightness of the ordinary circles; the odd one is lighter by `difference`.
    private(set) var brightness = 0.5
    private var random: SeededRandom

    init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        random = SeededRandom(seed: seed)
        next()
    }

    var side: Int { min(2 + level / 3, 6) }
    var difference: Double { max(0.035, 0.26 * pow(0.88, Double(level))) }

    mutating func next() {
        brightness = random.double(0.32...0.58)
        odd = random.int(0...side * side - 1)
    }

    /// Returns the points earned, or nil for a wrong circle.
    mutating func tap(_ index: Int) -> Int? {
        guard index == odd else {
            level = max(0, level - 1)
            next()
            return nil
        }
        let points = 1 + level / 5
        level += 1
        next()
        return points
    }
}

/// Points for one reaction: quicker taps earn more.
enum ReactionScoring {
    static func points(milliseconds: Int) -> Int {
        switch milliseconds {
        case ..<250: 4
        case ..<320: 3
        case ..<420: 2
        default: 1
        }
    }
}

/// Short words with their letters shuffled; tap the letters back into order.
struct WordGame {
    static let words: [String] = [
        "CALM", "GRIT", "CORE", "MINT", "SAGE", "MOON", "PEAR", "TIDE", "WAVE", "FERN", "DUSK", "DAWN", "IRON", "PACE",
        "STEEL", "STONE", "RIVER", "OCEAN", "TIGER", "PULSE", "FOCUS", "SWEAT", "FLAME", "NIGHT", "LIGHT", "SQUAT",
        "PLANK", "LUNGE", "PRESS", "STORM", "CLOUD", "CORAL", "ORBIT", "PEARL", "QUIET", "RAVEN", "TEMPO", "POWER",
        "SPEED", "OLIVE", "LEMON", "HONEY", "BASIL", "CEDAR", "AMBER", "SHORE", "TRAIL", "CLIMB", "STEADY", "STRIDE",
        "SPRINT", "SHADOW", "SILENT", "FOREST", "DESERT", "ANCHOR", "BRIDGE", "CANDLE", "FALCON", "GARDEN", "HARBOR",
        "ISLAND", "MARBLE", "MEADOW", "PILLAR", "SUMMIT", "VELVET", "WINTER", "ZENITH", "GINGER", "REPEAT", "BREATH",
        "BALANCE", "STAMINA", "RECOVER", "LANTERN", "THUNDER", "HORIZON", "MORNING", "CRYSTAL",
    ]
    private static let known = Set(words)

    enum Pick: Equatable { case partial, solved(points: Int), wrong }

    private(set) var word = ""
    private(set) var letters: [Character] = []
    private(set) var picked: [Int] = []
    private var random: SeededRandom

    init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        random = SeededRandom(seed: seed)
        next()
    }

    var typed: String { String(picked.map { letters[$0] }) }

    mutating func next() {
        word = Self.words[random.int(0...Self.words.count - 1)]
        var shuffled = Array(word)
        repeat {
            for index in shuffled.indices.reversed() { shuffled.swapAt(index, random.int(0...index)) }
        } while String(shuffled) == word
        letters = shuffled
        picked = []
    }

    mutating func pick(_ index: Int) -> Pick {
        guard letters.indices.contains(index), !picked.contains(index) else { return .partial }
        picked.append(index)
        guard picked.count == letters.count else { return .partial }
        // Another real word from the same letters (STEEL/SLEET-style) counts too.
        guard typed == word || Self.known.contains(typed) else { picked = []; return .wrong }
        let points = word.count
        next()
        return .solved(points: points)
    }

    mutating func undo() { _ = picked.popLast() }
}

// MARK: - Rest screen

struct RestView: View {
    let game: RestGame
    @Environment(\.dismiss) private var dismiss
    @AppStorage private var best: Int
    @State private var started = Date.now
    @State private var score = 0
    @State private var finished = false

    private static let notificationID = "nagisen.rest.over"

    init(game: RestGame) {
        self.game = game
        _best = AppStorage(wrappedValue: 0, "nagisen.rest.best.\(game.rawValue)")
    }

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: started, by: 0.25)) { context in
                let remaining = max(0, RestGame.restSeconds - context.date.timeIntervalSince(started))
                header(remaining: remaining)
                    .onChange(of: remaining == 0) { _, over in if over { finish() } }
            }
            Group {
                switch game {
                case .memory: MemoryGridView(score: $score, active: !finished)
                case .odd: OddOneOutView(score: $score, active: !finished)
                case .reaction: ReactionView(score: $score, active: !finished)
                case .words: UnscrambleView(score: $score, active: !finished)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 22)
            Button("End rest") { dismiss() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .frame(minWidth: 44, minHeight: 44)
                .padding(.bottom, 8)
        }
        .foregroundStyle(Theme.ink)
        .background(Color(red: 0.035, green: 0.03, blue: 0.035).ignoresSafeArea())
        .overlay { if finished { endCard } }
        .sensoryFeedback(.success, trigger: finished)
        .onAppear(perform: scheduleReminder)
        .onDisappear { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID]) }
    }

    private func header(remaining: Double) -> some View {
        VStack(spacing: 0) {
            GeometryReader { bar in
                Rectangle().fill(Theme.accent).frame(width: bar.size.width * remaining / RestGame.restSeconds, height: 2)
            }
            .frame(height: 2)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("REST · \(game.name)".uppercased()).font(.caption2.weight(.semibold)).nagisenTracking(2).foregroundStyle(Theme.muted)
                    Text(Duration.seconds(remaining.rounded(.up)).formatted(.time(pattern: .minuteSecond)))
                        .font(.system(size: 34, design: .serif)).monospacedDigit()
                        .accessibilityLabel(String(localized: "Rest left"))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(score)").font(.system(size: 34, design: .serif)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text("Best \(best)").font(.caption).foregroundStyle(Theme.muted)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, 22).padding(.top, 14)
        }
    }

    private var endCard: some View {
        VStack(spacing: 14) {
            Text("Rest is over").font(.system(size: 34, design: .serif))
            Text(score > 0 && score >= best ? String(localized: "\(score) points · a new best") : String(localized: "\(score) points"))
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.7).ignoresSafeArea())
        .foregroundStyle(Theme.ink)
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        best = max(best, score)
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
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: RestGame.restSeconds, repeats: false)
            center.add(UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger))
        }
    }
}

// MARK: - Games

private struct MemoryGridView: View {
    @Binding var score: Int
    let active: Bool
    @State private var game = MemoryGame()
    @State private var showing = true
    @State private var missed: Int?
    @State private var round = 0

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text(showing ? String(localized: "Remember \(game.length) tiles") : String(localized: "Tap them"))
                .font(.system(size: 22, design: .serif))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(0..<MemoryGame.tiles, id: \.self) { tile in
                    let lit = (showing && game.pattern.contains(tile)) || game.found.contains(tile)
                    RoundedRectangle(cornerRadius: 12)
                        .fill(missed == tile ? Theme.ink.opacity(0.35) : lit ? Theme.accent : Theme.ink.opacity(0.07))
                        .aspectRatio(1, contentMode: .fit)
                        .onTapGesture { tap(tile) }
                        .accessibilityLabel(String(localized: "Tile \(tile + 1)"))
                        .accessibilityAddTraits(.isButton)
                }
            }
            .animation(.easeOut(duration: 0.15), value: game.found)
            Spacer()
        }
        .task(id: round) {
            showing = true
            missed = nil
            try? await Task.sleep(for: .seconds(1.0 + 0.15 * Double(game.length)))
            showing = false
        }
    }

    private func tap(_ tile: Int) {
        guard active, !showing, missed == nil else { return }
        switch game.tap(tile) {
        case .hit: break
        case .cleared(let points):
            score += points
            Task { try? await Task.sleep(for: .seconds(0.4)); game.newRound(); round += 1 }
        case .miss:
            missed = tile
            Task { try? await Task.sleep(for: .seconds(0.6)); game.newRound(); round += 1 }
        }
    }
}

private struct OddOneOutView: View {
    @Binding var score: Int
    let active: Bool
    @State private var game = OddOneOutGame()
    @State private var wrong = 0

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Text("Find the different shade").font(.system(size: 22, design: .serif))
            let side = game.side
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: side), spacing: 10) {
                ForEach(0..<side * side, id: \.self) { index in
                    Circle()
                        .fill(Color(hue: 0.95, saturation: 0.62,
                                    brightness: game.brightness + (index == game.odd ? game.difference : 0)))
                        .aspectRatio(1, contentMode: .fit)
                        .onTapGesture { tap(index) }
                        .accessibilityLabel(String(localized: "Circle \(index + 1)"))
                        .accessibilityAddTraits(.isButton)
                }
            }
            .id("\(game.level)-\(game.odd)")
            .phaseAnimator([0, 12, -12, 0], trigger: wrong) { view, offset in view.offset(x: offset) }
            Text("Level \(game.level + 1)").font(.subheadline).foregroundStyle(Theme.muted)
            Spacer()
        }
    }

    private func tap(_ index: Int) {
        guard active else { return }
        if let points = game.tap(index) { score += points } else { wrong += 1 }
    }
}

private struct ReactionView: View {
    @Binding var score: Int
    let active: Bool
    private enum Phase: Equatable { case waiting, go(Date), early, result(Int) }
    @State private var phase = Phase.waiting
    @State private var round = 0
    @State private var times: [Int] = []

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Circle()
                .fill(isGo ? Theme.accent : Theme.ink.opacity(0.08))
                .frame(width: 220, height: 220)
                .overlay(Text(label).font(.system(size: 26, design: .serif)).multilineTextAlignment(.center).padding(30))
            Text(times.isEmpty ? String(localized: "Tap the moment it turns red.")
                 : String(localized: "Average \(times.reduce(0, +) / times.count) ms · best \(times.min() ?? 0) ms"))
                .font(.subheadline).foregroundStyle(Theme.muted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .accessibilityAddTraits(.isButton)
        .task(id: round) {
            phase = .waiting
            try? await Task.sleep(for: .seconds(Double.random(in: 1.3...3.8)))
            if !Task.isCancelled, phase == .waiting { phase = .go(.now) }
        }
    }

    private var isGo: Bool { if case .go = phase { true } else { false } }

    private var label: String {
        switch phase {
        case .waiting: String(localized: "Wait…")
        case .go: String(localized: "Now")
        case .early: String(localized: "Too soon")
        case .result(let ms): "\(ms) ms"
        }
    }

    private func tap() {
        guard active else { return }
        switch phase {
        case .waiting:
            phase = .early
            restart(after: 0.8)
        case .go(let shown):
            let ms = Int(Date.now.timeIntervalSince(shown) * 1000)
            times.append(ms)
            score += ReactionScoring.points(milliseconds: ms)
            phase = .result(ms)
            restart(after: 0.9)
        case .early, .result:
            break
        }
    }

    private func restart(after seconds: Double) {
        Task { try? await Task.sleep(for: .seconds(seconds)); round += 1 }
    }
}

private struct UnscrambleView: View {
    @Binding var score: Int
    let active: Bool
    @State private var game = WordGame()
    @State private var wrong = 0

    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            HStack(spacing: 8) {
                ForEach(0..<game.letters.count, id: \.self) { slot in
                    let typed = Array(game.typed)
                    Text(slot < typed.count ? String(typed[slot]) : " ")
                        .font(.system(size: 26, design: .serif))
                        .frame(width: 38, height: 48)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.muted).frame(height: 1) }
                }
            }
            .phaseAnimator([0, 12, -12, 0], trigger: wrong) { view, offset in view.offset(x: offset) }
            .onTapGesture { if active { game.undo() } }
            .accessibilityLabel(game.typed.isEmpty ? String(localized: "Nothing typed") : game.typed)
            .accessibilityHint(String(localized: "Tap to remove the last letter"))
            HStack(spacing: 8) {
                ForEach(Array(game.letters.enumerated()), id: \.offset) { index, letter in
                    let used = game.picked.contains(index)
                    Button { pick(index) } label: {
                        Text(String(letter)).font(.system(size: 24, weight: .medium, design: .rounded))
                            .frame(width: 44, height: 52)
                            .background(Theme.ink.opacity(used ? 0.02 : 0.09), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(used ? Theme.muted.opacity(0.4) : Theme.ink)
                    }
                    .buttonStyle(.plain)
                    .disabled(used)
                }
            }
            Button(String(localized: "Skip")) { if active { game.next() } }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .frame(minHeight: 44)
            Spacer()
        }
    }

    private func pick(_ index: Int) {
        guard active else { return }
        switch game.pick(index) {
        case .partial: break
        case .solved(let points): score += points
        case .wrong: wrong += 1
        }
    }
}

// MARK: - Entry

/// The Workouts card: pick a game and rest for three minutes.
struct RestGameCard: View {
    @State private var playing: RestGame?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "hourglass").foregroundStyle(Theme.accentText)
                Text("REST · 3:00")
                    .font(.caption2.weight(.semibold)).nagisenTracking(1.6)
                    .foregroundStyle(Theme.muted)
            }
            Text("Something small while your muscles recover")
                .font(.system(size: 19, design: .serif))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach(RestGame.allCases) { game in
                    Button { playing = game } label: {
                        Label(game.name, systemImage: game.symbol)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.16), lineWidth: 0.5))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .softCardStyle()
        .fullScreenCover(item: $playing) { RestView(game: $0) }
    }
}
