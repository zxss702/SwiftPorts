import Foundation

/// A single column value read from SQLite, preserving its storage class.
public enum SQLiteValue: Equatable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
}

public extension SQLiteValue {
    /// The value rendered the way SQLite's shell prints it in text modes
    /// (list / column / csv / line), or `nil` for `NULL` so the caller can
    /// substitute its configured null placeholder.
    var cliText: String? {
        switch self {
        case .null: return nil
        case .integer(let i): return String(i)
        case .real(let d): return String(d)
        case .text(let s): return s
        // sqlite3 dumps raw blob bytes in text modes; we decode as UTF-8
        // (lossy for non-textual binary), since the formatter works in
        // String space rather than raw bytes.
        case .blob(let b): return String(decoding: b, as: UTF8.self)
        }
    }

    /// The value as a SQL literal — how sqlite3 renders it in `quote` /
    /// `insert` modes and `.dump`. Strings are single-quoted (quotes
    /// doubled), blobs become `X'…'`, NULL becomes `NULL`.
    var sqlLiteral: String {
        switch self {
        case .null: return "NULL"
        case .integer(let i): return String(i)
        case .real(let d): return String(d)
        case .text(let s): return "'" + s.replacingOccurrences(of: "'", with: "''") + "'"
        case .blob(let b): return "X'" + b.map { String(format: "%02x", $0) }.joined() + "'"
        }
    }
}

/// One result row: parallel `columns` and `values` arrays.
public struct SQLiteRow: Sendable {
    public let columns: [String]
    public let values: [SQLiteValue]

    public init(columns: [String], values: [SQLiteValue]) {
        self.columns = columns
        self.values = values
    }

    public subscript(index: Int) -> SQLiteValue { values[index] }

    public subscript(name: String) -> SQLiteValue? {
        columns.firstIndex(of: name).map { values[$0] }
    }
}

/// The columns + rows produced by a single result-bearing SQL statement.
public struct ResultSet: Sendable {
    public let columns: [String]
    public let rows: [[SQLiteValue]]

    public init(columns: [String], rows: [[SQLiteValue]]) {
        self.columns = columns
        self.rows = rows
    }
}
