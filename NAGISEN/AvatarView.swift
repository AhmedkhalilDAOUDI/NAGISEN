import SwiftUI

extension BorderTier {
    /// The ring's colors: quiet materials that sit on the dark backdrop.
    var colors: [Color] {
        switch self {
        case .none: [Theme.line]
        case .washi: [Color(hex: 0xF2EBDF), Color(hex: 0xCFC3B0), Color(hex: 0xF2EBDF)]
        case .hinoki: [Color(hex: 0xE8D1A8), Color(hex: 0x9C7650), Color(hex: 0xD2B385), Color(hex: 0xE8D1A8)]
        case .copper: [Color(hex: 0xE0A070), Color(hex: 0x8A4B24), Color(hex: 0xC7834F), Color(hex: 0xE0A070)]
        case .bronze: [Color(hex: 0xD6A665), Color(hex: 0x6F4A24), Color(hex: 0xB08045), Color(hex: 0xD6A665)]
        case .silver: [Color(hex: 0xF4F6F7), Color(hex: 0x8F989F), Color(hex: 0xDADFE3), Color(hex: 0xF4F6F7)]
        case .gold: [Color(hex: 0xF5DFA3), Color(hex: 0xA97A3E), Color(hex: 0xE9C77B), Color(hex: 0xF5DFA3)]
        case .sakura: [Color(hex: 0xF9E6EA), Color(hex: 0xC98A98), Color(hex: 0xF0C6CF), Color(hex: 0xF9E6EA)]
        case .indigo: [Color(hex: 0x8FA3D6), Color(hex: 0x223666), Color(hex: 0x4C64A3), Color(hex: 0x8FA3D6)]
        case .jade: [Color(hex: 0x9AD5BC), Color(hex: 0x1F5E4A), Color(hex: 0x4FA285), Color(hex: 0x9AD5BC)]
        case .sumi: [Color(hex: 0x8A8A92), Color(hex: 0x111113), Color(hex: 0x4A4A50), Color(hex: 0x8A8A92)]
        case .kintsugi: [Color(hex: 0x17171A), Color(hex: 0xE2BC66), Color(hex: 0x17171A), Color(hex: 0xF5DC92), Color(hex: 0x17171A)]
        }
    }
}

extension SpecialBorder {
    /// Deep burgundy lacquer, darkening and catching light as it turns.
    var colors: [Color] {
        switch self {
        case .enji: [Color(hex: 0x8B2B49), Color(hex: 0x3A0C18), Color(hex: 0x6E1B33),
                     Color(hex: 0xB04A66), Color(hex: 0x3A0C18), Color(hex: 0x8B2B49)]
        }
    }

    /// The fine gold line just inside the ring, like the gilded edge of lacquerware.
    var innerLine: Color { Color(hex: 0xD9B36A) }

    /// The red of the name, light enough to read on the dark paper.
    var nameColor: Color { Color(hex: 0xB04A66) }

    /// For a name inside a sentence, where it can't animate.
    var nameStyle: LinearGradient {
        LinearGradient(colors: [nameColor, innerLine, nameColor], startPoint: .leading, endPoint: .trailing)
    }
}

/// A name inside a sentence (Text + Text): tinted, not animated, for a special border.
func nameText(_ name: String, _ special: SpecialBorder?) -> Text {
    special.map { Text(name).foregroundStyle($0.nameStyle) } ?? Text(name)
}

extension View {
    /// Writes a member's name: plain for most, glowing lacquer with a gold sheen for a special border.
    func memberName(_ special: SpecialBorder?) -> some View { modifier(MemberNameStyle(special: special)) }
}

private struct MemberNameStyle: ViewModifier {
    let special: SpecialBorder?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if let special {
            TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
                // Gold sweeps left to right over 2.2 s, then rests off the edge until the 3.5 s cycle ends.
                let x = reduceMotion ? 0.5
                    : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.5) / 2.2 * 2.4 - 0.7
                content
                    .foregroundStyle(LinearGradient(stops: [.init(color: special.nameColor, location: 0),
                                                            .init(color: special.innerLine, location: 0.5),
                                                            .init(color: special.nameColor, location: 1)],
                                                    startPoint: UnitPoint(x: x - 0.35, y: 0.5),
                                                    endPoint: UnitPoint(x: x + 0.35, y: 0.5)))
                    .shadow(color: special.nameColor.opacity(0.75), radius: 5)
            }
        } else {
            content
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// A member's picture (or initial) inside the border they have earned.
struct AvatarView: View {
    let url: URL?
    let username: String
    let tier: BorderTier
    var special: SpecialBorder? = nil
    var size: CGFloat = 36

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheen = false

    private var hasRing: Bool { special != nil || tier != .none }
    private var ringWidth: CGFloat { hasRing ? max(2, size * (special == nil ? 0.065 : 0.085)) : 1 }

    var body: some View {
        ZStack {
            Circle().fill(Theme.surface)
            if let url {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        initial
                    }
                }
            } else {
                initial
            }
        }
        .clipShape(Circle())
        .padding(ringWidth + (hasRing ? 1.5 : 0))
        .overlay(ring)
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(special.map { "@\(username), \($0.name) border" } ??
                            (tier == .none ? "@\(username)" : "@\(username), \(tier.name) border"))
        .onAppear {
            guard special != nil || tier.shimmers, !reduceMotion else { return }
            withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) { sheen = true }
        }
    }

    private var initial: some View {
        Text(String(username.prefix(1)).uppercased())
            .font(.system(size: size * 0.42, design: .serif))
            .foregroundStyle(Theme.muted)
    }

    @ViewBuilder
    private var ring: some View {
        if let special {
            ZStack {
                Circle()
                    .strokeBorder(AngularGradient(colors: special.colors, center: .center,
                                                  angle: .degrees(sheen ? 360 : 0)),
                                  lineWidth: ringWidth)
                Circle()
                    .strokeBorder(special.innerLine.opacity(0.85), lineWidth: max(0.75, size * 0.012))
                    .padding(ringWidth)
            }
        } else {
            Circle()
                .strokeBorder(AngularGradient(colors: tier.colors, center: .center,
                                              angle: .degrees(sheen ? 360 : 0)),
                              lineWidth: ringWidth)
        }
    }
}
