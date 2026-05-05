import ArgumentParser
import Foundation
import SwiftGit

/// `git archive` — produce a tar / tar.gz / tar.bz2 / tar.xz / tar.zst /
/// zip of any tree-ish, entirely in-process via libarchive. No `Process`
/// spawn, no shell-out — works under sandboxed iOS / tvOS / watchOS /
/// visionOS.
struct Archive: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "archive",
        abstract: "Create an archive of files from a named tree.",
        discussion: """
        Examples:
          git archive --format=tar.gz -o release.tar.gz HEAD
          git archive --format=zip --prefix=foo/ v1.2.3 -o foo.zip
          git archive --format=tar.zst -o snapshot.tzst HEAD

        bzip2 / xz / zstd variants only run on macOS / Linux /
        Windows — iOS / Android skip those filter traits.
        """
    )

    @Option(name: .long,
            help: "tar | tar.gz | tar.bz2 | tar.xz | tar.zst | zip. Default inferred from -o, else tar.")
    var format: String?

    @Option(name: [.customShort("o"), .long],
            help: "Write archive to FILE. Required (stdout streaming TBD).")
    var output: String

    @Option(name: .long,
            help: "Prepend PREFIX to every entry path (trailing slash optional).")
    var prefix: String?

    @Argument(help: "Tree-ish to archive (commit, branch, tag, or tree SHA). Default: HEAD.")
    var treeish: String = "HEAD"

    func run() async throws {
        let resolvedFormat = try resolveFormat()
        let outputURL = URL(fileURLWithPath: output)
        let client = SwiftGit.GitClient(
            workingDirectory: URL(fileURLWithPath:
                FileManager.default.currentDirectoryPath))
        try await client.archiveTree(
            treeish: treeish,
            format: resolvedFormat,
            to: outputURL,
            prefix: prefix)
    }

    /// Picks the archive format, in priority order:
    /// 1. `--format=` if given.
    /// 2. Output file suffix (`.tar.gz`, `.tgz`, `.zip`, …).
    /// 3. Plain tar.
    private func resolveFormat() throws -> GitArchiveFormat {
        if let raw = format?.lowercased() {
            switch raw {
            case "tar":                          return .tar
            case "tar.gz", "tgz":                return .tarGzip
            case "tar.bz2", "tbz", "tbz2":       return .tarBzip2
            case "tar.xz", "txz":                return .tarXz
            case "tar.zst", "tzst":              return .tarZstd
            case "zip":                          return .zip
            default:
                throw ValidationError(
                    "Unknown --format '\(raw)'. Supported: tar, tar.gz, tar.bz2, tar.xz, tar.zst, zip.")
            }
        }
        let lower = output.lowercased()
        if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz") {
            return .tarGzip
        }
        if lower.hasSuffix(".tar.bz2") || lower.hasSuffix(".tbz")
            || lower.hasSuffix(".tbz2") {
            return .tarBzip2
        }
        if lower.hasSuffix(".tar.xz") || lower.hasSuffix(".txz") {
            return .tarXz
        }
        if lower.hasSuffix(".tar.zst") || lower.hasSuffix(".tzst") {
            return .tarZstd
        }
        if lower.hasSuffix(".zip") {
            return .zip
        }
        return .tar
    }
}
