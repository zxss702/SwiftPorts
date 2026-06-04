import ArgumentParser
import Foundation
import ShellKit
import Sqlite3Shell

/// `sqlite3 [OPTIONS] FILENAME [SQL]` — run SQL against a SQLite database
/// from the command line.
///
/// A thin ArgumentParser shell that captures the whole argv and hands it
/// to ``Sqlite3Shell/Sqlite3Executable``; SQLite's single-dash long
/// options are parsed there. The driver lives in the ArgumentParser-free
/// ``Sqlite3Shell`` target so hosts that can't link ArgumentParser (e.g.
/// SwiftBash on Android) can drive the CLI in-process without this
/// wrapper. Exposed as a library target so SwiftBash and other hosts can
/// register it as a builtin.
public struct Sqlite3: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "sqlite3",
        abstract: "Run SQL against a SQLite database from the command line."
    )

    @Argument(parsing: .captureForPassthrough,
              help: "OPTIONS, FILENAME, SQL…")
    public var rawArgv: [String] = []

    public init() {}

    public func run() async throws {
        let code = try await Sqlite3Executable.run(
            argv: rawArgv,
            stdin: Shell.current.stdin,
            stdout: Shell.current.stdout,
            stderr: Shell.current.stderr)
        if code != 0 {
            throw ExitCode(code)
        }
    }
}
