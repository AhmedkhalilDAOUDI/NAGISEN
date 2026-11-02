import SwiftUI

/// A line figure in motion, drawn for one moment of its stride. `phase` runs 0…2π per stride.
/// Shared by the recording screen (animated smoothly) and the Lock Screen (one pose per update).
struct MoveFigure: View {
    enum Motion { case run, walk, ride, hike }

    var motion: Motion
    var phase: Double
    var ink: Color
    var accent: Color

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 100
            func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * unit + (size.width - 100 * unit) / 2, y: y * unit) }
            let line = StrokeStyle(lineWidth: 5 * unit, lineCap: .round, lineJoin: .round)
            func limb(_ points: [CGPoint], _ color: Color) {
                var path = Path(); path.addLines(points)
                context.stroke(path, with: .color(color), style: line)
            }
            func joint(from origin: CGPoint, length: Double, angle: Double) -> CGPoint {
                CGPoint(x: origin.x + sin(angle) * length * unit, y: origin.y + cos(angle) * length * unit)
            }

            if motion == .ride {
                // Wheels, frame, and a rider whose feet go round with the cranks.
                let back = p(26, 76), front = p(76, 76), crank = p(48, 76)
                for wheel in [back, front] {
                    context.stroke(Path(ellipseIn: CGRect(x: wheel.x - 17 * unit, y: wheel.y - 17 * unit,
                                                          width: 34 * unit, height: 34 * unit)),
                                   with: .color(ink.opacity(0.55)), lineWidth: 2.5 * unit)
                    let spoke = CGPoint(x: wheel.x + cos(phase * 2) * 15 * unit, y: wheel.y + sin(phase * 2) * 15 * unit)
                    limb([wheel, spoke], ink.opacity(0.35))
                }
                let seat = p(40, 48), bars = p(68, 46)
                limb([back, seat, crank, back], ink.opacity(0.55))
                limb([crank, bars, front], ink.opacity(0.55))
                let shoulder = p(58, 30), head = p(66, 18)
                limb([seat, shoulder], ink)
                limb([shoulder, bars], ink)
                for offset in [0, Double.pi] {
                    let pedal = CGPoint(x: crank.x + cos(phase + offset) * 9 * unit, y: crank.y + sin(phase + offset) * 9 * unit)
                    let knee = CGPoint(x: (seat.x + pedal.x) / 2 + 9 * unit, y: (seat.y + pedal.y) / 2 - 4 * unit)
                    limb([seat, knee, pedal], offset == 0 ? accent : ink.opacity(0.7))
                }
                context.fill(Path(ellipseIn: CGRect(x: head.x - 7 * unit, y: head.y - 7 * unit, width: 14 * unit, height: 14 * unit)),
                             with: .color(ink))
                return
            }

            // On foot: how far the limbs swing and how far the body leans.
            let swing = motion == .run ? 0.75 : motion == .hike ? 0.45 : 0.5
            let lean = motion == .run ? 0.16 : motion == .hike ? 0.12 : 0.04
            let bounce = motion == .run ? abs(sin(phase)) * 3 : abs(sin(phase)) * 1.2
            let hip = p(50 - lean * 20, 56 - bounce)
            let neck = joint(from: hip, length: -30, angle: -lean)
            let head = joint(from: neck, length: -11, angle: -lean)

            for side in [0.0, Double.pi] {
                let a = sin(phase + side)
                let color = side == 0 ? accent : ink.opacity(0.7)
                // Legs: the thigh swings, the knee folds most as the leg comes forward.
                let knee = joint(from: hip, length: 22, angle: a * swing)
                let fold = max(0, -cos(phase + side)) * (motion == .run ? 1.3 : 0.6)
                let foot = joint(from: knee, length: 22, angle: a * swing - fold)
                limb([hip, knee, foot], color)
                // Arms swing against the legs.
                let elbow = joint(from: neck, length: 15, angle: -a * swing * 0.9)
                let hand = joint(from: elbow, length: 13, angle: -a * swing * 0.9 + (motion == .run ? -1.4 : -0.4))
                limb([neck, elbow, hand], color)
                if motion == .hike, side == 0 {
                    limb([hand, CGPoint(x: hand.x + 8 * unit, y: p(0, 98).y)], ink.opacity(0.45))
                }
            }
            limb([hip, neck], ink)
            context.fill(Path(ellipseIn: CGRect(x: head.x - 7 * unit, y: head.y - 7 * unit, width: 14 * unit, height: 14 * unit)),
                         with: .color(ink))
        }
        .accessibilityHidden(true)
    }
}

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
