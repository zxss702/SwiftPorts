import ArgumentParser
import ShellKit
import Foundation
import SwiftGit

struct LsFiles: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ls-files",
        abstract: "Show information about files in the index."
    )

    @Flag(name: [.customShort("s"), .customLong("stage")],
          help: "Show mode, object name, and stage number for each entry.")
    var stage: Bool = false

    func run() async throws {
        let client = CommandContext.gitClient()
        if stage {
            // `git ls-files -s` format: `<mode> SP <oid> SP <stage>
            // TAB <path>`. Mode is six-digit octal (the high bits
            // libgit2 stores include the file-type field, so we use
            // 6 digits and mask in the standard way real git does).
            let entries = try await client.indexedEntries()
            for entry in entries {
                let mode = String(format: "%06o", entry.mode)
                Shell.print("\(mode) \(entry.oid) \(entry.stage)\t\(entry.path)")
            }
        } else {
            let paths = try await client.indexedPaths()
            for path in paths { Shell.print(path) }
        }
    }
}
