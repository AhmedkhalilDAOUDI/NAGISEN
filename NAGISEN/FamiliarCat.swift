import SwiftUI

/// The familiar: a small dark cat drawn in fine cream line, like the NAGISEN mark. It grows through
/// four stages and shows its mood in its eyes, its tail and how it breathes.
struct FamiliarCat: View {
    enum Stage: Int, CaseIterable, Comparable {
        case kitten, young, grown, elder

        static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }
    }

    enum Mood { case bright, calm, resting }

    var stage: Stage
    var mood: Mood
    /// Seconds; drives breathing, blinking and the tail. Leave at 0 for a still picture.
    var time: Double = 0

    static let fur = Color(red: 0.23, green: 0.21, blue: 0.25)
    static let chest = Color(red: 0.31, green: 0.29, blue: 0.33)
    static let line = Color(red: 0.94, green: 0.91, blue: 0.86)
    static let iris = Color(red: 0.89, green: 0.71, blue: 0.36)
    static let pupil = Color(red: 0.10, green: 0.07, blue: 0.09)
    static let collar = Color(red: 0.545, green: 0.169, blue: 0.286)
    static let blush = Color(red: 0.86, green: 0.56, blue: 0.64)

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 200
            context.translateBy(x: (size.width - 200 * unit) / 2, y: (size.height - 200 * unit) / 2)
            context.scaleBy(x: unit, y: unit)
            draw(&context)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(Self.describe(stage, mood))
    }

    static func describe(_ stage: Stage, _ mood: Mood) -> String {
        let who = switch stage {
        case .kitten: String(localized: "A kitten")
        case .young: String(localized: "A young cat")
        case .grown: String(localized: "A grown cat")
        case .elder: String(localized: "An elder cat")
        }
        let how = switch mood {
        case .bright: String(localized: "bright and awake")
        case .calm: String(localized: "calm")
        case .resting: String(localized: "asleep")
        }
        return "\(who), \(how)"
    }

    // MARK: Motion

    private var breath: Double { sin(time * 2 * .pi / (mood == .resting ? 4.5 : 3.2)) }

    private var sway: Double {
        switch mood {
        case .bright: 9 * sin(time * 2 * .pi / 2.4)
        case .calm: 5 * sin(time * 2 * .pi / 3.6)
        case .resting: 1.5 * sin(time * 2 * .pi / 6)
        }
    }

    /// How open the eyes are, 0…1, with a quick blink every few seconds while awake.
    private var openness: Double {
        if mood == .resting { return 0 }
        let blinking = time.truncatingRemainder(dividingBy: 4.2) > 4.05
        return blinking ? 0.08 : mood == .bright ? 1 : 0.55
    }

    private var size: Double { [0.7, 0.85, 1, 1][stage.rawValue] }
    /// Kittens are mostly head.
    private var headSize: Double { [1.24, 1.08, 1, 1][stage.rawValue] }

    // MARK: Drawing (in a 200×200 box, ground at 186)

    private func draw(_ context: inout GraphicsContext) {
        if stage == .elder {
            let glow = Path(ellipseIn: CGRect(x: 20, y: 6, width: 160, height: 160))
            context.fill(glow, with: .radialGradient(Gradient(colors: [Self.collar.opacity(0.45), .clear]),
                                                     center: CGPoint(x: 100, y: 86), startRadius: 8, endRadius: 80))
        }
        context.translateBy(x: 100, y: 186)
        context.scaleBy(x: size, y: size * (1 + 0.016 * breath))
        context.translateBy(x: -100, y: -186)

        let tail = tailPath
        context.stroke(tail, with: .color(Self.line), style: StrokeStyle(lineWidth: 15, lineCap: .round))
        context.stroke(tail, with: .color(Self.fur), style: StrokeStyle(lineWidth: 11, lineCap: .round))

        var head = context
        head.translateBy(x: 100, y: 116 + (mood == .resting ? 5 : 0))
        head.scaleBy(x: headSize, y: headSize)
        head.translateBy(x: -100, y: -116)

        // Outline first, fur over it, so the parts read as one silhouette.
        let outline = StrokeStyle(lineWidth: 5, lineJoin: .round)
        context.stroke(bodyPath, with: .color(Self.line), style: outline)
        for part in headParts { head.stroke(part, with: .color(Self.line), style: outline) }
        context.fill(bodyPath, with: .color(Self.fur))
        for part in headParts { head.fill(part, with: .color(Self.fur)) }

        // A soft lighter chest that fades into the fur, not a patch with an edge.
        context.fill(Path(ellipseIn: CGRect(x: 80, y: 120, width: 40, height: 56)),
                     with: .radialGradient(Gradient(colors: [Self.chest, Self.fur]), center: CGPoint(x: 100, y: 146),
                                           startRadius: 2, endRadius: 24))
        for paw in [CGRect(x: 77, y: 174, width: 21, height: 12), CGRect(x: 102, y: 174, width: 21, height: 12)] {
            context.fill(Path(ellipseIn: paw), with: .color(Self.fur))
            context.stroke(Path(ellipseIn: paw), with: .color(Self.line), lineWidth: 2)
        }
        if stage >= .grown {
            var band = Path()
            band.move(to: CGPoint(x: 76, y: 117))
            band.addQuadCurve(to: CGPoint(x: 124, y: 117), control: CGPoint(x: 100, y: 131))
            context.stroke(band, with: .color(Self.collar), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        }
        if stage == .elder {
            let bell = Path(ellipseIn: CGRect(x: 96, y: 122, width: 8, height: 8))
            context.fill(bell, with: .color(Self.iris))
            context.stroke(bell, with: .color(Self.line), lineWidth: 1)
        }
        drawFace(&head)
        if mood == .resting { drawSleep(&context) }
    }

    private var bodyPath: Path {
        var path = Path()
        path.move(to: CGPoint(x: 62, y: 186))
        path.addCurve(to: CGPoint(x: 74, y: 118), control1: CGPoint(x: 54, y: 160), control2: CGPoint(x: 60, y: 128))
        path.addCurve(to: CGPoint(x: 126, y: 118), control1: CGPoint(x: 88, y: 108), control2: CGPoint(x: 112, y: 108))
        path.addCurve(to: CGPoint(x: 138, y: 186), control1: CGPoint(x: 140, y: 128), control2: CGPoint(x: 146, y: 160))
        path.addQuadCurve(to: CGPoint(x: 62, y: 186), control: CGPoint(x: 100, y: 192))
        return path
    }

    private var headParts: [Path] {
        var left = Path(), right = Path()
        left.move(to: CGPoint(x: 68, y: 80)); left.addLine(to: CGPoint(x: 73, y: 42)); left.addLine(to: CGPoint(x: 96, y: 60))
        left.closeSubpath()
        right.move(to: CGPoint(x: 104, y: 60)); right.addLine(to: CGPoint(x: 127, y: 42)); right.addLine(to: CGPoint(x: 132, y: 80))
        right.closeSubpath()
        return [left, right, Path(ellipseIn: CGRect(x: 64, y: 56, width: 72, height: 64))]
    }

    private var tailPath: Path {
        var path = Path()
        path.move(to: CGPoint(x: 128, y: 178))
        path.addCurve(to: CGPoint(x: 168 + sway * 0.4, y: 136), control1: CGPoint(x: 168, y: 184), control2: CGPoint(x: 180, y: 152))
        path.addQuadCurve(to: CGPoint(x: 158 + sway, y: 116), control: CGPoint(x: 164 + sway * 0.8, y: 118))
        return path
    }

    private func drawFace(_ context: inout GraphicsContext) {
        for (x, y) in [(73.0, 46.0), (127.0, 46.0)] {
            var inner = Path()
            let toward: Double = x < 100 ? 1 : -1
            inner.move(to: CGPoint(x: x + toward * 3, y: y + 10))
            inner.addLine(to: CGPoint(x: x + toward * 4, y: y + 4))
            inner.addLine(to: CGPoint(x: x + toward * 13, y: y + 15))
            inner.closeSubpath()
            context.fill(inner, with: .color(Self.blush.opacity(0.45)))
        }
        for x in [86.0, 114.0] {
            if openness > 0.15 {
                let height = 11 * openness
                let eye = Path(ellipseIn: CGRect(x: x - 7, y: 90 - height / 2, width: 14, height: height))
                context.fill(eye, with: .color(Self.iris))
                context.fill(Path(ellipseIn: CGRect(x: x - 1.6, y: 90 - height * 0.42, width: 3.2, height: height * 0.84)),
                             with: .color(Self.pupil))
                context.fill(Path(ellipseIn: CGRect(x: x + 1.5, y: 90 - height * 0.32, width: 2.6, height: 2.6)), with: .color(.white))
            } else {
                var closed = Path()
                closed.move(to: CGPoint(x: x - 7, y: 90))
                closed.addQuadCurve(to: CGPoint(x: x + 7, y: 90), control: CGPoint(x: x, y: 95))
                context.stroke(closed, with: .color(Self.line), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        var nose = Path()
        nose.move(to: CGPoint(x: 96.5, y: 99)); nose.addLine(to: CGPoint(x: 103.5, y: 99)); nose.addLine(to: CGPoint(x: 100, y: 103))
        nose.closeSubpath()
        context.fill(nose, with: .color(Self.blush))
        var mouth = Path()
        mouth.move(to: CGPoint(x: 100, y: 103)); mouth.addQuadCurve(to: CGPoint(x: 94.5, y: 106), control: CGPoint(x: 97.5, y: 106.5))
        mouth.move(to: CGPoint(x: 100, y: 103)); mouth.addQuadCurve(to: CGPoint(x: 105.5, y: 106), control: CGPoint(x: 102.5, y: 106.5))
        context.stroke(mouth, with: .color(Self.line), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        var whiskers = Path()
        for (from, to) in [((80.0, 100.0), (56.0, 95.0)), ((80.0, 104.0), (55.0, 105.0)),
                           ((120.0, 100.0), (144.0, 95.0)), ((120.0, 104.0), (145.0, 105.0))] {
            whiskers.move(to: CGPoint(x: from.0, y: from.1)); whiskers.addLine(to: CGPoint(x: to.0, y: to.1))
        }
        context.stroke(whiskers, with: .color(Self.line.opacity(0.45)), lineWidth: 1)
    }

    /// Two small z's drifting up from the sleeping cat.
    private func drawSleep(_ context: inout GraphicsContext) {
        for (index, size) in [13.0, 10.0].enumerated() {
            let rise = (time / 3 + Double(index) * 0.5).truncatingRemainder(dividingBy: 1)
            let text = Text("z").font(.system(size: size, weight: .medium, design: .serif)).foregroundStyle(Self.line)
            var layer = context
            layer.opacity = sin(rise * .pi) * 0.8
            layer.draw(text, at: CGPoint(x: 152 + Double(index) * 12 + rise * 6, y: 52 - Double(index) * 14 - rise * 18))
        }
    }
}
