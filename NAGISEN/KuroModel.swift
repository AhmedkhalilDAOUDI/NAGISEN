import SceneKit
#if canImport(UIKit)
import UIKit
typealias InkColor = UIColor
#else
import AppKit
typealias InkColor = NSColor
#endif

/// The ink-and-wash look shared by Kuro and the dojo: flat bands of light like a woodblock print,
/// and a sumi outline drawn by a slightly swollen back-facing copy of each shape.
enum Ink {
    static let sumi = InkColor(red: 0.09, green: 0.07, blue: 0.08, alpha: 1)

    static func colour(_ hex: UInt32) -> InkColor {
        InkColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                 blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// Three bands of light per lamp, the way a print shades with a few flat tones.
    private static let toon = """
    float ndl = max(0.0, dot(_surface.normal, _light.direction));
    float band = ndl > 0.55 ? 1.0 : (ndl > 0.18 ? 0.62 : 0.3);
    _lightingContribution.diffuse += band * _light.intensity.rgb;
    """

    static func material(_ colour: InkColor, glow: CGFloat = 0) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .lambert
        material.diffuse.contents = colour
        material.shaderModifiers = [.lightingModel: toon]
        if glow > 0 { material.emission.contents = colour; material.emission.intensity = glow }
        return material
    }

    static func material(image: CGImage) -> SCNMaterial {
        let material = material(.white)
        material.diffuse.contents = image
        return material
    }

    private static let outlineMaterial: SCNMaterial = {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = sumi
        material.cullMode = .front
        material.shaderModifiers = [.geometry: "_geometry.position.xyz += _geometry.normal * 0.006;"]
        return material
    }()

    /// A node for the shape in this colour, with its ink outline.
    static func part(_ geometry: SCNGeometry, _ colour: InkColor, outlined: Bool = true, glow: CGFloat = 0) -> SCNNode {
        geometry.materials = [material(colour, glow: glow)]
        let node = SCNNode(geometry: geometry)
        if outlined {
            let hull = geometry.copy() as! SCNGeometry
            hull.materials = [outlineMaterial]
            let outline = SCNNode(geometry: hull)
            outline.name = "outline"
            node.addChildNode(outline)
        }
        return node
    }
}

/// Kuro in 3D: a black cat built from soft shapes, with amber eyes, a red collar and, as Kuro grows,
/// a gold bell and finally a dojo master's headband.
final class KuroModel {
    enum Pose { case sit, stand, sleep, eat, swipe }

    static let fur = Ink.colour(0x2A2630)
    static let muzzle = Ink.colour(0x3A3540)
    static let amber = Ink.colour(0xE3B14F)
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
    private(set) var pose = Pose.sit

    init(stage: FamiliarCat.Stage) {
        root.name = "Kuro"
        body = Ink.part(SCNSphere(radius: 0.15), Self.fur)
        root.addChildNode(body)

        // Head: a wide soft ball, ears, a slightly lighter muzzle, nose and whiskers.
        head.addChildNode(Ink.part(SCNSphere(radius: 0.125), Self.fur))
        head.childNodes.first?.scale = SCNVector3(1.12, 0.94, 0.96)
        for side in [-1.0, 1.0] {
            let ear = Ink.part(SCNCone(topRadius: 0.004, bottomRadius: 0.052, height: 0.1), Self.fur)
            ear.position = SCNVector3(0.07 * side, 0.1, -0.01)
            ear.eulerAngles = SCNVector3(-0.12, 0, -0.38 * side)
            let inner = Ink.part(SCNCone(topRadius: 0.002, bottomRadius: 0.03, height: 0.065), Self.pink, outlined: false)
            inner.position = SCNVector3(0, -0.008, 0.02)
            ear.addChildNode(inner)
            head.addChildNode(ear)
        }
        let snout = Ink.part(SCNSphere(radius: 0.05), Self.muzzle, outlined: false)
        snout.position = SCNVector3(0, -0.035, 0.095)
        snout.scale = SCNVector3(1.25, 0.8, 0.7)
        head.addChildNode(snout)
        let nose = Ink.part(SCNSphere(radius: 0.012), Self.pink, outlined: false)
        nose.position = SCNVector3(0, -0.02, 0.13)
        head.addChildNode(nose)
        for side in [-1.0, 1.0] {
            for (index, tilt) in [0.12, -0.05].enumerated() {
                let whisker = Ink.part(SCNCylinder(radius: 0.0018, height: 0.13), Self.cloth, outlined: false)
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
            let pupil = Ink.part(SCNSphere(radius: 0.02), Ink.sumi, outlined: false)
            pupil.scale = SCNVector3(0.3, 1, 0.6)
            pupil.position = SCNVector3(0, 0, 0.012)
            eye.addChildNode(pupil)
            let lid = Ink.part(SCNCapsule(capRadius: 0.006, height: 0.05), Ink.sumi, outlined: false)
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
        let sun = Ink.part(SCNCylinder(radius: 0.016, height: 0.004), Self.red, outlined: false)
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
        haunches = (0..<2).map { _ in Ink.part(SCNSphere(radius: 0.075), Self.fur) }
        (legs + haunches).forEach(root.addChildNode)

        // The tail is a chain, each piece hanging from the last, so it can curl and sway.
        var tail: [SCNNode] = []
        var parent = root
        for index in 0..<6 {
            let segment = Ink.part(SCNCapsule(capRadius: 0.024 - 0.002 * CGFloat(index), height: 0.075), Self.fur)
            segment.pivot = SCNMatrix4MakeTranslation(0, -0.03, 0)
            parent.addChildNode(segment)
            tail.append(segment)
            parent = segment
        }
        self.tail = tail
        grow(to: stage)
        set(.sit, animated: false)
    }

    func grow(to stage: FamiliarCat.Stage) {
        let size: Float = [0.62, 0.8, 1, 1.08][stage.rawValue]
        root.scale = SCNVector3(size, size, size)
        // Kittens are mostly head.
        let headSize: Float = [1.28, 1.1, 1, 1][stage.rawValue]
        head.scale = SCNVector3(headSize, headSize, headSize)
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
            place(head, 0, pose == .eat ? 0.16 : 0.35, pose == .eat ? 0.33 : 0.27, pitch: pose == .eat ? 0.55 : -0.1)
            place(collar, 0, pose == .eat ? 0.2 : 0.27, pose == .eat ? 0.25 : 0.19, pitch: pose == .eat ? 1.1 : 0.7)
            for (index, (x, z)) in [(-0.065, 0.14), (0.065, 0.14), (-0.065, -0.14), (0.065, -0.14)].enumerated() {
                place(legs[index], Float(x), 0.095, Float(z))
            }
            place(haunches[0], -0.07, 0.2, -0.13, scale: SCNVector3(0.8, 0.9, 1))
            place(haunches[1], 0.07, 0.2, -0.13, scale: SCNVector3(0.8, 0.9, 1))
            curlTail([0, 0.3, 0.35, 0.35, 0.4, 0.45], pitch: -0.7)
            tail[0].position = SCNVector3(0, 0.23, -0.19)
            setEyes(open: true)
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

    func hop() {
        root.runAction(.sequence([.moveBy(x: 0, y: 0.08, z: 0, duration: 0.16), .moveBy(x: 0, y: -0.08, z: 0, duration: 0.2)]))
    }
}
