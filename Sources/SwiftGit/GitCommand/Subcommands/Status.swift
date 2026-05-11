import ArgumentParser
import ForgeKit
import ShellKit
import Foundation
import SwiftGit

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show the working-tree status."
    )

    @Flag(name: [.customShort("s"), .customLong("short")],
          help: "One-line-per-file `XY <path>` format.")
    var short: Bool = false

    @Flag(name: .customLong("porcelain"),
          help: "Stable machine-readable format (alias for --short).")
    var porcelain: Bool = false

    @Flag(name: [.customShort("b"), .customLong("branch")],
          help: "Show the branch in the header (always shown in verbose mode).")
    var branch: Bool = false

    @Option(name: .customLong("color"),
            help: "Colorize output: always, auto (default), or never.")
    var color: ColorChoice = .auto

    func run() async throws {
        let report = try await CommandContext.gitClient().status()

        // --short and --porcelain produce identical output for our
        // subset (we don't implement the `=v2` variant).
        if short || porcelain {
            let out = report.shortFormat(branchHeader: branch)
            Shell.current.stdout.write(Data(out.utf8))
            return
        }

        // Verbose form.
        let palette = ColorPalette(enabled: color.resolved())
        let out = report.verboseFormat(palette: palette)
        Shell.current.stdout.write(Data(out.utf8))
    }
}
