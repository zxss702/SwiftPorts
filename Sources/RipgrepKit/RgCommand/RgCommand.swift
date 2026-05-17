import ArgumentParser
import Foundation
import ForgeKit
import RipgrepKit
import ShellKit

/// `rg [OPTIONS] PATTERN [PATH ...]` — recursive code search.
///
/// Pure-Swift port of BurntSushi/ripgrep. Mirrors upstream's flag
/// surface for the options users actually reach for daily:
///
///   * Search shape: `-i`, `-S`, `-s`, `-F`, `-w`, `-x`, `-v`, `-U`,
///     `-m`, `-A`, `-B`, `-C`, `-E`.
///   * Walker: `-t`, `-T`, `-g`, `--iglob`, `--hidden`, `-L`,
///     `--max-depth`, `--max-filesize`, `--no-ignore` family.
///   * Output: `-n`, `-N`, `-H`, `-I`, `--column`, `-b`, `--heading`,
///     `--color`, `-r`, `-o`, `--passthru`, `--null`, `-0`, `--trim`,
///     `--max-columns`, `--vimgrep`, `--path-separator`.
///   * Modes: `-c`, `--count-matches`, `-l`, `--files-without-match`,
///     `--json`, `-q`, `--files`, `--type-list`.
///   * Multi-pattern: `-e`, `-f`.
///   * Misc: `--no-config`, `--version`, `-h`/`--help`.
///
/// The CLI hand-parses argv so users can put flags anywhere on the
/// command line — `rg pattern -i path` works just like real `rg`.
public struct Rg: AsyncParsableCommand {

    public static let configuration = CommandConfiguration(
        commandName: "rg",
        abstract: "Recursively search the current directory for lines matching a regex pattern.",
        discussion: """
            A pure-Swift reimplementation of BurntSushi/ripgrep.
            Respects .gitignore, .ignore, .rgignore. Skips hidden
            files and binary files by default. Emits ANSI color on
            TTY stdout; JSON Lines via --json.
            """,
        version: Rg.versionString
    )

    @Argument(parsing: .captureForPassthrough,
              help: "OPTIONS, PATTERN, PATH...")
    public var rawArgv: [String] = []

    public init() {}

    public static let versionString = "rg 0.1.0 (swift-ports)"

    public func run() async throws {
        let stdin = Shell.current.stdin
        let stdout = Shell.current.stdout
        let stderr = Shell.current.stderr
        let exit = try await RgExecutable.run(argv: rawArgv,
                                              stdin: stdin,
                                              stdout: stdout,
                                              stderr: stderr)
        if exit != 0 {
            throw ExitCode(exit)
        }
    }
}
