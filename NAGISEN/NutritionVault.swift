import Foundation
import SQLite3

/// A small transactional database for the diary and settings. Each collection has its own row.
final class NutritionVault {
    private var database: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init?() {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = support.appendingPathComponent("NAGISEN", isDirectory: true)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { return nil }
        let path = folder.appendingPathComponent("nutrition.sqlite").path
        guard sqlite3_open(path, &database) == SQLITE_OK else {
            if database != nil { sqlite3_close(database) }
            database = nil
            return nil
        }
        _ = sqlite3_exec(database, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        _ = sqlite3_exec(database, "PRAGMA synchronous=FULL;", nil, nil, nil)
        guard sqlite3_exec(database, "CREATE TABLE IF NOT EXISTS records (key TEXT PRIMARY KEY, value BLOB NOT NULL);", nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(database)
            database = nil
            return nil
        }
    }

    deinit { if database != nil { sqlite3_close(database) } }

    func read<T: Decodable>(_ key: String, as type: T.Type = T.self) -> T? {
        guard let database else { return nil }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "SELECT value FROM records WHERE key = ?", -1, &statement, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(statement, 1, key, -1, Self.transient)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let bytes = sqlite3_column_blob(statement, 0) else { return nil }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        return try? decoder.decode(type, from: data)
    }

    @discardableResult
    func write<T: Encodable>(_ key: String, value: T) -> Bool {
        guard let database, let data = try? encoder.encode(value) else { return false }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "INSERT OR REPLACE INTO records (key, value) VALUES (?, ?)", -1, &statement, nil) == SQLITE_OK else { return false }
        sqlite3_bind_text(statement, 1, key, -1, Self.transient)
        let result = data.withUnsafeBytes { buffer in
            sqlite3_bind_blob(statement, 2, buffer.baseAddress, Int32(buffer.count), Self.transient)
            return sqlite3_step(statement)
        }
        return result == SQLITE_DONE
    }

    @discardableResult
    func transaction(_ work: () -> Bool) -> Bool {
        guard let database, sqlite3_exec(database, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { return false }
        if work(), sqlite3_exec(database, "COMMIT", nil, nil, nil) == SQLITE_OK { return true }
        _ = sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
        return false
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
