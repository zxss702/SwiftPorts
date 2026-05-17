import ArgumentParser
import Foundation
import FdKit
import ForgeKit
import ShellKit

/// `fd [OPTIONS] [PATTERN] [PATH ...]` — file/directory finder.
///
/// Pure-Swift port of sharkdp/fd. Mirrors upstream's flag surface for
/// the options users reach for daily:
///
///   * Pattern syntax: `--glob`, `--regex`, `-F`/`--fixed-strings`.
///   * Case: `-i`/`--ignore-case`, `-s`/`--case-sensitive`,
///     `--smart-case`.
///   * Path matching: `-p`/`--full-path`, `-e`/`--extension`.
///   * Ignore family: `-H`/`--hidden`, `-I`/`--no-ignore`,
///     `--no-ignore-vcs`, `--no-ignore-parent`,
///     `--no-global-ignore-file`, `--no-require-git`, `-u`/
///     `--unrestricted`.
///   * Filters: `-t`/`--type`, `-E`/`--exclude`, `-S`/`--size`,
///     `--changed-within`, `--changed-before`.
///   * Depth: `-d`/`--max-depth`, `--min-depth`, `--exact-depth`,
///     `--max-results`, `-1`.
///   * Output: `-a`/`--absolute-path`, `--relative-path`,
///     `--strip-cwd-prefix`, `--path-separator`, `-0`/`--print0`,
///     `--color`, `-q`/`--quiet`.
///
/// The CLI hand-parses argv so flags can be sprinkled anywhere on the
/// command line — `fd --hidden 'foo' src` works just like real `fd`.
public struct FdCommand: AsyncParsableCommand {

    public static let configuration = CommandConfiguration(
        commandName: "fd",
        abstract: "Find files and directories whose names match a pattern.",
        discussion: """
            A pure-Swift reimplementation of sharkdp/fd. Respects
            .gitignore, .ignore, and .fdignore. Skips hidden files by
            default. Emits ANSI color on TTY stdout.
            """,
        version: FdCommand.versionString
    )

    @Argument(parsing: .captureForPassthrough,
              help: "OPTIONS, PATTERN, PATH...")
    public var rawArgv: [String] = []

    public init() {}

    public static let versionString = "fd 0.1.0 (swift-ports)"

    public func run() async throws {
        let stdin = Shell.current.stdin
        let stdout = Shell.current.stdout
        let stderr = Shell.current.stderr
        let exit = try await FdExecutable.run(argv: rawArgv,
                                              stdin: stdin,
                                              stdout: stdout,
                                              stderr: stderr)
        if exit != 0 {
            throw ExitCode(exit)
        }
    }
}
