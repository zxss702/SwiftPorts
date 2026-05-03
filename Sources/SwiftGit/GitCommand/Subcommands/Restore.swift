import ArgumentParser
import Foundation
import SwiftGit

/// `git restore` is real git's modern replacement for `git checkout
/// -- <paths>` and `git reset HEAD <paths>`. Maps directly onto our
/// existing checkout / reset machinery.
struct Restore: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restore",
        abstract: "Restore working-tree files."
    )

    @Flag(name: [.customShort("S"), .customLong("staged")],
          help: "Restore the index from <source> instead of the working tree.")
    var staged: Bool = false

    @Option(name: [.customShort("s"), .customLong("source")],
            help: "Source to restore from. Defaults to HEAD when --staged, otherwise the index.")
    var source: String?

    @Argument(help: "Paths to restore.")
    var paths: [String]

    func validate() throws {
        if paths.isEmpty {
            throw ValidationError("you must specify path(s) to restore")
        }
    }

    func run() async throws {
        let client = CommandContext.gitClient()

        if staged {
            // Reset paths from <source> (default HEAD) into the index.
            _ = try await client.reset(paths: paths, from: source ?? "HEAD")
            return
        }
        // Working-tree restore: from <source> if given, else from index.
        if let source {
            try await client.checkoutPaths(paths, from: source)
        } else {
            try await client.checkoutPaths(paths)
        }
    }
}
