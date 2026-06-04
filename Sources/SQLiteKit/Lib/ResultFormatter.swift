import Foundation

/// Output modes mirroring the `sqlite3` shell's `.mode` settings.
public enum OutputMode: String, Sendable, CaseIterable {
    case list, csv, line, column, json
    case tabs, ascii, html, markdown, table, box, quote, insert
}

/// Renders result sets the way the `sqlite3` shell does for each output
/// mode. Shared by the CLI and any embedder that wants matching output.
public struct ResultFormatter: Sendable {
    public var mode: OutputMode
    public var showHeader: Bool
    public var separator: String
    public var nullValue: String
    /// Table name for `insert` mode; `nil` uses sqlite3's quoted default.
    public var insertTable: String?

    public init(mode: OutputMode = .list,
                showHeader: Bool = false,
                separator: String = "|",
                nullValue: String = "",
                insertTable: String? = nil) {
        self.mode = mode
        self.showHeader = showHeader
        self.separator = separator
        self.nullValue = nullValue
        self.insertTable = insertTable
    }

    public func render(_ set: ResultSet) -> String {
        switch mode {
        case .list: return separated(set, colSep: separator, rowSep: "\n")
        case .tabs: return separated(set, colSep: "\t", rowSep: "\n")
        case .ascii: return separated(set, colSep: "\u{1F}", rowSep: "\u{1E}")
        case .csv: return renderCSV(set)
        case .line: return renderLine(set)
        case .column: return renderColumn(set)
        case .json: return renderJSON(set)
        case .html: return renderHTML(set)
        case .markdown: return renderMarkdown(set)
        case .table: return renderBordered(set, ascii: true)
        case .box: return renderBordered(set, ascii: false)
        case .quote: return renderQuote(set)
        case .insert: return renderInsert(set)
        }
    }

    private func text(_ value: SQLiteValue) -> String { value.cliText ?? nullValue }

    // MARK: list / tabs / ascii (separator-delimited)

    private func separated(_ set: ResultSet, colSep: String, rowSep: String) -> String {
        var items: [String] = []
        if showHeader { items.append(set.columns.joined(separator: colSep)) }
        for row in set.rows { items.append(row.map(text).joined(separator: colSep)) }
        return items.map { $0 + rowSep }.joined()
    }

    // MARK: csv

    private func renderCSV(_ set: ResultSet) -> String {
        var rows: [String] = []
        if showHeader { rows.append(set.columns.map(csvField).joined(separator: ",")) }
        for row in set.rows {
            rows.append(row.map { csvField(text($0)) }.joined(separator: ","))
        }
        return rows.map { $0 + "\r\n" }.joined()
    }

    private func csvField(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    // MARK: line

    private func renderLine(_ set: ResultSet) -> String {
        guard !set.columns.isEmpty else { return "" }
        // sqlite3 right-justifies the column name in a field at least 5 wide
        // (its hard floor), widening only if a column name exceeds it.
        let width = max(set.columns.map(\.count).max() ?? 0, 5)
        var blocks: [String] = []
        for row in set.rows {
            let lines = set.columns.enumerated().map { (i, col) -> String in
                let leading = String(repeating: " ", count: max(0, width - col.count))
                return "\(leading)\(col) = \(text(row[i]))"
            }
            blocks.append(lines.joined(separator: "\n"))
        }
        return blocks.isEmpty ? "" : blocks.joined(separator: "\n\n") + "\n"
    }

    // MARK: column

    private func renderColumn(_ set: ResultSet) -> String {
        let widths = columnWidths(set)
        var lines: [String] = []
        if showHeader {
            lines.append(zip(set.columns, widths).map { pad($0, $1) }.joined(separator: "  "))
            lines.append(widths.map { String(repeating: "-", count: $0) }.joined(separator: "  "))
        }
        for row in set.rows {
            lines.append(zip(row.map(text), widths).map { pad($0, $1) }.joined(separator: "  "))
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    // MARK: markdown / table / box (column-width based)

    private func renderMarkdown(_ set: ResultSet) -> String {
        let widths = columnWidths(set)
        func rowLine(_ cells: [String], _ justify: (String, Int) -> String) -> String {
            "|" + zip(cells, widths).map { " \(justify($0, $1)) " }.joined(separator: "|") + "|"
        }
        var lines: [String] = []
        if showHeader {
            lines.append(rowLine(set.columns, center))   // sqlite3 centers headers
            lines.append("|" + widths.map { String(repeating: "-", count: $0 + 2) }.joined(separator: "|") + "|")
        }
        for row in set.rows { lines.append(rowLine(row.map(text), pad)) }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    private func renderBordered(_ set: ResultSet, ascii: Bool) -> String {
        let widths = columnWidths(set)
        let glyphs = ascii
            ? (tl: "+", tm: "+", tr: "+", ml: "+", mm: "+", mr: "+",
               bl: "+", bm: "+", br: "+", h: "-", v: "|")
            : (tl: "┌", tm: "┬", tr: "┐", ml: "├", mm: "┼", mr: "┤",
               bl: "└", bm: "┴", br: "┘", h: "─", v: "│")
        func border(_ l: String, _ m: String, _ r: String) -> String {
            l + widths.map { String(repeating: glyphs.h, count: $0 + 2) }.joined(separator: m) + r
        }
        func rowLine(_ cells: [String], _ justify: (String, Int) -> String) -> String {
            glyphs.v + zip(cells, widths).map { " \(justify($0, $1)) " }.joined(separator: glyphs.v) + glyphs.v
        }
        var lines = [border(glyphs.tl, glyphs.tm, glyphs.tr)]
        if showHeader {
            lines.append(rowLine(set.columns, center))   // sqlite3 centers headers
            lines.append(border(glyphs.ml, glyphs.mm, glyphs.mr))
        }
        for row in set.rows { lines.append(rowLine(row.map(text), pad)) }
        lines.append(border(glyphs.bl, glyphs.bm, glyphs.br))
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: quote / insert (SQL literals)

    private func renderQuote(_ set: ResultSet) -> String {
        var items: [String] = []
        if showHeader {
            items.append(set.columns
                .map { "'" + $0.replacingOccurrences(of: "'", with: "''") + "'" }
                .joined(separator: ","))
        }
        for row in set.rows { items.append(row.map(\.sqlLiteral).joined(separator: ",")) }
        return items.map { $0 + "\n" }.joined()
    }

    private func renderInsert(_ set: ResultSet) -> String {
        let name = insertTable ?? "\"table\""
        // sqlite3 lists the columns only when headers are on:
        //   headers on  → INSERT INTO t(a,b) VALUES(…)
        //   headers off → INSERT INTO t VALUES(…)
        let cols = showHeader
            ? "(" + set.columns.map { SQLiteDatabase.quoteIdentifier($0) }.joined(separator: ",") + ")"
            : ""
        return set.rows
            .map { "INSERT INTO \(name)\(cols) VALUES(" + $0.map(\.sqlLiteral).joined(separator: ",") + ");\n" }
            .joined()
    }

    // MARK: json

    private func renderJSON(_ set: ResultSet) -> String {
        let objects = set.rows.map { row -> String in
            let pairs = set.columns.enumerated().map { (i, col) in
                "\(jsonString(col)):\(jsonValue(row[i]))"
            }
            return "{" + pairs.joined(separator: ",") + "}"
        }
        return "[" + objects.joined(separator: ",\n") + "]\n"
    }

    private func jsonValue(_ value: SQLiteValue) -> String {
        switch value {
        case .null: return "null"
        case .integer(let i): return String(i)
        // sqlite3's JSON mode prints reals with its own full-precision dtoa
        // (e.g. 3.14 → 3.140000000000000124). We emit the shortest
        // round-tripping form instead — equivalent value, cleaner text,
        // since reproducing sqlite's dtoa byte-for-byte isn't possible via
        // the platform formatter.
        case .real(let d): return String(d)
        case .text(let s): return jsonString(s)
        case .blob(let b): return jsonBlob(b)
        }
    }

    /// SQLite renders BLOBs in JSON as one \u00XX escape per byte.
    private func jsonBlob(_ bytes: Data) -> String {
        "\"" + bytes.map { String(format: "\\u%04x", $0) }.joined() + "\""
    }

    private func jsonString(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    // MARK: html

    private func renderHTML(_ set: ResultSet) -> String {
        var out = ""
        if showHeader {
            out += "<TR>" + set.columns.map { "<TH>\(htmlEscape($0))</TH>" }.joined(separator: "\n") + "\n</TR>\n"
        }
        for row in set.rows {
            out += "<TR>" + row.map { "<TD>\(htmlEscape(text($0)))</TD>" }.joined(separator: "\n") + "\n</TR>\n"
        }
        return out
    }

    private func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: shared width helpers

    private func columnWidths(_ set: ResultSet) -> [Int] {
        var widths = set.columns.map(\.count)
        for row in set.rows {
            for (i, cell) in row.map(text).enumerated() where i < widths.count {
                widths[i] = max(widths[i], cell.count)
            }
        }
        return widths
    }

    private func pad(_ s: String, _ width: Int) -> String {
        s + String(repeating: " ", count: max(0, width - s.count))
    }

    /// Centers `s` in `width`, putting any odd extra space on the right —
    /// matching how sqlite3 centers column headers in box / markdown / table.
    private func center(_ s: String, _ width: Int) -> String {
        let total = max(0, width - s.count)
        let left = total / 2
        return String(repeating: " ", count: left) + s + String(repeating: " ", count: total - left)
    }
}
