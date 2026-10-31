import CloudKit
import CryptoKit
import Foundation

struct CommunityPost: Identifiable {
    let id: CKRecord.ID
    let authorName: String
    let authorID: String?
    let text: String
    let createdAt: Date

    init?(record: CKRecord) {
        guard let text = record["text"] as? String, !text.isEmpty else { return nil }
        id = record.recordID
        let savedName = record["authorName"] as? String ?? ""
        authorName = savedName.isEmpty ? "NAGISEN member" : savedName
        authorID = record.creatorUserRecordID?.recordName
        self.text = text
        createdAt = record.creationDate ?? .now
    }
}

@MainActor
final class CommunityCloud: ObservableObject {
    @Published private(set) var accountReady = false
    @Published private(set) var accountMessage = "Checking iCloud…"
    @Published private(set) var syncMessage = "Your history has not synced yet."
    @Published private(set) var posts: [CommunityPost] = []
    @Published private(set) var feedMessage: String?
    @Published private(set) var isBusy = false
    @Published private(set) var hasConflict = false

    private lazy var container = CKContainer(identifier: "iCloud.com.daywell.nutrition")
    private let backupID = CKRecord.ID(recordName: "NAGISENPrivateBackupV1")
    private var lastSyncedKey: String {
        "nagisen.cloud.lastSyncedDigest.\(currentUserID ?? "unavailable")"
    }
    private var currentUserID: String?
    private var cursor: CKQueryOperation.Cursor?

    func connect() async {
        #if targetEnvironment(simulator)
        accountReady = false
        accountMessage = "iCloud community is available on iPhone."
        return
        #else
        let status: CKAccountStatus = await withCheckedContinuation { continuation in
            container.accountStatus { status, _ in continuation.resume(returning: status) }
        }
        accountReady = status == .available
        accountMessage = accountReady ? "Connected with your Apple Account" :
            "Sign in to iCloud in iPhone Settings to post and sync."
        guard accountReady else { currentUserID = nil; return }
        let userRecord = try? await container.userRecordID()
        currentUserID = userRecord?.recordName
        if currentUserID == nil {
            accountReady = false
            accountMessage = "Couldn’t identify this iCloud account. Try again in a moment."
        }
        #endif
    }

    func refreshFeed() async {
        guard accountReady else { return }
        feedMessage = nil
        cursor = nil
        do {
            let query = CKQuery(recordType: "NagisenPost", predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let page = try await container.publicCloudDatabase.records(matching: query,
                                                                        resultsLimit: 40)
            posts = page.matchResults.compactMap { try? $0.1.get() }.compactMap(CommunityPost.init)
            cursor = page.queryCursor
        } catch let error as CKError where error.code == .unknownItem {
            posts = [] // New development container, before its first post creates the schema.
        } catch {
            feedMessage = "Couldn’t load the community. \(error.localizedDescription)"
        }
    }

    func loadMore() async {
        guard accountReady, let cursor else { return }
        do {
            let page = try await container.publicCloudDatabase.records(continuingMatchFrom: cursor,
                                                                        resultsLimit: 40)
            let more = page.matchResults.compactMap { try? $0.1.get() }.compactMap(CommunityPost.init)
            posts.append(contentsOf: more)
            self.cursor = page.queryCursor
        } catch {
            feedMessage = "Couldn’t load more posts. \(error.localizedDescription)"
        }
    }

    var canLoadMore: Bool { cursor != nil }

    func isMine(_ post: CommunityPost) -> Bool {
        post.authorID != nil && post.authorID == currentUserID
    }

    func publish(_ text: String, as name: String) async -> Bool {
        guard accountReady else { feedMessage = accountMessage; return false }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= 1000 else {
            feedMessage = "Posts must be between 1 and 1,000 characters."
            return false
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let record = CKRecord(recordType: "NagisenPost")
            record["text"] = body as NSString
            record["authorName"] = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)) as NSString
            let saved = try await container.publicCloudDatabase.save(record)
            if let post = CommunityPost(record: saved) { posts.insert(post, at: 0) }
            feedMessage = nil
            return true
        } catch {
            feedMessage = "Post wasn’t shared. \(error.localizedDescription)"
            return false
        }
    }

    func delete(_ post: CommunityPost) async {
        guard accountReady, isMine(post) else { return }
        do {
            _ = try await container.publicCloudDatabase.deleteRecord(withID: post.id)
            posts.removeAll { $0.id == post.id }
        } catch {
            feedMessage = "Couldn’t delete the post. \(error.localizedDescription)"
        }
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
