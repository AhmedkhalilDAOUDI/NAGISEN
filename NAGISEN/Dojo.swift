import CoreText
import SceneKit

/// Kuro's dojo: a small tatami room at dusk, with shoji glowing on one side, a scroll and a bonsai in
/// the alcove, a cushion to sleep on, a bowl and a temari ball. Kuro moves between them on its own,
/// choosing what to do from its mood.
final class Dojo {
    enum Activity: Equatable { case sleeping, eating, playing, sitting }

    let scene = SCNScene()
    let camera = SCNNode()
    /// Everything that turns when you drag: the room, its things and Kuro.
    let stage = SCNNode()
    let kuro: KuroModel
    var mood: FamiliarCat.Mood
    var onActivity: ((Activity) -> Void)?
    private(set) var activity = Activity.sitting

    private let ball: SCNNode
    private let cushion = SCNVector3(-0.62, 0.075, -0.5)
    private let bowl = SCNVector3(0.62, 0, -0.42)
    private var running = false

    init(stage growth: FamiliarCat.Stage, mood: FamiliarCat.Mood) {
        kuro = KuroModel(stage: growth)
        self.mood = mood
        ball = Ink.part(SCNSphere(radius: 0.065), .white)
        ball.geometry?.firstMaterial?.diffuse.contents = DojoArt.temari()
        scene.background.contents = Ink.colour(0x1B1A1E)
        scene.rootNode.addChildNode(stage)
        buildRoom()
        buildLight()
        ball.position = SCNVector3(0.28, 0.065, 0.32)
        stage.addChildNode(ball)
        stage.addChildNode(kuro.root)

        camera.camera = SCNCamera()
        // Framed by width, so the whole room fits a phone held upright.
        camera.camera?.projectionDirection = .horizontal
        camera.camera?.fieldOfView = 54
        camera.camera?.zNear = 0.05
        camera.position = SCNVector3(1.75, 1.75, 2.5)
        camera.look(at: SCNVector3(-0.15, 0.3, -0.2))
        scene.rootNode.addChildNode(camera)
    }

    // MARK: Life

    func start() {
        guard !running else { return }
        running = true
        let blinking = SCNAction.repeatForever(.sequence([.wait(duration: 3.4, withRange: 2),
                                                          .run { [weak self] _ in DispatchQueue.main.async { self?.kuro.blink() } }]))
        scene.rootNode.runAction(blinking, forKey: "blink")
        if mood == .resting {
            kuro.root.position = cushion
            perform(.sleeping, walk: false)
        } else {
            kuro.root.position = SCNVector3(0, 0, 0.1)
            next()
        }
    }

    func stop() {
        running = false
        scene.rootNode.removeAllActions()
        kuro.root.removeAllActions()
    }

    /// A tap on Kuro: a little hop when awake.
    func pet() {
        guard activity != .sleeping else { return }
        kuro.hop()
    }

    private func next() {
        guard running else { return }
        perform(choose(), walk: true)
    }

    /// What to do next, weighted by mood: a resting Kuro mostly sleeps, a bright one mostly plays.
    private func choose() -> Activity {
        let weights: [(Activity, Double)] = switch mood {
        case .resting: [(.sleeping, 0.7), (.sitting, 0.2), (.eating, 0.1)]
        case .calm: [(.sleeping, 0.3), (.sitting, 0.3), (.eating, 0.2), (.playing, 0.2)]
        case .bright: [(.playing, 0.4), (.sitting, 0.2), (.eating, 0.2), (.sleeping, 0.2)]
        }
        var roll = Double.random(in: 0..<1)
        for (choice, weight) in weights where choice != activity {
            roll -= weight
            if roll < 0 { return choice }
        }
        return weights.first { $0.0 != activity }?.0 ?? .sitting
    }

    private func perform(_ choice: Activity, walk: Bool) {
        activity = choice
        DispatchQueue.main.async { self.onActivity?(choice) }
        switch choice {
        case .sleeping:
            let settle = { [weak self] in
                guard let self else { return }
                self.face(toward: SCNVector3(0.4, 0, 0.6))
                self.kuro.set(.sleep, duration: 1.2)
                self.kuro.breathe()
                self.kuro.swayTail(lively: false)
                self.floatZs()
                self.after(.random(in: 14...22)) { self.stopZs(); self.kuro.set(.sit); self.after(1) { self.next() } }
            }
            if walk { self.walk(to: cushion, then: settle) } else { settle() }
        case .eating:
            let spot = SCNVector3(bowl.x - 0.12, 0, bowl.z + 0.3)
            self.walk(to: spot) { [weak self] in
                guard let self else { return }
                self.face(toward: self.bowl)
                self.kuro.set(.eat)
                self.after(0.7) { self.kuro.bob() }
                self.after(6) { self.kuro.set(.sit); self.after(1.2) { self.next() } }
            }
        case .playing:
            play(rounds: 3)
        case .sitting:
            let spot = SCNVector3(Float.random(in: -0.5...0.6), 0, Float.random(in: -0.2...0.7))
            self.walk(to: spot) { [weak self] in
                guard let self else { return }
                self.face(toward: SCNVector3(1.5, 0, 2.15))
                self.kuro.set(.sit)
                self.kuro.breathe()
                self.kuro.swayTail(lively: self.mood == .bright)
                self.after(1.2) { self.kuro.lookAround() }
                self.after(.random(in: 6...9)) { self.next() }
            }
        }
    }

    /// Walk up to the ball, bat it, watch it roll, and go after it again.
    private func play(rounds: Int) {
        guard rounds > 0 else { after(0.8) { self.next() }; return }
        let target = ball.position
        let approach = SCNVector3(target.x - 0.05, 0, target.z - 0.2)
        walk(to: approach) { [weak self] in
            guard let self else { return }
            self.face(toward: self.ball.position)
            self.kuro.set(.swipe, duration: 0.35)
            self.after(0.4) {
                self.kuro.swipePaw()
                self.roll()
                self.after(1.2) { self.kuro.set(.sit, duration: 0.4); self.after(0.6) { self.play(rounds: rounds - 1) } }
            }
        }
    }

    private func roll() {
        let to = SCNVector3(Float.random(in: -0.75...0.85), 0.065, Float.random(in: -0.1...0.85))
        let distance = hypot(to.x - ball.position.x, to.z - ball.position.z)
        let move = SCNAction.move(to: to, duration: Double(distance) / 0.5 + 0.3)
        move.timingMode = .easeOut
        let spin = SCNAction.rotateBy(x: CGFloat(distance / 0.065), y: 0, z: 0, duration: move.duration)
        spin.timingMode = .easeOut
        ball.runAction(.group([move, spin]))
    }

    // MARK: Moving

    private func face(toward point: SCNVector3) {
        let yaw = atan2(point.x - kuro.root.position.x, point.z - kuro.root.position.z)
        kuro.root.runAction(.rotateTo(x: 0, y: CGFloat(yaw), z: 0, duration: 0.4, usesShortestUnitArc: true))
    }

    private func walk(to point: SCNVector3, then done: @escaping () -> Void) {
        let from = kuro.root.position
        let distance = hypot(point.x - from.x, point.z - from.z)
        guard distance > 0.05 else { kuro.root.runAction(.move(to: point, duration: 0.3)) { DispatchQueue.main.async(execute: done) }; return }
        face(toward: point)
        kuro.set(.stand, duration: 0.4)
        after(0.4) {
            self.kuro.walkCycle()
            let move = SCNAction.move(to: point, duration: Double(distance) / 0.24)
            self.kuro.root.runAction(move) {
                DispatchQueue.main.async {
                    self.kuro.standStill()
                    done()
                }
            }
        }
    }

    private func after(_ seconds: Double, _ work: @escaping () -> Void) {
        scene.rootNode.runAction(.wait(duration: seconds)) { [weak self] in
            DispatchQueue.main.async { if self?.running == true { work() } }
        }
    }

    private func floatZs() {
        let z = SCNText(string: "z", extrusionDepth: 0)
        z.font = CTFontCreateWithName("Hiragino Mincho ProN" as CFString, 0.09, nil)
        z.flatness = 0.05
        z.firstMaterial = Ink.material(Ink.colour(0xF2EADB), glow: 0.6)
        let rise = SCNAction.run { [weak self] _ in
            guard let self else { return }
            let letter = SCNNode(geometry: z)
            letter.position = SCNVector3(self.cushion.x + 0.12, 0.32, self.cushion.z + 0.1)
            letter.constraints = [SCNBillboardConstraint()]
            letter.opacity = 0
            self.stage.addChildNode(letter)
            letter.runAction(.sequence([.group([.moveBy(x: 0.08, y: 0.3, z: 0, duration: 2.6),
                                                .sequence([.fadeOpacity(to: 0.9, duration: 0.6), .wait(duration: 1.2),
                                                           .fadeOut(duration: 0.8)])]),
                                        .removeFromParentNode()]))
        }
        stage.runAction(.repeatForever(.sequence([rise, .wait(duration: 1.6)])), forKey: "zs")
    }

    private func stopZs() { stage.removeAction(forKey: "zs") }

    // MARK: Room

    private func add(_ node: SCNNode, _ x: Float, _ y: Float, _ z: Float, yaw: Float = 0) {
        node.position = SCNVector3(x, y, z)
        node.eulerAngles.y = .init(yaw)
        stage.addChildNode(node)
    }

    private func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ colour: InkColor, outlined: Bool = false, chamfer: CGFloat = 0) -> SCNNode {
        Ink.part(SCNBox(width: w, height: h, length: l, chamferRadius: chamfer), colour, outlined: outlined)
    }

    private func buildRoom() {
        let wood = Ink.colour(0x4A3426), darkWood = Ink.colour(0x33241B), plaster = Ink.colour(0xD9CBB0)
        // Eight tatami: four across on the left, four turned on the right, so no four corners ever meet.
        let mat = Ink.material(image: DojoArt.tatami())
        let layout: [(Float, Float, Bool)] = [(-0.6, -0.9, false), (-0.6, -0.3, false), (-0.6, 0.3, false), (-0.6, 0.9, false),
                                              (0.3, -0.6, true), (0.9, -0.6, true), (0.3, 0.6, true), (0.9, 0.6, true)]
        for (x, z, turned) in layout {
            let tatami = SCNNode(geometry: SCNBox(width: 1.2, height: 0.03, length: 0.6, chamferRadius: 0.004))
            tatami.geometry?.materials = [mat]
            add(tatami, x, 0, z, yaw: turned ? .pi / 2 : 0)
        }
        add(box(2.5, 0.05, 2.5, darkWood), 0, -0.03, 0)

        // Back wall: plaster between dark posts, a low beam, and the alcove on the left.
        add(box(2.4, 1.7, 0.06, plaster), 0, 0.85, -1.23)
        add(box(0.06, 1.7, 2.4, plaster), -1.23, 0.85, 0)
        for x in [-1.2, -0.25, 1.2] { add(box(0.09, 1.72, 0.09, wood), Float(x), 0.86, -1.2) }
        add(box(2.48, 0.08, 0.1, wood), 0, 1.38, -1.19)
        add(box(0.1, 0.08, 2.48, wood), -1.19, 1.38, 0)

        // Tokonoma: a raised board, the hanging scroll for Kuro (黒, black), and a bonsai.
        add(box(0.9, 0.09, 0.42, Ink.colour(0x5B4030), outlined: true), -0.72, 0.045, -1.0)
        let scroll = SCNNode(geometry: SCNPlane(width: 0.36, height: 0.86))
        scroll.geometry?.materials = [Ink.material(image: DojoArt.scroll())]
        add(scroll, -0.72, 0.82, -1.19)
        let rod = Ink.part(SCNCylinder(radius: 0.012, height: 0.42), darkWood)
        rod.eulerAngles.z = .pi / 2
        add(rod, -0.72, 1.26, -1.18)
        add(bonsai(), -0.55, 0.09, -0.98)

        // Shoji down the left wall, lit from outside by the last of the evening.
        for index in 0..<4 {
            let shoji = SCNNode(geometry: SCNPlane(width: 0.6, height: 1.3))
            let paper = Ink.material(image: DojoArt.shoji())
            paper.emission.contents = DojoArt.shoji()
            paper.emission.intensity = 0.55
            shoji.geometry?.materials = [paper]
            shoji.eulerAngles.y = .pi / 2
            add(shoji, -1.195, 0.68, -0.9 + Float(index) * 0.6)
        }

        // A bokken resting on two pegs, for the dojo it is.
        for x in [0.15, 0.85] { add(box(0.03, 0.05, 0.05, darkWood), Float(x), 1.0, -1.18) }
        let bokken = Ink.part(SCNCapsule(capRadius: 0.013, height: 0.95), Ink.colour(0x8A6A48))
        let guardRing = Ink.part(SCNCylinder(radius: 0.032, height: 0.012), Ink.sumi, outlined: false)
        guardRing.position.y = -0.2
        let grip = Ink.part(SCNCylinder(radius: 0.016, height: 0.24), Ink.colour(0x2A2630), outlined: false)
        grip.position.y = -0.34
        bokken.addChildNode(guardRing); bokken.addChildNode(grip)
        bokken.eulerAngles.z = .pi / 2 - 0.04
        add(bokken, 0.5, 1.04, -1.16)

        let zabuton = Ink.part(SCNBox(width: 0.5, height: 0.07, length: 0.5, chamferRadius: 0.03), Ink.colour(0x8B2B49))
        add(zabuton, Float(cushion.x), 0.035, Float(cushion.z), yaw: 0.2)
        add(foodBowl(), Float(bowl.x), 0, Float(bowl.z))
        add(andon(), 0.95, 0, -0.95)
    }

    private func bonsai() -> SCNNode {
        let tree = SCNNode()
        let pot = Ink.part(SCNBox(width: 0.2, height: 0.07, length: 0.12, chamferRadius: 0.01), Ink.colour(0x2F3E5C))
        pot.position.y = 0.035
        tree.addChildNode(pot)
        let trunk = Ink.part(SCNCylinder(radius: 0.014, height: 0.2), Ink.colour(0x5A4030))
        trunk.position = SCNVector3(0.01, 0.16, 0); trunk.eulerAngles.z = -0.35
        tree.addChildNode(trunk)
        for (x, y, r) in [(0.05, 0.26, 0.07), (-0.03, 0.3, 0.06), (0.09, 0.31, 0.05)] {
            let leaves = Ink.part(SCNSphere(radius: CGFloat(r)), Ink.colour(0x56703F))
            leaves.position = SCNVector3(x, y, 0); leaves.scale = SCNVector3(1.3, 0.7, 1)
            tree.addChildNode(leaves)
        }
        return tree
    }

    private func foodBowl() -> SCNNode {
        let node = SCNNode()
        let dish = Ink.part(SCNTube(innerRadius: 0.07, outerRadius: 0.085, height: 0.05), Ink.colour(0xE9E2D4))
        dish.position.y = 0.025
        let base = Ink.part(SCNCylinder(radius: 0.08, height: 0.01), Ink.colour(0xE9E2D4), outlined: false)
        base.position.y = 0.006
        let band = Ink.part(SCNTube(innerRadius: 0.0855, outerRadius: 0.087, height: 0.012), Ink.colour(0x2F3E5C), outlined: false)
        band.position.y = 0.035
        let fish = Ink.part(SCNSphere(radius: 0.035), Ink.colour(0xD9824A))
        fish.position.y = 0.04; fish.scale = SCNVector3(1.4, 0.5, 0.6)
        [dish, base, band, fish].forEach(node.addChildNode)
        return node
    }

    private func andon() -> SCNNode {
        let lamp = SCNNode()
        let paper = Ink.part(SCNBox(width: 0.2, height: 0.32, length: 0.2, chamferRadius: 0), Ink.colour(0xF4E3C0), glow: 0.9)
        paper.position.y = 0.3
        lamp.addChildNode(paper)
        for (x, z) in [(-0.105, -0.105), (0.105, -0.105), (-0.105, 0.105), (0.105, 0.105)] {
            let leg = Ink.part(SCNBox(width: 0.018, height: 0.48, length: 0.018, chamferRadius: 0), Ink.colour(0x33241B), outlined: false)
            leg.position = SCNVector3(x, 0.24, z)
            lamp.addChildNode(leg)
        }
        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .omni
        light.light?.color = Ink.colour(0xFFB866)
        light.light?.intensity = 450
        light.light?.attenuationStartDistance = 0.2
        light.light?.attenuationEndDistance = 2.6
        light.position.y = 0.3
        lamp.addChildNode(light)
        return lamp
    }

    private func buildLight() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = Ink.colour(0x8E8A9A)
        ambient.light?.intensity = 420
        scene.rootNode.addChildNode(ambient)
        // Evening light through the shoji, soft enough to leave a quiet shadow under Kuro.
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.color = Ink.colour(0xFFF1DC)
        key.light?.intensity = 650
        key.light?.castsShadow = true
        key.light?.shadowMode = .deferred
        key.light?.shadowColor = InkColor(white: 0, alpha: 0.35)
        key.light?.shadowRadius = 6
        key.light?.shadowSampleCount = 8
        key.eulerAngles = SCNVector3(-0.95, -1.0, 0)
        scene.rootNode.addChildNode(key)
    }
}

/// The dojo's paper, straw and cloth, painted in code.
enum DojoArt {
    private static func draw(_ width: Int, _ height: Int, _ paint: (CGContext) -> Void) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        paint(context)
        return context.makeImage()!
    }

    private static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    /// Woven straw with the dark heri cloth on the long edges.
    static func tatami() -> CGImage {
        let width = 512, height = 256
        return draw(width, height) { c in
            c.setFillColor(rgb(0xB9AF78)); c.fill(CGRect(x: 0, y: 0, width: width, height: height))
            // Same straw every time, so the floor never shimmers between launches.
            var generator = SeededRandom(seed: 3)
            for x in stride(from: 0, to: width, by: 3) {
                c.setFillColor(rgb(generator.double(0...1) > 0.5 ? 0xA89F69 : 0xC7BE88, 0.55))
                c.fill(CGRect(x: x, y: 0, width: 1, height: height))
            }
            c.setFillColor(rgb(0x26232A))
            c.fill(CGRect(x: 0, y: 0, width: width, height: 18))
            c.fill(CGRect(x: 0, y: height - 18, width: width, height: 18))
        }
    }

    /// Washi paper on a kumiko grid of dark wood.
    static func shoji() -> CGImage {
        draw(240, 520) { c in
            c.setFillColor(rgb(0xF2E8D6)); c.fill(CGRect(x: 0, y: 0, width: 240, height: 520))
            c.setFillColor(rgb(0x4A3426))
            for x in stride(from: 0, through: 240, by: 60) { c.fill(CGRect(x: max(0, x - 3), y: 0, width: 6, height: 520)) }
            for y in stride(from: 0, through: 520, by: 87) { c.fill(CGRect(x: 0, y: max(0, y - 3), width: 240, height: 6)) }
            c.fill(CGRect(x: 0, y: 0, width: 240, height: 16)); c.fill(CGRect(x: 0, y: 504, width: 240, height: 16))
            c.fill(CGRect(x: 0, y: 0, width: 12, height: 520)); c.fill(CGRect(x: 228, y: 0, width: 12, height: 520))
        }
    }

    /// A hanging scroll: an ensō circle, 黒 in brush ink, and a red seal.
    static func scroll() -> CGImage {
        draw(360, 860) { c in
            c.setFillColor(rgb(0x2F3E5C)); c.fill(CGRect(x: 0, y: 0, width: 360, height: 860))
            c.setFillColor(rgb(0xEFE5D0)); c.fill(CGRect(x: 26, y: 40, width: 308, height: 780))
            c.setStrokeColor(rgb(0x1A1416, 0.88)); c.setLineCap(.round)
            for (index, width) in [22.0, 16.0, 9.0].enumerated() {
                c.setLineWidth(width)
                // An ensō: one breath of the brush, almost closing on itself.
                c.addArc(center: CGPoint(x: 180, y: 560), radius: 108 - CGFloat(index) * 2,
                         startAngle: 1.1 + CGFloat(index) * 0.35, endAngle: 1.1 + .pi * 1.9, clockwise: false)
                c.strokePath()
            }
            let font = CTFontCreateWithName("Hiragino Mincho ProN" as CFString, 150, nil)
            let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: rgb(0x1A1416)] as CFDictionary
            let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, "黒" as CFString, attributes))
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            c.textPosition = CGPoint(x: 180 - bounds.midX, y: 250 - bounds.midY)
            CTLineDraw(line, c)
            c.setFillColor(rgb(0xB0283A)); c.fill(CGRect(x: 236, y: 110, width: 44, height: 44))
        }
    }

    /// A temari ball: bands of thread in red, indigo, gold and cream.
    static func temari() -> CGImage {
        draw(256, 128) { c in
            let colours: [UInt32] = [0xB0283A, 0xF2EADB, 0x2F3E5C, 0xD8B04A, 0xF2EADB, 0xB0283A, 0x2F3E5C, 0xF2EADB]
            for (index, colour) in colours.enumerated() {
                c.setFillColor(rgb(colour)); c.fill(CGRect(x: 0, y: index * 16, width: 256, height: 16))
            }
            c.setStrokeColor(rgb(0xD8B04A)); c.setLineWidth(3)
            for x in stride(from: 0, to: 256, by: 32) {
                c.move(to: CGPoint(x: x, y: 0)); c.addLine(to: CGPoint(x: x + 32, y: 128)); c.strokePath()
            }
        }
    }
}
