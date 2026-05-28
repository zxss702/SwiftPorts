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
            headerExplicit: options.headerExplicit)

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

    private(set) var shouldQuit = false
    private(set) var exitCode: Int32 = 0
    private var buffer = ""

    init(database: SQLiteDatabase,
         formatter: ResultFormatter,
         stdout: OutputSink,
         stderr: OutputSink,
         interactive: Bool,
         headerExplicit: Bool) {
        self.database = database
        self.formatter = formatter
        self.stdout = stdout
        self.stderr = stderr
        self.interactive = interactive
        self.headerExplicit = headerExplicit
    }

    private func out(_ s: String) { stdout.write(s) }
    private func err(_ s: String) { stderr.write(s) }

    /// Processes a chunk of input (stdin, a SQL argument, a -cmd string, or
    /// a script file), tracking line numbers for error reporting. Returns
    /// `false` when a SQL error should stop a non-interactive run.
    @discardableResult
    func process(_ text: String, context: SourceContext) async -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var lineNo = 0
        var statementStart = 1
        for line in lines {
            if shouldQuit { return true }
            lineNo += 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Dot-commands are only recognized at a statement boundary.
            if buffer.isEmpty && trimmed.hasPrefix(".") {
                await handleDot(trimmed)
                continue
            }
            if buffer.isEmpty { statementStart = lineNo }
            buffer += line + "\n"
            if SQLiteDatabase.isCompleteStatement(buffer) {
                let sql = buffer
                buffer = ""
                if !runStatement(sql, startLine: statementStart, context: context) && !interactive {
                    return false
                }
            }
        }
        // SQLite runs a final statement even without a trailing semicolon.
        let leftover = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        if !leftover.isEmpty {
            if !runStatement(leftover, startLine: statementStart, context: context) && !interactive {
                return false
            }
        }
        return true
    }

    /// Runs one chunk of SQL and renders any result sets. Returns `false`
    /// on error (after reporting it).
    @discardableResult
    private func runStatement(_ sql: String, startLine: Int, context: SourceContext) -> Bool {
        do {
            for set in try database.evaluate(sql) {
                out(formatter.render(set))
            }
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

    // MARK: Small helpers

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
