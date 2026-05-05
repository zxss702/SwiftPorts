import ArgumentParser
import Foundation

public struct GhCommand: AsyncParsableCommand {
    /// Custom entry point so we can rewrite bare `--json` (no value, or
    /// followed by another flag) into `--json ""`. Subcommands then
    /// detect the empty value and print the available-fields list, the
    /// way upstream `gh` does.
    public static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        if let idx = args.firstIndex(of: "--json") {
            let next = idx + 1
            if next >= args.count || args[next].hasPrefix("-") {
                args.insert("", at: next)
            }
        }
        do {
            var command = try parseAsRoot(args)
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            exit(withError: error)
        }
    }

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
            SshKeyCommand.self,
            GpgKeyCommand.self,
            OrgCommand.self,
            VariableCommand.self,
            CacheCommand.self,
            SecretCommand.self,
        ]
    )

    public init() {}
}
