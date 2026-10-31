import SwiftUI

@main
struct DaywellApp: App {
    @StateObject private var store = NutritionStore()
    @StateObject private var spotify = SpotifyManager()
    @StateObject private var health = HealthManager()
    @StateObject private var community = CommunityCloud()
    @State private var syncTask: Task<Void, Never>?
    @AppStorage("nagisen.health.autoImport") private var autoImportHealth = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(spotify)
                .environmentObject(health)
                .environmentObject(community)
                .onOpenURL { spotify.handle(url: $0) }
                .onReceive(health.$workouts) { _ in
                    if autoImportHealth { _ = store.importHealth(workouts: health.workouts, weights: health.weightSamples) }
                }
                .onReceive(health.$weightSamples) { _ in
                    if autoImportHealth { _ = store.importHealth(workouts: health.workouts, weights: health.weightSamples) }
                }
                .onAppear {
                    WaterReminders.reconcile()
                    spotify.connectIfAuthorized()
                    Task {
                        await community.connect()
                        await community.sync(store)
                    }
                    #if DEBUG
                    DebugMigration.runIfRequested(store: store)
                    #endif
                }
                .onReceive(store.objectWillChange) { _ in
                    syncTask?.cancel()
                    syncTask = Task {
                        try? await Task.sleep(for: .seconds(12))
                        guard !Task.isCancelled else { return }
                        await community.sync(store)
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        spotify.connectIfAuthorized()
                        health.refresh()
                        WaterReminders.reconcile()
                        Task {
                            await community.connect()
                            await community.sync(store)
                        }
                    }
                    if phase == .inactive { spotify.disconnect() }
                    if phase == .background {
                        store.backupNow()
                        Task { await community.sync(store) }
                    }
                }
        }
    }
}

#if DEBUG
/// Test-only hook: launching with `-NAGISENImportFile /path/file.json` runs the Lose It!
/// pipeline at startup so the migration can be verified on a simulator without tapping
/// through the UI. Never compiled into Release builds.
private enum DebugMigration {
    static func runIfRequested(store: NutritionStore) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-NAGISENImportFile"),
              index + 1 < arguments.count else { return }
        let raw = arguments[index + 1]
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let candidates = [
            URL(fileURLWithPath: raw),
            documents?.appendingPathComponent(raw),
            documents?.appendingPathComponent(URL(fileURLWithPath: raw).lastPathComponent)
        ].compactMap { $0 }
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let data = try? Data(contentsOf: url) else {
            print("NAGISEN DEBUG IMPORT: could not read \(raw)")
            return
        }
        let plan = LoseItImporter.preview(files: [LoseItSourceFile(name: url.lastPathComponent, data: data)],
                                          existingEntryFingerprints: store.entryFingerprints,
                                          existingWeights: store.weights)
        let outcome = store.importLoseIt(plan)
        print("NAGISEN DEBUG IMPORT: \(outcome.message)")
    }
}
#endif
