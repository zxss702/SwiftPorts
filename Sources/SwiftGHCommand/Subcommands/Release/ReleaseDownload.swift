import ArgumentParser
import Foundation
import SwiftGHCore

struct ReleaseDownload: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "download",
        abstract: "Download release assets.",
        discussion: """
        Downloads matching assets to the current directory.

        Without --pattern, all assets are downloaded.
        Use --tag to pick a specific tag (default: latest).
        """
    )

    @Option(name: [.short, .long],
            help: "Repository as OWNER/REPO.")
    var repo: RepositoryReference

    @Option(name: .long, help: "Release tag to download.")
    var tag: String?

    @Option(name: [.short, .customLong("pattern")],
            parsing: .singleValue,
            help: "Glob to match asset names; repeatable.")
    var patterns: [String] = []

    @Option(name: [.short, .customLong("dir")],
            help: "Destination directory.")
    var directory: String = "."

    func run() async throws {
        let client = APIClient()
        let path = tag.map { "repos/\(repo.slug)/releases/tags/\($0)" }
            ?? "repos/\(repo.slug)/releases/latest"
        let release: Release = try await client.get(path)

        let matching = release.assets.filter { asset in
            patterns.isEmpty || patterns.contains { fnmatch(pattern: $0, name: asset.name) }
        }
        guard !matching.isEmpty else {
            throw ValidationError(
                "No assets matched. Available: " +
                release.assets.map(\.name).joined(separator: ", "))
        }

        let destDir = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(
            at: destDir, withIntermediateDirectories: true)

        for asset in matching {
            let dest = destDir.appendingPathComponent(asset.name)
            print("→ \(asset.name) (\(ByteCountFormatter.string(fromByteCount: asset.size, countStyle: .file)))")
            let (data, _) = try await URLSession.shared.data(from: asset.browserDownloadUrl)
            try data.write(to: dest)
        }
    }

    /// Minimal `fnmatch` — supports `*` and `?`. No bracket classes.
    private func fnmatch(pattern: String, name: String) -> Bool {
        let p = Array(pattern), n = Array(name)
        var memo: [[Bool?]] = Array(
            repeating: Array(repeating: nil, count: n.count + 1),
            count: p.count + 1)
        func match(_ i: Int, _ j: Int) -> Bool {
            if let cached = memo[i][j] { return cached }
            let result: Bool
            if i == p.count { result = j == n.count }
            else if p[i] == "*" {
                result = match(i + 1, j) || (j < n.count && match(i, j + 1))
            } else if j < n.count && (p[i] == "?" || p[i] == n[j]) {
                result = match(i + 1, j + 1)
            } else {
                result = false
            }
            memo[i][j] = result
            return result
        }
        return match(0, 0)
    }
}
