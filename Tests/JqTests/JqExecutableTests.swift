#if !os(Android)  // argv-parsing test; ArgumentParser trips the Android explicit-module scanner
import Foundation
import ShellKit
import Testing
@testable import JqCommand
@testable import JqKit

@Suite struct JqExecutableTests {

    /// Drive the JqExecutable with a fake stdin and capture stdout/stderr
    /// through ShellKit's `OutputSink` / `InputSource`.
    private func run(_ argv: [String], input: String = "") async throws -> (stdout: String, stderr: String, exit: Int32) {
        let stdinSource: InputSource = .string(input)
        let stdoutSink = OutputSink()
        let stderrSink = OutputSink()

        let exit = try await JqExecutable.run(
            argv: argv,
            stdin: stdinSource,
            stdout: stdoutSink,
            stderr: stderrSink)

        stdoutSink.finish()
        stderrSink.finish()
        let outString = await stdoutSink.readAllString()
        let errString = await stderrSink.readAllString()
        return (outString, errString, exit)
    }

    @Test func identity() async throws {
        let r = try await run(["."], input: #"{"a":1}"#)
        #expect(r.exit == 0)
        #expect(r.stdout == "{\n  \"a\": 1\n}\n")
    }

    @Test func compactOutput() async throws {
        let r = try await run(["-c", "."], input: #"{"a":1,"b":2}"#)
        #expect(r.exit == 0)
        #expect(r.stdout == #"{"a":1,"b":2}"# + "\n")
    }

    @Test func rawOutput() async throws {
        let r = try await run(["-r", ".name"], input: #"{"name":"alice"}"#)
        #expect(r.exit == 0)
        #expect(r.stdout == "alice\n")
    }

    @Test func sortKeys() async throws {
        let r = try await run(["-cS", "."], input: #"{"b":2,"a":1}"#)
        #expect(r.exit == 0)
        #expect(r.stdout == #"{"a":1,"b":2}"# + "\n")
    }

    @Test func nullInputWithArg() async throws {
        let r = try await run(["-n", "--arg", "x", "hi", "$x"])
        #expect(r.exit == 0)
        #expect(r.stdout == "\"hi\"\n")
    }

    @Test func argjsonParsesNumbers() async throws {
        let r = try await run(["-n", "--argjson", "n", "42", "$n + 1"])
        #expect(r.exit == 0)
        #expect(r.stdout == "43\n")
    }

    @Test func filterParseErrorReturnsExit3() async throws {
        let r = try await run([".a |"], input: "{}")
        #expect(r.exit == 3)
        #expect(r.stderr.contains("jq:"))
    }

    @Test func exitStatusOnFalsy() async throws {
        let r = try await run(["-e", ".missing"], input: "{}")
        #expect(r.exit == 1)
    }

    @Test func iteratesArray() async throws {
        let r = try await run([".[]"], input: "[1,2,3]")
        #expect(r.exit == 0)
        #expect(r.stdout == "1\n2\n3\n")
    }

    @Test func parsesWithAsyncParsableCommand() throws {
        let cmd = try Jq.parse(["-r", ".name"])
        #expect(cmd.rawArgv == ["-r", ".name"])
    }
}

#endif  // !os(Android)
