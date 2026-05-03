import ArgumentParser

struct RepoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "repo",
        abstract: "Manage repositories.",
        subcommands: [
            RepoView.self,
            RepoList.self,
            RepoClone.self,
            RepoCreate.self,
            RepoFork.self,
        ]
    )
}
