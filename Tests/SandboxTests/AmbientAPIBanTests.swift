import Foundation
import Testing

/// Enforces the Phase 2 retrofit invariant: production sources outside
/// `Sources/Sandbox/` must not reach for process-global ambient APIs
/// directly. Reads must go through `Sandbox.env(_:)` /
/// `Sandbox.environment` / `Sandbox.arguments` / `Sandbox.<region>`
/// / `Sandbox.currentDirectory` / `Sandbox.resolve(_:)`.
///
/// This catches regressions: future PRs that accidentally reintroduce
/// `FileManager.default.currentDirectoryPath` or
/// `ProcessInfo.processInfo.environment` will fail this test.
///
/// **What's checked**: every `.swift` file under `Sources/`, excluding
/// `Sources/Sandbox/` itself (which legitimately implements the
/// fallbacks).
///
/// **What's allowed**: `Sources/Sandbox/Sandbox.swift` and
/// `Sandbox+Factories.swift` may reference these APIs as the
/// authoritative fallback path.
@Suite struct AmbientAPIBanTests {

    /// Substrings that, if found in a non-Sandbox source file, fail
    /// the test. Each entry is `(needle, advice)` so the failure
    /// message points at the right replacement.
    private static let bannedNeedles: [(String, String)] = [
        ("FileManager.default.currentDirectoryPath",
         "use Sandbox.currentDirectory"),
        ("FileManager.default.homeDirectoryForCurrentUser",
         "use Sandbox.homeDirectory"),
        ("FileManager.default.temporaryDirectory",
         "use Sandbox.temporaryDirectory"),
        ("NSTemporaryDirectory()",
         "use Sandbox.temporaryDirectory"),
        ("ProcessInfo.processInfo.environment",
         "use Sandbox.env(_:) or Sandbox.environment"),
        ("CommandLine.arguments",
         "use Sandbox.arguments"),
        ("URL.documentsDirectory",
         "use Sandbox.documentsDirectory"),
        ("URL.cachesDirectory",
         "use Sandbox.cachesDirectory"),
        ("URL.downloadsDirectory",
         "use Sandbox.downloadsDirectory"),
        ("URL.libraryDirectory",
         "use Sandbox.libraryDirectory"),
        ("URL.moviesDirectory",
         "use Sandbox.moviesDirectory"),
        ("URL.musicDirectory",
         "use Sandbox.musicDirectory"),
        ("URL.picturesDirectory",
         "use Sandbox.picturesDirectory"),
        ("URL.sharedPublicDirectory",
         "use Sandbox.sharedPublicDirectory"),
        ("URL.trashDirectory",
         "use Sandbox.trashDirectory"),
        ("URL.userDirectory",
         "use Sandbox.userDirectory"),
        ("URL.temporaryDirectory",
         "use Sandbox.temporaryDirectory"),
    ]

    @Test func noBannedAmbientAPIsInSources() throws {
        let sourcesURL = repoRoot().appendingPathComponent("Sources", isDirectory: true)
        let sandboxURL = sourcesURL.appendingPathComponent("Sandbox", isDirectory: true)

        let allSwiftFiles = try collectSwiftFiles(under: sourcesURL)
        let auditFiles = allSwiftFiles.filter {
            !$0.path.hasPrefix(sandboxURL.path + "/")
                && $0.path != sandboxURL.path
        }

        var violations: [(file: URL, line: Int, needle: String, advice: String)] = []

        for file in auditFiles {
            let body: String
            do {
                body = try String(contentsOf: file, encoding: .utf8)
            } catch {
                continue
            }
            let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
            for (idx, line) in lines.enumerated() {
                // Skip comment-only lines (// or /// or *) — needles in
                // explanatory comments are fine.
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//")
                    || trimmed.hasPrefix("*")
                    || trimmed.hasPrefix("/*") {
                    continue
                }
                for (needle, advice) in Self.bannedNeedles {
                    if line.contains(needle) {
                        violations.append((
                            file: file,
                            line: idx + 1,
                            needle: needle,
                            advice: advice))
                    }
                }
            }
        }

        if !violations.isEmpty {
            let message = violations.map { v in
                "\(v.file.path):\(v.line) — found `\(v.needle)`; \(v.advice)"
            }.joined(separator: "\n")
            Issue.record(
                "\(violations.count) ambient-API ban violation(s) in Sources/:\n\(message)")
        }
    }

    // MARK: - Helpers

    private func repoRoot() -> URL {
        // SourceFile lives at <root>/Tests/SandboxTests/AmbientAPIBanTests.swift.
        // Walk up from #filePath until we find Package.swift.
        var url = URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()
        while url.path != "/" {
            if FileManager.default.fileExists(
                atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            url = url.deletingLastPathComponent()
        }
        return url
    }

    private func collectSwiftFiles(under root: URL) throws -> [URL] {
        var result: [URL] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles])
        else { return [] }
        for case let url as URL in enumerator {
            if url.pathExtension == "swift" {
                result.append(url)
            }
        }
        return result
    }
}
