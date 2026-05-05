import ArgumentParser

public struct GitCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "git",
        abstract: "Pure-Swift git client backed by libgit2.",
        discussion: """
            A focused subset of the git CLI implemented on top of the
            in-process libgit2 build — no `git` binary required.

            Today's surface mirrors the `GitClient` protocol: clone,
            fetch, checkout, push, plus `remote` and `branch` reads.
            Useful as a SwiftBash builtin, in sandboxed embedders, and
            anywhere you'd otherwise shell out to `git`.
            """,
        version: "0.1.0-dev",
        subcommands: [
            VersionCommand.self,
            GitInit.self,
            Clone.self,
            Fetch.self,
            Pull.self,
            Checkout.self,
            Push.self,
            Add.self,
            Reset.self,
            Status.self,
            Commit.self,
            Merge.self,
            Rebase.self,
            CherryPick.self,
            Diff.self,
            Log.self,
            StashCommand.self,
            RemoteCommand.self,
            Branch.self,
            Tag.self,
            RevParse.self,
            Show.self,
            Mv.self,
            Rm.self,
            Config.self,
            Switch.self,
            Restore.self,
            LsFiles.self,
            Clean.self,
            Blame.self,
            Apply.self,
            Reflog.self,
            Describe.self,
            LsTree.self,
            CatFile.self,
            Archive.self,
        ]
    )

    public init() {}
}
