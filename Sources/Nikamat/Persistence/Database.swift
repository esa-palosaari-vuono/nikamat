import Foundation
import SQLite3

/// A very small SQLite wrapper: prepare, bind, step.
///
/// SQLite is used rather than a private binary format precisely so the data is
/// not private: the file can be opened from Emacs (`M-x sqlite-mode-open-file`
/// or an org-babel `sqlite` block), the `sqlite3` command line, or any other
/// tool, without this app being running or even installed.
final class Database {
    enum Error: Swift.Error, CustomStringConvertible {
        case open(String)
        case statement(String)

        var description: String {
            switch self {
            case .open(let message): return "tietokantaa ei voitu avata: \(message)"
            case .statement(let message): return "SQL-virhe: \(message)"
            }
        }
    }

    /// A bindable value. Deliberately minimal — this schema stores timestamps
    /// as ISO 8601 text, which is what makes the file pleasant to read by hand.
    enum Value {
        case text(String)
        case int(Int)
        case double(Double)
        case null
    }

    private var handle: OpaquePointer?

    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "tuntematon virhe"
            sqlite3_close_v2(handle)
            throw Error.open(message)
        }
        self.handle = handle
        // Write-ahead logging so a reader (Emacs, sqlite3) never blocks the
        // app, and vice versa.
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA foreign_keys = ON")
    }

    deinit { sqlite3_close_v2(handle) }

    private var errorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "tuntematon virhe"
    }

    /// Run one or more statements with no results and no parameters.
    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw Error.statement("\(errorMessage) (\(sql))")
        }
    }

    /// Run a parameterised statement, returning the new rowid for inserts.
    @discardableResult
    func run(_ sql: String, _ parameters: [Value] = []) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Error.statement("\(errorMessage) (\(sql))")
        }
        defer { sqlite3_finalize(statement) }
        bind(parameters, to: statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw Error.statement("\(errorMessage) (\(sql))")
        }
        return Int(sqlite3_last_insert_rowid(handle))
    }

    /// Run a query and map each row.
    func query<T>(_ sql: String, _ parameters: [Value] = [], row: (Row) -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Error.statement("\(errorMessage) (\(sql))")
        }
        defer { sqlite3_finalize(statement) }
        bind(parameters, to: statement)
        var results: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(row(Row(statement: statement)))
        }
        return results
    }

    private func bind(_ parameters: [Value], to statement: OpaquePointer?) {
        for (offset, value) in parameters.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .text(let string): sqlite3_bind_text(statement, index, string, -1, SQLITE_TRANSIENT)
            case .int(let number): sqlite3_bind_int64(statement, index, Int64(number))
            case .double(let number): sqlite3_bind_double(statement, index, number)
            case .null: sqlite3_bind_null(statement, index)
            }
        }
    }

    /// One result row, addressed by column index.
    struct Row {
        let statement: OpaquePointer?

        func text(_ index: Int32) -> String {
            guard let cString = sqlite3_column_text(statement, index) else { return "" }
            return String(cString: cString)
        }

        func int(_ index: Int32) -> Int { Int(sqlite3_column_int64(statement, index)) }
        func double(_ index: Int32) -> Double { sqlite3_column_double(statement, index) }
    }
}

/// SQLite's own "copy this string" sentinel, which the C shim does not export.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
