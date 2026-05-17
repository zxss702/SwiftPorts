import Foundation
import Testing
@testable import RipgrepKit

@Suite struct WalkerTests {

    /// Mint a temp directory tree, run the walker over it, and return
    /// the emitted relative paths.
    private func walk(
        _ tree: [String: String],
        options: WalkerOptions = WalkerOptions()
    ) throws -> [String] {
        let root = makeTree(tree)
        defer { try? FileManager.default.removeItem(at: root) }
        var paths: [String] = []
        let walker = Walker(options: options)
        try walker.walk(roots: [Walker.Root(url: root, display: ".")]) { entry in
            paths.append(entry.relativePath)
        }
        return paths.sorted()
    }

    private func makeTree(_ tree: [String: String]) -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rg-walker-\(UUID().uuidString)",
                                    isDirectory: true)
        try? FileManager.default.createDirectory(at: root,
                                                 withIntermediateDirectories: true)
        for (path, content) in tree {
            let url = root.appendingPathComponent(path)
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path,
                                           contents: Data(content.utf8))
        }
        return root
    }

    @Test func walksRegularFiles() throws {
        let paths = try walk([
            "a.txt": "x", "b.txt": "y", "sub/c.txt": "z",
        ])
        #expect(paths == ["a.txt", "b.txt", "sub/c.txt"])
    }

    @Test func skipsHiddenByDefault() throws {
        let paths = try walk([
            "a.txt": "x", ".hidden": "y", ".secret/c.txt": "z",
        ])
        #expect(paths == ["a.txt"])
    }

    @Test func hiddenFlagIncludesHidden() throws {
        var opts = WalkerOptions()
        opts.hidden = true
        let paths = try walk([
            "a.txt": "x", ".hidden": "y",
        ], options: opts)
        #expect(paths.contains("a.txt"))
        #expect(paths.contains(".hidden"))
    }

    @Test func gitignoreRespected() throws {
        let paths = try walk([
            ".gitignore": "*.log\n",
            "a.txt": "x",
            "b.log": "y",
        ])
        #expect(paths == ["a.txt"])
    }

    @Test func gitignoreNegation() throws {
        let paths = try walk([
            ".gitignore": "*.log\n!important.log\n",
            "important.log": "x",
            "other.log": "y",
        ])
        #expect(paths == ["important.log"])
    }

    @Test func noIgnoreFlag() throws {
        var opts = WalkerOptions()
        opts.respectGitignore = false
        let paths = try walk([
            ".gitignore": "*.log\n",
            "a.txt": "x",
            "b.log": "y",
        ], options: opts)
        // .gitignore is hidden so it still gets skipped without --hidden;
        // matches real rg behaviour: `--no-ignore` doesn't imply hidden.
        #expect(paths == ["a.txt", "b.log"])
    }

    @Test func maxDepth() throws {
        var opts = WalkerOptions()
        opts.maxDepth = 0
        let paths = try walk([
            "a.txt": "x", "sub/b.txt": "y", "sub/deep/c.txt": "z",
        ], options: opts)
        // depth 0 = the root itself only — no descent.
        // Walker emits files in the root at depth 1; max-depth 0 prevents
        // any descent. So no files emitted.
        #expect(paths.isEmpty)

        var deeper = WalkerOptions()
        deeper.maxDepth = 1
        let p2 = try walk([
            "a.txt": "x", "sub/b.txt": "y", "sub/deep/c.txt": "z",
        ], options: deeper)
        #expect(p2.contains("a.txt"))
        #expect(!p2.contains("sub/b.txt"))
    }

    @Test func globIncludeAndExclude() throws {
        var opts = WalkerOptions()
        opts.globs = ["*.txt"]
        let paths = try walk([
            "a.txt": "x", "b.md": "y", "c.txt": "z",
        ], options: opts)
        #expect(paths.sorted() == ["a.txt", "c.txt"])

        var negative = WalkerOptions()
        negative.globs = ["!*.md"]
        let p2 = try walk([
            "a.txt": "x", "b.md": "y", "c.txt": "z",
        ], options: negative)
        #expect(!p2.contains("b.md"))
    }

    @Test func typeFilterRestrictsToSwift() throws {
        var opts = WalkerOptions()
        opts.includeTypes = ["swift"]
        let paths = try walk([
            "a.swift": "x", "b.md": "y",
        ], options: opts)
        #expect(paths == ["a.swift"])
    }

    @Test func typeExcludeDropsSwift() throws {
        var opts = WalkerOptions()
        opts.excludeTypes = ["swift"]
        let paths = try walk([
            "a.swift": "x", "b.md": "y",
        ], options: opts)
        #expect(paths == ["b.md"])
    }
}
