import Foundation
import SQLite3

enum SQLiteValue: Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
}

struct SQLiteRow: Sendable {
    private let values: [String: SQLiteValue]

    init(values: [String: SQLiteValue]) {
        self.values = values
    }

    func data(_ column: String) -> Data? {
        guard case .blob(let data) = values[column] else {
            return nil
        }

        return data
    }
}

final class SQLiteDatabase: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: OpaquePointer?

    init(fileURL: URL = .vicuConfigurationDatabaseURL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var openedHandle: OpaquePointer?
        let status = sqlite3_open_v2(
            fileURL.path,
            &openedHandle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )

        guard status == SQLITE_OK, let openedHandle else {
            let message = openedHandle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database."
            sqlite3_close(openedHandle)
            throw SQLiteDatabaseError.openFailed(message)
        }

        handle = openedHandle
        try executeRaw("PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL;")
    }

    deinit {
        lock.lock()
        defer { lock.unlock() }

        if let handle {
            sqlite3_close(handle)
        }
        handle = nil
    }

    // Executes one or more semicolon-separated SQL statements via sqlite3_exec.
    // Use for DDL (CREATE TABLE, CREATE INDEX, PRAGMA) where multi-statement
    // strings are convenient. Do NOT use for DML with user-supplied values —
    // use execute(_:bindings:) instead, which uses prepared statements to prevent
    // injection and only accepts a single statement per call.
    func executeRaw(_ sql: String) throws {
        try withLockedHandle { handle in
            var errorMessage: UnsafeMutablePointer<CChar>?
            let status = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
            guard status == SQLITE_OK else {
                let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
                sqlite3_free(errorMessage)
                throw SQLiteDatabaseError.executionFailed(message)
            }
        }
    }

    func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        try withLockedStatement(sql, bindings: bindings) { statement in
            let status = sqlite3_step(statement)
            guard status == SQLITE_DONE else {
                throw SQLiteDatabaseError.executionFailed(errorMessage)
            }
        }
    }

    func query(_ sql: String, bindings: [SQLiteValue] = []) throws -> [SQLiteRow] {
        try withLockedStatement(sql, bindings: bindings) { statement in
            var rows: [SQLiteRow] = []

            while true {
                let status = sqlite3_step(statement)
                switch status {
                case SQLITE_ROW:
                    rows.append(Self.row(from: statement))
                case SQLITE_DONE:
                    return rows
                default:
                    throw SQLiteDatabaseError.executionFailed(errorMessage)
                }
            }
        }
    }

    private func withLockedStatement<T>(
        _ sql: String,
        bindings: [SQLiteValue],
        _ body: (OpaquePointer?) throws -> T
    ) throws -> T {
        try withLockedHandle { handle in
            var statement: OpaquePointer?
            let prepareStatus = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
            guard prepareStatus == SQLITE_OK else {
                throw SQLiteDatabaseError.prepareFailed(String(cString: sqlite3_errmsg(handle)))
            }
            defer { sqlite3_finalize(statement) }

            for (index, value) in bindings.enumerated() {
                try bind(value, to: statement, at: Int32(index + 1))
            }

            return try body(statement)
        }
    }

    private func withLockedHandle<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }

        guard let handle else {
            throw SQLiteDatabaseError.closed
        }

        return try body(handle)
    }

    private func bind(_ value: SQLiteValue, to statement: OpaquePointer?, at index: Int32) throws {
        let status: Int32
        switch value {
        case .null:
            status = sqlite3_bind_null(statement, index)
        case .integer(let value):
            status = sqlite3_bind_int64(statement, index, value)
        case .real(let value):
            status = sqlite3_bind_double(statement, index, value)
        case .text(let value):
            status = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        case .blob(let data):
            status = data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(data.count), sqliteTransient)
            }
        }

        guard status == SQLITE_OK else {
            throw SQLiteDatabaseError.bindFailed(errorMessage)
        }
    }

    private static func row(from statement: OpaquePointer?) -> SQLiteRow {
        var values: [String: SQLiteValue] = [:]

        for columnIndex in 0..<sqlite3_column_count(statement) {
            let columnName = sqlite3_column_name(statement, columnIndex).map { String(cString: $0) } ?? ""
            let value: SQLiteValue

            switch sqlite3_column_type(statement, columnIndex) {
            case SQLITE_INTEGER:
                value = .integer(sqlite3_column_int64(statement, columnIndex))
            case SQLITE_FLOAT:
                value = .real(sqlite3_column_double(statement, columnIndex))
            case SQLITE_TEXT:
                let text = sqlite3_column_text(statement, columnIndex).map { String(cString: $0) } ?? ""
                value = .text(text)
            case SQLITE_BLOB:
                let byteCount = Int(sqlite3_column_bytes(statement, columnIndex))
                if byteCount > 0, let bytes = sqlite3_column_blob(statement, columnIndex) {
                    value = .blob(Data(bytes: bytes, count: byteCount))
                } else {
                    value = .blob(Data())
                }
            default:
                value = .null
            }

            values[columnName] = value
        }

        return SQLiteRow(values: values)
    }

    private var errorMessage: String {
        guard let handle else {
            return "Database connection is closed."
        }

        return String(cString: sqlite3_errmsg(handle))
    }
}

enum SQLiteDatabaseError: LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case bindFailed(String)
    case executionFailed(String)
    case closed

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            "SQLite open failed: \(message)"
        case .prepareFailed(let message):
            "SQLite prepare failed: \(message)"
        case .bindFailed(let message):
            "SQLite bind failed: \(message)"
        case .executionFailed(let message):
            "SQLite execution failed: \(message)"
        case .closed:
            "SQLite database is closed."
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private extension URL {
    static var vicuConfigurationDatabaseURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL
            .appendingPathComponent("Vicu", isDirectory: true)
            .appendingPathComponent("configuration.sqlite3")
    }
}
