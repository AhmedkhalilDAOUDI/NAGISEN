import CoreText
import SceneKit

/// Kuro's hideout: an open engawa in a spring garden under Mount Fuji, with cherry trees, a koi pond,
/// flowers and a stone lantern. Kuro roams all of it on its own, jumping down off the veranda to watch
/// the koi, stalk a butterfly, sniff the flowers or doze on a warm stone, and back up to nap on the
/// zabuton. You can play with it directly: dangle a feather for it to stalk and pounce on, drop treats,
/// rub it until it purrs (or until it has had enough), call it over, or talk to it.
final class Dojo {
    enum Activity: Equatable {
        case sleeping, sunbathing, sitting, grooming, playing, watchingKoi, chasingButterfly, sniffing,
             eating, hunting, coming, purring, annoyed, listening
    }

    /// What your finger does in the garden.
    enum Hand { case look, feather, treat }

    let scene = SCNScene()
    let camera = SCNNode()
    /// Everything that turns when you drag: the hideout, the garden and Kuro.
    let stage = SCNNode()
    let kuro: KuroModel
    var mood: FamiliarCat.Mood
    var onActivity: ((Activity) -> Void)?
    private(set) var activity = Activity.sitting
    private(set) var hand = Hand.look

    /// The veranda floor's height.
    static let deck: Float = 0.32
    private let ball: SCNNode
    private let feather = SCNNode()
    private let treat: SCNNode
    private let butterfly = SCNNode()
    private var koi: [SCNNode] = []
    private let cushion = SCNVector3(-0.62, Dojo.deck + 0.07, -0.45)
    private static let pondCentre = SCNVector3(-1.9, 0, -2.4), pondRadius = (x: Float(1.6), z: Float(1.0))
    private static let sunStone = SCNVector3(2.05, 0.06, 0.55)
    private static let flowerBeds = [SCNVector3(1.75, 0, -0.35), SCNVector3(-1.75, 0, 0.85), SCNVector3(2.4, 0, -1.7)]
    /// Where the camera stands and what it looks at; the painted sky is turned to match.
    private static let eye = SCNVector3(0.3, 1.05, 2.1), focus = SCNVector3(-0.15, 0.5, -0.45)
    private let focusNode = SCNNode()
    private var running = false
    /// Bumped whenever you interrupt Kuro, so plans made before then quietly drop.
    private var plan = 0
    private var grumpyUntil = Date.distantPast
    private var pokes: [Date] = []
    private var leaping = false
    private var travelling = false
    private var featherStill = 0.0
    private var lastFeather = SCNVector3(0, 0, 0)
    private var rubTime = 0.0
    private var purr = 0.0
    private var heartClock = 0.0

    init(stage growth: FamiliarCat.Stage, mood: FamiliarCat.Mood) {
        kuro = KuroModel(stage: growth)
        self.mood = mood
        ball = Ink.part(SCNSphere(radius: 0.065), .white, image: DojoArt.temari())
        treat = Ink.part(SCNSphere(radius: 0.035), Ink.colour(0xD9824A))
        // Above the painted sky: the same deep blue its top fades into.
        scene.background.contents = Ink.colour(0x2F4E7A)
        scene.rootNode.addChildNode(stage)
        buildGarden()
        buildVeranda()
        buildLife()
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
        focusNode.position = Dojo.focus
        stage.addChildNode(focusNode)
        let look = SCNLookAtConstraint(target: focusNode)
        look.isGimbalLockEnabled = true
        camera.constraints = [look]
        scene.rootNode.addChildNode(camera)
        dressCamera()
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
            perform(.sleeping)
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

    /// Runs every frame while the hideout is open: the camera keeps Kuro in view, a purr fades,
    /// and a hunt for the feather is steered step by step.
    func update(_ dt: Double) {
        guard running else { return }
        follow(dt)
        if rubTime == 0, purr > 0 {
            purr = max(0, purr - dt * 0.6)
            kuro.lean(Float(purr))
            if purr == 0, activity == .purring { next() }
        }
        if hand == .feather, !feather.isHidden { hunt(dt) }
    }

    // MARK: What you can do

    func choose(_ newHand: Hand) {
        hand = newHand
        feather.isHidden = true
        if newHand != .feather, activity == .hunting { interrupt(); next() }
    }

    /// The feather follows your finger across the boards or the lawn.
    func moveFeather(to point: SCNVector3) {
        guard running, hand == .feather else { return }
        let resting = SCNVector3(point.x, point.y + 0.05, point.z)
        if feather.isHidden {
            feather.isHidden = false
            interrupt()
            activity = .hunting
            report(.hunting)
            lastFeather = resting
        }
        feather.position = resting
    }

    /// A treat dropped where you tap; Kuro goes for it, wherever it is.
    func dropTreat(at point: SCNVector3) {
        guard running else { return }
        interrupt()
        treat.isHidden = false
        treat.position = SCNVector3(point.x, point.y + 0.03, point.z)
        treat.opacity = 0
        treat.runAction(.fadeIn(duration: 0.2))
        activity = .eating
        report(.eating)
        let spot = approach(treat.position, from: 0.16)
        travel(to: spot, run: true) {
            self.face(toward: self.treat.position)
            self.kuro.set(.eat)
            self.after(0.6) { self.kuro.bob() }
            self.after(4.5) {
                self.treat.isHidden = true
                self.kuro.set(.sit)
                self.float("♪", Ink.colour(0xF2EADB))
                self.after(1.2) { self.next() }
            }
        }
    }

    /// Double tap: Kuro comes over to that spot.
    func call(to point: SCNVector3) {
        guard running else { return }
        if Date.now < grumpyUntil { kuro.bristle(true); float("…", Ink.colour(0xF2EADB)); return }
        interrupt()
        activity = .coming
        report(.coming)
        if kuro.pose == .sleep { kuro.set(.sit, duration: 0.6) }
        after(kuro.pose == .sleep ? 0.6 : 0) {
            self.travel(to: SCNVector3(point.x, point.y, point.z), run: true) {
                self.kuro.set(.sit)
                self.faceCamera()
                self.float("?", Ink.colour(0xF2EADB))
                self.after(5) { self.next() }
            }
        }
    }

    /// A tap on Kuro: an ear flick and a look. Three in quick succession are too many.
    func tapKuro() {
        guard running else { return }
        pokes = pokes.filter { $0.timeIntervalSinceNow > -1.6 } + [.now]
        if pokes.count >= 3 { annoy(); return }
        if activity == .sleeping { float("…", Ink.colour(0xF2EADB)); return }
        faceCamera()
        kuro.blink()
    }

    /// Your finger stroking Kuro's back: the purr builds and Kuro leans in. Too long, and it swats.
    func rub(_ amount: Double, dt: Double) {
        guard running else { return }
        if Date.now < grumpyUntil { kuro.bristle(true); return }
        if activity != .purring {
            interrupt()
            activity = .purring
            report(.purring)
            if kuro.pose != .sit { kuro.set(.sit, duration: 0.5) }
            faceCamera()
            kuro.swayTail(lively: true)
        }
        rubTime += dt
        purr = min(1, purr + amount * 3)
        kuro.lean(Float(purr))
        heartClock -= dt
        if purr > 0.4, heartClock <= 0 { float("♥", Ink.colour(0xE07A92)); heartClock = 0.7 }
        if rubTime > 7 { rubTime = 0; purr = 0; kuro.swipePaw(); annoy() }
    }

    func endRub() { rubTime = 0 }

    /// How strongly Kuro is purring right now, 0…1, for the haptics.
    var purring: Double { activity == .purring ? purr : 0 }

    /// Too much: ears back, a hiss, and Kuro takes itself off somewhere away from you for a while.
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
            let away = SCNVector3(-2.4, 0, Float.random(in: -0.6...0.4))
            self.travel(to: away, run: true) {
                self.face(toward: SCNVector3(-4, 0, -3))
                self.kuro.set(.sit)
                self.after(6) { self.kuro.bristle(false); self.after(4) { self.next() } }
            }
        }
    }

    /// While you talk, Kuro comes to the front of the veranda and sits facing you.
    func listen() {
        guard running, activity != .listening else { return }
        interrupt()
        activity = .listening
        report(.listening)
        if kuro.pose == .sleep { kuro.set(.sit, duration: 1) }
        after(kuro.pose == .sleep ? 1 : 0) {
            self.travel(to: SCNVector3(0.05, Dojo.deck, 0.3), run: false) {
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
        leaping = false
        travelling = false
    }

    private func report(_ activity: Activity) {
        DispatchQueue.main.async { self.onActivity?(activity) }
    }

    private func next() {
        guard running else { return }
        perform(choose())
    }

    /// What to do next, weighted by mood: a resting Kuro mostly dozes, a bright one is out hunting and playing.
    private func choose() -> Activity {
        let weights: [(Activity, Double)] = switch mood {
        case .resting: [(.sleeping, 0.45), (.sunbathing, 0.25), (.grooming, 0.15), (.watchingKoi, 0.15)]
        case .calm: [(.sleeping, 0.2), (.sunbathing, 0.15), (.grooming, 0.15), (.watchingKoi, 0.2), (.sniffing, 0.15),
                     (.sitting, 0.1), (.chasingButterfly, 0.05)]
        case .bright: [(.chasingButterfly, 0.25), (.playing, 0.2), (.watchingKoi, 0.15), (.sniffing, 0.15), (.grooming, 0.1),
                       (.sitting, 0.05), (.sleeping, 0.1)]
        }
        let open = weights.filter { $0.0 != activity }
        var roll = Double.random(in: 0..<open.map(\.1).reduce(0, +))
        for (choice, weight) in open {
            roll -= weight
            if roll < 0 { return choice }
        }
        return open.first?.0 ?? .sitting
    }

    private func perform(_ choice: Activity) {
        activity = choice
        report(choice)
        switch choice {
        case .sleeping:
            nap(at: cushion, facing: SCNVector3(0.4, Dojo.deck, 0.6))
        case .sunbathing:
            nap(at: Dojo.sunStone, facing: SCNVector3(0, 0, 3))
        case .grooming:
            let spot = Bool.random() ? SCNVector3(Float.random(in: -0.8...0.8), Dojo.deck, Float.random(in: -0.2...0.6))
                                     : SCNVector3(Float.random(in: 1.5...2.4), 0, Float.random(in: 0.2...1.2))
            travel(to: spot, run: false) {
                self.faceCamera()
                self.kuro.set(.groom, duration: 0.5)
                self.kuro.groomCycle()
                self.after(4.5) { self.kuro.set(.sit); self.after(.random(in: 2...4)) { self.next() } }
            }
        case .watchingKoi:
            // Sits on the bank with its eyes on the fish; now and then a paw dips at one.
            let bank = SCNVector3(-1.0, 0, -1.75)
            travel(to: bank, run: false) {
                self.face(toward: Dojo.pondCentre)
                self.kuro.set(.sit)
                self.kuro.swayTail(lively: true)
                self.kuro.lookAround()
                self.after(3) { self.kuro.set(.swipe, duration: 0.3); self.after(0.35) { self.kuro.swipePaw(); self.ripple() } }
                self.after(4.2) { self.kuro.set(.sit, duration: 0.4) }
                self.after(.random(in: 9...13)) { self.next() }
            }
        case .chasingButterfly:
            stalkButterfly(rounds: 2)
        case .sniffing:
            let bed = Dojo.flowerBeds.randomElement()!
            travel(to: approach(bed, from: 0.3), run: false) {
                self.face(toward: bed)
                self.kuro.set(.eat, duration: 0.5)
                self.after(0.5) { self.kuro.bob() }
                self.after(3.2) {
                    self.kuro.set(.sit)
                    if Bool.random() { self.float("くしゅん", Ink.colour(0xF2EADB)); self.kuro.hop() }
                    self.after(2) { self.next() }
                }
            }
        case .playing:
            play(rounds: 3)
        case .sitting, .eating, .hunting, .coming, .purring, .annoyed, .listening:
            let spot = SCNVector3(Float.random(in: -0.9...0.9), Dojo.deck, Float.random(in: -0.3...0.7))
            travel(to: spot, run: false) {
                self.face(toward: SCNVector3(-1.5, 0, -6))
                self.kuro.set(.sit)
                self.kuro.breathe()
                self.kuro.swayTail(lively: self.mood == .bright)
                self.after(1.2) { self.kuro.lookAround() }
                self.after(.random(in: 6...9)) { self.next() }
            }
        }
    }

    private func nap(at spot: SCNVector3, facing: SCNVector3) {
        travel(to: spot, run: false) {
            self.face(toward: facing)
            self.kuro.set(.sleep, duration: 1.2)
            self.kuro.breathe()
            self.kuro.swayTail(lively: false)
            self.floatZs()
            self.after(.random(in: 14...22)) { self.stopZs(); self.kuro.set(.sit); self.after(1) { self.next() } }
        }
    }

    /// Walk up to the ball, bat it, watch it roll, and go after it again.
    private func play(rounds: Int) {
        guard rounds > 0 else { after(0.8) { self.next() }; return }
        travel(to: approach(ball.position, from: 0.2), run: true) {
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
        let distance = hypot(Float(to.x - ball.position.x), Float(to.z - ball.position.z))
        let move = SCNAction.move(to: to, duration: Double(distance) / 0.5 + 0.3)
        move.timingMode = .easeOut
        let spin = SCNAction.rotateBy(x: CGFloat(distance / 0.065), y: 0, z: 0, duration: move.duration)
        spin.timingMode = .easeOut
        ball.runAction(.group([move, spin]))
    }

    /// Creep up on the butterfly, wiggle, pounce: it always gets away, up and over to the next flower.
    private func stalkButterfly(rounds: Int) {
        guard rounds > 0 else { after(1) { self.next() }; return }
        let flutter = butterfly.presentation.position
        let ground = SCNVector3(Float(flutter.x), 0, Float(flutter.z))
        travel(to: approach(ground, from: 0.6), run: false) {
            self.face(toward: ground)
            self.kuro.set(.crouch, duration: 0.4)
            self.after(0.5) {
                self.kuro.walkCycle()
                let creep = SCNAction.move(to: self.approach(ground, from: 0.35), duration: 1.6)
                self.kuro.root.runAction(creep)
                self.after(1.7) {
                    self.kuro.standStill()
                    self.kuro.wiggle()
                    self.after(0.8) {
                        self.leap(to: ground) {
                            self.flyButterfly(far: true)
                            self.kuro.set(.sit, duration: 0.4)
                            self.float("!", Ink.colour(0xF2EADB))
                            self.after(1.5) { self.stalkButterfly(rounds: rounds - 1) }
                        }
                    }
                }
            }
        }
    }

    /// One step of a hunt for the feather: run when it is far, creep when close, pounce when it holds still.
    private func hunt(_ dt: Double) {
        guard !leaping, !travelling else { return }
        let target = feather.position
        let here = kuro.root.position
        let ground = SCNVector3(Float(target.x), Float(target.y) - 0.05, Float(target.z))
        if onDeck(here) != onDeck(ground) {
            travel(to: approach(ground, from: 0.4), run: true) {}
            return
        }
        let moved = hypot(Float(target.x - lastFeather.x), Float(target.z - lastFeather.z))
        featherStill = moved < 0.01 ? featherStill + dt : 0
        lastFeather = target
        let dx = Float(target.x - here.x), dz = Float(target.z - here.z)
        let distance = hypot(dx, dz)
        let yaw = atan2(dx, dz)
        kuro.root.eulerAngles.y = .init(Self.turn(Float(kuro.root.eulerAngles.y), toward: yaw, by: Float(dt) * 6))
        if distance > 0.55 {
            if kuro.pose != .stand { kuro.set(.stand, duration: 0.2); kuro.runCycle() }
            step(dx, dz, distance, speed: 0.9, dt)
        } else if distance > 0.2 {
            if kuro.pose != .crouch { kuro.set(.crouch, duration: 0.3); kuro.walkCycle() }
            step(dx, dz, distance, speed: featherStill > 0.3 ? 0 : 0.18, dt)
            if featherStill > 0.6 {
                featherStill = 0
                kuro.standStill()
                kuro.wiggle()
                leaping = true
                after(0.7) {
                    self.leaping = false
                    self.leap(to: ground) {
                        self.kuro.set(.swipe, duration: 0.2)
                        self.kuro.swipePaw()
                        self.float("!", Ink.colour(0xF2EADB))
                        self.after(0.6) { self.kuro.set(.crouch, duration: 0.3) }
                    }
                }
            }
        } else if kuro.pose != .swipe {
            kuro.standStill()
            kuro.set(.swipe, duration: 0.2)
            kuro.swipePaw()
        }
    }

    private func step(_ dx: Float, _ dz: Float, _ distance: Float, speed: Float, _ dt: Double) {
        guard distance > 0.001, speed > 0 else { return }
        let move = min(distance, speed * Float(dt))
        let here = kuro.root.position
        kuro.root.position = SCNVector3(Float(here.x) + dx / distance * move, Float(here.y), Float(here.z) + dz / distance * move)
    }

    private static func turn(_ from: Float, toward to: Float, by amount: Float) -> Float {
        var delta = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi } else if delta < -.pi { delta += 2 * .pi }
        return from + max(-amount, min(amount, delta))
    }

    // MARK: Getting around

    private func onDeck(_ point: SCNVector3) -> Bool {
        abs(Float(point.x)) < 1.3 && abs(Float(point.z)) < 1.0 && Float(point.y) > 0.1
    }

    /// A spot just short of `target`, on Kuro's side of it.
    private func approach(_ target: SCNVector3, from gap: Float) -> SCNVector3 {
        let here = kuro.root.position
        let dx = Float(here.x - target.x), dz = Float(here.z - target.z)
        let length = max(hypot(dx, dz), 0.001)
        let y: Float = onDeck(SCNVector3(Float(target.x), Dojo.deck, Float(target.z))) && Float(target.y) > 0.1 ? Dojo.deck : 0
        return SCNVector3(Float(target.x) + dx / length * gap, y, Float(target.z) + dz / length * gap)
    }

    /// Walks (or runs) anywhere: across the boards, down off the veranda with a jump, around the pond, and back up.
    private func travel(to target: SCNVector3, run: Bool, then done: @escaping () -> Void) {
        travelling = true
        let ticket = plan
        let finish = { if self.plan == ticket { self.travelling = false; done() } }
        let here = kuro.root.position
        let fromDeck = onDeck(here), toDeck = onDeck(target)
        if fromDeck == toDeck {
            walk(along: toDeck ? [target] : groundRoute(from: here, to: target), run: run, then: finish)
            return
        }
        // Cross the veranda's edge on the side nearest where Kuro is headed.
        let outside = toDeck ? here : target
        let edge = Self.edge(toward: outside)
        if fromDeck {
            walk(along: [edge.top], run: run) {
                self.leap(to: edge.bottom) { self.walk(along: self.groundRoute(from: edge.bottom, to: target), run: run, then: finish) }
            }
        } else {
            walk(along: groundRoute(from: here, to: edge.bottom), run: run) {
                self.leap(to: edge.top) { self.walk(along: [target], run: run, then: finish) }
            }
        }
    }

    private static func edge(toward point: SCNVector3) -> (top: SCNVector3, bottom: SCNVector3) {
        let x = Float(point.x), z = Float(point.z)
        if abs(x) > 1.3 || z < 0.9 {
            let side: Float = x < 0 ? -1 : 1
            let along = max(-0.75, min(0.75, z))
            return (SCNVector3(1.15 * side, Dojo.deck, along), SCNVector3(1.55 * side, 0, along))
        }
        let along = max(-1.0, min(1.0, x))
        return (SCNVector3(along, Dojo.deck, 0.85), SCNVector3(along, 0, 1.3))
    }

    /// Straight there, unless that crosses the pond: then around its nearer end.
    private func groundRoute(from: SCNVector3, to: SCNVector3) -> [SCNVector3] {
        let centre = Dojo.pondCentre, rx = Dojo.pondRadius.x + 0.35, rz = Dojo.pondRadius.z + 0.35
        let crosses = (1..<10).contains { index in
            let t = Float(index) / 10
            let x = (Float(from.x) + (Float(to.x) - Float(from.x)) * t - Float(centre.x)) / rx
            let z = (Float(from.z) + (Float(to.z) - Float(from.z)) * t - Float(centre.z)) / rz
            return x * x + z * z < 1
        }
        guard crosses else { return [to] }
        let around = Float(from.x) + Float(to.x) < 2 * Float(centre.x) ? Float(centre.x) - rx - 0.2 : Float(centre.x) + rx + 0.2
        return [SCNVector3(around, 0, Float(centre.z) + rz * 0.2), to]
    }

    private func walk(along points: [SCNVector3], run: Bool, then done: @escaping () -> Void) {
        guard let point = points.first else { done(); return }
        let ticket = plan
        let from = kuro.root.position
        let distance = hypot(Float(point.x - from.x), Float(point.z - from.z))
        let destination = SCNVector3(Float(point.x), Float(point.y), Float(point.z))
        guard distance > 0.05 else {
            kuro.root.runAction(.move(to: destination, duration: 0.25)) {
                DispatchQueue.main.async { if self.plan == ticket { self.walk(along: Array(points.dropFirst()), run: run, then: done) } }
            }
            return
        }
        face(toward: point)
        if kuro.pose != .stand { kuro.set(.stand, duration: 0.35) }
        after(kuro.pose == .stand ? 0.05 : 0.35) {
            if run { self.kuro.runCycle() } else { self.kuro.walkCycle() }
            let move = SCNAction.move(to: destination, duration: Double(distance) / (run ? 0.75 : 0.26))
            self.kuro.root.runAction(move) {
                DispatchQueue.main.async {
                    guard self.plan == ticket else { return }
                    self.kuro.standStill()
                    self.walk(along: Array(points.dropFirst()), run: run, then: done)
                }
            }
        }
    }

    /// A crouch, a spring in an arc and a soft landing.
    private func leap(to point: SCNVector3, then done: @escaping () -> Void) {
        let ticket = plan
        leaping = true
        face(toward: point)
        kuro.standStill()
        kuro.set(.crouch, duration: 0.2)
        after(0.25) {
            self.kuro.set(.pounce, duration: 0.15)
            let start = self.kuro.root.position
            let end = point
            let duration = 0.5
            let rise = max(Float(start.y), Float(end.y)) + 0.22
            let arc = SCNAction.customAction(duration: duration) { node, elapsed in
                let t = Float(elapsed / CGFloat(duration))
                let x = Float(start.x) + (Float(end.x) - Float(start.x)) * t
                let z = Float(start.z) + (Float(end.z) - Float(start.z)) * t
                let base = Float(start.y) + (Float(end.y) - Float(start.y)) * t
                let lift = 4 * t * (1 - t) * (rise - max(Float(start.y), Float(end.y)))
                node.position = SCNVector3(x, base + lift, z)
            }
            self.kuro.root.runAction(arc) {
                DispatchQueue.main.async {
                    guard self.plan == ticket else { return }
                    self.kuro.root.position = SCNVector3(Float(end.x), Float(end.y), Float(end.z))
                    self.kuro.set(.crouch, duration: 0.15)
                    self.after(0.2) { self.leaping = false; done() }
                }
            }
        }
    }

    /// Points Kuro at a spot on the stage.
    private func face(toward point: SCNVector3) {
        let yaw = atan2(Float(point.x - kuro.root.position.x), Float(point.z - kuro.root.position.z))
        kuro.root.runAction(.rotateTo(x: 0, y: CGFloat(yaw), z: 0, duration: 0.35, usesShortestUnitArc: true))
    }

    /// The camera sits outside the turning stage, so it is found from the stage's point of view.
    private func faceCamera() {
        face(toward: stage.convertPosition(camera.position, from: nil))
    }

    /// Eases the camera toward Kuro, so it stays in view out in the garden without the view lurching.
    private func follow(_ dt: Double) {
        let at = kuro.root.position
        let wanted = SCNVector3(Float(Dojo.focus.x) + (Float(at.x) - 0.0) * 0.55, Float(Dojo.focus.y) + (Float(at.y) - Dojo.deck) * 0.5,
                                Float(Dojo.focus.z) + (Float(at.z) - 0.2) * 0.5)
        let blend = Float(min(1, dt * 1.6))
        let now = focusNode.position
        focusNode.position = SCNVector3(Float(now.x) + (Float(wanted.x) - Float(now.x)) * blend,
                                        Float(now.y) + (Float(wanted.y) - Float(now.y)) * blend,
                                        Float(now.z) + (Float(wanted.z) - Float(now.z)) * blend)
        let shift = stage.convertPosition(focusNode.position, to: nil)
        let eye = SCNVector3(Float(Dojo.eye.x) + (Float(shift.x) - Float(Dojo.focus.x)) * 0.6, Float(Dojo.eye.y),
                             Float(Dojo.eye.z) + (Float(shift.z) - Float(Dojo.focus.z)) * 0.35)
        let current = camera.position
        camera.position = SCNVector3(Float(current.x) + (Float(eye.x) - Float(current.x)) * blend, Float(eye.y),
                                     Float(current.z) + (Float(eye.z) - Float(current.z)) * blend)
        if let lens = camera.camera { lens.focusDistance = CGFloat(distanceToKuro()) }
    }

    private func distanceToKuro() -> Float {
        let at = stage.convertPosition(kuro.root.position, to: nil), eye = camera.position
        return sqrt(pow(Float(at.x - eye.x), 2) + pow(Float(at.y - eye.y), 2) + pow(Float(at.z - eye.z), 2))
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
        node.position = SCNVector3(Float(kuro.root.position.x), Float(kuro.root.position.y) + 0.45, Float(kuro.root.position.z))
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

    // MARK: Garden life: koi, a butterfly, flowers, a warm stone, the feather and the treat

    private func buildLife() {
        // Koi circling slowly under the pond's surface.
        for (index, colours) in [(0xE8663A, 0xF5F0E6), (0xF5F0E6, 0xD64A3A), (0xE9A23B, 0x2A2524)].enumerated() {
            let fish = SCNNode()
            let body = Ink.part(SCNSphere(radius: 0.07), Ink.colour(UInt32(colours.0)))
            body.scale = SCNVector3(0.55, 0.35, 1.5)
            let patch = Ink.part(SCNSphere(radius: 0.045), Ink.colour(UInt32(colours.1)), outlined: false)
            patch.scale = SCNVector3(0.6, 0.4, 1.2)
            patch.position = SCNVector3(0, 0.012, 0.02)
            let fin = Ink.part(SCNCone(topRadius: 0, bottomRadius: 0.04, height: 0.06), Ink.colour(UInt32(colours.0)), outlined: false)
            fin.eulerAngles.x = .init(-Float.pi / 2)
            fin.position = SCNVector3(0, 0, -0.12)
            [body, patch, fin].forEach(fish.addChildNode)
            let orbit = SCNNode()
            orbit.position = SCNVector3(Float(Dojo.pondCentre.x), 0.014, Float(Dojo.pondCentre.z))
            fish.position = SCNVector3(0.5 + Float(index) * 0.18, 0, 0)
            orbit.addChildNode(fish)
            orbit.scale = SCNVector3(1.5, 1, 0.9)
            let lap: CGFloat = index % 2 == 0 ? 2 * .pi : -2 * .pi
            orbit.runAction(.repeatForever(.rotateBy(x: 0, y: lap, z: 0, duration: 14 + Double(index) * 4)))
            fish.runAction(.repeatForever(.sequence([.rotateBy(x: 0, y: 0.25, z: 0, duration: 0.4), .rotateBy(x: 0, y: -0.25, z: 0, duration: 0.4)])))
            stage.addChildNode(orbit)
            koi.append(fish)
        }
        // A flat stone that catches the afternoon sun.
        let stone = Ink.part(SCNCylinder(radius: 0.32, height: 0.12), Ink.colour(0x9C988E))
        stone.scale = SCNVector3(1.3, 1, 1)
        add(stone, Float(Dojo.sunStone.x), 0.0, Float(Dojo.sunStone.z))
        // Little beds of flowers: white, yellow and violet heads on green stems.
        var generator = SeededRandom(seed: 5)
        for bed in Dojo.flowerBeds {
            for _ in 0..<14 {
                let colour: UInt32 = [0xF4F0E6, 0xF2C94C, 0x9B7BC8, 0xE88FA6][generator.int(0...3)]
                let x = Float(bed.x) + Float(generator.double(-0.3...0.3)), z = Float(bed.z) + Float(generator.double(-0.25...0.25))
                let height = Float(generator.double(0.08...0.18))
                let stem = Ink.part(SCNCylinder(radius: 0.006, height: CGFloat(height)), Ink.colour(0x4F6E3A), outlined: false)
                add(stem, x, height / 2, z)
                let bloom = Ink.part(SCNSphere(radius: 0.025), Ink.colour(colour))
                bloom.scale = SCNVector3(1, 0.6, 1)
                add(bloom, x, height, z)
            }
        }
        // The butterfly: two wings flapping, drifting from flower to flower.
        for side in [-1.0, 1.0] {
            let wing = Ink.part(SCNPlane(width: 0.06, height: 0.05), Ink.colour(0xF2E8D5), outlined: false)
            wing.geometry?.firstMaterial?.isDoubleSided = true
            wing.geometry?.firstMaterial?.diffuse.contents = DojoArt.wing()
            wing.pivot = SCNMatrix4MakeTranslation(.init(-0.03 * side), 0, 0)
            wing.eulerAngles.x = .init(-Float.pi / 2)
            let flap = SCNAction.rotateBy(x: 0, y: 0, z: CGFloat(0.9 * side), duration: 0.12)
            wing.runAction(.repeatForever(.sequence([flap, flap.reversed()])))
            butterfly.addChildNode(wing)
        }
        butterfly.position = SCNVector3(Float(Dojo.flowerBeds[0].x), 0.35, Float(Dojo.flowerBeds[0].z))
        stage.addChildNode(butterfly)
        flyButterfly(far: false)

        // The feather toy: a tuft of red and cream feathers on a string from the wand above.
        let tuft = SCNNode()
        for (index, colour) in [0xB0283A, 0xF2EADB, 0xB0283A].enumerated() {
            let plume = Ink.part(SCNCone(topRadius: 0.002, bottomRadius: 0.018, height: 0.11), Ink.colour(UInt32(colour)))
            plume.eulerAngles = SCNVector3(0.5, 0, Float(index - 1) * 0.5)
            tuft.addChildNode(plume)
        }
        let string = Ink.part(SCNCylinder(radius: 0.0015, height: 1.2), Ink.colour(0x2A2524), outlined: false)
        string.position.y = 0.6
        feather.addChildNode(tuft)
        feather.addChildNode(string)
        feather.isHidden = true
        tuft.runAction(.repeatForever(.sequence([.rotateBy(x: 0, y: 0, z: 0.3, duration: 0.25), .rotateBy(x: 0, y: 0, z: -0.3, duration: 0.25)])))
        stage.addChildNode(feather)
        treat.isHidden = true
        treat.scale = SCNVector3(1.4, 0.5, 0.6)
        stage.addChildNode(treat)
    }

    /// Off to another flower, drifting with little rises and dips.
    private func flyButterfly(far: Bool) {
        guard let bed = Dojo.flowerBeds.randomElement() else { return }
        let to = SCNVector3(Float(bed.x) + Float.random(in: -0.3...0.3), Float.random(in: 0.22...0.45), Float(bed.z) + Float.random(in: -0.3...0.3))
        let upAndOver = SCNAction.sequence([.moveBy(x: 0, y: far ? 0.5 : 0.1, z: 0, duration: far ? 0.6 : 0.3), .move(to: to, duration: 2.4)])
        upAndOver.timingMode = .easeInEaseOut
        let yaw = atan2(Float(to.x - butterfly.position.x), Float(to.z - butterfly.position.z))
        butterfly.runAction(.sequence([.rotateTo(x: 0, y: CGFloat(yaw), z: 0, duration: 0.2), upAndOver,
                                       .wait(duration: 2.5, withRange: 2),
                                       .run { [weak self] _ in DispatchQueue.main.async { self?.flyButterfly(far: false) } }]),
                              forKey: "flight")
    }

    /// A ring spreading on the water where a paw dipped.
    private func ripple() {
        let ring = Ink.part(SCNTorus(ringRadius: 0.05, pipeRadius: 0.004), Ink.colour(0xEAF3F8), outlined: false, glow: 0.5)
        ring.position = SCNVector3(-1.15, 0.02, -2.0)
        stage.addChildNode(ring)
        ring.runAction(.sequence([.group([.scale(to: 5, duration: 1.4), .fadeOut(duration: 1.4)]), .removeFromParentNode()]))
    }

    // MARK: Light and lens

    /// Ambient occlusion in the corners, a soft bloom on the lantern and water, a touch of grading and
    /// a shallow focus that follows Kuro, so the picture has depth instead of flat colour.
    private func dressCamera() {
        guard let lens = camera.camera else { return }
        lens.wantsHDR = true
        lens.wantsExposureAdaptation = false
        lens.exposureOffset = 0.1
        lens.bloomIntensity = 0.35
        lens.bloomThreshold = 0.85
        lens.bloomBlurRadius = 10
        lens.screenSpaceAmbientOcclusionIntensity = 1.1
        lens.screenSpaceAmbientOcclusionRadius = 0.22
        lens.screenSpaceAmbientOcclusionBias = 0.03
        lens.vignettingIntensity = 0.5
        lens.vignettingPower = 0.9
        lens.saturation = 1.08
        lens.contrast = 0.06
        lens.wantsDepthOfField = true
        lens.fStop = 7
        lens.focusDistance = 1.8
        lens.focalBlurSampleCount = 8
    }

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
        let bowl = SCNVector3(0.68, deck, -0.5)
        add(foodBowl(), Float(bowl.x), deck, Float(bowl.z))
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
        // The pond: a dark bed, the koi above it, and a clear rippling surface over both.
        let bed = Ink.part(SCNCylinder(radius: 1.0, height: 0.004), Ink.colour(0x2C4656), outlined: false)
        bed.scale = SCNVector3(1.6, 1, 1)
        add(bed, -1.9, 0.004, -2.4)
        let pond = Ink.part(SCNCylinder(radius: 1.0, height: 0.01), Ink.colour(0x6E9EBE), outlined: false, glow: 0.12)
        pond.scale = SCNVector3(1.6, 1, 1)
        pond.geometry?.firstMaterial?.transparency = 0.55
        pond.geometry?.firstMaterial?.writesToDepthBuffer = false
        // Slow crossing ripples: the normal is bent by two moving waves, so the flat bands of light drift.
        pond.geometry?.firstMaterial?.shaderModifiers?[.surface] = """
        float2 p = _surface.diffuseTexcoord * 14.0;
        float t = scn_frame.time;
        _surface.normal = normalize(_surface.normal + float3(sin(p.x * 1.7 + t * 1.2) * 0.35, 0.0, cos(p.y * 1.3 + t * 0.9) * 0.35));
        """
        add(pond, -1.9, 0.03, -2.4)
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
        stage.addChildNode(grass())
    }

    /// Tufts of grass all over the lawn as four meshes of thin blades, one per shade of green, so
    /// thousands of blades cost four draws.
    private func grass() -> SCNNode {
        var generator = SeededRandom(seed: 13)
        let greens: [UInt32] = [0x5E7D3E, 0x6C8B47, 0x7FA052, 0x4F6E35]
        var points: [[SCNVector3]] = Array(repeating: [], count: greens.count)
        var placed = 0
        while placed < 1100 {
            let x = Float(generator.double(-4.6...4.6)), z = Float(generator.double(-4.2...3.0))
            let px = (x - Float(Dojo.pondCentre.x)) / 1.85, pz = (z - Float(Dojo.pondCentre.z)) / 1.2
            guard hypot(x, z) < 4.8, !(abs(x) < 1.45 && abs(z) < 1.15), px * px + pz * pz > 1 else { continue }
            for _ in 0..<4 {
                let angle = Float(generator.double(0...(2 * Double.pi)))
                let lean = Float(generator.double(0.01...0.04)), height = Float(generator.double(0.06...0.14)), width: Float = 0.012
                let bx = x + Float(generator.double(-0.04...0.04)), bz = z + Float(generator.double(-0.04...0.04))
                let sx = -sin(angle) * width, sz = cos(angle) * width
                points[generator.int(0...3)] += [SCNVector3(bx - sx, 0, bz - sz), SCNVector3(bx + sx, 0, bz + sz),
                                                 SCNVector3(bx + cos(angle) * lean, height, bz + sin(angle) * lean)]
            }
            placed += 1
        }
        let field = SCNNode()
        for (shade, blades) in points.enumerated() where !blades.isEmpty {
            let normals = Array(repeating: SCNVector3(0, 1, 0), count: blades.count)
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: blades), SCNGeometrySource(normals: normals)],
                                       elements: [SCNGeometryElement(indices: (0..<Int32(blades.count)).map { $0 }, primitiveType: .triangles)])
            let material = Ink.material(Ink.colour(greens[shade]))
            material.isDoubleSided = true
            // No rim light here: a blade is all edge, so it would glow white.
            material.shaderModifiers?[.fragment] = nil
            geometry.materials = [material]
            field.addChildNode(SCNNode(geometry: geometry))
        }
        return field
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
                // Grain: long wavering lines along each plank, with the odd knot.
                c.setStrokeColor(rgb(0x6B4A33, 0.35)); c.setLineWidth(1)
                for line in 0..<5 {
                    let base = CGFloat(y) + 5 + CGFloat(line) * 7, wave = CGFloat(generator.double(1...3))
                    c.move(to: CGPoint(x: 0, y: base))
                    for x in stride(from: 0, through: 512, by: 16) {
                        c.addLine(to: CGPoint(x: CGFloat(x), y: base + wave * sin(CGFloat(x) / 40 + CGFloat(line))))
                    }
                    c.strokePath()
                }
                if generator.double(0...1) > 0.6 {
                    let knot = CGFloat(generator.double(40...470))
                    c.setStrokeColor(rgb(0x4A3426, 0.5)); c.strokeEllipse(in: CGRect(x: knot, y: CGFloat(y) + 12, width: 16, height: 9))
                }
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

    /// A swallowtail-ish wing: cream with an ink edge and a red eye-spot.
    static func wing() -> CGImage {
        draw(64, 64) { c in
            c.setFillColor(rgb(0xF4ECD8)); c.fillEllipse(in: CGRect(x: 4, y: 8, width: 56, height: 48))
            c.setStrokeColor(rgb(0x1A1416)); c.setLineWidth(4); c.strokeEllipse(in: CGRect(x: 4, y: 8, width: 56, height: 48))
            c.setFillColor(rgb(0xB0283A)); c.fillEllipse(in: CGRect(x: 36, y: 26, width: 12, height: 12))
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
