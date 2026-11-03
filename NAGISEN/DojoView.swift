import AVFoundation
import SceneKit
import SwiftUI

/// Kuro's hideout, full screen. Feed, play, stroke or poke Kuro, or talk: Kuro is NAGISEN's AI now.
/// Drag to turn the garden, pinch to come closer; a quiet koto plays while you are here.
struct DojoView: View {
    /// Opens straight into the conversation, for the AI button.
    var opensChat = false
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Familiar.nameKey) private var name = Familiar.defaultName
    @AppStorage("nagisen.dojo.music") private var musicOn = true
    @State private var dojo: Dojo?
    @State private var activity = Dojo.Activity.sitting
    @State private var talking = false
    @State private var player: AVAudioPlayer?
    @State private var hand = Dojo.Hand.look
    @State private var ready = false

    var body: some View {
        ZStack {
            Color(red: 0.18, green: 0.3, blue: 0.48).ignoresSafeArea()
            if let dojo {
                // While you talk the garden slides up, so Kuro stays in view above the conversation.
                GeometryReader { geometry in
                    DojoSceneView(dojo: dojo) {
                        // Everything is loaded and its shaders built: show the garden and let Kuro begin.
                        withAnimation(.easeOut(duration: 0.6)) { ready = true }
                        dojo.start()
                        if opensChat { talking = true }
                    }
                    .offset(y: talking ? -geometry.size.height * 0.27 : 0)
                    .animation(.smooth(duration: 0.45), value: talking)
                }
                .ignoresSafeArea()
                .opacity(ready ? 1 : 0)
            }
            if !ready {
                VStack(spacing: 14) {
                    ProgressView().tint(.white)
                    Text("\(name)’s garden is waking up…").font(.subheadline).foregroundStyle(.white.opacity(0.85))
                }
            }
            VStack {
                HStack {
                    roundButton("xmark", String(localized: "Close")) { dismiss() }
                    Spacer()
                    VStack(spacing: 2) {
                        Text("\(name)’s hideout").font(.system(size: 20, design: .serif))
                        Text(Familiar.stageName(store.familiar.stage).uppercased())
                            .font(.caption2.weight(.semibold)).nagisenTracking(2).foregroundStyle(Theme.accentText)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .nagisenGlass(in: Capsule(), tint: Theme.surface.opacity(0.25))
                    Spacer()
                    roundButton(musicOn ? "speaker.wave.2" : "speaker.slash",
                                musicOn ? String(localized: "Turn the music off") : String(localized: "Turn the music on")) {
                        musicOn.toggle()
                        music(musicOn)
                    }
                }
                .padding(.horizontal, 14)
                Spacer()
                Text(Self.line(activity, name: name))
                    .font(.subheadline)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .nagisenGlass(in: Capsule(), tint: Theme.surface.opacity(0.3))
                    .animation(.easeInOut(duration: 0.3), value: activity)
                Text(Self.hint(hand, name: name))
                    .font(.caption2).foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20).padding(.top, 4)
                HStack(spacing: 10) {
                    mode(.feather, "wand.and.rays", String(localized: "Feather"))
                    mode(.treat, "fish", String(localized: "Treat"))
                    action("bubble.left.and.text.bubble.right", String(localized: "Talk"), selected: false) { talking = true }
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
            }
            .padding(.vertical, 8)
            .foregroundStyle(Theme.ink)
        }
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $talking, onDismiss: { dojo?.stopListening() }) {
            DeepSeekChatView(bottomMenuVisible: false, onClose: { talking = false }, familiarName: name,
                             onReply: { dojo?.speak() })
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .onAppear { dojo?.listen() }
        }
        .onAppear {
            guard dojo == nil else { return }
            let state = store.familiar
            if musicOn { music(true) }
            // The real trees and plants take a few seconds to load, so the garden is built off the main thread.
            Task {
                let made = await Task.detached(priority: .userInitiated) { Dojo(stage: state.stage, mood: state.mood) }.value
                made.onActivity = { activity = $0 }
                dojo = made
            }
        }
        .onDisappear {
            dojo?.stop()
            music(false)
        }
    }

    private func roundButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 40, height: 40)
                .nagisenGlass(in: Circle(), tint: Theme.surface.opacity(0.25))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func action(_ symbol: String, _ title: String, selected: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 18, weight: .regular))
                Text(title).font(.caption2.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .nagisenGlass(in: RoundedRectangle(cornerRadius: 16), tint: selected ? Theme.accent.opacity(0.7) : Theme.surface.opacity(0.3))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// A tool for your finger; tapping it again puts it down.
    private func mode(_ chosen: Dojo.Hand, _ symbol: String, _ title: String) -> some View {
        action(symbol, title, selected: hand == chosen) {
            hand = hand == chosen ? .look : chosen
            dojo?.choose(hand)
        }
    }

    static func hint(_ hand: Dojo.Hand, name: String) -> String {
        switch hand {
        case .look: String(localized: "Drag to turn and tilt · pinch to zoom · rub \(name) to pet · double-tap to call")
        case .feather: String(localized: "Drag the feather around. Hold it still and \(name) will pounce.")
        case .treat: String(localized: "Tap anywhere in the garden to drop a treat.")
        }
    }

    /// The hideout's music, looping; leaving hands the sound back to whatever was playing before.
    private func music(_ on: Bool) {
        let session = AVAudioSession.sharedInstance()
        guard on, let url = Bundle.main.url(forResource: "dojo_music", withExtension: "m4a") else {
            player?.stop()
            player = nil
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        try? session.setCategory(.playback)
        try? session.setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1
        player?.volume = 0.6
        player?.play()
    }

    static func line(_ activity: Dojo.Activity, name: String) -> String {
        switch activity {
        case .sleeping: String(localized: "\(name) is napping on the zabuton.")
        case .sunbathing: String(localized: "\(name) is dozing on the warm stone.")
        case .sitting: String(localized: "\(name) is sitting quietly, watching the garden.")
        case .grooming: String(localized: "\(name) is washing a paw.")
        case .playing: String(localized: "\(name) is batting the temari ball around.")
        case .watchingKoi: String(localized: "\(name) is watching the koi very closely.")
        case .chasingButterfly: String(localized: "\(name) is stalking a butterfly.")
        case .sniffing: String(localized: "\(name) is sniffing the flowers.")
        case .eating: String(localized: "\(name) is eating the treat you dropped.")
        case .hunting: String(localized: "\(name) has spotted the feather…")
        case .coming: String(localized: "\(name) is coming over.")
        case .purring: String(localized: "\(name) purrs and leans into your hand.")
        case .annoyed: String(localized: "\(name) has had enough and stalks off.")
        case .listening: String(localized: "\(name) is listening.")
        }
    }
}

private struct DojoSceneView: UIViewRepresentable {
    let dojo: Dojo
    let onReady: () -> Void

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = dojo.scene
        view.pointOfView = dojo.camera
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .clear
        view.rendersContinuously = true
        view.isPlaying = true
        view.preferredFramesPerSecond = 60
        let coordinator = context.coordinator
        let double = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.doubleTap))
        double.numberOfTapsRequired = 2
        let single = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.tap))
        single.require(toFail: double)
        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.pan))
        pan.maximumNumberOfTouches = 1
        [double, single, pan, UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.pinch))]
            .forEach(view.addGestureRecognizer)
        coordinator.view = view
        coordinator.startClock()
        view.prepare([dojo.scene]) { _ in DispatchQueue.main.async(execute: onReady) }
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) { coordinator.stopClock() }

    func makeCoordinator() -> Coordinator { Coordinator(dojo: dojo) }

    final class Coordinator: NSObject {
        let dojo: Dojo
        weak var view: SCNView?
        private var startYaw: Float = 0
        private var startLift: Float = 0
        private var startZoom: Float = 1
        private var clock: CADisplayLink?
        private var lastTick: CFTimeInterval = 0
        private var dragging = Drag.turning
        private var lastPoint = CGPoint.zero
        private var lastMove: CFTimeInterval = 0
        private let purrFeel = UIImpactFeedbackGenerator(style: .soft)
        private var nextPurr: CFTimeInterval = 0

        private enum Drag { case turning, rubbing, feather }

        init(dojo: Dojo) { self.dojo = dojo }

        func startClock() {
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            clock = link
        }

        func stopClock() { clock?.invalidate(); clock = nil }

        /// Every frame: moves Kuro's hunt and the camera on, and lets you feel the purr.
        @objc private func tick(_ link: CADisplayLink) {
            let dt = lastTick == 0 ? 1 / 60 : min(link.timestamp - lastTick, 0.1)
            lastTick = link.timestamp
            dojo.update(dt)
            if dojo.purring > 0.2, link.timestamp > nextPurr {
                purrFeel.impactOccurred(intensity: CGFloat(0.25 + dojo.purring * 0.55))
                nextPurr = link.timestamp + 0.11
            }
        }

        private func touchesKuro(_ point: CGPoint) -> Bool {
            guard let view else { return false }
            return view.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
                .contains { $0.node.isInside(dojo.kuro.root) }
        }

        /// Where on the boards or the lawn a point on screen falls, in the garden's own coordinates.
        private func spot(_ point: CGPoint) -> SCNVector3? {
            guard let view else { return nil }
            let hits = view.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            guard let hit = hits.first(where: { !$0.node.isInside(dojo.kuro.root) }) else { return nil }
            let local = dojo.stage.convertPosition(hit.worldCoordinates, from: nil)
            let x = Float(local.x), z = Float(local.z)
            guard hypot(x, z) < 4.2 else { return nil }
            let onDeck = abs(x) < 1.28 && abs(z) < 0.98 && Float(local.y) > 0.15
            return SCNVector3(x, onDeck ? Dojo.deck : 0, z)
        }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard let view else { return }
            let point = gesture.location(in: view)
            if touchesKuro(point) { dojo.tapKuro(); return }
            guard let target = spot(point) else { return }
            switch dojo.hand {
            case .treat: dojo.dropTreat(at: target)
            case .feather: dojo.moveFeather(to: target)
            case .look: break
            }
        }

        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let view, let target = spot(gesture.location(in: view)) else { return }
            dojo.call(to: target)
        }

        /// One finger: rubbing Kuro, steering the feather, or otherwise moving the camera: sideways turns the
        /// garden all the way round, up and down raises or lowers the view.
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            guard let view else { return }
            let point = gesture.location(in: view)
            switch gesture.state {
            case .began:
                if touchesKuro(point) { dragging = .rubbing } else if dojo.hand == .feather { dragging = .feather } else { dragging = .turning }
                startYaw = dojo.turn
                startLift = dojo.cameraLift
                lastPoint = point
                lastMove = CACurrentMediaTime()
                purrFeel.prepare()
            case .changed:
                switch dragging {
                case .rubbing:
                    let now = CACurrentMediaTime()
                    let stroke = hypot(point.x - lastPoint.x, point.y - lastPoint.y)
                    dojo.rub(Double(stroke) / 900, dt: now - lastMove)
                    lastPoint = point
                    lastMove = now
                case .feather:
                    if let target = spot(point) { dojo.moveFeather(to: target) }
                case .turning:
                    let moved = gesture.translation(in: view)
                    dojo.orbit(turn: startYaw + Float(moved.x / 220), lift: startLift + Float(moved.y / 260))
                }
            default:
                if dragging == .rubbing { dojo.endRub() }
            }
        }

        /// Pinch to come closer or move back.
        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            if gesture.state == .began { startZoom = dojo.cameraZoom }
            dojo.setZoom(startZoom / Float(gesture.scale))
        }
    }
}

private extension SCNNode {
    func isInside(_ ancestor: SCNNode) -> Bool {
        var node: SCNNode? = self
        while let current = node {
            if current === ancestor { return true }
            node = current.parent
        }
        return false
    }
}

/// A still of Kuro in 3D, for the Dashboard card and Kuro's page.
enum KuroPortrait {
    private static var cache: [String: UIImage] = [:]

    @MainActor static func image(_ stage: FamiliarCat.Stage, _ mood: FamiliarCat.Mood) -> UIImage {
        let key = "\(stage)-\(mood)"
        if let cached = cache[key] { return cached }
        let scene = SCNScene()
        let kuro = KuroModel(stage: stage)
        kuro.set(mood == .resting ? .sleep : .sit, animated: false)
        kuro.root.eulerAngles.y = mood == .resting ? 0.5 : 0.3
        scene.rootNode.addChildNode(kuro.root)
        let cushion = Ink.part(SCNCylinder(radius: 0.23, height: 0.02), Ink.colour(0x8B2B49))
        cushion.position.y = -0.01
        scene.rootNode.addChildNode(cushion)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 30
        let height: Float = mood == .resting ? 0.12 : 0.22
        camera.position = SCNVector3(0, height + 0.32, 1.25)
        camera.look(at: SCNVector3(0, height, 0))
        scene.rootNode.addChildNode(camera)
        let lamp = SCNNode()
        lamp.light = SCNLight(); lamp.light?.type = .directional; lamp.light?.intensity = 800
        lamp.eulerAngles = SCNVector3(-0.8, 0.7, 0)
        scene.rootNode.addChildNode(lamp)
        let ambient = SCNNode()
        ambient.light = SCNLight(); ambient.light?.type = .ambient; ambient.light?.intensity = 380
        scene.rootNode.addChildNode(ambient)
        scene.background.contents = UIColor(red: 0.106, green: 0.102, blue: 0.118, alpha: 1)
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 600, height: 600), antialiasingMode: .multisampling4X)
        cache[key] = image
        return image
    }
}

/// A small dojo hall: a roof that sweeps up at both ends over shoji doors.
struct DojoIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + w * x, y: rect.minY + h * y) }
        var path = Path()
        path.move(to: p(0, 0.28))
        path.addQuadCurve(to: p(0.5, 0.04), control: p(0.3, 0.36))
        path.addQuadCurve(to: p(1, 0.28), control: p(0.7, 0.36))
        path.move(to: p(0.07, 0.4)); path.addLine(to: p(0.93, 0.4))
        path.addRect(CGRect(origin: p(0.2, 0.4), size: CGSize(width: w * 0.6, height: h * 0.6)))
        path.move(to: p(0.5, 0.4)); path.addLine(to: p(0.5, 1))
        path.move(to: p(0.2, 0.7)); path.addLine(to: p(0.8, 0.7))
        return path
    }
}
