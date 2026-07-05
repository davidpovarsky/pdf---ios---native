import Foundation
import SQLite3

enum SQLiteValue {
    case null
    case int(Int)
    case int64(Int64)
    case double(Double)
    case text(String)
}

enum SQLiteDatabaseError: LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message): return "Database open failed: \(message)"
        case .prepareFailed(let message): return "Database prepare failed: \(message)"
        case .stepFailed(let message): return "Database step failed: \(message)"
        case .bindFailed(let message): return "Database bind failed: \(message)"
        }
    }
}

final class SQLiteDatabase {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "TorahPDFReader.SQLiteDatabase")

    init(url: URL) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(url.path, &handle, flags, nil) != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            throw SQLiteDatabaseError.openFailed(message)
        }
        db = handle
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA foreign_keys=ON;")
        try execute("PRAGMA synchronous=NORMAL;")
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func sync<T>(_ block: () throws -> T) rethrows -> T {
        try queue.sync(execute: block)
    }

    func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        try queue.sync {
            try self.executeOnQueue(sql, bindings: bindings)
        }
    }

    func query<T>(_ sql: String, bindings: [SQLiteValue] = [], rowHandler: (OpaquePointer) throws -> T) throws -> [T] {
        try queue.sync {
            var statement: OpaquePointer?
            guard let db else { throw SQLiteDatabaseError.openFailed("Missing handle") }
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                throw SQLiteDatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }
            try bind(bindings, to: statement)

            var rows: [T] = []
            while true {
                let code = sqlite3_step(statement)
                if code == SQLITE_ROW {
                    rows.append(try rowHandler(statement!))
                } else if code == SQLITE_DONE {
                    return rows
                } else {
                    throw SQLiteDatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
                }
            }
        }
    }

    func executeOnQueue(_ sql: String, bindings: [SQLiteValue] = []) throws {
        var statement: OpaquePointer?
        guard let db else { throw SQLiteDatabaseError.openFailed("Missing handle") }
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            throw SQLiteDatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        let code = sqlite3_step(statement)
        if code != SQLITE_DONE && code != SQLITE_ROW {
            throw SQLiteDatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func bind(_ bindings: [SQLiteValue], to statement: OpaquePointer?) throws {
        for (offset, value) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .null:
                result = sqlite3_bind_null(statement, index)
            case .int(let value):
                result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
            case .int64(let value):
                result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
            case .double(let value):
                result = sqlite3_bind_double(statement, index, value)
            case .text(let value):
                result = sqlite3_bind_text(statement, index, value, -1, SQLiteDatabase.transientDestructor)
            }
            if result != SQLITE_OK {
                throw SQLiteDatabaseError.bindFailed("Binding index \(index) failed")
            }
        }
    }

    private static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

extension OpaquePointer {
    func columnString(_ index: Int32) -> String {
        guard let cString = sqlite3_column_text(self, index) else { return "" }
        return String(cString: cString)
    }

    func columnOptionalString(_ index: Int32) -> String? {
        guard sqlite3_column_type(self, index) != SQLITE_NULL else { return nil }
        guard let cString = sqlite3_column_text(self, index) else { return nil }
        return String(cString: cString)
    }

    func columnInt(_ index: Int32) -> Int {
        Int(sqlite3_column_int64(self, index))
    }

    func columnDouble(_ index: Int32) -> Double {
        sqlite3_column_double(self, index)
    }
}
