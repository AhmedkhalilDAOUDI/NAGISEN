import CoreText
import SceneKit

/// Kuro's hideout: an open engawa under a tiled roof in a spring garden, cherry trees, a pond and a stone
/// lantern, Mount Fuji painted across the sky behind. Kuro lives on the veranda: it naps on the zabuton,
/// eats when you feed it, chases the temari ball, sits and watches, and minds being poked.
final class Dojo {
    enum Activity: Equatable { case sleeping, eating, playing, sitting, purring, annoyed, listening }

    let scene = SCNScene()
    let camera = SCNNode()
    /// Everything that turns when you drag: the hideout, the garden and Kuro.
    let stage = SCNNode()
    let kuro: KuroModel
    var mood: FamiliarCat.Mood
    var onActivity: ((Activity) -> Void)?
    private(set) var activity = Activity.sitting

    /// The veranda floor's height; everything Kuro does happens up here.
    static let deck: Float = 0.32
    private let ball: SCNNode
    private let food: SCNNode
    private let cushion = SCNVector3(-0.62, Dojo.deck + 0.07, -0.45)
    private let bowl = SCNVector3(0.68, Dojo.deck, -0.5)
    /// Where the camera stands and what it looks at; the painted sky is turned to match.
    private static let eye = SCNVector3(0.3, 1.05, 2.1), focus = SCNVector3(-0.15, 0.5, -0.45)
    private var running = false
    /// Bumped whenever you interrupt Kuro, so plans made before then quietly drop.
    private var plan = 0
    private var grumpyUntil = Date.distantPast
    private var pokes: [Date] = []

    init(stage growth: FamiliarCat.Stage, mood: FamiliarCat.Mood) {
        kuro = KuroModel(stage: growth)
        self.mood = mood
        ball = Ink.part(SCNSphere(radius: 0.065), .white, image: DojoArt.temari())
        food = Ink.part(SCNSphere(radius: 0.035), Ink.colour(0xD9824A))
        // Above the painted sky: the same deep blue its top fades into.
        scene.background.contents = Ink.colour(0x2F4E7A)
        scene.rootNode.addChildNode(stage)
        buildGarden()
        buildVeranda()
        buildLight()
        ball.position = SCNVector3(0.3, Dojo.deck + 0.065, 0.35)
        stage.addChildNode(ball)
        stage.addChildNode(kuro.root)

        camera.camera = SCNCamera()
        camera.camera?.projectionDirection = .horizontal
        camera.camera?.fieldOfView = 60
        camera.camera?.zNear = 0.05
        camera.camera?.zFar = 40
        camera.position = Dojo.eye
        camera.look(at: Dojo.focus)
        scene.rootNode.addChildNode(camera)
    }

    // MARK: Life

    func start() {
        guard !running else { return }
        running = true
        let blinking = SCNAction.repeatForever(.sequence([.wait(duration: 3.4, withRange: 2),
                                                          .run { [weak self] _ in DispatchQueue.main.async { self?.kuro.blink() } }]))
        stage.runAction(blinking, forKey: "blink")
        if mood == .resting {
            kuro.root.position = cushion
            perform(.sleeping, walk: false)
        } else {
            kuro.root.position = SCNVector3(0, Dojo.deck, 0.2)
            next()
        }
    }

    func stop() {
        running = false
        plan += 1
        scene.rootNode.removeAllActions()
        stage.removeAllActions()
        kuro.root.removeAllActions()
    }

    // MARK: What you can do

    /// Puts fish in the bowl; Kuro goes straight to it.
    func feed() {
        guard running else { return }
        food.isHidden = false
        interrupt()
        perform(.eating, walk: true)
    }

    /// Throws the temari ball onto the veranda for Kuro to chase.
    func play() {
        guard running else { return }
        interrupt()
        let landing = SCNVector3(Float.random(in: -0.6...0.8), Dojo.deck + 0.065, Float.random(in: 0.0...0.7))
        ball.position = SCNVector3(1.4, 1.1, 1.6)
        let toss = SCNAction.move(to: landing, duration: 0.7)
        toss.timingMode = .easeIn
        ball.runAction(.group([toss, .rotateBy(x: 6, y: 0, z: 2, duration: 0.7)]))
        activity = .playing
        report(.playing)
        after(0.75) { self.play(rounds: 3) }
    }

    /// A stroke: purring and a little lean in, unless Kuro is still cross with you.
    /// Three pokes in quick succession count as annoying.
    func pet() {
        guard running else { return }
        pokes = pokes.filter { $0.timeIntervalSinceNow > -1.6 } + [.now]
        if pokes.count >= 3 { annoy(); return }
        if Date.now < grumpyUntil { kuro.bristle(true); float("…", Ink.colour(0xF2EADB)); return }
        interrupt()
        activity = .purring
        report(.purring)
        if kuro.pose == .sleep { kuro.set(.sit, duration: 1) } else { kuro.hop() }
        faceCamera()
        for delay in [0.0, 0.5, 1.0] { after(delay) { self.float("♥", Ink.colour(0xE07A92)) } }
        kuro.swayTail(lively: true)
        after(3.5) { self.next() }
    }

    /// A poke too many: ears back, a hiss, and Kuro takes itself off to the far corner for a while.
    func annoy() {
        guard running else { return }
        pokes = []
        interrupt()
        grumpyUntil = .now + 15
        activity = .annoyed
        report(.annoyed)
        if kuro.pose == .sleep { kuro.set(.sit, duration: 0.3) }
        faceCamera()
        kuro.bristle(true)
        float("シャー!", Ink.colour(0xF2EADB))
        after(1.4) {
            let corner = SCNVector3(-1.0, Dojo.deck, Float.random(in: -0.7 ... -0.4))
            self.walk(to: corner) {
                self.face(toward: SCNVector3(-3, 0, -2))
                self.kuro.set(.sit)
                self.after(6) { self.kuro.bristle(false); self.after(4) { self.next() } }
            }
        }
    }

    /// While you talk, Kuro sits and faces you; each answer gets a nod.
    func listen() {
        guard running, activity != .listening else { return }
        interrupt()
        activity = .listening
        report(.listening)
        if kuro.pose == .sleep { kuro.set(.sit, duration: 1) }
        // Comes to the front of the veranda to sit with you.
        after(kuro.pose == .sleep ? 1 : 0) {
            self.walk(to: SCNVector3(0.05, Dojo.deck, 0.3)) {
                self.kuro.set(.sit, duration: 0.4)
                self.faceCamera()
                self.kuro.swayTail(lively: false)
            }
        }
    }

    func speak() {
        kuro.bob()
        float("…", Ink.colour(0xF2EADB))
    }

    func stopListening() {
        guard activity == .listening else { return }
        next()
    }

    // MARK: Kuro on its own

    private func interrupt() {
        plan += 1
        kuro.root.removeAllActions()
        kuro.standStill()
        stopZs()
        kuro.bristle(false)
    }

    private func report(_ activity: Activity) {
        DispatchQueue.main.async { self.onActivity?(activity) }
    }

    private func next() {
        guard running else { return }
        perform(choose(), walk: true)
    }

    /// What to do next, weighted by mood: a resting Kuro mostly sleeps, a bright one mostly plays.
    /// Kuro only eats when you put something in the bowl.
    private func choose() -> Activity {
        let weights: [(Activity, Double)] = switch mood {
        case .resting: [(.sleeping, 0.7), (.sitting, 0.3)]
        case .calm: [(.sleeping, 0.4), (.sitting, 0.4), (.playing, 0.2)]
        case .bright: [(.playing, 0.45), (.sitting, 0.35), (.sleeping, 0.2)]
        }
        let open = weights.filter { $0.0 != activity }
        var roll = Double.random(in: 0..<open.map(\.1).reduce(0, +))
        for (choice, weight) in open {
            roll -= weight
            if roll < 0 { return choice }
        }
        return open.first?.0 ?? .sitting
    }

    private func perform(_ choice: Activity, walk: Bool) {
        activity = choice
        report(choice)
        switch choice {
        case .sleeping:
            let settle = {
                self.face(toward: SCNVector3(0.4, Dojo.deck, 0.6))
                self.kuro.set(.sleep, duration: 1.2)
                self.kuro.breathe()
                self.kuro.swayTail(lively: false)
                self.floatZs()
                self.after(.random(in: 14...22)) { self.stopZs(); self.kuro.set(.sit); self.after(1) { self.next() } }
            }
            if walk { self.walk(to: cushion, then: settle) } else { settle() }
        case .eating:
            let spot = SCNVector3(Float(bowl.x) - 0.12, Dojo.deck, Float(bowl.z) + 0.3)
            self.walk(to: spot) {
                self.face(toward: self.bowl)
                self.kuro.set(.eat)
                self.after(0.7) { self.kuro.bob() }
                self.after(5.5) {
                    self.food.isHidden = true
                    self.kuro.set(.sit)
                    self.float("♪", Ink.colour(0xF2EADB))
                    self.after(1.2) { self.next() }
                }
            }
        case .playing:
            play(rounds: 3)
        case .sitting, .purring, .annoyed, .listening:
            let spot = SCNVector3(Float.random(in: -0.9...0.9), Dojo.deck, Float.random(in: -0.3...0.7))
            self.walk(to: spot) {
                self.face(toward: SCNVector3(-1.5, 0, -6))
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
        let approach = SCNVector3(Float(target.x) - 0.05, Dojo.deck, Float(target.z) - 0.2)
        walk(to: approach) {
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
        let to = SCNVector3(Float.random(in: -0.9...0.95), Dojo.deck + 0.065, Float.random(in: -0.2...0.8))
        let distance = hypot(to.x - ball.position.x, to.z - ball.position.z)
        let move = SCNAction.move(to: to, duration: Double(distance) / 0.5 + 0.3)
        move.timingMode = .easeOut
        let spin = SCNAction.rotateBy(x: CGFloat(distance / 0.065), y: 0, z: 0, duration: move.duration)
        spin.timingMode = .easeOut
        ball.runAction(.group([move, spin]))
    }

    // MARK: Moving

    /// Points Kuro at a spot on the stage.
    private func face(toward point: SCNVector3) {
        let yaw = atan2(point.x - kuro.root.position.x, point.z - kuro.root.position.z)
        kuro.root.runAction(.rotateTo(x: 0, y: CGFloat(yaw), z: 0, duration: 0.4, usesShortestUnitArc: true))
    }

    /// The camera sits outside the turning stage, so it is found from the stage's point of view.
    private func faceCamera() {
        face(toward: stage.convertPosition(camera.position, from: nil))
    }

    private func walk(to point: SCNVector3, then done: @escaping () -> Void) {
        let from = kuro.root.position
        let distance = hypot(point.x - from.x, point.z - from.z)
        let ticket = plan
        guard distance > 0.05 else {
            kuro.root.runAction(.move(to: point, duration: 0.3)) { DispatchQueue.main.async { if self.plan == ticket { done() } } }
            return
        }
        face(toward: point)
        kuro.set(.stand, duration: 0.4)
        after(0.4) {
            self.kuro.walkCycle()
            let move = SCNAction.move(to: point, duration: Double(distance) / 0.24)
            self.kuro.root.runAction(move) {
                DispatchQueue.main.async {
                    guard self.plan == ticket else { return }
                    self.kuro.standStill()
                    done()
                }
            }
        }
    }

    private func after(_ seconds: Double, _ work: @escaping () -> Void) {
        let ticket = plan
        scene.rootNode.runAction(.wait(duration: seconds)) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.running, self.plan == ticket else { return }
                work()
            }
        }
    }

    /// A word or sign drifting up from Kuro's head and fading.
    private func float(_ text: String, _ colour: InkColor) {
        let glyph = SCNText(string: text, extrusionDepth: 0)
        glyph.font = CTFontCreateWithName("Hiragino Mincho ProN" as CFString, 0.07, nil)
        glyph.flatness = 0.05
        glyph.firstMaterial = Ink.material(colour, glow: 0.7)
        let node = SCNNode(geometry: glyph)
        let (low, high) = node.boundingBox
        node.pivot = SCNMatrix4MakeTranslation((low.x + high.x) / 2, 0, 0)
        node.position = SCNVector3(kuro.root.position.x, kuro.root.position.y + 0.45, kuro.root.position.z)
        node.constraints = [SCNBillboardConstraint()]
        node.opacity = 0
        stage.addChildNode(node)
        node.runAction(.sequence([.group([.moveBy(x: 0, y: 0.25, z: 0, duration: 1.8),
                                          .sequence([.fadeIn(duration: 0.3), .wait(duration: 0.9), .fadeOut(duration: 0.6)])]),
                                  .removeFromParentNode()]))
    }

    private func floatZs() {
        let rise = SCNAction.run { [weak self] _ in DispatchQueue.main.async { self?.float("z", Ink.colour(0xF2EADB)) } }
        stage.runAction(.repeatForever(.sequence([rise, .wait(duration: 1.6)])), forKey: "zs")
    }

    private func stopZs() { stage.removeAction(forKey: "zs") }

    // MARK: The hideout

    private func add(_ node: SCNNode, _ x: Float, _ y: Float, _ z: Float, yaw: Float = 0) {
        node.position = SCNVector3(x, y, z)
        node.eulerAngles.y = .init(yaw)
        stage.addChildNode(node)
    }

    private func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ colour: InkColor, outlined: Bool = false, chamfer: CGFloat = 0) -> SCNNode {
        Ink.part(SCNBox(width: w, height: h, length: l, chamferRadius: chamfer), colour, outlined: outlined)
    }

    private func buildVeranda() {
        let wood = Ink.colour(0x6B4A33), darkWood = Ink.colour(0x3E2B20), tiles = Ink.colour(0x4A3426)
        let deck = Dojo.deck
        // The engawa: planks on short posts, two tatami at the back.
        let floor = SCNNode(geometry: SCNBox(width: 2.6, height: 0.06, length: 2.0, chamferRadius: 0.01))
        floor.geometry?.materials = [Ink.material(image: DojoArt.planks())]
        add(floor, 0, deck - 0.03, 0)
        for x in [-1.2, 0, 1.2] { for z in [-0.9, 0.9] { add(box(0.1, CGFloat(deck), 0.1, darkWood), Float(x), deck / 2, Float(z)) } }
        let mat = Ink.material(image: DojoArt.tatami())
        for x in [-0.55, 0.55] {
            let tatami = SCNNode(geometry: SCNBox(width: 1.05, height: 0.025, length: 0.62, chamferRadius: 0.004))
            tatami.geometry?.materials = [mat]
            add(tatami, Float(x), deck + 0.012, -0.55)
        }
        // Four pillars and an open frame of rafters, so the sky stays in view.
        for x in [-1.22, 1.22] { for z in [-0.92, 0.92] { add(box(0.09, 1.55, 0.09, wood, outlined: true), Float(x), deck + 0.775, Float(z)) } }
        for z in [-0.92, 0.92] { add(box(2.9, 0.1, 0.12, darkWood, outlined: true), 0, deck + 1.55, Float(z)) }
        for x in [-1.22, 1.22] { add(box(0.12, 0.1, 2.3, darkWood, outlined: true), Float(x), deck + 1.55, 0) }
        for x in [-0.8, 0, 0.8] { add(box(0.06, 0.06, 2.3, tiles, outlined: true), Float(x), deck + 1.63, 0) }
        // A low shoji screen at the back, half slid open.
        let shoji = SCNNode(geometry: SCNPlane(width: 1.1, height: 0.9))
        let paper = Ink.material(image: DojoArt.shoji())
        paper.isDoubleSided = true
        shoji.geometry?.materials = [paper]
        add(shoji, -0.62, deck + 0.45, -0.94)

        let zabuton = Ink.part(SCNBox(width: 0.5, height: 0.07, length: 0.5, chamferRadius: 0.03), Ink.colour(0xA3283F))
        add(zabuton, Float(cushion.x), deck + 0.035, Float(cushion.z), yaw: 0.2)
        let rug = Ink.part(SCNBox(width: 0.9, height: 0.008, length: 0.6, chamferRadius: 0), Ink.colour(0xC4533A), outlined: false)
        add(rug, 0.4, deck + 0.004, 0.45)
        let dish = foodBowl()
        add(dish, Float(bowl.x), deck, Float(bowl.z))
        food.position.y = 0.045
        food.scale = SCNVector3(1.4, 0.5, 0.6)
        food.isHidden = true
        dish.addChildNode(food)
        let cup = Ink.part(SCNTube(innerRadius: 0.04, outerRadius: 0.05, height: 0.05), .white, image: DojoArt.porcelain())
        add(cup, Float(bowl.x) + 0.2, deck + 0.025, Float(bowl.z) - 0.1)
    }

    private func buildGarden() {
        let backdrop = SCNNode(geometry: SCNCylinder(radius: 14, height: 11))
        let sky = SCNMaterial()
        sky.lightingModel = .constant
        sky.diffuse.contents = DojoArt.sky()
        sky.cullMode = .front
        // Only the wall of the cylinder is painted; its lids stay invisible.
        let none = SCNMaterial()
        none.transparency = 0
        backdrop.geometry?.materials = [sky, none, none]
        backdrop.position.y = 4.2
        // Turned so the middle of the painting, Fuji, stands behind the veranda where the camera looks.
        backdrop.eulerAngles.y = .init(atan2(Float(Dojo.focus.x - Dojo.eye.x), Float(Dojo.focus.z - Dojo.eye.z)))
        stage.addChildNode(backdrop)

        let ground = Ink.part(SCNCylinder(radius: 14, height: 0.02), Ink.colour(0x7E9A5C), outlined: false)
        add(ground, 0, -0.01, 0)
        let pond = Ink.part(SCNCylinder(radius: 1.0, height: 0.02), Ink.colour(0x5D8DAE), outlined: false, glow: 0.15)
        pond.scale = SCNVector3(1.6, 1, 1)
        add(pond, -1.9, 0.005, -2.4)
        for (x, z, r) in [(-3.0, -2.0, 0.22), (-0.6, -2.8, 0.18), (-2.4, -3.2, 0.26), (-1.0, -1.7, 0.14), (2.6, -1.4, 0.3)] {
            let rock = Ink.part(SCNSphere(radius: CGFloat(r)), Ink.colour(0x8C8A86))
            rock.scale = SCNVector3(1.3, 0.6, 1)
            add(rock, Float(x), Float(r) * 0.3, Float(z))
        }
        // Stepping stones leading off the veranda toward the pond.
        for (x, z) in [(-1.45, 0.55), (-1.85, 0.1), (-2.15, -0.4)] {
            let stone = Ink.part(SCNCylinder(radius: 0.16, height: 0.04), Ink.colour(0x9A978F))
            add(stone, Float(x), 0.02, Float(z))
        }
        add(sakura(scale: 1.15), -2.6, 0, -1.0)
        add(sakura(scale: 1.0), 2.4, 0, -2.4)
        add(sakura(scale: 0.85), -0.4, 0, -3.6)
        add(sakura(scale: 0.9), 4.0, 0, -0.8)
        add(lantern(), 1.9, 0, -0.9)
        add(bridge(), -2.2, 0, -3.3, yaw: 0.3)
        stage.addChildNode(petals())
    }

    private func sakura(scale: Float) -> SCNNode {
        let tree = SCNNode()
        let bark = Ink.colour(0x4A342A)
        let trunk = Ink.part(SCNCylinder(radius: 0.08, height: 1.5), bark)
        trunk.position.y = 0.75
        trunk.eulerAngles.z = 0.12
        tree.addChildNode(trunk)
        for (angle, length) in [(0.9, 0.8), (-0.8, 0.7), (0.3, 0.6)] {
            let branch = Ink.part(SCNCylinder(radius: 0.04, height: CGFloat(length)), bark)
            branch.position = SCNVector3(Float(sin(angle) * length * 0.4), 1.35, 0)
            branch.eulerAngles.z = .init(-angle)
            tree.addChildNode(branch)
        }
        var generator = SeededRandom(seed: UInt64(scale * 100))
        for _ in 0..<9 {
            let pink: UInt32 = generator.double(0...1) > 0.5 ? 0xF2B8C6 : 0xE89AAE
            let bloom = Ink.part(SCNSphere(radius: CGFloat(generator.double(0.28...0.45))), Ink.colour(pink))
            bloom.position = SCNVector3(Float(generator.double(-0.75...0.75)), Float(generator.double(1.45...2.15)),
                                        Float(generator.double(-0.5...0.5)))
            bloom.scale = SCNVector3(1.2, 0.85, 1.1)
            tree.addChildNode(bloom)
        }
        tree.scale = SCNVector3(scale, scale, scale)
        return tree
    }

    /// A stone tōrō with a warm light inside.
    private func lantern() -> SCNNode {
        let lamp = SCNNode(), stone = Ink.colour(0x9A978F)
        let parts: [(SCNGeometry, Float)] = [(SCNCylinder(radius: 0.16, height: 0.08), 0.04), (SCNCylinder(radius: 0.06, height: 0.45), 0.3),
                                             (SCNBox(width: 0.28, height: 0.05, length: 0.28, chamferRadius: 0.01), 0.55),
                                             (SCNCone(topRadius: 0.02, bottomRadius: 0.24, height: 0.14), 0.83),
                                             (SCNSphere(radius: 0.035), 0.92)]
        for (geometry, y) in parts {
            let piece = Ink.part(geometry, stone)
            piece.position.y = .init(y)
            lamp.addChildNode(piece)
        }
        let light = Ink.part(SCNBox(width: 0.18, height: 0.18, length: 0.18, chamferRadius: 0.01), Ink.colour(0xF8D9A0), glow: 0.8)
        light.position.y = 0.67
        lamp.addChildNode(light)
        return lamp
    }

    /// A small red taiko bridge over the pond's end.
    private func bridge() -> SCNNode {
        let node = SCNNode(), red = Ink.colour(0xB0283A)
        for index in 0..<7 {
            let t = Float(index - 3) / 3
            let plank = Ink.part(SCNBox(width: 0.2, height: 0.04, length: 0.5, chamferRadius: 0.005), red)
            plank.position = SCNVector3(t * 0.6, 0.22 * (1 - t * t) + 0.05, 0)
            plank.eulerAngles.z = .init(-t * 0.5)
            node.addChildNode(plank)
        }
        return node
    }

    private func petals() -> SCNNode {
        let system = SCNParticleSystem()
        system.particleImage = DojoArt.petal()
        system.birthRate = 7
        system.particleLifeSpan = 9
        system.particleSize = 0.035
        system.particleSizeVariation = 0.012
        system.particleVelocity = 0.15
        system.particleVelocityVariation = 0.1
        system.acceleration = SCNVector3(0.06, -0.1, 0.03)
        system.particleAngularVelocity = 90
        system.particleAngularVelocityVariation = 80
        system.emitterShape = SCNBox(width: 7, height: 0.1, length: 6, chamferRadius: 0)
        system.blendMode = .alpha
        let node = SCNNode()
        node.position = SCNVector3(0, 3.2, -0.6)
        node.addParticleSystem(system)
        return node
    }

    private func foodBowl() -> SCNNode {
        let node = SCNNode()
        let dish = Ink.part(SCNTube(innerRadius: 0.07, outerRadius: 0.085, height: 0.05), .white, image: DojoArt.porcelain())
        dish.position.y = 0.025
        let base = Ink.part(SCNCylinder(radius: 0.08, height: 0.01), Ink.colour(0xF1ECE2), outlined: false)
        base.position.y = 0.006
        let stand = Ink.part(SCNBox(width: 0.26, height: 0.02, length: 0.26, chamferRadius: 0.004), Ink.colour(0x241F20))
        stand.position.y = -0.002
        [stand, dish, base].forEach(node.addChildNode)
        return node
    }

    private func buildLight() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = Ink.colour(0xB9C2D4)
        ambient.light?.intensity = 520
        scene.rootNode.addChildNode(ambient)
        // A clear spring afternoon, the sun low enough to throw soft shadows across the boards.
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.color = Ink.colour(0xFFF0D6)
        sun.light?.intensity = 900
        sun.light?.castsShadow = true
        sun.light?.shadowMode = .deferred
        sun.light?.shadowColor = InkColor(white: 0, alpha: 0.3)
        sun.light?.shadowRadius = 5
        sun.light?.shadowSampleCount = 8
        sun.light?.orthographicScale = 6
        sun.eulerAngles = SCNVector3(-0.85, 0.7, 0)
        scene.rootNode.addChildNode(sun)
    }
}

/// The hideout's paper, straw, wood, porcelain and sky, painted in code in a woodblock-print palette.
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
        draw(512, 256) { c in
            c.setFillColor(rgb(0xC2B67E)); c.fill(CGRect(x: 0, y: 0, width: 512, height: 256))
            // Same straw every time, so the floor never shimmers between launches.
            var generator = SeededRandom(seed: 3)
            for x in stride(from: 0, to: 512, by: 3) {
                c.setFillColor(rgb(generator.double(0...1) > 0.5 ? 0xAFA46C : 0xCFC48E, 0.55))
                c.fill(CGRect(x: x, y: 0, width: 1, height: 256))
            }
            c.setFillColor(rgb(0x2A3550))
            c.fill(CGRect(x: 0, y: 0, width: 512, height: 18)); c.fill(CGRect(x: 0, y: 238, width: 512, height: 18))
        }
    }

    /// Long hinoki planks with dark joins.
    static func planks() -> CGImage {
        draw(512, 512) { c in
            c.setFillColor(rgb(0x9C7552)); c.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
            var generator = SeededRandom(seed: 9)
            for y in stride(from: 0, to: 512, by: 40) {
                c.setFillColor(rgb(generator.double(0...1) > 0.5 ? 0xA77E5A : 0x8F6A4A))
                c.fill(CGRect(x: 0, y: y, width: 512, height: 38))
                c.setFillColor(rgb(0x4A3426)); c.fill(CGRect(x: 0, y: y + 38, width: 512, height: 2))
            }
        }
    }

    static func shoji() -> CGImage {
        draw(440, 360) { c in
            c.setFillColor(rgb(0xF4EBDA)); c.fill(CGRect(x: 0, y: 0, width: 440, height: 360))
            c.setFillColor(rgb(0x4A3426))
            for x in stride(from: 0, through: 440, by: 55) { c.fill(CGRect(x: max(0, x - 3), y: 0, width: 6, height: 360)) }
            for y in stride(from: 0, through: 360, by: 72) { c.fill(CGRect(x: 0, y: max(0, y - 3), width: 440, height: 6)) }
            c.fill(CGRect(x: 0, y: 0, width: 440, height: 14)); c.fill(CGRect(x: 0, y: 346, width: 440, height: 14))
            c.fill(CGRect(x: 0, y: 0, width: 12, height: 360)); c.fill(CGRect(x: 428, y: 0, width: 12, height: 360))
        }
    }

    /// White porcelain with an indigo band and blossoms, like the bowls in the print.
    static func porcelain() -> CGImage {
        draw(256, 64) { c in
            c.setFillColor(rgb(0xF4F0E8)); c.fill(CGRect(x: 0, y: 0, width: 256, height: 64))
            c.setFillColor(rgb(0x24396B)); c.fill(CGRect(x: 0, y: 46, width: 256, height: 10)); c.fill(CGRect(x: 0, y: 6, width: 256, height: 4))
            for x in stride(from: 12, to: 256, by: 40) {
                c.setFillColor(rgb(0x2E4A85)); c.fillEllipse(in: CGRect(x: x, y: 20, width: 16, height: 16))
                c.setFillColor(rgb(0xF4F0E8)); c.fillEllipse(in: CGRect(x: x + 5, y: 25, width: 6, height: 6))
            }
        }
    }

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

    static func petal() -> CGImage {
        draw(32, 32) { c in
            c.setFillColor(rgb(0xF6C3CF)); c.fillEllipse(in: CGRect(x: 4, y: 9, width: 24, height: 14))
            c.setFillColor(rgb(0xE88FA6, 0.7)); c.fillEllipse(in: CGRect(x: 8, y: 13, width: 10, height: 6))
        }
    }

    /// The sky all around the garden: banded clouds, layered blue hills, a pagoda, and Fuji with snow.
    static func sky() -> CGImage {
        let width = 4096, height = 1024
        return draw(width, height) { c in
            let colours = [rgb(0x2F4E7A), rgb(0x8FA9C4), rgb(0xF3E4C8)] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0, 0.55, 1])!
            c.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 380), options: [.drawsAfterEndLocation])
            // Woodblock clouds: thin cream bands drifting high over the mountain.
            for (x, y, w) in [(1400, 780, 380), (2240, 820, 420), (900, 900, 500), (2650, 930, 520), (300, 880, 700), (3300, 840, 600)] {
                let band = CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: 18), cornerWidth: 9, cornerHeight: 9, transform: nil)
                c.setFillColor(rgb(0xF6EEDD, 0.75)); c.addPath(band); c.fillPath()
            }
            // Fuji in the middle of the picture.
            let fuji = CGMutablePath()
            fuji.move(to: CGPoint(x: 1730, y: 400))
            fuji.addCurve(to: CGPoint(x: 2022, y: 900), control1: CGPoint(x: 1880, y: 470), control2: CGPoint(x: 1985, y: 800))
            fuji.addLine(to: CGPoint(x: 2074, y: 900))
            fuji.addCurve(to: CGPoint(x: 2366, y: 400), control1: CGPoint(x: 2111, y: 800), control2: CGPoint(x: 2216, y: 470))
            fuji.closeSubpath()
            c.setFillColor(rgb(0x4C6A8E)); c.addPath(fuji); c.fillPath()
            let snow = CGMutablePath()
            snow.move(to: CGPoint(x: 1958, y: 720))
            snow.addCurve(to: CGPoint(x: 2022, y: 900), control1: CGPoint(x: 1985, y: 800), control2: CGPoint(x: 2005, y: 860))
            snow.addLine(to: CGPoint(x: 2074, y: 900))
            snow.addCurve(to: CGPoint(x: 2138, y: 720), control1: CGPoint(x: 2091, y: 860), control2: CGPoint(x: 2111, y: 800))
            for (index, x) in stride(from: 2138, through: 1958, by: -15).enumerated() {
                snow.addLine(to: CGPoint(x: x, y: index % 2 == 0 ? 680 : 720))
            }
            snow.closeSubpath()
            c.setFillColor(rgb(0xF7F3EC)); c.addPath(snow); c.fillPath()
            c.setStrokeColor(rgb(0x1A1416, 0.6)); c.setLineWidth(3); c.addPath(fuji); c.strokePath()
            // Layered hills, farther ones paler.
            for (index, colour) in [UInt32(0x7D95B0), 0x5E7896, 0x4F6A5C].enumerated() {
                let base = CGFloat(430 - index * 50), rise = CGFloat(40 + index * 15)
                c.setFillColor(rgb(colour))
                c.move(to: CGPoint(x: 0, y: 0))
                for x in stride(from: 0, through: width, by: 64) {
                    c.addLine(to: CGPoint(x: CGFloat(x), y: base + rise * sin(CGFloat(x) / CGFloat(300 + index * 90) + CGFloat(index))))
                }
                c.addLine(to: CGPoint(x: width, y: 0)); c.closePath(); c.fillPath()
            }
            // A five-storey pagoda on the near hill.
            c.setFillColor(rgb(0x2E2A30))
            for tier in 0..<5 {
                let y = CGFloat(380 + tier * 22), half = CGFloat(30 - tier * 4), x: CGFloat = 1760
                c.move(to: CGPoint(x: x - half, y: y)); c.addLine(to: CGPoint(x: x + half, y: y))
                c.addLine(to: CGPoint(x: x + half * 0.55, y: y + 10)); c.addLine(to: CGPoint(x: x - half * 0.55, y: y + 10))
                c.closePath(); c.fillPath()
                c.fill(CGRect(x: x - half * 0.4, y: y + 10, width: half * 0.8, height: 12))
            }
            c.fill(CGRect(x: 1758, y: 490, width: 4, height: 30))
            // The garden's own green at the foot, so the ground meets the sky without a seam.
            c.setFillColor(rgb(0x7E9A5C)); c.fill(CGRect(x: 0, y: 0, width: width, height: 300))
        }
    }
}
