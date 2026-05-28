import Foundation
import ShellKit
import Testing
@testable import Sqlite3Command
@testable import SQLiteKit

@Suite struct Sqlite3ExecutableTests {

    /// Drives the executable with a fake stdin and captures stdout/stderr
    /// via ShellKit's `OutputSink` / `InputSource` — same harness as the
    /// other CLI ports. Uses an in-memory database so no filesystem (and
    /// no sandbox authorization) is involved.
    private func run(_ argv: [String], input: String = "") async throws
        -> (stdout: String, stderr: String, exit: Int32) {
        let stdinSource: InputSource = .string(input)
        let stdoutSink = OutputSink()
        let stderrSink = OutputSink()

        let exit = try await Sqlite3Executable.run(
            argv: argv,
            stdin: stdinSource,
            stdout: stdoutSink,
            stderr: stderrSink)

        stdoutSink.finish()
        stderrSink.finish()
        return (await stdoutSink.readAllString(), await stderrSink.readAllString(), exit)
    }

    @Test func inlineSelect() async throws {
        let r = try await run([":memory:", "SELECT 1 + 1;"])
        #expect(r.exit == 0)
        #expect(r.stdout == "2\n")
    }

    @Test func crudViaStdin() async throws {
        let script = """
        CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT, qty INTEGER);
        INSERT INTO t(name, qty) VALUES ('apple', 3), ('banana', 5);
        UPDATE t SET qty = qty + 1 WHERE name = 'apple';
        DELETE FROM t WHERE name = 'banana';
        SELECT * FROM t;
        """
        let r = try await run([":memory:"], input: script)
        #expect(r.exit == 0)
        #expect(r.stdout == "1|apple|4\n")
    }

    @Test func csvFlagWithHeader() async throws {
        let r = try await run(["-csv", "-header", ":memory:", "SELECT 1 AS a, 'x' AS b;"])
        #expect(r.exit == 0)
        #expect(r.stdout == "a,b\r\n1,x\r\n")
    }

    @Test func jsonFlag() async throws {
        let r = try await run(["-json", ":memory:", "SELECT 1 AS a;"])
        #expect(r.stdout == "[{\"a\":1}]\n")
    }

    @Test func jsonBlob() async throws {
        let r = try await run(["-json", ":memory:", "SELECT x'00ff' AS b;"])
        #expect(r.stdout == "[{\"b\":\"\\u0000\\u00ff\"}]\n")
    }

    @Test func boxFlag() async throws {
        let r = try await run(["-box", ":memory:", "SELECT 1 AS a;"])
        #expect(r.stdout == "┌───┐\n│ a │\n├───┤\n│ 1 │\n└───┘\n")
    }

    @Test func insertModeNamedTable() async throws {
        let r = try await run([":memory:"],
            input: "CREATE TABLE t(a);INSERT INTO t VALUES(1);\n.mode insert t\nSELECT * FROM t;\n")
        #expect(r.stdout == "INSERT INTO t VALUES(1);\n")
    }

    @Test func dumpRoundTrip() async throws {
        let r = try await run([":memory:"], input: """
        CREATE TABLE t(id INTEGER, name TEXT);
        INSERT INTO t VALUES (1,'alice'),(2,NULL);
        .dump
        """)
        #expect(r.exit == 0)
        #expect(r.stdout == """
        PRAGMA foreign_keys=OFF;
        BEGIN TRANSACTION;
        CREATE TABLE t(id INTEGER, name TEXT);
        INSERT INTO t VALUES(1,'alice');
        INSERT INTO t VALUES(2,NULL);
        COMMIT;
        """ + "\n")
    }

    @Test func dotModeAndHeadersFromStdin() async throws {
        let script = """
        .mode csv
        .headers on
        SELECT 1 AS a, 2 AS b;
        """
        let r = try await run([":memory:"], input: script)
        #expect(r.stdout == "a,b\r\n1,2\r\n")
    }

    @Test func dotModeColumnEnablesHeaders() async throws {
        // `.mode column` turns headers on (sqlite3 behavior).
        let r = try await run([":memory:"], input: ".mode column\nSELECT 1 AS a, 2 AS b;\n")
        #expect(r.stdout == "a  b\n-  -\n1  2\n")
    }

    @Test func columnFlagDoesNotEnableHeaders() async throws {
        // ...but the -column flag does not.
        let r = try await run(["-column", ":memory:", "SELECT 1 AS a, 2 AS b;"])
        #expect(r.stdout == "1  2\n")
    }

    @Test func explicitHeadersOffBeatsColumnMode() async throws {
        let r = try await run([":memory:"], input: ".headers off\n.mode column\nSELECT 1 AS a;\n")
        #expect(r.stdout == "1\n")
    }

    @Test func dotTablesAndSchema() async throws {
        let script = """
        CREATE TABLE foo(id INTEGER);
        CREATE TABLE bar(id INTEGER);
        .tables
        .schema foo
        """
        let r = try await run([":memory:"], input: script)
        #expect(r.stdout.contains("bar"))
        #expect(r.stdout.contains("foo"))
        #expect(r.stdout.contains("CREATE TABLE foo(id INTEGER);"))
    }

    @Test func inlinePrepareError() async throws {
        // Command-line SQL: "Error: in prepare, ..." and exit = SQLite code.
        let r = try await run([":memory:", "SELECT * FROM missing;"])
        #expect(r.exit == 1)
        #expect(r.stderr == "Error: in prepare, no such table: missing\n")
    }

    @Test func inlineRuntimeError() async throws {
        // Stepping failure: "Error: stepping, ... (code)" and exit = code.
        let r = try await run([":memory:",
            "CREATE TABLE x(a INTEGER NOT NULL); INSERT INTO x VALUES(NULL);"])
        #expect(r.exit == 19)
        #expect(r.stderr == "Error: stepping, NOT NULL constraint failed: x.a (19)\n")
    }

    @Test func scriptParseErrorWithCaret() async throws {
        let r = try await run([":memory:"], input: "SELEC 1;\n")
        #expect(r.exit == 1)
        #expect(r.stderr == "Parse error near line 1: near \"SELEC\": syntax error\n  SELEC 1;\n  ^--- error here\n")
    }

    @Test func dotReadMissingFileFailsExitCode() async throws {
        let r = try await run([":memory:"], input: ".read /no/such/file\n")
        #expect(r.exit == 1)
        #expect(!r.stderr.isEmpty)
    }

    @Test func scriptRuntimeErrorLineNumber() async throws {
        let r = try await run([":memory:"],
            input: "CREATE TABLE x(a INTEGER NOT NULL);\nINSERT INTO x VALUES(NULL);\n")
        #expect(r.exit == 1)
        #expect(r.stderr == "Runtime error near line 2: NOT NULL constraint failed: x.a (19)\n")
    }

    @Test func unknownDotCommandContinues() async throws {
        let r = try await run([":memory:"], input: ".bogus\nSELECT 1;\n")
        #expect(r.exit == 0)
        #expect(r.stderr.contains("unknown command"))
        #expect(r.stdout == "1\n")
    }

    @Test func quitStopsProcessing() async throws {
        let script = """
        SELECT 1;
        .quit
        SELECT 2;
        """
        let r = try await run([":memory:"], input: script)
        #expect(r.stdout == "1\n")
    }

    @Test func versionFlag() async throws {
        let r = try await run(["-version"])
        #expect(r.exit == 0)
        #expect(r.stdout.hasPrefix("3.50.4 "))
        #expect(r.stdout.hasSuffix(" (64-bit)\n"))
    }

    @Test func unknownOptionFails() async throws {
        let r = try await run(["-bogus", ":memory:"])
        #expect(r.exit == 1)
        #expect(r.stderr.contains("unknown option"))
    }
}
