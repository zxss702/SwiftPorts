import ArgumentParser

struct ReleaseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "release",
        abstract: "Manage GitLab releases.",
        subcommands: [
            ReleaseList.self,
            ReleaseView.self,
            ReleaseCreate.self,
            ReleaseDelete.self,
        ]
    )
}
