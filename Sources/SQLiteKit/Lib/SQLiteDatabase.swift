import Foundation
import SQLiteSwiftCSQLite
#if SQLiteVec
import CSQLiteVec
#endif

/// An error surfaced by SQLite, carrying the result code, message, the
/// byte offset of the error within the SQL (or -1), and whether it arose
/// while preparing or stepping the statement — the CLI uses all of these
/// to reproduce sqlite3's exact error reporting.
public struct SQLiteError: Error, CustomStringConvertible, Equatable, Sendable {
    public enum Phase: Sendable, Equatable { case prepare, step }

    public let code: Int32
    public let message: String
    public let offset: Int32
    public let phase: Phase

    public init(code: Int32, message: String, offset: Int32 = -1, phase: Phase = .prepare) {
        self.code = code
        self.message = message
        self.offset = offset
        self.phase = phase
    }

    public var description: String { message }
}

#if SQLiteVec
/// Registers sqlite-vec exactly once, before the first connection opens, so
/// every ``SQLiteDatabase`` exposes the `vec0` virtual table and `vec_*`
/// functions. A file-scope `let` initializes lazily and thread-safely, so
/// touching it at the top of `init` runs the registration a single time.
/// Gated behind the `SQLiteVec` package trait.
private let sqliteVecRegistered: Void = {
    _ = csqlite_vec_register()
}()
#endif

/// A thin Swift wrapper over a SQLite connection backed by the vendored
/// amalgamation. Intentionally minimal — just what the `sqlite3` CLI and
/// in-process embedders need to run SQL and read results back.
public final class SQLiteDatabase {
    public enum Location: Equatable, Sendable {
        case memory
        case file(String)
    }

    private var handle: OpaquePointer?

    public init(_ location: Location, readonly: Bool = false) throws {
        #if SQLiteVec
        _ = sqliteVecRegistered   // one-time sqlite-vec auto-extension registration
        #endif
        let path: String
        switch location {
        case .memory: path = ":memory:"
        case .file(let p): path = p
        }
        let flags = readonly
            ? SQLITE_OPEN_READONLY
            : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        var opened: OpaquePointer?
        let rc = sqlite3_open_v2(path, &opened, flags, nil)
        guard rc == SQLITE_OK, let opened else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) }
                ?? "unable to open database \"\(path)\""
            if let opened { sqlite3_close_v2(opened) }
            throw SQLiteError(code: rc, message: message)
        }
        handle = opened
    }

    public convenience init(path: String, readonly: Bool = false) throws {
        try self.init(.file(path), readonly: readonly)
    }

    public static func inMemory() throws -> SQLiteDatabase {
        try SQLiteDatabase(.memory)
    }

    deinit { close() }

    public func close() {
        if let handle {
            sqlite3_close_v2(handle)
            self.handle = nil
        }
    }

    public var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }
    public var changes: Int { Int(sqlite3_changes(handle)) }
    public var totalChanges: Int { Int(sqlite3_total_changes(handle)) }

    // MARK: Running SQL

    /// Runs every statement in `sql`, collecting one ``ResultSet`` per
    /// statement that returns columns (SELECT / PRAGMA / RETURNING …).
    /// Statements that don't return rows still execute but add no set.
    @discardableResult
    public func evaluate(_ sql: String) throws -> [ResultSet] {
        var sets: [ResultSet] = []
        try eachStatement(in: sql) { stmt in
            let columns = Self.columnNames(stmt)
            var rows: [[SQLiteValue]] = []
            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_DONE { break }
                guard rc == SQLITE_ROW else { throw self.lastError(phase: .step) }
                if !columns.isEmpty {
                    rows.append(Self.rowValues(stmt, count: columns.count))
                }
            }
            if !columns.isEmpty {
                sets.append(ResultSet(columns: columns, rows: rows))
            }
        }
        return sets
    }

    /// Streaming variant: runs every statement, invoking `row` for each
    /// result row as it is produced.
    public func execute(_ sql: String, row: ((SQLiteRow) throws -> Void)? = nil) throws {
        try eachStatement(in: sql) { stmt in
            let columns = Self.columnNames(stmt)
            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_DONE { break }
                guard rc == SQLITE_ROW else { throw self.lastError(phase: .step) }
                if let row, !columns.isEmpty {
                    try row(SQLiteRow(columns: columns,
                                      values: Self.rowValues(stmt, count: columns.count)))
                }
            }
        }
    }

    // MARK: Introspection

    public func tableNames() throws -> [String] {
        let sql = """
            SELECT name FROM sqlite_schema
            WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%'
            ORDER BY name;
            """
        return try evaluate(sql).first?.rows.compactMap { $0.first?.text } ?? []
    }

    public func schemaSQL(of table: String?) throws -> [String] {
        // Filter on `tbl_name`, not `name`, so `.schema foo` also returns
        // foo's indexes and triggers (whose tbl_name is foo) — matching
        // sqlite3. For the table/view row itself, tbl_name == name.
        let filter = table.map { " AND tbl_name = '\(Self.quote($0))'" } ?? ""
        let sql = "SELECT sql FROM sqlite_schema WHERE sql NOT NULL\(filter) ORDER BY rowid;"
        return try evaluate(sql).first?.rows.compactMap { $0.first?.text } ?? []
    }

    public func databaseList() throws -> [(name: String, file: String)] {
        try evaluate("PRAGMA database_list;").first?.rows.map { row in
            (name: row.count > 1 ? (row[1].text ?? "") : "",
             file: row.count > 2 ? (row[2].text ?? "") : "")
        } ?? []
    }

    /// Whether the named database (default `main`) is open read-only — used
    /// by `.databases` to print the `r/w` / `r/o` tag.
    public func isReadOnly(_ name: String = "main") -> Bool {
        sqlite3_db_readonly(handle, name) == 1
    }

    /// Reads (or, when `newValue >= 0`, sets and returns the new effective
    /// value of) a run-time limit — backing the `.limit` dot-command.
    /// `code` is a `SQLITE_LIMIT_*` constant.
    @discardableResult
    public func limit(_ code: Int32, newValue: Int32 = -1) -> Int32 {
        let prior = sqlite3_limit(handle, code, newValue)
        // sqlite3_limit returns the PRIOR value; re-read to report the new
        // (possibly clamped) one after a set.
        return newValue < 0 ? prior : sqlite3_limit(handle, code, -1)
    }

    // MARK: -safe authorizer

    /// When the `-safe`-mode authorizer denies an operation, the shell's
    /// refusal message for it (e.g. `cannot run ATTACH in safe mode`). The
    /// CLI reads and clears this after a failed statement so it reports
    /// sqlite3's exact safe-mode error rather than the engine's
    /// "not authorized".
    public private(set) var safeModeViolation: String?

    public func clearSafeModeViolation() { safeModeViolation = nil }

    /// Filesystem-reaching SQL functions `-safe` mode forbids. `load_extension`
    /// is the one present in the amalgamation; `readfile` / `writefile` /
    /// `edit` / `fsdir` / `zipfile` are CLI-shell-only (absent here, so they
    /// already fail as "no such function") — listed for forward-compatibility.
    private static let safeModeProhibitedFunctions: Set<String> = [
        "load_extension", "readfile", "writefile", "edit", "fsdir", "zipfile",
    ]

    /// Scratch buffer for ``attachTargets(in:)`` — the recording authorizer
    /// appends ATTACH filenames here.
    private var collectedAttachPaths: [String] = []

    /// The file paths the `ATTACH` statements in `sql` would open, found by
    /// preparing each statement (never stepping it, so nothing runs and no
    /// file is opened) under a recording authorizer. The CLI gates these
    /// through ShellKit's sandbox before executing the SQL for real — the
    /// same `resolve` + `authorize` path the database file / `.read` /
    /// `.open` already take, so ATTACH can't reach outside the sandbox.
    ///
    /// Literal paths (the overwhelmingly common form) are captured regardless
    /// of statement order. An ATTACH whose path *expression* only resolves
    /// after a prior statement executes isn't pre-seen — closing that needs a
    /// VFS-level interceptor (a tracked follow-up), not this prepare pass.
    public func attachTargets(in sql: String) -> [String] {
        collectedAttachPaths = []
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        sqlite3_set_authorizer(handle, { ctx, op, filename, _, _, _ in
            if op == SQLITE_ATTACH, let ctx, let filename {
                Unmanaged<SQLiteDatabase>.fromOpaque(ctx).takeUnretainedValue()
                    .collectedAttachPaths.append(String(cString: filename))
            }
            return SQLITE_OK
        }, ctx)
        defer { sqlite3_set_authorizer(handle, nil, nil) }
        sql.withCString { start in
            let end = start + sql.utf8.count
            var cursor: UnsafePointer<CChar>? = start
            while let head = cursor, head < end {
                var stmt: OpaquePointer?
                var tail: UnsafePointer<CChar>?
                // Prepare-only: the authorizer observes ATTACHes without any
                // statement executing. Stop at the first prepare error (a
                // later statement may depend on an earlier one running).
                guard sqlite3_prepare_v2(handle, head, -1, &stmt, &tail) == SQLITE_OK else { break }
                if let stmt { sqlite3_finalize(stmt) }
                guard let tail, tail != cursor else { break }
                cursor = tail
            }
        }
        return collectedAttachPaths
    }

    /// Installs sqlite3's `-safe` SQL-level authorizer: deny `ATTACH` (any
    /// target — it can create a disk file) and the filesystem-reaching
    /// functions, recording the matching refusal message. `DETACH` and every
    /// other operation stay allowed, matching the real shell.
    public func enableSafeMode() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        sqlite3_set_authorizer(handle, { ctx, op, _, fnName, _, _ in
            guard let ctx else { return SQLITE_OK }
            let db = Unmanaged<SQLiteDatabase>.fromOpaque(ctx).takeUnretainedValue()
            switch op {
            case SQLITE_ATTACH:
                db.safeModeViolation = "cannot run ATTACH in safe mode"
                return SQLITE_DENY
            case SQLITE_FUNCTION:
                guard let fnName else { return SQLITE_OK }
                let name = String(cString: fnName)
                if SQLiteDatabase.safeModeProhibitedFunctions.contains(name) {
                    db.safeModeViolation = "cannot use the \(name)() function in safe mode"
                    return SQLITE_DENY
                }
                return SQLITE_OK
            default:
                return SQLITE_OK
            }
        }, context)
    }

    /// The names of `table`'s real (non-generated) columns in declared
    /// order. `.dump` must SELECT only these so VIRTUAL / STORED generated
    /// columns are excluded from the emitted `INSERT` — matching sqlite3,
    /// whose dump emits the bare `INSERT INTO t VALUES(…)` with only the
    /// storable values (a dump that included generated values can't replay).
    /// Reads `pragma_table_xinfo`'s `hidden` flag: 2 = VIRTUAL generated,
    /// 3 = STORED generated (0 / 1 = ordinary / hidden-but-storable).
    public func nonGeneratedColumns(of table: String) throws -> [String] {
        let sql = """
            SELECT name FROM pragma_table_xinfo('\(Self.quote(table))')
            WHERE hidden NOT IN (2, 3) ORDER BY cid;
            """
        return try evaluate(sql).first?.rows.compactMap { $0.first?.text } ?? []
    }

    /// Copies this database into `destination` using SQLite's online backup
    /// API — backing the CLI's `.backup` / `.restore`.
    public func backup(to destination: SQLiteDatabase,
                       sourceName: String = "main",
                       destinationName: String = "main") throws {
        guard let backup = sqlite3_backup_init(destination.handle, destinationName, handle, sourceName) else {
            throw SQLiteError(code: sqlite3_errcode(destination.handle),
                              message: String(cString: sqlite3_errmsg(destination.handle)))
        }
        sqlite3_backup_step(backup, -1)
        let rc = sqlite3_backup_finish(backup)
        guard rc == SQLITE_OK else {
            throw SQLiteError(code: rc, message: String(cString: sqlite3_errmsg(destination.handle)))
        }
    }

    // MARK: Static helpers

    public static var libVersion: String { String(cString: sqlite3_libversion()) }
    public static var sourceID: String { String(cString: sqlite3_sourceid()) }

    /// True when `sql` forms one or more complete statements — used by a
    /// REPL to know when enough input has been read to execute.
    public static func isCompleteStatement(_ sql: String) -> Bool {
        sqlite3_complete(sql) != 0
    }

    /// Escapes a string for use inside a single-quoted SQL literal.
    public static func quote(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "''")
    }

    /// Quotes a SQL identifier the way the `sqlite3` shell does in `.dump`:
    /// a simple identifier — an ASCII letter or `_` followed by letters,
    /// digits, or `_`, and not a SQL keyword — is returned bare; anything
    /// else is wrapped in double quotes with embedded `"` doubled. This keeps
    /// emitted DDL/DML valid for any table name (e.g. `order`, `my table`).
    public static func quoteIdentifier(_ name: String) -> String {
        guard identifierNeedsQuoting(name) else { return name }
        return "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func identifierNeedsQuoting(_ name: String) -> Bool {
        func isAlpha(_ v: UInt32) -> Bool {
            (v >= 65 && v <= 90) || (v >= 97 && v <= 122) || v == 95   // A–Z a–z _
        }
        func isAlnum(_ v: UInt32) -> Bool { isAlpha(v) || (v >= 48 && v <= 57) }  // + 0–9
        let scalars = name.unicodeScalars
        guard let first = scalars.first, isAlpha(first.value) else { return true }
        guard scalars.dropFirst().allSatisfy({ isAlnum($0.value) }) else { return true }
        // A lexically-simple identifier that collides with a SQL keyword
        // (e.g. `order`) still needs quoting; ask the engine's own keyword set.
        return name.withCString { sqlite3_keyword_check($0, Int32(name.utf8.count)) != 0 }
    }

    // MARK: Internals

    private func lastError(phase: SQLiteError.Phase) -> SQLiteError {
        SQLiteError(code: sqlite3_errcode(handle),
                    message: String(cString: sqlite3_errmsg(handle)),
                    offset: sqlite3_error_offset(handle),
                    phase: phase)
    }

    /// Prepares each statement in `sql` in turn and hands it to `body`,
    /// finalizing afterwards. `body` is responsible for stepping it.
    private func eachStatement(in sql: String, _ body: (OpaquePointer) throws -> Void) throws {
        try sql.withCString { start in
            let end = start + sql.utf8.count
            var cursor: UnsafePointer<CChar>? = start
            while let head = cursor, head < end {
                var stmt: OpaquePointer?
                var tail: UnsafePointer<CChar>?
                let rc = sqlite3_prepare_v2(handle, head, -1, &stmt, &tail)
                guard rc == SQLITE_OK else { throw lastError(phase: .prepare) }
                let advanced = (tail != cursor)
                cursor = tail
                guard let stmt else {
                    // Blank / comment-only fragment: skip if we made progress,
                    // otherwise stop to avoid spinning.
                    if advanced { continue } else { break }
                }
                defer { sqlite3_finalize(stmt) }
                try body(stmt)
            }
        }
    }

    private static func columnNames(_ stmt: OpaquePointer) -> [String] {
        let count = Int(sqlite3_column_count(stmt))
        guard count > 0 else { return [] }
        return (0..<count).map { String(cString: sqlite3_column_name(stmt, Int32($0))) }
    }

    private static func rowValues(_ stmt: OpaquePointer, count: Int) -> [SQLiteValue] {
        (0..<count).map { columnValue(stmt, Int32($0)) }
    }

    private static func columnValue(_ stmt: OpaquePointer, _ i: Int32) -> SQLiteValue {
        switch sqlite3_column_type(stmt, i) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(stmt, i))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(stmt, i))
        case SQLITE_NULL:
            return .null
        case SQLITE_BLOB:
            if let bytes = sqlite3_column_blob(stmt, i) {
                return .blob(Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, i))))
            }
            return .blob(Data())
        default:
            if let c = sqlite3_column_text(stmt, i) {
                return .text(String(cString: c))
            }
            return .text("")
        }
    }
}

private extension SQLiteValue {
    /// Convenience used by the introspection helpers above.
    var text: String? {
        if case .text(let s) = self { return s }
        return nil
    }
}
