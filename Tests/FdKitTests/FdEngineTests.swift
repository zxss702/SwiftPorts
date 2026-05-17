import Foundation
import RipgrepKit
import ShellKit
import Testing
@testable import FdKit

/// Engine-level smoke tests against `Fd.run`. These cover the walker
/// integration (gitignore / .fdignore / hidden / depth / filter) and
/// the printer output shape. The CLI-layer tests live in `FdTests`.
@Suite struct FdEngineTests {

    @Test func listsAllEntriesUnderRoot() async throws {
        let root = try makeTree([
            "a.txt":     "x",
            "b.md":      "y",
            "sub/c.txt": "z",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let lines = try await runEngine(config: Fd.Configuration(),
                                        rootPath: root.path)
        let cleaned = stripRootPrefix(lines, root: root)
        #expect(cleaned.contains("a.txt"))
        #expect(cleaned.contains("b.md"))
        #expect(cleaned.contains("sub/c.txt"))
        #expect(cleaned.contains("sub/"))
    }

    @Test func regexAgainstBasename() async throws {
        let root = try makeTree([
            "a.swift": "x",
            "b.txt":   "y",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        var cfg = Fd.Configuration()
        cfg.pattern.pattern = "\\.swift$"
        cfg.pattern.caseMode = .caseSensitive
        let lines = try await runEngine(config: cfg, rootPath: root.path)
        let cleaned = stripRootPrefix(lines, root: root)
        #expect(cleaned.contains("a.swift"))
        #expect(!cleaned.contains("b.txt"))
    }

    @Test func globMatchesBasename() async throws {
        let root = try makeTree([
            "a.txt":     "x",
            "b.md":      "y",
            "sub/c.txt": "z",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        var cfg = Fd.Configuration()
        cfg.pattern.pattern = "*.txt"
        cfg.pattern.syntax = .glob
        let lines = try await runEngine(config: cfg, rootPath: root.path)
        let cleaned = stripRootPrefix(lines, root: root)
        #expect(cleaned.contains("a.txt"))
        #expect(cleaned.contains("sub/c.txt"))
        #expect(!cleaned.contains("b.md"))
    }

    @Test func gitignoreRespected() async throws {
        let root = try makeTree([
            ".git/HEAD":  "ref: refs/heads/main\n",
            ".gitignore": "*.log\n",
            "a.log":      "x",
            "a.txt":      "y",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let lines = try await runEngine(config: Fd.Configuration(),
                                        rootPath: root.path)
        let cleaned = stripRootPrefix(lines, root: root)
        #expect(cleaned.contains("a.txt"))
        #expect(!cleaned.contains("a.log"))
    }

    @Test func fdignoreRespected() async throws {
        let root = try makeTree([
            ".git/HEAD": "ref: refs/heads/main\n",
            ".fdignore": "drop/\n",
            "drop/x":    "x",
            "keep/y":    "y",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let lines = try await runEngine(config: Fd.Configuration(),
                                        rootPath: root.path)
        let cleaned = stripRootPrefix(lines, root: root)
        #expect(cleaned.contains("keep/y"))
        #expect(!cleaned.contains("drop/x"))
        #expect(!cleaned.contains("drop/"))
    }

    @Test func hiddenFilesIncludedWithFlag() async throws {
        let root = try makeTree([
            ".secret":  "x",
            "visible":  "y",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        var cfg = Fd.Configuration()
        cfg.walker.hidden = true
        let lines = try await runEngine(config: cfg, rootPath: root.path)
        let cleaned = stripRootPrefix(lines, root: root)
        #expect(cleaned.contains(".secret"))
        #expect(cleaned.contains("visible"))
    }

    @Test func maxResultsCapsOutput() async throws {
        let root = try makeTree([
            "a": "1",
            "b": "2",
            "c": "3",
            "d": "4",
            "e": "5",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        var cfg = Fd.Configuration()
        cfg.filter.maxResults = 2
        let lines = try await runEngine(config: cfg, rootPath: root.path)
        #expect(lines.count == 2)
    }

    @Test func typeFilterFilesOnly() async throws {
        let root = try makeTree([
            "a.txt":       "x",
            "sub/b.txt":   "y",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        var cfg = Fd.Configuration()
        cfg.filter.fileTypes = [.file]
        let lines = try await runEngine(config: cfg, rootPath: root.path)
        let cleaned = stripRootPrefix(lines, root: root)
        #expect(cleaned.contains("a.txt"))
        #expect(cleaned.contains("sub/b.txt"))
        // sub/ is a directory — must be excluded when filtering files.
        #expect(!cleaned.contains("sub/"))
    }

    @Test func typeFilterDirectoriesOnly() async throws {
        let root = try makeTree([
            "a.txt":         "x",
            "sub/b.txt":     "y",
            "sub2/c.txt":    "z",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        var cfg = Fd.Configuration()
        cfg.filter.fileTypes = [.directory]
        let lines = try await runEngine(config: cfg, rootPath: root.path)
        let cleaned = stripRootPrefix(lines, root: root)
        #expect(cleaned.contains("sub/"))
        #expect(cleaned.contains("sub2/"))
        #expect(!cleaned.contains("a.txt"))
    }

    @Test func excludePatternFiltersMatches() async throws {
        let root = try makeTree([
            "a.txt": "x",
            "b.md":  "y",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        var cfg = Fd.Configuration()
        cfg.filter.excludePatterns = ["*.md"]
        let lines = try await runEngine(config: cfg, rootPath: root.path)
        let cleaned = stripRootPrefix(lines, root: root)
        #expect(cleaned.contains("a.txt"))
        #expect(!cleaned.contains("b.md"))
    }

    @Test func minDepthDropsRootImmediateChildren() async throws {
        let root = try makeTree([
            "a.txt":          "x",
            "sub/b.txt":      "y",
            "sub/nested/c":   "z",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        var cfg = Fd.Configuration()
        cfg.filter.minDepth = 2
        let lines = try await runEngine(config: cfg, rootPath: root.path)
        let cleaned = stripRootPrefix(lines, root: root)
        #expect(!cleaned.contains("a.txt"))
        #expect(cleaned.contains("sub/b.txt"))
        #expect(cleaned.contains("sub/nested/c"))
    }

    @Test func print0UsesNullTerminator() async throws {
        let root = try makeTree([
            "a.txt": "x",
            "b.txt": "y",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        var cfg = Fd.Configuration()
        cfg.printer.print0 = true
        cfg.filter.fileTypes = [.file]
        let stdoutSink = OutputSink()
        let stderrSink = OutputSink()
        _ = try await Fd.run(
            configuration: cfg,
            searchPaths: [Walker.Root(url: root, display: root.path)],
            stdout: stdoutSink,
            stderr: stderrSink)
        stdoutSink.finish()
        let raw = await stdoutSink.readAllString()
        #expect(raw.contains("a.txt\0"))
        #expect(raw.contains("b.txt\0"))
        #expect(!raw.contains("a.txt\n"))
    }

    @Test func extensionFilter() async throws {
        let root = try makeTree([
            "a.swift": "x",
            "b.md":    "y",
            "c.swift": "z",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        var cfg = Fd.Configuration()
        cfg.pattern.extensions = ["swift"]
        let lines = try await runEngine(config: cfg, rootPath: root.path)
        let cleaned = stripRootPrefix(lines, root: root)
        #expect(cleaned.contains("a.swift"))
        #expect(cleaned.contains("c.swift"))
        #expect(!cleaned.contains("b.md"))
    }

    // MARK: - LS_COLORS plumbing

    /// A pinned LsColors spec routes through the printer end-to-end.
    /// Picks a couple of unmistakable codes so the assertion is on
    /// exact byte sequences.
    @Test func lsColorsPaintsByExtensionAndType() async throws {
        let root = try makeTree([
            "a.swift": "x",
            "sub/b.md": "y",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        var cfg = Fd.Configuration()
        cfg.printer.color = true
        cfg.printer.lsColors = LsColors(spec: "di=01;34:*.swift=38;5;202")
        let stdoutSink = OutputSink()
        let stderrSink = OutputSink()
        _ = try await Fd.run(
            configuration: cfg,
            searchPaths: [Walker.Root(url: root, display: root.path)],
            stdout: stdoutSink,
            stderr: stderrSink)
        stdoutSink.finish()
        let raw = await stdoutSink.readAllString()
        // .swift gets the 256-color code.
        #expect(raw.contains("\u{1B}[38;5;202m") && raw.contains("a.swift"))
        // The subdirectory gets the di code.
        #expect(raw.contains("\u{1B}[01;34m") && raw.contains("sub/"))
        // .md falls through with no styling and isn't escaped.
        let mdLine = raw.split(separator: "\n").first { $0.contains("b.md") }
        if let mdLine {
            #expect(!String(mdLine).contains("\u{1B}["),
                    "unexpected ANSI escape on .md line: \(mdLine)")
        }
    }

    @Test func lsColorsDisabledWhenColorOff() async throws {
        let root = try makeTree([
            "a.swift": "x",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        var cfg = Fd.Configuration()
        cfg.printer.color = false
        cfg.printer.lsColors = LsColors(spec: "*.swift=01;31")
        let stdoutSink = OutputSink()
        let stderrSink = OutputSink()
        _ = try await Fd.run(
            configuration: cfg,
            searchPaths: [Walker.Root(url: root, display: root.path)],
            stdout: stdoutSink,
            stderr: stderrSink)
        stdoutSink.finish()
        let raw = await stdoutSink.readAllString()
        #expect(!raw.contains("\u{1B}["),
                "ANSI escape leaked with color=false: \(raw)")
    }

    // MARK: - Match highlighting

    /// The matched portion of the path is painted with the highlight
    /// code, and the rest gets the base style. Use codes we can
    /// assert on exactly.
    @Test func matchHighlightPaintsOnlyTheMatchedPortion() async throws {
        let root = try makeTree([
            "src/foo.swift": "x",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        var cfg = Fd.Configuration()
        cfg.printer.color = true
        cfg.printer.lsColors = LsColors(spec: "")
        cfg.printer.matchHighlight = "33"
        cfg.pattern.pattern = "\\.swift$"
        cfg.pattern.caseMode = .caseSensitive
        let stdoutSink = OutputSink()
        let stderrSink = OutputSink()
        _ = try await Fd.run(
            configuration: cfg,
            searchPaths: [Walker.Root(url: root, display: root.path)],
            stdout: stdoutSink,
            stderr: stderrSink)
        stdoutSink.finish()
        let raw = await stdoutSink.readAllString()
        // The match-highlight escape must precede `.swift` and the
        // reset escape must follow it.
        #expect(raw.contains("\u{1B}[33m.swift\u{1B}[0m"),
                "match highlight not applied: \(raw)")
        // The pre-match path should be unstyled (LsColors spec is empty).
        #expect(raw.contains("foo\u{1B}[33m.swift"))
    }

    /// With `--full-path`, the highlight can span path separators.
    @Test func matchHighlightSpansFullPath() async throws {
        let root = try makeTree([
            "a/b/c/leaf.txt": "x",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        var cfg = Fd.Configuration()
        cfg.printer.color = true
        cfg.printer.lsColors = LsColors(spec: "")
        cfg.printer.matchHighlight = "33"
        cfg.pattern.pattern = "b/c"
        cfg.pattern.matchFullPath = true
        cfg.pattern.caseMode = .caseSensitive
        let stdoutSink = OutputSink()
        let stderrSink = OutputSink()
        _ = try await Fd.run(
            configuration: cfg,
            searchPaths: [Walker.Root(url: root, display: root.path)],
            stdout: stdoutSink,
            stderr: stderrSink)
        stdoutSink.finish()
        let raw = await stdoutSink.readAllString()
        #expect(raw.contains("\u{1B}[33mb/c\u{1B}[0m"),
                "full-path highlight missing: \(raw)")
    }

    /// When there's no pattern, no highlight should appear — even
    /// though base coloring still does.
    @Test func emptyPatternDoesNotPaintAnyHighlight() async throws {
        let root = try makeTree([
            "a.swift": "x",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        var cfg = Fd.Configuration()
        cfg.printer.color = true
        cfg.printer.lsColors = LsColors(spec: "*.swift=38;5;202")
        cfg.printer.matchHighlight = "01;31"
        // cfg.pattern.pattern stays empty.
        let stdoutSink = OutputSink()
        let stderrSink = OutputSink()
        _ = try await Fd.run(
            configuration: cfg,
            searchPaths: [Walker.Root(url: root, display: root.path)],
            stdout: stdoutSink,
            stderr: stderrSink)
        stdoutSink.finish()
        let raw = await stdoutSink.readAllString()
        #expect(raw.contains("\u{1B}[38;5;202m"),
                "base style missing: \(raw)")
        #expect(!raw.contains("\u{1B}[01;31m"),
                "highlight leaked under empty pattern: \(raw)")
    }

    /// Match highlight overlays the base style: pre/post segments
    /// keep the base code, the matched bytes get the highlight code.
    @Test func matchHighlightOverlaysOnBaseStyle() async throws {
        let root = try makeTree([
            "a.swift": "x",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        var cfg = Fd.Configuration()
        cfg.printer.color = true
        cfg.printer.lsColors = LsColors(spec: "*.swift=32")
        cfg.printer.matchHighlight = "31"
        cfg.pattern.pattern = "\\.swift$"
        cfg.pattern.caseMode = .caseSensitive
        let stdoutSink = OutputSink()
        let stderrSink = OutputSink()
        _ = try await Fd.run(
            configuration: cfg,
            searchPaths: [Walker.Root(url: root, display: root.path)],
            stdout: stdoutSink,
            stderr: stderrSink)
        stdoutSink.finish()
        let raw = await stdoutSink.readAllString()
        // The path is `<root.path>/a.swift`. With LsColors `*.swift=32`
        // and matchHighlight `31`, the pre-match segment (root.path
        // ending in `…/a`) wears `\e[32m…\e[0m` and the matched
        // `.swift` wears `\e[31m.swift\e[0m`. We assert on the
        // junction so the temp-dir prefix doesn't make the test brittle.
        #expect(raw.contains("a\u{1B}[0m\u{1B}[31m.swift\u{1B}[0m"),
                "expected base→highlight junction: \(raw)")
        #expect(raw.contains("\u{1B}[32m"),
                "expected base color code: \(raw)")
    }

    /// `matchHighlight = nil` disables highlighting while leaving the
    /// base color path alone.
    @Test func nilMatchHighlightDisablesOverlay() async throws {
        let root = try makeTree([
            "a.swift": "x",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        var cfg = Fd.Configuration()
        cfg.printer.color = true
        cfg.printer.lsColors = LsColors(spec: "*.swift=32")
        cfg.printer.matchHighlight = nil
        cfg.pattern.pattern = "\\.swift$"
        cfg.pattern.caseMode = .caseSensitive
        let stdoutSink = OutputSink()
        let stderrSink = OutputSink()
        _ = try await Fd.run(
            configuration: cfg,
            searchPaths: [Walker.Root(url: root, display: root.path)],
            stdout: stdoutSink,
            stderr: stderrSink)
        stdoutSink.finish()
        let raw = await stdoutSink.readAllString()
        #expect(raw.contains("\u{1B}[32m"),
                "base style missing: \(raw)")
        #expect(!raw.contains("\u{1B}[01;31m") && !raw.contains("\u{1B}[31m"),
                "highlight code leaked despite nil setting: \(raw)")
    }

    // MARK: - Helpers

    private func makeTree(_ tree: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fd-engine-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: root,
                                                withIntermediateDirectories: true)
        for (path, content) in tree {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        return root
    }

    /// Drive `Fd.run` against `rootPath` and return the newline-split
    /// stdout lines.
    private func runEngine(config: Fd.Configuration,
                           rootPath: String) async throws -> [String] {
        let stdoutSink = OutputSink()
        let stderrSink = OutputSink()
        _ = try await Fd.run(
            configuration: config,
            searchPaths: [Walker.Root(url: URL(fileURLWithPath: rootPath),
                                      display: rootPath)],
            stdout: stdoutSink,
            stderr: stderrSink)
        stdoutSink.finish()
        let out = await stdoutSink.readAllString()
        return out.split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    /// Strip the temp-dir prefix off each line so assertions can match
    /// `sub/c.txt`-shaped paths regardless of which temp dir the run
    /// landed in. Display paths from the walker are root-prefixed
    /// (`<root>/sub/c.txt`).
    private func stripRootPrefix(_ lines: [String], root: URL) -> [String] {
        let prefix = root.path + "/"
        return lines.map { line -> String in
            if line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count))
            }
            return line
        }
    }
}
