import Foundation
import SQLiteSwiftCSQLite

/// SQLite's `SQLITE_TRANSIENT` sentinel — a `(-1)`-valued destructor pointer
/// telling the engine to take its *own* copy of bound text / blob bytes
/// before the bind call returns. The macro isn't imported into Swift, so we
/// reconstruct it the canonical way. Without this, SQLite would alias the
/// Swift `String` / `Data` buffer, which doesn't outlive the call — the
/// classic silent-garbage / use-after-free binding bug.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A prepared SQLite statement — a reusable handle for the bulk path
/// (prepare once, bind + step + reset many). Values are handed to SQLite
/// *separately* from the SQL text via the `sqlite3_bind_*` family, so there
/// is no escaping, no literal interpolation, and no re-parse of the statement
/// between rows.
///
/// ```swift
/// let stmt = try SQLiteStatement(db, "INSERT INTO vecs(rowid, v) VALUES (?, ?)")
/// for (id, vector) in chunks {          // vector: Data of packed float32
///     try stmt.bind([.integer(id), .blob(vector)])
///     _ = try stmt.step()
///     stmt.reset()
/// }
/// ```
///
/// Single statement only: binding can't disambiguate which `?` belongs to
/// which statement, so the initializer prepares exactly one and throws if a
/// second follows. The handle is finalized in `deinit`; the strong reference
/// to the owning ``SQLiteDatabase`` keeps the connection alive for the
/// statement's lifetime.
public final class SQLiteStatement {
    /// Held strongly so the connection outlives the statement and so bind /
    /// step errors can be read from it.
    private let database: SQLiteDatabase
    private var handle: OpaquePointer?

    /// The result column names, fixed at prepare time. Empty for statements
    /// that return no rows (INSERT / UPDATE / DELETE / DDL).
    public let columns: [String]

    /// Prepares `sql` as a single statement against `database`.
    /// - Throws: ``SQLiteError`` on a syntax error, blank input, or a
    ///   trailing second statement.
    public init(_ database: SQLiteDatabase, _ sql: String) throws {
        self.database = database
        let stmt = try database.prepareSingleStatement(sql)
        self.handle = stmt
        self.columns = SQLiteDatabase.columnNames(stmt)
    }

    deinit {
        if let handle { sqlite3_finalize(handle) }
    }

    /// Binds all positional `?`-parameters at once (1-based at the SQL level,
    /// 0-based in the array), clearing any prior bindings first. Throws a
    /// `.prepare`-phase error when the count doesn't match the statement's
    /// parameter count.
    public func bind(_ parameters: [SQLiteValue]) throws {
        guard let handle else { return }
        let expected = Int(sqlite3_bind_parameter_count(handle))
        guard parameters.count == expected else {
            throw SQLiteError(
                code: SQLITE_ERROR,
                message: "statement has \(expected) parameter(s) but \(parameters.count) value(s) were bound",
                phase: .prepare)
        }
        sqlite3_clear_bindings(handle)
        for (offset, value) in parameters.enumerated() {
            try bind(value, at: Int32(offset + 1))
        }
    }

    /// Binds one named parameter (`:name` / `@name` / `$name`); `name`
    /// includes the leading sigil. An unknown name throws a `.prepare`-phase
    /// error. Does not clear other bindings, so several named binds compose.
    public func bind(_ name: String, _ value: SQLiteValue) throws {
        guard let handle else { return }
        let index = name.withCString { sqlite3_bind_parameter_index(handle, $0) }
        guard index != 0 else {
            throw SQLiteError(code: SQLITE_ERROR,
                              message: "no such parameter: \(name)", phase: .prepare)
        }
        try bind(value, at: index)
    }

    /// Steps the statement once. Returns the next ``SQLiteRow`` while rows
    /// remain, or `nil` at `SQLITE_DONE` (including immediately, for a
    /// statement that produces no rows).
    @discardableResult
    public func step() throws -> SQLiteRow? {
        guard let handle else { return nil }
        let rc = sqlite3_step(handle)
        if rc == SQLITE_DONE { return nil }
        guard rc == SQLITE_ROW else { throw database.lastError(phase: .step) }
        return SQLiteRow(columns: columns,
                         values: SQLiteDatabase.rowValues(handle, count: columns.count))
    }

    /// Resets the statement to its initial state and clears all bindings, so
    /// it can be re-bound and re-stepped for the next row.
    public func reset() {
        guard let handle else { return }
        sqlite3_reset(handle)
        sqlite3_clear_bindings(handle)
    }

    /// Steps to completion, collecting a single ``ResultSet`` when the
    /// statement produced columns. Backs the bound `evaluate(_:_:)` overloads.
    func collectResultSet() throws -> [ResultSet] {
        var rows: [[SQLiteValue]] = []
        while let produced = try step() {
            rows.append(produced.values)
        }
        return columns.isEmpty ? [] : [ResultSet(columns: columns, rows: rows)]
    }

    /// Dispatches one ``SQLiteValue`` onto the matching `sqlite3_bind_*` call.
    /// Text and blob binds use `SQLITE_TRANSIENT` so the engine copies the
    /// bytes — the Swift buffer doesn't outlive the call.
    private func bind(_ value: SQLiteValue, at index: Int32) throws {
        guard let handle else { return }
        let rc: Int32
        switch value {
        case .null:
            rc = sqlite3_bind_null(handle, index)
        case .integer(let v):
            rc = sqlite3_bind_int64(handle, index, v)
        case .real(let v):
            rc = sqlite3_bind_double(handle, index, v)
        case .text(let v):
            rc = sqlite3_bind_text(handle, index, v, -1, SQLITE_TRANSIENT)
        case .blob(let v):
            if v.isEmpty {
                // `withUnsafeBytes` yields a nil base pointer for empty Data,
                // which `sqlite3_bind_blob` would read as SQL NULL. Bind an
                // explicit zero-length blob instead.
                rc = sqlite3_bind_zeroblob(handle, index, 0)
            } else {
                rc = v.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(handle, index, buffer.baseAddress,
                                      Int32(buffer.count), SQLITE_TRANSIENT)
                }
            }
        }
        guard rc == SQLITE_OK else { throw database.lastError(phase: .prepare) }
    }
}
