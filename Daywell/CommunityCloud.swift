import CloudKit
import CryptoKit
import Foundation

@MainActor
final class CommunityCloud: ObservableObject {
    @Published private(set) var accountReady = false
    @Published private(set) var accountMessage = "Checking iCloud…"
    @Published private(set) var syncMessage = "Your history has not synced yet."
    @Published private(set) var isBusy = false
    @Published private(set) var hasConflict = false

    private lazy var container = CKContainer(identifier: "iCloud.com.daywell.nutrition")
    private let backupID = CKRecord.ID(recordName: "NAGISENPrivateBackupV1")
    private var lastSyncedKey: String {
        "nagisen.cloud.lastSyncedDigest.\(currentUserID ?? "unavailable")"
    }
    private var currentUserID: String?

    func connect() async {
        #if targetEnvironment(simulator)
        accountReady = false
        accountMessage = "iCloud sync is available on iPhone."
        return
        #elseif NAGISEN_NO_ICLOUD
        // Builds signed by a personal team cannot carry the iCloud entitlement.
        accountReady = false
        accountMessage = "iCloud isn’t available in this test build."
        return
        #else
        let status: CKAccountStatus = await withCheckedContinuation { continuation in
            container.accountStatus { status, _ in continuation.resume(returning: status) }
        }
        accountReady = status == .available
        accountMessage = accountReady ? "Connected with your Apple Account" :
            "Sign in to iCloud in iPhone Settings to sync."
        guard accountReady else { currentUserID = nil; return }
        let userRecord = try? await container.userRecordID()
        currentUserID = userRecord?.recordName
        if currentUserID == nil {
            accountReady = false
            accountMessage = "Couldn’t identify this iCloud account. Try again in a moment."
        }
        #endif
    }

    func sync(_ store: NutritionStore) async {
        guard accountReady, !isBusy, let local = store.exportJSON() else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let remote = try await fetchBackup()
            let localDigest = digest(local)
            guard let remote else {
                try await upload(local, previous: nil)
                return
            }
            let remoteDigest = digest(remote.data)
            if localDigest == remoteDigest {
                UserDefaults.standard.set(localDigest, forKey: lastSyncedKey)
                hasConflict = false
                syncMessage = "Up to date in iCloud"
                return
            }
            let last = UserDefaults.standard.string(forKey: lastSyncedKey)
            if last == remoteDigest {
                try await upload(local, previous: remote.record)
            } else if last == localDigest || (last == nil && !hasPersonalHistory(store)) {
                guard store.backupNow(), store.restoreJSON(remote.data) else {
                    syncMessage = "iCloud backup could not be read. Your iPhone data is unchanged."
                    return
                }
                UserDefaults.standard.set(remoteDigest, forKey: lastSyncedKey)
                hasConflict = false
                syncMessage = "Restored from iCloud"
            } else {
                hasConflict = true
                syncMessage = "This iPhone and iCloud both have changes. Choose which copy to keep in Your space."
            }
        } catch {
            syncMessage = "iCloud sync unavailable: \(error.localizedDescription)"
        }
    }

    func keepThisPhone(_ store: NutritionStore) async {
        guard accountReady, let data = store.exportJSON() else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await upload(data, previous: try await fetchBackup()?.record)
        } catch {
            syncMessage = "Couldn’t upload this iPhone: \(error.localizedDescription)"
        }
    }

    func useICloud(_ store: NutritionStore) async {
        guard accountReady else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            guard let remote = try await fetchBackup(), store.backupNow(),
                  store.restoreJSON(remote.data) else {
                syncMessage = "Couldn’t restore the iCloud copy. Your iPhone data is unchanged."
                return
            }
            UserDefaults.standard.set(digest(remote.data), forKey: lastSyncedKey)
            hasConflict = false
            syncMessage = "Restored from iCloud"
        } catch {
            syncMessage = "Couldn’t restore from iCloud: \(error.localizedDescription)"
        }
    }

    private func fetchBackup() async throws -> (record: CKRecord, data: Data)? {
        do {
            let record = try await container.privateCloudDatabase.record(for: backupID)
            guard let asset = record["snapshot"] as? CKAsset, let url = asset.fileURL else { return nil }
            return (record, try Data(contentsOf: url))
        } catch let error as CKError where error.code == .unknownItem { return nil }
    }

    private func upload(_ data: Data, previous: CKRecord?) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nagisen-cloud-\(UUID().uuidString).json")
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        let record = previous ?? CKRecord(recordType: "NagisenPrivateBackup", recordID: backupID)
        record["snapshot"] = CKAsset(fileURL: url)
        _ = try await container.privateCloudDatabase.save(record)
        UserDefaults.standard.set(digest(data), forKey: lastSyncedKey)
        hasConflict = false
        syncMessage = "Saved to iCloud"
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func hasPersonalHistory(_ store: NutritionStore) -> Bool {
        !store.entries.isEmpty || !store.weights.isEmpty || !store.workouts.isEmpty ||
        !store.groceryStock.isEmpty || !store.customFoods.isEmpty || !store.waterEntries.isEmpty ||
        !store.completedLoggingDays.isEmpty || !store.strengthRecords.isEmpty ||
        !store.creatineTakenDays.isEmpty ||
        store.goals.calories != 2000 || store.goals.protein != 120 || store.goals.fat != 65 ||
        store.profile.age != nil || store.profile.heightCm != nil
    }
}
