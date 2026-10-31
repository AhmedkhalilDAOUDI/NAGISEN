import SwiftUI

extension BorderTier {
    /// The ring's colors: quiet materials that sit on the dark backdrop.
    var colors: [Color] {
        switch self {
        case .none: [Theme.line]
        case .washi: [Color(hex: 0xF2EBDF), Color(hex: 0xCFC3B0), Color(hex: 0xF2EBDF)]
        case .copper: [Color(hex: 0xE0A070), Color(hex: 0x8A4B24), Color(hex: 0xC7834F), Color(hex: 0xE0A070)]
        case .silver: [Color(hex: 0xF4F6F7), Color(hex: 0x8F989F), Color(hex: 0xDADFE3), Color(hex: 0xF4F6F7)]
        case .gold: [Color(hex: 0xF5DFA3), Color(hex: 0xA97A3E), Color(hex: 0xE9C77B), Color(hex: 0xF5DFA3)]
        case .jade: [Color(hex: 0x9AD5BC), Color(hex: 0x1F5E4A), Color(hex: 0x4FA285), Color(hex: 0x9AD5BC)]
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
    var size: CGFloat = 36

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheen = false

    private var ringWidth: CGFloat { tier == .none ? 1 : max(2, size * 0.065) }

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
        .padding(ringWidth + (tier == .none ? 0 : 1.5))
        .overlay(ring)
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(tier == .none ? "@\(username)" : "@\(username), \(tier.name) border")
        .onAppear {
            guard tier == .jade, !reduceMotion else { return }
            withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) { sheen = true }
        }
    }

    private var initial: some View {
        Text(String(username.prefix(1)).uppercased())
            .font(.system(size: size * 0.42, design: .serif))
            .foregroundStyle(Theme.muted)
    }

    private var ring: some View {
        Circle()
            .strokeBorder(AngularGradient(colors: tier.colors, center: .center,
                                          angle: .degrees(sheen ? 360 : 0)),
                          lineWidth: ringWidth)
    }
}

/// What other members see when they tap a name: picture, border, username and bio.
struct MemberCardView: View {
    let member: FeedMember
    @EnvironmentObject private var feed: FeedService

    var body: some View {
        VStack(spacing: 14) {
            AvatarView(url: feed.avatarURL(member.avatarPath), username: member.username,
                       tier: member.borderTier, size: 104)
            Text("@\(member.username)")
                .font(.system(size: 25, design: .serif))
            if member.borderTier != .none {
                Text("\(member.borderTier.name.uppercased()) BORDER")
                    .font(.caption2.weight(.semibold)).tracking(2)
                    .foregroundStyle(Theme.muted)
            }
            Text(member.bio.isEmpty ? "No bio yet." : member.bio)
                .font(.subheadline)
                .foregroundStyle(member.bio.isEmpty ? Theme.muted : Theme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.ink)
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(NagisenBackdrop())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
