import SwiftUI

@main
struct DaywellApp: App {
    @StateObject private var store = NutritionStore()
    @StateObject private var spotify = SpotifyManager()
    @StateObject private var health = HealthManager()
    @StateObject private var community = CommunityCloud()
    @StateObject private var feed = FeedService()
    #if !NAGISEN_NO_ICLOUD
    @UIApplicationDelegateAdaptor(PushRelay.self) private var pushRelay
    #endif
    @State private var syncTask: Task<Void, Never>?
    @AppStorage("nagisen.health.autoImport") private var autoImportHealth = false
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.system.rawValue

    init() {
        LanguageBundle.use(AppLanguage.current)
    }
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            let language = AppLanguage(rawValue: languageCode) ?? .system
            ContentView()
                .id(language)
                .environment(\.locale, language.locale)
                .environment(\.layoutDirection, language.layoutDirection)
                .environmentObject(store)
                .environmentObject(spotify)
                .environmentObject(health)
                .environmentObject(community)
                .environmentObject(feed)
                .onOpenURL { url in
                    spotify.handle(url: url)
                    feed.handle(url: url)
                }
                .sheet(isPresented: $feed.recoveringPassword) {
                    NewPasswordView().environmentObject(feed)
                }
                .onReceive(health.$workouts) { _ in
                    if autoImportHealth { _ = store.importHealth(workouts: health.workouts, weights: health.weightSamples) }
                }
                .onReceive(health.$weightSamples) { _ in
                    if autoImportHealth { _ = store.importHealth(workouts: health.workouts, weights: health.weightSamples) }
                }
                .onAppear {
                    WaterReminders.reconcile()
                    Reminders.reconcile(store: store)
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
                        await syncBorder()
                        Reminders.reconcile(store: store)
                    }
                }
                .onChange(of: feed.state) { _, state in
                    if state == .ready { Task { await syncBorder() } }
                    #if !NAGISEN_NO_ICLOUD
                    if state == .ready {
                        PushRelay.onToken = { token in Task { await feed.savePushToken(token) } }
                        if let token = UserDefaults.standard.string(forKey: FeedPush.tokenKey), FeedPush.isEnabled {
                            Task { await feed.savePushToken(token) }
                        }
                    }
                    #endif
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        spotify.connectIfAuthorized()
                        health.refresh()
                        WaterReminders.reconcile()
                        Reminders.reconcile(store: store)
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

    /// Publishes the border earned from this iPhone's challenges, records and trophies.
    private func syncBorder() async {
        let path = PathProgress(store: store)
        await feed.syncBorder(path.tier)
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
