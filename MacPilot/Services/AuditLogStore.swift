import Foundation
import SQLite3

/// Minimal local audit log stored inside the app's sandbox container.
/// Only event names and timestamps are persisted; user file paths are deliberately excluded.
final class AuditLogStore {
    static let shared = AuditLogStore()

    private let database: OpaquePointer?
    private let queue = DispatchQueue(label: "com.macpilot.audit-log")

    private init() {
        let fileManager = FileManager.default
        let baseURL = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        let appDirectory = baseURL.appendingPathComponent("MacPilot", isDirectory: true)
        try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        var handle: OpaquePointer?
        if sqlite3_open(appDirectory.appendingPathComponent("audit.sqlite3").path, &handle) == SQLITE_OK {
            let createTable = """
            CREATE TABLE IF NOT EXISTS audit_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                event TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            """
            sqlite3_exec(handle, createTable, nil, nil, nil)
            database = handle
        } else {
            if let handle { sqlite3_close(handle) }
            database = nil
        }
    }

    func record(_ event: String) {
        queue.async { [weak self] in
            guard let database = self?.database else { return }
            let safeEvent = event.replacingOccurrences(of: "'", with: "''")
            let sql = "INSERT INTO audit_events (event) VALUES ('\(safeEvent)');"
            sqlite3_exec(database, sql, nil, nil, nil)
        }
    }

    deinit {
        if let database { sqlite3_close(database) }
    }
}
