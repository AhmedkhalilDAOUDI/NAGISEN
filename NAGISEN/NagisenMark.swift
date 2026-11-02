import SwiftUI

/// The NAGISEN mark: a burgundy sun over two horizon lines. `breath` (0…1) lifts and brightens the sun.
struct NagisenMark: View {
    var breath: Double = 0.5
    var ink: Color
    var accent: Color

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width, h = geometry.size.height
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [accent.opacity(0.35 + 0.25 * breath), .clear], center: .center,
                                         startRadius: 0, endRadius: w * 0.45))
                    .frame(width: w * 0.95, height: w * 0.95)
                    .position(x: w / 2, y: h * (0.44 - 0.04 * breath))
                Circle()
                    .fill(accent)
                    .frame(width: w * (0.36 + 0.04 * breath), height: w * (0.36 + 0.04 * breath))
                    .position(x: w / 2, y: h * (0.44 - 0.04 * breath))
                Capsule().fill(ink.opacity(0.85)).frame(width: w * 0.8, height: max(1.5, h * 0.05)).position(x: w / 2, y: h * 0.74)
                Capsule().fill(ink.opacity(0.45)).frame(width: w * 0.5, height: max(1.5, h * 0.05)).position(x: w / 2, y: h * 0.86)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
