import Foundation
import SQLite3

/// Reads a chat's name ("Predictive ordering UI sweep") from Cursor's own database.
///
/// This goes against SPEC section 2, which kept Cursor's database out because it's undocumented.
/// Nina chose it to match her tab names (DECISIONS.md). So it's kept as small and safe as possible:
/// opened read-only, one lookup by chat id, names only, and any failure just means no name,
/// in which case the ticket falls back to the first-message name.
public enum CursorChatNames {
    /// Cursor's global state database, or CONTROL_ROOM_CURSOR_STATE_DB if set (used by tests).
    static var databasePath: String {
        if let override = ProcessInfo.processInfo.environment["CONTROL_ROOM_CURSOR_STATE_DB"] { return override }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb").path
    }

    public static func name(for conversationID: String) -> String? {
        let path = databasePath
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open_v2("file:\(path)?mode=ro", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        // Cursor is writing to it at the same time; wait briefly rather than fail.
        sqlite3_busy_timeout(db, 200)

        var statement: OpaquePointer?
        let sql = "SELECT json_extract(value, '$.name') FROM cursorDiskKV WHERE key = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, "composerData:\(conversationID)", -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { return nil }
        let name = String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}
