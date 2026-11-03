import SceneKit
#if canImport(UIKit)
import UIKit
typealias InkColor = UIColor
#else
import AppKit
typealias InkColor = NSColor
#endif

/// The materials shared by Kuro and the hideout: physically based, so they take their light from the real
/// sky around the garden, with photographed wood, straw, stone and bark where the scene has them.
enum Ink {
    static let sumi = InkColor(red: 0.09, green: 0.07, blue: 0.08, alpha: 1)

    /// The folder of real textures and models (Poly Haven, CC0). Tools outside the app can point at it with NAGISEN_HIDEOUT.
    static let assets: URL? = Bundle.main.url(forResource: "Hideout", withExtension: nil)
        ?? ProcessInfo.processInfo.environment["NAGISEN_HIDEOUT"].map { URL(fileURLWithPath: $0) }

    static func colour(_ hex: UInt32) -> InkColor {
        InkColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                 blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    static func material(_ colour: InkColor, glow: CGFloat = 0, roughness: CGFloat = 0.8) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = colour
        material.roughness.contents = roughness
        material.metalness.contents = 0.0
        if glow > 0 { material.emission.contents = colour; material.emission.intensity = glow }
        return material
    }

    static func material(image: CGImage, roughness: CGFloat = 0.8) -> SCNMaterial {
        let material = material(.white, roughness: roughness)
        material.diffuse.contents = image
        return material
    }

    /// A photographed surface: colour, bumps and roughness, repeated `tile` times across the shape.
    static func surface(_ name: String, tile: (CGFloat, CGFloat) = (1, 1), fallback: InkColor) -> SCNMaterial {
        let material = material(fallback)
        guard let folder = assets else { return material }
        let scale = SCNMatrix4MakeScale(.init(tile.0), .init(tile.1), 1)
        for (property, suffix) in [(material.diffuse, "diff"), (material.normal, "nor"), (material.roughness, "rough")] {
            let url = folder.appendingPathComponent("\(name)_\(suffix).jpg")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            property.contents = url
            property.wrapS = .repeat
            property.wrapT = .repeat
            property.contentsTransform = scale
            property.mipFilter = .linear
        }
        return material
    }

    /// A node for the shape in this colour, or painted with `image`, or dressed in `surface`.
    static func part(_ geometry: SCNGeometry, _ colour: InkColor, image: CGImage? = nil, surface: SCNMaterial? = nil,
                     glow: CGFloat = 0, roughness: CGFloat = 0.8) -> SCNNode {
        geometry.materials = [surface ?? image.map { material(image: $0, roughness: roughness) } ?? material(colour, glow: glow, roughness: roughness)]
        return SCNNode(geometry: geometry)
    }
}

/// Kuro in 3D: a calico (mike-neko) built from soft shapes, white with orange and black tabby patches,
/// with golden eyes, a red collar and, as Kuro grows, a gold bell and finally a dojo master's headband.
final class KuroModel {
    enum Pose { case sit, stand, sleep, eat, swipe, crouch, pounce, groom }

    static let fur = Ink.colour(0xF3EDE2)
    static let ginger = Ink.colour(0xD07A3A)
    static let black = Ink.colour(0x2A2524)
    static let muzzle = Ink.colour(0xFBF7EF)
    static let amber = Ink.colour(0xCDB54C)
    static let pink = Ink.colour(0xD98DA0)
    static let red = Ink.colour(0xA3283F)
    static let gold = Ink.colour(0xD8B04A)
    static let cloth = Ink.colour(0xF2EADB)

    let root = SCNNode()
    private let body: SCNNode
    private let head = SCNNode()
    private let legs: [SCNNode]
    private let haunches: [SCNNode]
    private let tail: [SCNNode]
    private let eyes: [SCNNode]
    private let lids: [SCNNode]
    private let collar = SCNNode()
    private let bell: SCNNode
    private let headband = SCNNode()
    private var ears: [SCNNode] = []
    private(set) var pose = Pose.sit

    init(stage: FamiliarCat.Stage) {
        root.name = "Kuro"
        body = Ink.part(SCNSphere(radius: 0.15), Self.fur, image: Calico.body)
        root.addChildNode(body)

        // Head: a wide soft ball, ears, a slightly lighter muzzle, nose and whiskers.
        head.addChildNode(Ink.part(SCNSphere(radius: 0.125), Self.fur, image: Calico.head))
        head.childNodes.first?.scale = SCNVector3(1.12, 0.94, 0.96)
        for side in [-1.0, 1.0] {
            let ear = Ink.part(SCNCone(topRadius: 0.004, bottomRadius: 0.052, height: 0.1), side < 0 ? Self.ginger : Self.black)
            ear.position = SCNVector3(0.07 * side, 0.1, -0.01)
            ear.eulerAngles = SCNVector3(-0.12, 0, -0.38 * side)
            let inner = Ink.part(SCNCone(topRadius: 0.002, bottomRadius: 0.03, height: 0.065), Self.pink)
            inner.position = SCNVector3(0, -0.008, 0.02)
            ear.addChildNode(inner)
            head.addChildNode(ear)
            ears.append(ear)
        }
        let snout = Ink.part(SCNSphere(radius: 0.05), Self.muzzle)
        snout.position = SCNVector3(0, -0.035, 0.095)
        snout.scale = SCNVector3(1.25, 0.8, 0.7)
        head.addChildNode(snout)
        let nose = Ink.part(SCNSphere(radius: 0.012), Self.pink)
        nose.position = SCNVector3(0, -0.02, 0.13)
        head.addChildNode(nose)
        for side in [-1.0, 1.0] {
            for (index, tilt) in [0.12, -0.05].enumerated() {
                let whisker = Ink.part(SCNCylinder(radius: 0.0018, height: 0.13), Self.cloth)
                whisker.position = SCNVector3(0.085 * side, -0.035 - 0.012 * Double(index), 0.1)
                whisker.eulerAngles = SCNVector3(0, 0.25 * side, .pi / 2 + tilt * side)
                head.addChildNode(whisker)
            }
        }
        var eyes: [SCNNode] = [], lids: [SCNNode] = []
        for side in [-1.0, 1.0] {
            let eye = Ink.part(SCNSphere(radius: 0.026), Self.amber, glow: 0.25)
            // Almond eyes tilted up at the outer corner, the way cats are drawn in ukiyo-e prints.
            eye.position = SCNVector3(0.052 * side, 0.016, 0.1)
            eye.scale = SCNVector3(1.2, 0.74, 0.55)
            eye.eulerAngles = SCNVector3(0, 0, 0.24 * side)
            let pupil = Ink.part(SCNSphere(radius: 0.02), Ink.sumi)
            pupil.scale = SCNVector3(0.3, 1, 0.6)
            pupil.position = SCNVector3(0, 0, 0.012)
            eye.addChildNode(pupil)
            let shine = Ink.part(SCNSphere(radius: 0.006), .white, glow: 1)
            shine.position = SCNVector3(0.008 * side, 0.009, 0.02)
            eye.addChildNode(shine)
            let lid = Ink.part(SCNCapsule(capRadius: 0.006, height: 0.05), Ink.sumi)
            lid.eulerAngles = SCNVector3(0, 0, .pi / 2 + 0.25 * side)
            lid.position = SCNVector3(0.05 * side, 0.005, 0.112)
            lid.isHidden = true
            head.addChildNode(eye); head.addChildNode(lid)
            eyes.append(eye); lids.append(lid)
        }
        self.eyes = eyes
        self.lids = lids

        // Hugs the head just above the eyes: the head is wider than it is deep, so the band is too.
        let band = Ink.part(SCNTorus(ringRadius: 0.116, pipeRadius: 0.009), Self.cloth)
        band.eulerAngles = SCNVector3(-0.12, 0, 0)
        band.position = SCNVector3(0, 0.05, -0.002)
        band.scale = SCNVector3(1.14, 1, 0.99)
        let sun = Ink.part(SCNCylinder(radius: 0.016, height: 0.004), Self.red)
        sun.eulerAngles = SCNVector3(.pi / 2 - 0.12, 0, 0)
        sun.position = SCNVector3(0, 0.066, 0.12)
        headband.addChildNode(band); headband.addChildNode(sun)
        head.addChildNode(headband)
        root.addChildNode(head)

        let ring = Ink.part(SCNTorus(ringRadius: 0.075, pipeRadius: 0.012), Self.red)
        collar.addChildNode(ring)
        bell = Ink.part(SCNSphere(radius: 0.019), Self.gold, glow: 0.15)
        bell.position = SCNVector3(0, -0.01, 0.083)
        collar.addChildNode(bell)
        root.addChildNode(collar)

        legs = (0..<4).map { _ in Ink.part(SCNCapsule(capRadius: 0.032, height: 0.19), Self.fur) }
        haunches = [Ink.part(SCNSphere(radius: 0.075), Self.ginger, image: Calico.patch(ginger: true)),
                    Ink.part(SCNSphere(radius: 0.075), Self.black, image: Calico.patch(ginger: false))]
        (legs + haunches).forEach(root.addChildNode)

        // The tail is a chain, each piece hanging from the last, so it can curl and sway.
        var tail: [SCNNode] = []
        var parent = root
        for index in 0..<6 {
            // Banded like a tabby's tail, ending dark.
            let segment = Ink.part(SCNCapsule(capRadius: 0.024 - 0.002 * CGFloat(index), height: 0.075),
                                   index % 2 == 0 ? Self.ginger : Self.black)
            segment.pivot = SCNMatrix4MakeTranslation(0, -0.03, 0)
            parent.addChildNode(segment)
            tail.append(segment)
            parent = segment
        }
        self.tail = tail
        dressFur()
        grow(to: stage)
        set(.sit, animated: false)
    }

    /// Fur everywhere (fine strands in the surface, soft and matte), then the glossy bits: wet eyes and
    /// nose, a gold bell, cloth that is a little smoother than fur.
    private func dressFur() {
        root.enumerateHierarchy { node, _ in
            guard let material = node.geometry?.firstMaterial else { return }
            material.normal.contents = Calico.furNormal
            material.normal.intensity = 0.55
            material.roughness.contents = 0.85
        }
        for eye in eyes {
            eye.enumerateHierarchy { node, _ in
                node.geometry?.firstMaterial?.normal.contents = nil
                node.geometry?.firstMaterial?.roughness.contents = 0.05
            }
        }
        bell.geometry?.firstMaterial?.metalness.contents = 1.0
        bell.geometry?.firstMaterial?.roughness.contents = 0.25
        bell.geometry?.firstMaterial?.normal.contents = nil
        collar.enumerateHierarchy { node, _ in node.geometry?.firstMaterial?.normal.contents = nil }
    }

    /// How far ahead of its paws Kuro's mouth is with its head down to eat, at its current size.
    private(set) var reach: Float = 0.42

    func grow(to stage: FamiliarCat.Stage) {
        let size: Float = [0.62, 0.8, 1, 1.08][stage.rawValue]
        root.scale = SCNVector3(size, size, size)
        // Kittens are mostly head.
        let headSize: Float = [1.28, 1.1, 1, 1][stage.rawValue]
        head.scale = SCNVector3(headSize, headSize, headSize)
        reach = (0.32 + 0.11 * headSize) * size
        collar.isHidden = stage == .kitten
        bell.isHidden = stage < .grown
        headband.isHidden = stage != .elder
    }

    // MARK: Poses

    func set(_ pose: Pose, animated: Bool = true, duration: Double = 0.7) {
        self.pose = pose
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? duration : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        apply(pose)
        SCNTransaction.commit()
    }

    private func place(_ node: SCNNode, _ x: Float, _ y: Float, _ z: Float, pitch: Float = 0, yaw: Float = 0, roll: Float = 0,
                       scale: SCNVector3 = SCNVector3(1, 1, 1)) {
        node.position = SCNVector3(x, y, z)
        node.eulerAngles = SCNVector3(pitch, yaw, roll)
        node.scale = scale
    }

    private func setEyes(open: Bool) {
        eyes.forEach { $0.isHidden = !open }
        lids.forEach { $0.isHidden = open }
    }

    private func curlTail(_ bends: [Float], pitch: Float, yaw: Float = 0) {
        for (index, segment) in tail.enumerated() {
            segment.position = index == 0 ? SCNVector3(0, 0, 0) : SCNVector3(0, 0.046, 0)
            segment.eulerAngles = index == 0 ? SCNVector3(pitch, yaw, 0) : SCNVector3(0, 0, bends[index])
        }
    }

    private func apply(_ pose: Pose) {
        let hide = SCNVector3(0.01, 0.01, 0.01)
        switch pose {
        case .sit, .swipe:
            place(body, 0, 0.17, -0.02, pitch: -0.25, scale: SCNVector3(1, 1.25, 0.95))
            place(head, 0, 0.37, 0.04)
            place(collar, 0, 0.27, 0.02, pitch: 0.3)
            place(legs[0], -0.055, 0.1, 0.085)
            place(legs[1], 0.055, pose == .swipe ? 0.2 : 0.1, pose == .swipe ? 0.16 : 0.085, pitch: pose == .swipe ? -1.25 : 0)
            place(legs[2], -0.1, 0.03, 0.06, pitch: .pi / 2, scale: SCNVector3(1, 0.55, 1))
            place(legs[3], 0.1, 0.03, 0.06, pitch: .pi / 2, scale: SCNVector3(1, 0.55, 1))
            place(haunches[0], -0.095, 0.075, -0.05, scale: SCNVector3(0.85, 1, 1.25))
            place(haunches[1], 0.095, 0.075, -0.05, scale: SCNVector3(0.85, 1, 1.25))
            tail[0].position = SCNVector3(0, 0.03, -0.17)
            curlTail([0, 0.45, 0.5, 0.5, 0.45, 0.4], pitch: -1.45, yaw: 0.9)
            tail[0].position = SCNVector3(0, 0.03, -0.17)
            setEyes(open: true)
        case .stand, .eat:
            place(body, 0, 0.2, 0, scale: SCNVector3(0.92, 0.85, 1.32))
            // Eating, the head goes right down so the mouth meets the ground in front of the paws.
            place(head, 0, pose == .eat ? 0.11 : 0.35, pose == .eat ? 0.32 : 0.27, pitch: pose == .eat ? 0.8 : -0.1)
            place(collar, 0, pose == .eat ? 0.18 : 0.27, pose == .eat ? 0.24 : 0.19, pitch: pose == .eat ? 1.2 : 0.7)
            for (index, (x, z)) in [(-0.065, 0.14), (0.065, 0.14), (-0.065, -0.14), (0.065, -0.14)].enumerated() {
                place(legs[index], Float(x), 0.095, Float(z))
            }
            place(haunches[0], -0.07, 0.2, -0.13, scale: SCNVector3(0.8, 0.9, 1))
            place(haunches[1], 0.07, 0.2, -0.13, scale: SCNVector3(0.8, 0.9, 1))
            curlTail([0, 0.3, 0.35, 0.35, 0.4, 0.45], pitch: -0.7)
            tail[0].position = SCNVector3(0, 0.23, -0.19)
            setEyes(open: true)
        case .crouch:
            // Low to the boards, weight back, eyes on whatever it is about to catch.
            place(body, 0, 0.12, 0, scale: SCNVector3(0.95, 0.7, 1.4))
            place(head, 0, 0.2, 0.27, pitch: 0.12)
            place(collar, 0, 0.18, 0.19, pitch: 0.9)
            for (index, (x, z)) in [(-0.065, 0.16), (0.065, 0.16), (-0.065, -0.12), (0.065, -0.12)].enumerated() {
                place(legs[index], Float(x), 0.05, Float(z), pitch: index < 2 ? 0.5 : -0.6, scale: SCNVector3(1, 0.55, 1))
            }
            place(haunches[0], -0.08, 0.13, -0.12, scale: SCNVector3(0.9, 0.95, 1.05))
            place(haunches[1], 0.08, 0.13, -0.12, scale: SCNVector3(0.9, 0.95, 1.05))
            curlTail([0, 0.05, 0.05, 0.1, 0.12, 0.18], pitch: -1.35)
            tail[0].position = SCNVector3(0, 0.13, -0.2)
            setEyes(open: true)
        case .pounce:
            // Stretched out in the air: front paws reaching, back legs pushing away.
            place(body, 0, 0.22, 0.05, pitch: -0.2, scale: SCNVector3(0.85, 0.8, 1.55))
            place(head, 0, 0.36, 0.33, pitch: -0.15)
            place(collar, 0, 0.29, 0.24, pitch: 0.6)
            place(legs[0], -0.06, 0.25, 0.31, pitch: -1.2)
            place(legs[1], 0.06, 0.25, 0.31, pitch: -1.2)
            place(legs[2], -0.065, 0.13, -0.2, pitch: 0.8)
            place(legs[3], 0.065, 0.13, -0.2, pitch: 0.8)
            place(haunches[0], -0.07, 0.2, -0.13, scale: SCNVector3(0.8, 0.9, 1))
            place(haunches[1], 0.07, 0.2, -0.13, scale: SCNVector3(0.8, 0.9, 1))
            curlTail([0, 0.08, 0.08, 0.1, 0.1, 0.12], pitch: -1.05)
            tail[0].position = SCNVector3(0, 0.24, -0.22)
            setEyes(open: true)
        case .groom:
            // Sitting, one paw up at the mouth, head bent to it.
            place(body, 0, 0.17, -0.02, pitch: -0.25, scale: SCNVector3(1, 1.25, 0.95))
            place(head, 0.01, 0.35, 0.06, pitch: 0.35, yaw: -0.2, roll: -0.15)
            place(collar, 0, 0.27, 0.02, pitch: 0.3)
            place(legs[0], -0.055, 0.1, 0.085)
            place(legs[1], 0.035, 0.27, 0.15, pitch: -2.1)
            place(legs[2], -0.1, 0.03, 0.06, pitch: .pi / 2, scale: SCNVector3(1, 0.55, 1))
            place(legs[3], 0.1, 0.03, 0.06, pitch: .pi / 2, scale: SCNVector3(1, 0.55, 1))
            place(haunches[0], -0.095, 0.075, -0.05, scale: SCNVector3(0.85, 1, 1.25))
            place(haunches[1], 0.095, 0.075, -0.05, scale: SCNVector3(0.85, 1, 1.25))
            curlTail([0, 0.45, 0.5, 0.5, 0.45, 0.4], pitch: -1.45, yaw: 0.9)
            tail[0].position = SCNVector3(0, 0.03, -0.17)
            setEyes(open: false)
        case .sleep:
            place(body, 0, 0.095, 0, scale: SCNVector3(1.25, 0.66, 1.25))
            place(head, 0.05, 0.13, 0.15, pitch: 0.35, yaw: 0.35, roll: 0.15)
            place(collar, 0.03, 0.12, 0.08, pitch: 1.0, scale: hide)
            for (index, (x, z)) in [(-0.06, 0.2), (0.04, 0.21), (-0.1, -0.05), (0.1, -0.05)].enumerated() {
                place(legs[index], Float(x), 0.03, Float(z), pitch: .pi / 2, scale: index < 2 ? SCNVector3(0.9, 0.5, 0.9) : hide)
            }
            place(haunches[0], -0.12, 0.08, -0.08, scale: SCNVector3(0.9, 0.85, 1.1))
            place(haunches[1], 0.12, 0.08, -0.08, scale: SCNVector3(0.9, 0.85, 1.1))
            curlTail([0, 0.55, 0.55, 0.55, 0.5, 0.45], pitch: -1.5, yaw: -1.2)
            tail[0].position = SCNVector3(-0.1, 0.04, -0.14)
            setEyes(open: false)
        }
    }

    // MARK: Motion

    /// Breathing, slow when asleep.
    func breathe() {
        body.removeAction(forKey: "breath")
        let period = pose == .sleep ? 2.6 : 1.8
        let swell = SCNAction.scale(by: 1.03, duration: period / 2)
        swell.timingMode = .easeInEaseOut
        body.runAction(.repeatForever(.sequence([swell, swell.reversed()])), forKey: "breath")
    }

    func swayTail(lively: Bool) {
        tail[3].removeAction(forKey: "sway")
        let amount: CGFloat = lively ? 0.35 : 0.15
        let swing = SCNAction.rotateBy(x: 0, y: 0, z: amount, duration: lively ? 0.6 : 1.2)
        swing.timingMode = .easeInEaseOut
        tail[3].runAction(.repeatForever(.sequence([swing, swing.reversed(), swing.reversed(), swing])), forKey: "sway")
    }

    /// Legs swinging in pairs while walking; stop with `standStill`.
    func walkCycle() {
        for (index, leg) in legs.enumerated() {
            let forward = (index == 0 || index == 3) ? 1.0 : -1.0
            let step = SCNAction.rotateBy(x: CGFloat(0.5 * forward), y: 0, z: 0, duration: 0.18)
            leg.runAction(.repeatForever(.sequence([step, step.reversed(), step.reversed(), step])), forKey: "walk")
        }
    }

    func standStill() { legs.forEach { $0.removeAction(forKey: "walk") } }

    /// Faster legs for a trot or a dash.
    func runCycle() {
        for (index, leg) in legs.enumerated() {
            let forward = (index == 0 || index == 3) ? 1.0 : -1.0
            let step = SCNAction.rotateBy(x: CGFloat(0.7 * forward), y: 0, z: 0, duration: 0.1)
            leg.runAction(.repeatForever(.sequence([step, step.reversed(), step.reversed(), step])), forKey: "walk")
        }
    }

    /// The bottom wiggle before a pounce.
    func wiggle() {
        let sway = SCNAction.rotateBy(x: 0, y: 0, z: 0.09, duration: 0.09)
        body.runAction(.repeat(.sequence([sway, sway.reversed(), sway.reversed(), sway]), count: 4), forKey: "wiggle")
        tail[4].runAction(.repeat(.sequence([.rotateBy(x: 0, y: 0, z: 0.4, duration: 0.08),
                                             .rotateBy(x: 0, y: 0, z: -0.4, duration: 0.08)]), count: 8))
    }

    /// Licking a paw and wiping it over an ear, over and over.
    func groomCycle() {
        let paw = legs[1]
        let lick = SCNAction.sequence([.moveBy(x: 0, y: 0.015, z: 0.01, duration: 0.18), .moveBy(x: 0, y: -0.015, z: -0.01, duration: 0.18)])
        paw.runAction(.repeat(lick, count: 12), forKey: "groom")
        head.runAction(.repeat(.sequence([.rotateBy(x: 0.12, y: 0, z: 0, duration: 0.18),
                                          .rotateBy(x: -0.12, y: 0, z: 0, duration: 0.18)]), count: 12), forKey: "groom")
    }

    /// Purring under your hand: eyes shut in contentment and the head pushed into the stroke.
    func lean(_ amount: Float) {
        setEyes(open: amount < 0.3)
        head.eulerAngles.z = .init(-0.25 * amount)
    }

    func bob() {
        head.runAction(.repeat(.sequence([.moveBy(x: 0, y: -0.025, z: 0.01, duration: 0.25),
                                          .moveBy(x: 0, y: 0.025, z: -0.01, duration: 0.25)]), count: 10), forKey: "bob")
    }

    func swipePaw() {
        let paw = legs[1]
        let swipe = SCNAction.sequence([.rotateBy(x: 0, y: 0.6, z: 0, duration: 0.15), .rotateBy(x: 0, y: -0.6, z: 0, duration: 0.25)])
        paw.runAction(swipe)
    }

    func blink() {
        guard pose != .sleep else { return }
        setEyes(open: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
            guard let self, self.pose != .sleep else { return }
            self.setEyes(open: true)
        }
    }

    func lookAround() {
        head.runAction(.sequence([.rotateBy(x: 0, y: 0.5, z: 0, duration: 0.6), .wait(duration: 0.8),
                                  .rotateBy(x: 0, y: -1.0, z: 0, duration: 0.9), .wait(duration: 0.8),
                                  .rotateBy(x: 0, y: 0.5, z: 0, duration: 0.6)]), forKey: "look")
    }

    /// Ears pressed back and the tail lashing: the cat has had enough.
    func bristle(_ cross: Bool) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.2
        for (index, ear) in ears.enumerated() {
            let side: Float = index == 0 ? -1 : 1
            ear.eulerAngles = cross ? SCNVector3(-0.9, 0, -1.1 * side) : SCNVector3(-0.12, 0, -0.38 * side)
        }
        SCNTransaction.commit()
        tail[3].removeAction(forKey: "sway")
        if cross {
            let lash = SCNAction.rotateBy(x: 0, y: 0, z: 0.6, duration: 0.12)
            tail[3].runAction(.repeat(.sequence([lash, lash.reversed(), lash.reversed(), lash]), count: 6), forKey: "sway")
        }
    }

    func hop() {
        root.runAction(.sequence([.moveBy(x: 0, y: 0.08, z: 0, duration: 0.16), .moveBy(x: 0, y: -0.08, z: 0, duration: 0.2)]))
    }
}

/// The calico coat, painted onto Kuro's spheres. On a SceneKit sphere the middle of the picture faces
/// forward, its edges meet at the back and its top is the crown.
enum Calico {
    private static let width = 512, height = 256

    private static func paint(_ work: (CGContext) -> Void) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(KuroModel.fur.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        work(context)
        // Short fur strokes all over, a little darker and lighter, so the coat reads as fur, not plastic.
        var generator = SeededRandom(seed: 21)
        context.setLineCap(.round)
        context.setLineWidth(1.6)
        for _ in 0..<2600 {
            let x = generator.double(0...Double(width)), y = generator.double(0...Double(height))
            let lean = generator.double(-3...3)
            context.setStrokeColor(generator.double(0...1) > 0.5 ? CGColor(red: 0, green: 0, blue: 0, alpha: 0.07)
                                                                 : CGColor(red: 1, green: 1, blue: 1, alpha: 0.1))
            context.move(to: CGPoint(x: x, y: y))
            context.addLine(to: CGPoint(x: x + lean, y: y - generator.double(5...9)))
            context.strokePath()
        }
        return context.makeImage()!
    }

    /// A soft-edged patch of ginger or black fur, with thin wavy tabby stripes across it.
    private static func patch(_ c: CGContext, _ blobs: [CGRect], ginger: Bool) {
        let shape = CGMutablePath()
        blobs.forEach { shape.addEllipse(in: $0) }
        c.addPath(shape)
        c.setFillColor((ginger ? KuroModel.ginger : KuroModel.black).cgColor)
        c.fillPath()
        c.saveGState()
        c.addPath(shape)
        c.clip()
        c.setStrokeColor(ginger ? CGColor(red: 0.55, green: 0.28, blue: 0.12, alpha: 0.6) : CGColor(red: 0.08, green: 0.07, blue: 0.07, alpha: 0.7))
        c.setLineCap(.round)
        c.setLineWidth(3.5)
        // Stripes run along the coat in short broken waves, not pole to pole.
        for (row, y) in stride(from: CGFloat(20), through: CGFloat(height), by: 24).enumerated() {
            var x = CGFloat(row % 2) * 30 - 40
            while x < CGFloat(width) {
                c.move(to: CGPoint(x: x, y: y))
                c.addQuadCurve(to: CGPoint(x: x + 52, y: y + 4), control: CGPoint(x: x + 26, y: y + 12))
                c.strokePath()
                x += 70
            }
        }
        c.restoreGState()
    }

    /// White face and chin; ginger over the crown and one ear, black over the other, like a mike-neko.
    static let head: CGImage = paint { c in
        patch(c, [CGRect(x: 110, y: 150, width: 160, height: 140), CGRect(x: -30, y: 120, width: 150, height: 170)], ginger: true)
        patch(c, [CGRect(x: 262, y: 155, width: 150, height: 130), CGRect(x: 400, y: 110, width: 160, height: 180)], ginger: false)
    }

    /// Mostly white: a black saddle over the back with a ginger flank on one side, white chest and belly.
    static let body: CGImage = paint { c in
        patch(c, [CGRect(x: 420, y: 110, width: 150, height: 170), CGRect(x: -60, y: 110, width: 140, height: 170),
                  CGRect(x: 330, y: 160, width: 110, height: 90)], ginger: false)
        patch(c, [CGRect(x: 70, y: 130, width: 120, height: 110), CGRect(x: 20, y: 200, width: 90, height: 70)], ginger: true)
    }

    /// Fur strands as a bump map: short strokes tilted every which way on a flat surface.
    static let furNormal: CGImage = {
        let size = 512
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        var generator = SeededRandom(seed: 33)
        context.setLineCap(.round)
        context.setLineWidth(1.4)
        for _ in 0..<9000 {
            let x = generator.double(0...Double(size)), y = generator.double(0...Double(size))
            let tilt = generator.double(-0.3...0.3)
            context.setStrokeColor(CGColor(red: 0.5 + tilt, green: 0.5 + generator.double(-0.25...0.25), blue: 0.9, alpha: 0.8))
            context.move(to: CGPoint(x: x, y: y))
            context.addLine(to: CGPoint(x: x + tilt * 6, y: y - generator.double(4...8)))
            context.strokePath()
        }
        return context.makeImage()!
    }()

    static func patch(ginger: Bool) -> CGImage {
        paint { c in patch(c, [CGRect(x: -40, y: 40, width: 600, height: 260)], ginger: ginger) }
    }
}
