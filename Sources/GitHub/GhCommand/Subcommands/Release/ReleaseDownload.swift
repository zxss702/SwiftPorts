import ArgumentParser
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking  // URLSession lives in a separate module on Linux
#endif
import GitHub
import TarKit
import XzKit
import ZipKit

struct ReleaseDownload: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "download",
        abstract: "Download release assets.",
        discussion: """
        Downloads matching assets to the current directory.

        Without --pattern, all assets are downloaded.
        Use --tag to pick a specific tag (default: latest).

        With --extract, recognized archive assets (.zip, .tar, .tar.gz,
        .tgz) are unpacked into a sibling directory named after the
        asset (with the archive suffix stripped). The original archive
        file is kept; pass --extract --no-keep-archive to remove it
        after a successful extract.
        """
    )

    @Option(name: [.short, .long],
            help: "Repository as OWNER/REPO. Defaults to the current directory's git remote.")
    var repo: RepositoryReference?

    @Option(name: .long, help: "Release tag to download.")
    var tag: String?

    @Option(name: [.short, .customLong("pattern")],
            parsing: .singleValue,
            help: "Glob to match asset names; repeatable.")
    var patterns: [String] = []

    @Option(name: [.short, .customLong("dir")],
            help: "Destination directory.")
    var directory: String = "."

    @Flag(name: .long,
          help: "Unpack recognized archive assets after download.")
    var extract: Bool = false

    @Flag(name: .customLong("no-keep-archive"),
          help: "After --extract, remove the original archive file.")
    var noKeepArchive: Bool = false

    func run() async throws {
        let target = try await RepositoryResolver.resolve(flag: repo)
        let client = try await CommandContext.apiClient()
        let path = tag.map { "repos/\(target.slug)/releases/tags/\($0)" }
            ?? "repos/\(target.slug)/releases/latest"
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

        // Linux's swift-corelibs-foundation doesn't expose
        // `URLSession.shared`; instantiate explicitly so the same code
        // builds on every platform.
        let session = URLSession(configuration: .default)
        for asset in matching {
            let dest = destDir.appendingPathComponent(asset.name)
            print("→ \(asset.name) (\(ByteCountFormatter.string(fromByteCount: asset.size, countStyle: .file)))")
            let (data, _) = try await session.data(from: asset.browserDownloadUrl)
            try data.write(to: dest)

            if extract, let format = ArchiveFormatDetector.detect(name: asset.name) {
                let extractDir = destDir.appendingPathComponent(
                    ArchiveFormatDetector.strippedBaseName(asset.name),
                    isDirectory: true)
                try FileManager.default.createDirectory(
                    at: extractDir, withIntermediateDirectories: true)
                try ArchiveFormatDetector.extract(
                    archive: dest, format: format, into: extractDir)
                print("  ↳ extracted into \(extractDir.lastPathComponent)/")
                if noKeepArchive {
                    try? FileManager.default.removeItem(at: dest)
                }
            }
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

/// Routes archive assets to the appropriate extractor based on
/// filename suffix. Lives next to the download command because that's
/// the only caller today; promote to GitHub/Lib/IO/ if a second
/// caller appears.
enum ArchiveFormatDetector {
    enum Format {
        case zip
        case tar           // any libarchive-readable tar (.tar, .tar.gz, .tgz, …)
    }

    static func detect(name: String) -> Format? {
        let lower = name.lowercased()
        if lower.hasSuffix(".zip") { return .zip }
        if lower.hasSuffix(".tar")
            || lower.hasSuffix(".tar.gz")
            || lower.hasSuffix(".tgz")
            || lower.hasSuffix(".tar.bz2")
            || lower.hasSuffix(".tar.xz")
            || lower.hasSuffix(".tar.zst") {
            return .tar
        }
        return nil
    }

    /// Returns the archive's "natural" extracted directory name —
    /// `foo-1.2.3.tar.gz` → `foo-1.2.3`, `foo.zip` → `foo`.
    static func strippedBaseName(_ name: String) -> String {
        let suffixes = [".tar.gz", ".tar.bz2", ".tar.xz", ".tar.zst",
                        ".tgz", ".tar", ".zip"]
        let lower = name.lowercased()
        for suffix in suffixes where lower.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    static func extract(archive: URL, format: Format, into dest: URL) throws {
        switch format {
        case .zip:
            try ZipKit.Archive.extract(
                from: archive,
                options: ZipKit.ExtractOptions(destination: dest))
        case .tar:
            // For `.tar.xz` on platforms where libarchive's lzma
            // filter isn't compiled in (Apple-mobile / Android in our
            // build matrix), libarchive's tar reader will fail on
            // the wrapper. Detect that suffix and pre-decompress
            // through XzKit (which has its own Apple-libcompression
            // backend), then hand plain tar bytes to TarKit. Other
            // platforms fall through to libarchive's auto-detect
            // path which handles every supported filter natively.
            #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
            let lower = archive.lastPathComponent.lowercased()
            if lower.hasSuffix(".tar.xz") || lower.hasSuffix(".txz") {
                let xzBytes = try Data(contentsOf: archive)
                let tarBytes = try XzKit.Xz.decompress(xzBytes)
                try TarKit.Archive.extract(
                    from: tarBytes,
                    options: TarKit.ExtractOptions(destination: dest))
                return
            }
            #endif
            try TarKit.Archive.extract(
                from: archive,
                options: TarKit.ExtractOptions(destination: dest))
        }
    }
}
