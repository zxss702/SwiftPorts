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
        case .real(let d): return Self.realText(d)
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

extension SQLiteValue {
    /// Formats a Double the way the `sqlite3` shell does in text/display modes
    /// (`%!.15g`): 15 significant digits, always rendered as a real (a decimal
    /// point or exponent is guaranteed) and `-0.0` normalized to `0.0`.
    /// Round-trip contexts (quote / insert / `.dump`, and JSON) instead use
    /// full precision; see ``sqlLiteral``.
    static func realText(_ d: Double) -> String {
        if d == 0 { return "0.0" }                          // also normalizes -0.0
        if d.isNaN { return "" }                             // SQLite maps NaN to NULL; defensive
        if d.isInfinite { return d < 0 ? "-Inf" : "Inf" }
        var s = String(format: "%.15g", d)
        // sqlite3's "!" flag forces float-looking output: %g drops the decimal
        // point for integral magnitudes ("100") and bare exponents ("1e+20").
        if let e = s.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            if !s[s.startIndex..<e].contains(".") { s.insert(contentsOf: ".0", at: e) }
        } else if !s.contains(".") {
            s += ".0"
        }
        return s
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
