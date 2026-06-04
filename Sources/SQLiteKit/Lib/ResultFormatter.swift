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
    /// CSV row terminator. sqlite3 distinguishes the `-csv` command-line
    /// flag (LF, the default here) from the `.mode csv` dot-command (CRLF,
    /// which the dispatcher sets explicitly) — same renderer, different
    /// stored row separator.
    public var rowSeparator: String
    /// Per-column `.width` overrides for the column-family modes (column /
    /// table / box / markdown). Signed: a negative width right-justifies;
    /// `0` or an absent entry auto-sizes. Empty until `.width` is used.
    public var widths: [Int]
    /// Table name for `insert` mode; `nil` uses sqlite3's quoted default.
    public var insertTable: String?

    /// sqlite3's default column-family wrap width (`--wrap 60`): an
    /// auto-sized column never grows past this, wrapping longer values into
    /// continuation rows instead.
    static let defaultWrap = 60

    public init(mode: OutputMode = .list,
                showHeader: Bool = false,
                separator: String = "|",
                nullValue: String = "",
                rowSeparator: String = "\n",
                widths: [Int] = [],
                insertTable: String? = nil) {
        self.mode = mode
        self.showHeader = showHeader
        self.separator = separator
        self.nullValue = nullValue
        self.rowSeparator = rowSeparator
        self.widths = widths
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
        return rows.map { $0 + rowSeparator }.joined()
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

    // MARK: column / table / box / markdown (width-aware + wrapping)

    /// The wrapped, width-resolved layout shared by the four column-family
    /// modes — mirrors sqlite3's `exec_prepared_stmt_columnar`: each value is
    /// wrapped to its column's width into one or more physical rows, headers
    /// are truncated to the width, and a column's final width is the widest
    /// line it holds (never past the explicit `.width` / the `--wrap` cap).
    private struct Columnar {
        var header: [String]        // header cells, truncated to width
        var rows: [[String]]        // physical (post-wrap) rows
        var logicalEnd: [Bool]      // per physical row: last line of its logical row
        var width: [Int]            // resolved render width per column
        var rightJustify: [Bool]    // per column (negative `.width`)
        var multiLine: Bool         // any value wrapped to >1 line
    }

    private func columnarLayout(_ set: ResultSet) -> Columnar {
        let n = set.columns.count
        func explicit(_ i: Int) -> Int { i < widths.count ? widths[i] : 0 }
        func wrapWidth(_ i: Int) -> Int { let w = explicit(i); return w != 0 ? abs(w) : Self.defaultWrap }
        // Headers truncate (first wrapped line only); data wraps fully.
        let header = (0..<n).map { wrapCell(set.columns[$0], width: wrapWidth($0)).first ?? "" }
        var rows: [[String]] = []
        var logicalEnd: [Bool] = []
        var multiLine = false
        for row in set.rows {
            let cells = (0..<n).map { wrapCell(text(row[$0]), width: wrapWidth($0)) }
            let lineCount = cells.map(\.count).max() ?? 1
            if lineCount > 1 { multiLine = true }
            for li in 0..<lineCount {
                rows.append((0..<n).map { li < cells[$0].count ? cells[$0][li] : "" })
                logicalEnd.append(li == lineCount - 1)
            }
        }
        var width = (0..<n).map { abs(explicit($0)) }
        for line in [header] + rows {
            for i in 0..<n where dw(line[i]) > width[i] { width[i] = dw(line[i]) }
        }
        return Columnar(header: header, rows: rows, logicalEnd: logicalEnd,
                        width: width, rightJustify: (0..<n).map { explicit($0) < 0 },
                        multiLine: multiLine)
    }

    /// Splits `s` into display lines no wider than `width`, the way sqlite3's
    /// `translateForDisplayAndDup` does on its common path: hard-break at
    /// embedded newlines, expand tabs to 8-column stops, character-wrap
    /// (word-wrap is off by default and not yet exposed). `width <= 0` means
    /// no limit.
    private func wrapCell(_ s: String, width: Int) -> [String] {
        let limit = width <= 0 ? Int.max : width
        var lines: [String] = []
        var current = ""
        var col = 0
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\n" { lines.append(current); current = ""; col = 0; i += 1; continue }
            if c == "\r", i + 1 < chars.count, chars[i + 1] == "\n" {
                lines.append(current); current = ""; col = 0; i += 2; continue
            }
            if c == "\t" {
                repeat { current.append(" "); col += 1 } while col % 8 != 0 && col < limit
                i += 1
                if col >= limit { lines.append(current); current = ""; col = 0 }
                continue
            }
            if col >= limit { lines.append(current); current = ""; col = 0 }
            current.append(c); col += 1; i += 1
        }
        lines.append(current)
        return lines
    }

    private func renderColumn(_ set: ResultSet) -> String {
        let n = set.columns.count
        guard n > 0 else { return "" }
        let layout = columnarLayout(set)
        func cell(_ s: String, _ i: Int) -> String {
            justify(s, width: layout.width[i], right: layout.rightJustify[i])
        }
        var lines: [String] = []
        if showHeader {
            lines.append((0..<n).map { cell(layout.header[$0], $0) }.joined(separator: "  "))
            lines.append(layout.width.map { String(repeating: "-", count: $0) }.joined(separator: "  "))
        }
        for (idx, row) in layout.rows.enumerated() {
            lines.append((0..<n).map { cell(row[$0], $0) }.joined(separator: "  "))
            // sqlite3 separates logical rows with a blank line once any value
            // in the result wrapped to multiple physical lines.
            if layout.multiLine, layout.logicalEnd[idx], idx != layout.rows.count - 1 {
                lines.append("")
            }
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    private func renderMarkdown(_ set: ResultSet) -> String {
        let n = set.columns.count
        guard n > 0 else { return "" }
        let layout = columnarLayout(set)
        func dataRow(_ cells: [String]) -> String {
            "|" + (0..<n).map { " \(justify(cells[$0], width: layout.width[$0], right: layout.rightJustify[$0])) " }
                .joined(separator: "|") + "|"
        }
        // The bordered modes always print the (centered) header — sqlite3
        // doesn't gate it on `.headers`.
        var lines = ["|" + (0..<n).map { " \(center(layout.header[$0], layout.width[$0])) " }.joined(separator: "|") + "|"]
        lines.append("|" + layout.width.map { String(repeating: "-", count: $0 + 2) }.joined(separator: "|") + "|")
        for row in layout.rows { lines.append(dataRow(row)) }
        return lines.joined(separator: "\n") + "\n"
    }

    private func renderBordered(_ set: ResultSet, ascii: Bool) -> String {
        let n = set.columns.count
        guard n > 0 else { return "" }
        let layout = columnarLayout(set)
        let g = ascii
            ? (tl: "+", tm: "+", tr: "+", ml: "+", mm: "+", mr: "+",
               bl: "+", bm: "+", br: "+", h: "-", v: "|")
            : (tl: "┌", tm: "┬", tr: "┐", ml: "├", mm: "┼", mr: "┤",
               bl: "└", bm: "┴", br: "┘", h: "─", v: "│")
        func border(_ l: String, _ m: String, _ r: String) -> String {
            l + layout.width.map { String(repeating: g.h, count: $0 + 2) }.joined(separator: m) + r
        }
        func dataRow(_ cells: [String]) -> String {
            g.v + (0..<n).map { " \(justify(cells[$0], width: layout.width[$0], right: layout.rightJustify[$0])) " }
                .joined(separator: g.v) + g.v
        }
        var lines = [border(g.tl, g.tm, g.tr)]
        lines.append(g.v + (0..<n).map { " \(center(layout.header[$0], layout.width[$0])) " }.joined(separator: g.v) + g.v)
        lines.append(border(g.ml, g.mm, g.mr))
        for (idx, row) in layout.rows.enumerated() {
            lines.append(dataRow(row))
            // A wrapped logical row is closed off by a mid-rule before the next.
            if layout.multiLine, layout.logicalEnd[idx], idx != layout.rows.count - 1 {
                lines.append(border(g.ml, g.mm, g.mr))
            }
        }
        lines.append(border(g.bl, g.bm, g.br))
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
        // (e.g. 3.14 → 3.140000000000000124), via the same `%!.20g` as
        // .dump/quote/insert. We match it byte-for-byte through the engine.
        case .real(let d): return SQLiteValue.realLiteral(d)
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

    /// Display width of `s` (grapheme count — exact for ASCII / Latin; wide
    /// CJK columns are a deferred edge, like the rest of the formatter).
    private func dw(_ s: String) -> Int { s.count }

    private func justify(_ s: String, width: Int, right: Bool) -> String {
        right ? padLeft(s, width) : pad(s, width)
    }

    private func pad(_ s: String, _ width: Int) -> String {
        s + String(repeating: " ", count: max(0, width - s.count))
    }

    private func padLeft(_ s: String, _ width: Int) -> String {
        String(repeating: " ", count: max(0, width - s.count)) + s
    }

    /// Centers `s` in `width`, putting any odd extra space on the right —
    /// matching how sqlite3 centers column headers in box / markdown / table.
    private func center(_ s: String, _ width: Int) -> String {
        let total = max(0, width - s.count)
        let left = total / 2
        return String(repeating: " ", count: left) + s + String(repeating: " ", count: total - left)
    }
}
