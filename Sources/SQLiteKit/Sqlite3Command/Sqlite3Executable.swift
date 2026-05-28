import Foundation
import ShellKit
import SQLiteKit

/// Argv-level entry point for the `sqlite3` CLI. Returns the process exit
/// code. Kept in its own enum — mirroring the other ports — so embedders
/// can drive the CLI behavior in-process.
public enum Sqlite3Executable {

    @discardableResult
    public static func run(argv: [String],
                           stdin: InputSource,
                           stdout: OutputSink,
                           stderr: OutputSink) async throws -> Int32 {
        let options: Parser.Options
        do {
            options = try Parser.parse(argv)
        } catch let error as Parser.ArgError {
            stderr.write("sqlite3: Error: \(error.message)\n")
            return 1
        }

        switch options.special {
        case .help:
            stdout.write(Parser.helpText)
            return 0
        case .version:
            stdout.write("\(SQLiteDatabase.libVersion) \(SQLiteDatabase.sourceID) (64-bit)\n")
            return 0
        case .none:
            break
        }

        // Resolve + authorize the database file through ShellKit so the
        // tool honors the host's sandbox / path mapping. A missing name or
        // ":memory:" means a transient in-memory database.
        let location: SQLiteDatabase.Location
        if let path = options.databasePath, path != ":memory:", !path.isEmpty {
            let url = Shell.resolve(path)
            do {
                try await Shell.authorize(url)
            } catch {
                stderr.write("sqlite3: Error: \(error)\n")
                return 1
            }
            location = .file(url.path)
        } else {
            location = .memory
        }

        let database: SQLiteDatabase
        do {
            database = try SQLiteDatabase(location, readonly: options.readonly)
        } catch let error as SQLiteError {
            stderr.write("sqlite3: Error: \(error.message)\n")
            return 1
        }

        // The -markdown/-table/-box flags turn headers on unless the user
        // pinned them; the -column flag notably does not (matching sqlite3).
        var showHeader = options.showHeader
        if !options.headerExplicit, [.markdown, .table, .box].contains(options.mode) {
            showHeader = true
        }

        let session = Session(
            database: database,
            formatter: ResultFormatter(mode: options.mode,
                                       showHeader: showHeader,
                                       separator: options.separator,
                                       nullValue: options.nullValue),
            stdout: stdout,
            stderr: stderr,
            interactive: options.interactive,
            headerExplicit: options.headerExplicit,
            echo: options.echo,
            bail: options.bail)

        // -init FILE, then any -cmd commands, before the main input.
        if let initFile = options.initFile {
            await session.runScript(path: initFile)
        }
        for command in options.commands where !session.shouldQuit {
            _ = await session.process(command, context: .inline)
        }

        // A trailing SQL argument runs and exits; otherwise read stdin.
        if !options.sql.isEmpty {
            for statement in options.sql where !session.shouldQuit {
                if await session.process(statement, context: .inline) == false { break }
            }
        } else if !session.shouldQuit {
            let input = await stdin.readAllString()
            _ = await session.process(input, context: .script)
        }

        session.finishOutput()
        return session.exitCode
    }
}

/// Holds the mutable shell state (current database, output formatter) and
/// drives statement / dot-command execution. One instance per invocation.
final class Session {
    /// Where the current input came from. SQLite formats errors (and sets
    /// exit codes) differently for a command-line argument vs a script.
    enum SourceContext { case inline, script }

    private var database: SQLiteDatabase
    private var formatter: ResultFormatter
    private let stdout: OutputSink
    private let stderr: OutputSink
    private let interactive: Bool
    /// Whether the user pinned headers via `-header`/`-noheader`/`.headers`.
    /// Until they do, `.mode column` turns headers on (matching sqlite3).
    private var headerExplicit: Bool
    private var echo: Bool
    private var bail: Bool
    private var changesMode = false
    /// When on, print the EXPLAIN QUERY PLAN tree before each statement.
    private var eqp = false
    /// When set, result output is buffered to a file instead of stdout
    /// (`.output` / `.once`).
    private var redirect: Redirect?

    private struct Redirect { let url: URL; var buffer: String; let once: Bool }

    private(set) var shouldQuit = false
    private(set) var exitCode: Int32 = 0
    private var buffer = ""

    init(database: SQLiteDatabase,
         formatter: ResultFormatter,
         stdout: OutputSink,
         stderr: OutputSink,
         interactive: Bool,
         headerExplicit: Bool,
         echo: Bool,
         bail: Bool) {
        self.database = database
        self.formatter = formatter
        self.stdout = stdout
        self.stderr = stderr
        self.interactive = interactive
        self.headerExplicit = headerExplicit
        self.echo = echo
        self.bail = bail
    }

    private func out(_ s: String) {
        if redirect != nil { redirect!.buffer += s } else { stdout.write(s) }
    }
    private func err(_ s: String) { stderr.write(s) }

    /// Flushes the current `.output`/`.once` redirect to its file and
    /// reverts to stdout. Called at end of input too.
    func finishOutput() {
        guard let active = redirect else { return }
        redirect = nil
        do {
            try active.buffer.write(to: active.url, atomically: true, encoding: .utf8)
        } catch {
            err("Error: unable to write \"\(active.url.path)\"\n")
            exitCode = 1
        }
    }

    /// Processes a chunk of input (stdin, a SQL argument, a -cmd string, or
    /// a script file), tracking line numbers for error reporting. Returns
    /// `false` when a SQL error should stop a non-interactive run.
    @discardableResult
    func process(_ text: String, context: SourceContext) async -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var lineNo = 0
        var statementStart = 1
        // Command-line SQL bails on the first error; a script keeps going
        // unless `.bail on` is set (matching sqlite3).
        func stopsOnError() -> Bool { context == .inline || bail }
        for line in lines {
            if shouldQuit { return true }
            lineNo += 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Dot-commands are only recognized at a statement boundary.
            if buffer.isEmpty && trimmed.hasPrefix(".") {
                if echo { out(trimmed + "\n") }
                await handleDot(trimmed)
                continue
            }
            if buffer.isEmpty { statementStart = lineNo }
            buffer += line + "\n"
            if SQLiteDatabase.isCompleteStatement(buffer) {
                let sql = buffer
                buffer = ""
                if !runStatement(sql, startLine: statementStart, context: context) && stopsOnError() {
                    return false
                }
            }
        }
        // SQLite runs a final statement even without a trailing semicolon.
        let leftover = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        if !leftover.isEmpty {
            if !runStatement(leftover, startLine: statementStart, context: context) && stopsOnError() {
                return false
            }
        }
        return true
    }

    /// Runs one chunk of SQL and renders any result sets. Returns `false`
    /// on error (after reporting it).
    @discardableResult
    private func runStatement(_ sql: String, startLine: Int, context: SourceContext) -> Bool {
        if echo { out(sql.trimmingCharacters(in: .whitespacesAndNewlines) + "\n") }
        if eqp { renderQueryPlan(sql) }
        do {
            for set in try database.evaluate(sql) {
                out(formatter.render(set))
            }
            if changesMode {
                out("changes: \(database.changes)   total_changes: \(database.totalChanges)\n")
            }
            if redirect?.once == true { finishOutput() }
            return true
        } catch let error as SQLiteError {
            report(error, sql: sql, startLine: startLine, context: context)
            return false
        } catch {
            err("Error: \(error)\n")
            exitCode = 1
            return false
        }
    }

    /// Reproduces sqlite3's error reporting: script input gets
    /// `Parse/Runtime error near line N:` (exit 1); a command-line argument
    /// gets `Error: in prepare,/stepping,` (exit = SQLite result code).
    /// Both append a caret pointer when SQLite reports an error offset, and
    /// runtime errors append the result code.
    private func report(_ error: SQLiteError, sql: String, startLine: Int, context: SourceContext) {
        let header: String
        switch context {
        case .script:
            let line = errorLine(start: startLine, sql: sql, offset: error.offset)
            header = (error.phase == .prepare ? "Parse error" : "Runtime error") + " near line \(line): "
            exitCode = 1
        case .inline:
            header = error.phase == .prepare ? "Error: in prepare, " : "Error: stepping, "
            exitCode = error.code
        }
        var message = error.message
        if error.phase == .step { message += " (\(error.code))" }
        err(header + message + "\n")
        if error.offset >= 0 {
            err(caretBlock(sql: sql, offset: Int(error.offset)))
        }
    }

    private func errorLine(start: Int, sql: String, offset: Int32) -> Int {
        guard offset >= 0 else { return start }
        let newlines = sql.utf8.prefix(Int(offset)).reduce(0) { $0 + ($1 == 0x0a ? 1 : 0) }
        return start + newlines
    }

    /// Builds the `  <source line>\n  <spaces>^--- error here\n` block that
    /// sqlite3 prints under a failing statement.
    private func caretBlock(sql: String, offset: Int) -> String {
        let bytes = Array(sql.utf8)
        let position = min(max(offset, 0), bytes.count)
        var lineStart = position
        while lineStart > 0 && bytes[lineStart - 1] != 0x0a { lineStart -= 1 }
        var lineEnd = position
        while lineEnd < bytes.count && bytes[lineEnd] != 0x0a { lineEnd += 1 }
        let line = String(decoding: bytes[lineStart..<lineEnd], as: UTF8.self)
        let pad = String(repeating: " ", count: position - lineStart)
        return "  \(line)\n  \(pad)^--- error here\n"
    }

    /// Renders `EXPLAIN QUERY PLAN` for `sql` as the tree sqlite3 prints
    /// under `.eqp on` — children grouped by parent id with `|--` / `\`--`
    /// connectors.
    private func renderQueryPlan(_ sql: String) {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let plan = try? database.evaluate("EXPLAIN QUERY PLAN \(trimmed)").first,
              !plan.rows.isEmpty else { return }
        let nodes: [(id: Int, parent: Int, detail: String)] = plan.rows.compactMap { row in
            guard case .integer(let id) = row[0], case .integer(let parent) = row[1] else { return nil }
            return (Int(id), Int(parent), row.count > 3 ? (row[3].cliText ?? "") : "")
        }
        var output = "QUERY PLAN\n"
        func level(_ parent: Int, _ prefix: String) {
            let children = nodes.filter { $0.parent == parent }
            for (i, node) in children.enumerated() {
                let last = i == children.count - 1
                output += prefix + (last ? "`--" : "|--") + node.detail + "\n"
                level(node.id, prefix + (last ? "   " : "|  "))
            }
        }
        level(0, "")
        out(output)
    }

    // MARK: Dot-commands

    private func handleDot(_ line: String) async {
        let tokens = Self.tokenize(line)
        guard let command = tokens.first else { return }
        let args = Array(tokens.dropFirst())

        switch command {
        case ".quit", ".exit":
            shouldQuit = true

        case ".help":
            out(Parser.helpText)

        case ".tables":
            introspect {
                var names = try database.tableNames()
                if let pattern = args.first {
                    names = names.filter { Self.glob(pattern, matches: $0) }
                }
                if !names.isEmpty { out(Self.columnize(names)) }
            }

        case ".schema":
            introspect {
                let statements = try database.schemaSQL(of: args.first)
                if !statements.isEmpty {
                    out(statements.map { $0 + ";" }.joined(separator: "\n") + "\n")
                }
            }

        case ".databases":
            introspect {
                let list = try database.databaseList()
                if !list.isEmpty {
                    out(list.map { "\($0.name): \($0.file)" }.joined(separator: "\n") + "\n")
                }
            }

        case ".indexes", ".indices":
            introspect {
                let filter = args.first.map { " AND tbl_name = '\(SQLiteDatabase.quote($0))'" } ?? ""
                let sql = "SELECT name FROM sqlite_schema WHERE type='index'\(filter) ORDER BY name;"
                let names = try database.evaluate(sql).first?.rows.compactMap { $0.first?.cliText } ?? []
                if !names.isEmpty { out(Self.columnize(names)) }
            }

        case ".dump":
            introspect {
                out("PRAGMA foreign_keys=OFF;\nBEGIN TRANSACTION;\n")
                let only = args.first
                let tableFilter = only.map { " AND name = '\(SQLiteDatabase.quote($0))'" } ?? ""
                // Each table: its CREATE statement, then its rows as INSERTs.
                let tables = try database.evaluate("""
                    SELECT name, sql FROM sqlite_schema
                    WHERE type='table' AND name NOT LIKE 'sqlite_%' AND sql NOT NULL\(tableFilter)
                    ORDER BY rowid;
                    """).first?.rows ?? []
                for t in tables {
                    guard case .text(let name) = t[0], case .text(let createSQL) = t[1] else { continue }
                    out(createSQL + ";\n")
                    let ident = name.replacingOccurrences(of: "\"", with: "\"\"")
                    let rows = try database.evaluate("SELECT * FROM \"\(ident)\";").first?.rows ?? []
                    for row in rows {
                        out("INSERT INTO \(name) VALUES(\(row.map(\.sqlLiteral).joined(separator: ",")));\n")
                    }
                }
                // Then views + triggers, then indexes last (sqlite3's order).
                let objFilter = only.map { " AND tbl_name = '\(SQLiteDatabase.quote($0))'" } ?? ""
                for types in ["'view','trigger'", "'index'"] {
                    let sqls = try database.evaluate("""
                        SELECT sql FROM sqlite_schema
                        WHERE type IN (\(types)) AND sql NOT NULL\(objFilter) ORDER BY rowid;
                        """).first?.rows.compactMap { $0.first?.cliText } ?? []
                    for sql in sqls { out(sql + ";\n") }
                }
                out("COMMIT;\n")
            }

        case ".mode":
            guard let raw = args.first, let mode = OutputMode(rawValue: raw) else {
                err("Error: .mode expects one of: \(OutputMode.allCases.map(\.rawValue).joined(separator: ", "))\n")
                return
            }
            formatter.mode = mode
            // `.mode insert [TABLE]` carries an optional destination table.
            if mode == .insert { formatter.insertTable = args.count > 1 ? args[1] : nil }
            // The column-family modes turn headers on unless the user already
            // pinned them (matching sqlite3's `.mode` dot-command).
            if !headerExplicit, [.column, .markdown, .table, .box].contains(mode) {
                formatter.showHeader = true
            }

        case ".headers", ".header":
            guard let value = args.first else {
                err("Error: .headers expects on or off\n")
                return
            }
            formatter.showHeader = ["on", "1", "yes", "true"].contains(value.lowercased())
            headerExplicit = true

        case ".separator":
            guard let value = args.first else {
                err("Error: .separator expects a value\n")
                return
            }
            formatter.separator = value

        case ".nullvalue":
            formatter.nullValue = args.first ?? ""

        case ".echo":
            if let value = Self.onOff(args.first) { echo = value }

        case ".bail":
            if let value = Self.onOff(args.first) { bail = value }

        case ".changes":
            if let value = Self.onOff(args.first) { changesMode = value }

        case ".eqp":
            // "full" also dumps bytecode in sqlite3; we render the plan tree.
            if args.first?.lowercased() == "full" { eqp = true }
            else if let value = Self.onOff(args.first) { eqp = value }

        case ".print":
            out(args.joined(separator: " ") + "\n")

        case ".output":
            finishOutput()
            if let path = args.first {
                guard let url = await resolveAuthorized(path) else { return }
                redirect = Redirect(url: url, buffer: "", once: false)
            }

        case ".once":
            guard let path = args.first else {
                err("Error: .once expects a filename\n")
                return
            }
            finishOutput()
            guard let url = await resolveAuthorized(path) else { return }
            redirect = Redirect(url: url, buffer: "", once: true)

        case ".import":
            guard args.count >= 2 else {
                err("Error: .import expects FILE and TABLE\n")
                return
            }
            guard let url = await resolveAuthorized(args[0]) else { return }
            let text: String
            do {
                text = try String(contentsOf: url, encoding: .utf8)
            } catch {
                err("Error: cannot open \"\(args[0])\"\n")
                exitCode = 1
                return
            }
            importDelimited(text, into: args[1])

        case ".backup":
            guard let (dbName, path) = Self.dbAndFile(args) else {
                err("Error: .backup expects ?DB? FILE\n")
                return
            }
            guard let url = await resolveAuthorized(path) else { return }
            do {
                let destination = try SQLiteDatabase(.file(url.path))
                defer { destination.close() }
                try database.backup(to: destination, sourceName: dbName)
            } catch let error as SQLiteError {
                err("Error: \(error.message)\n")
                exitCode = 1
            } catch {
                err("Error: \(error)\n")
                exitCode = 1
            }

        case ".restore":
            guard let (dbName, path) = Self.dbAndFile(args) else {
                err("Error: .restore expects ?DB? FILE\n")
                return
            }
            guard let url = await resolveAuthorized(path) else { return }
            do {
                let source = try SQLiteDatabase(.file(url.path))
                defer { source.close() }
                try source.backup(to: database, destinationName: dbName)
            } catch let error as SQLiteError {
                err("Error: \(error.message)\n")
                exitCode = 1
            } catch {
                err("Error: \(error)\n")
                exitCode = 1
            }

        case ".show":
            let settings = [
                "     mode: \(formatter.mode.rawValue)",
                "  headers: \(formatter.showHeader ? "on" : "off")",
                "separator: \"\(formatter.separator)\"",
                "nullvalue: \"\(formatter.nullValue)\"",
            ]
            out(settings.joined(separator: "\n") + "\n")

        case ".open":
            guard let path = args.first else {
                err("Error: .open expects a filename\n")
                return
            }
            guard let url = await resolveAuthorized(path) else { return }
            do {
                let replacement = try SQLiteDatabase(.file(url.path))
                database.close()
                database = replacement
            } catch let error as SQLiteError {
                err("Error: \(error.message)\n")
            } catch {
                err("Error: \(error)\n")
            }

        case ".read":
            guard let path = args.first else {
                err("Error: .read expects a filename\n")
                return
            }
            await runScript(path: path)

        default:
            err("Error: unknown command or invalid arguments: \"\(command.dropFirst())\". Enter \".help\" for help\n")
        }
    }

    /// Reads a SQL/dot-command script through ShellKit's sandbox gate and
    /// runs it.
    func runScript(path: String) async {
        guard let url = await resolveAuthorized(path) else { exitCode = 1; return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            _ = await process(text, context: .script)
        } catch {
            err("Error: cannot open \"\(path)\"\n")
            exitCode = 1
        }
    }

    /// Converts a user-supplied path to a sandbox URL and asks the host to
    /// authorize it. Returns `nil` (after reporting) if denied.
    private func resolveAuthorized(_ path: String) async -> URL? {
        let url = Shell.resolve(path)
        do {
            try await Shell.authorize(url)
            return url
        } catch {
            err("Error: \(error)\n")
            return nil
        }
    }

    private func introspect(_ body: () throws -> Void) {
        do {
            try body()
        } catch let error as SQLiteError {
            err("Error: \(error.message)\n")
        } catch {
            err("Error: \(error)\n")
        }
    }

    /// Column separator implied by the current mode (used by `.import`).
    private func currentColumnSeparator() -> Character {
        switch formatter.mode {
        case .csv: return ","
        case .tabs: return "\t"
        case .ascii: return "\u{1F}"
        default: return formatter.separator.first ?? "|"
        }
    }

    private func tableExists(_ name: String) throws -> Bool {
        let sql = "SELECT 1 FROM sqlite_schema WHERE type='table' AND name='\(SQLiteDatabase.quote(name))' LIMIT 1;"
        return !((try database.evaluate(sql).first?.rows.isEmpty) ?? true)
    }

    /// Imports delimited rows from `text` into `table`, creating the table
    /// from the header row (all TEXT columns) when it doesn't yet exist —
    /// matching sqlite3's `.import`.
    private func importDelimited(_ text: String, into table: String) {
        let rows = Self.parseDelimited(text, separator: currentColumnSeparator())
        guard !rows.isEmpty else { return }
        let ident = table.replacingOccurrences(of: "\"", with: "\"\"")
        introspect {
            var data = rows
            if try !tableExists(table) {
                data = Array(rows.dropFirst())
                let cols = rows[0]
                    .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\" TEXT" }
                    .joined(separator: ", ")
                // sqlite normalizes "IF NOT EXISTS" out of the stored schema,
                // so .schema/.dump show `CREATE TABLE "t"(…)`. Real sqlite3's
                // import retains the prefix in stored text; matching that
                // would mean bypassing the normalizer — a cosmetic-only diff.
                try database.evaluate("CREATE TABLE IF NOT EXISTS \"\(ident)\"(\n\(cols));")
            }
            for row in data {
                let values = row
                    .map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }
                    .joined(separator: ",")
                try database.evaluate("INSERT INTO \"\(ident)\" VALUES(\(values));")
            }
        }
    }

    // MARK: Small helpers

    /// Parses delimited text — CSV-style: double-quoted fields, `""`
    /// escapes, embedded separators and newlines — into rows of fields.
    private static func parseDelimited(_ text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 2; continue }
                    inQuotes = false
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case separator: row.append(field); field = ""
                case "\n": row.append(field); rows.append(row); row = []; field = ""
                case "\r": break
                default: field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    /// Parses an on/off argument; returns nil for an unrecognized value.
    private static func onOff(_ value: String?) -> Bool? {
        switch value?.lowercased() {
        case "on", "1", "yes", "true": return true
        case "off", "0", "no", "false": return false
        default: return nil
        }
    }

    /// Parses a `?DB? FILE` argument list (db name defaults to "main").
    private static func dbAndFile(_ args: [String]) -> (db: String, file: String)? {
        if args.count >= 2 { return (args[0], args[1]) }
        if args.count == 1 { return ("main", args[0]) }
        return nil
    }

    /// Splits a dot-command line into tokens, honoring double quotes.
    private static func tokenize(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuote = false
        var sawToken = false
        for ch in line {
            if ch == "\"" {
                inQuote.toggle()
                sawToken = true
            } else if ch == " " && !inQuote {
                if sawToken { tokens.append(current); current = ""; sawToken = false }
            } else {
                current.append(ch)
                sawToken = true
            }
        }
        if sawToken { tokens.append(current) }
        return tokens
    }

    /// Tiny GLOB matcher (`*` and `?`) for `.tables PATTERN`.
    private static func glob(_ pattern: String, matches name: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        return name.range(of: "^\(escaped)$", options: .regularExpression) != nil
    }

    /// Packs names into space-padded columns the way sqlite3's `.tables`
    /// does: column-major order, every entry left-padded to the longest
    /// name, columns separated by two spaces, 80-column budget.
    private static func columnize(_ names: [String], width totalWidth: Int = 80) -> String {
        guard !names.isEmpty else { return "" }
        let maxLen = names.map(\.count).max() ?? 0
        let printCols = max(1, totalWidth / (maxLen + 2))
        let printRows = (names.count + printCols - 1) / printCols
        var output = ""
        for i in 0..<printRows {
            var j = i
            var first = true
            while j < names.count {
                let name = names[j]
                let padded = name + String(repeating: " ", count: maxLen - name.count)
                output += (first ? "" : "  ") + padded
                first = false
                j += printRows
            }
            output += "\n"
        }
        return output
    }
}
