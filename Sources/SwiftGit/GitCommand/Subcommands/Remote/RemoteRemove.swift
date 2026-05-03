import ArgumentParser
import SwiftGit

struct RemoteRemove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove the named remote.",
        aliases: ["rm"]
    )

    @Argument(help: "Remote name.")
    var name: String

    func run() async throws {
        do {
            try await CommandContext.gitClient().remoteDelete(name: name)
        } catch let err as Libgit2Error
            where err.message.lowercased().contains("not found") {
            throw CLIError.stderr(
                "error: No such remote: '\(name)'", exitCode: 2)
        }
    }
}
