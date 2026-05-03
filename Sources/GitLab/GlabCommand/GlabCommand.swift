import ArgumentParser

public struct GlabCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "glab",
        abstract: "Work seamlessly with GitLab from the command line.",
        version: "0.1.0-dev",
        subcommands: [
            VersionCommand.self,
            AuthCommand.self,
            IssueCommand.self,
            MrCommand.self,
            CiCommand.self,
            RepoCommand.self,
            ReleaseCommand.self,
        ]
    )

    public init() {}
}
