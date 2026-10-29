import SwiftUI

@main
struct DaywellApp: App {
    @StateObject private var store = NutritionStore()
    @StateObject private var spotify = SpotifyManager()
    @StateObject private var health = HealthManager()
    @AppStorage("nagisen.health.autoImport") private var autoImportHealth = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(spotify)
                .environmentObject(health)
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
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        spotify.connectIfAuthorized()
                        health.refresh()
                        WaterReminders.reconcile()
                    }
                    if phase == .inactive { spotify.disconnect() }
                    if phase == .background { store.backupNow() }
                }
        }
    }
}
