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

    var body: some View {
        ZStack {
            Color(red: 0.18, green: 0.3, blue: 0.48).ignoresSafeArea()
            if let dojo {
                // While you talk the garden slides up, so Kuro stays in view above the conversation.
                GeometryReader { geometry in
                    DojoSceneView(dojo: dojo)
                        .offset(y: talking ? -geometry.size.height * 0.27 : 0)
                        .animation(.smooth(duration: 0.45), value: talking)
                }
                .ignoresSafeArea()
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
                HStack(spacing: 10) {
                    action("fish", String(localized: "Feed")) { dojo?.feed() }
                    action("circle.hexagongrid", String(localized: "Play")) { dojo?.play() }
                    action("hand.raised", String(localized: "Stroke")) { dojo?.pet() }
                    action("hand.point.up.left", String(localized: "Poke")) { dojo?.annoy() }
                    action("bubble.left.and.text.bubble.right", String(localized: "Talk")) { talking = true }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
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
            let made = Dojo(stage: state.stage, mood: state.mood)
            made.onActivity = { activity = $0 }
            dojo = made
            made.start()
            if musicOn { music(true) }
            if opensChat { talking = true }
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

    private func action(_ symbol: String, _ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 18, weight: .regular))
                Text(title).font(.caption2.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .nagisenGlass(in: RoundedRectangle(cornerRadius: 16), tint: Theme.surface.opacity(0.3))
        }
        .buttonStyle(.plain)
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
        case .eating: String(localized: "\(name) is eating the fish you gave.")
        case .playing: String(localized: "\(name) is chasing the temari ball.")
        case .sitting: String(localized: "\(name) is sitting quietly, watching the garden.")
        case .purring: String(localized: "\(name) purrs and leans into your hand.")
        case .annoyed: String(localized: "\(name) has had enough and stalks off.")
        case .listening: String(localized: "\(name) is listening.")
        }
    }
}

private struct DojoSceneView: UIViewRepresentable {
    let dojo: Dojo

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = dojo.scene
        view.pointOfView = dojo.camera
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .clear
        view.rendersContinuously = true
        view.isPlaying = true
        view.preferredFramesPerSecond = 60
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap)))
        view.addGestureRecognizer(UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan)))
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch)))
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dojo: dojo) }

    final class Coordinator: NSObject {
        let dojo: Dojo
        weak var view: SCNView?
        private var startYaw: Float = 0
        private var startView: CGFloat = 54

        init(dojo: Dojo) { self.dojo = dojo }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard let view else { return }
            let hits = view.hitTest(gesture.location(in: view), options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            if hits.contains(where: { $0.node.isInside(dojo.kuro.root) }) { dojo.pet() }
        }

        /// Turns the room a little either way, never far enough to look behind the walls.
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began { startYaw = dojo.stage.eulerAngles.y }
            let turn = startYaw + Float(gesture.translation(in: view).x / 300)
            dojo.stage.eulerAngles.y = min(max(turn, -0.5), 0.5)
        }

        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            guard let camera = dojo.camera.camera else { return }
            if gesture.state == .began { startView = camera.fieldOfView }
            camera.fieldOfView = min(max(startView / gesture.scale, 34), 72)
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
        let cushion = Ink.part(SCNCylinder(radius: 0.23, height: 0.02), Ink.colour(0x8B2B49), outlined: false)
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
