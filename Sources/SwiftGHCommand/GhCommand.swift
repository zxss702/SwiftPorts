import ArgumentParser

public struct GhCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "gh",
        abstract: "Work seamlessly with GitHub from the command line.",
        version: "0.1.0-dev",
        subcommands: [
            VersionCommand.self,
            AuthCommand.self,
            ApiCommand.self,
            RepoCommand.self,
            ReleaseCommand.self,
            IssueCommand.self,
            PrCommand.self,
            SearchCommand.self,
            GistCommand.self,
            WorkflowCommand.self,
            RunCommand.self,
            LabelCommand.self,
            ConfigCommand.self,
            ProjectCommand.self,
            BrowseCommand.self,
        ]
    )

    public init() {}
}
