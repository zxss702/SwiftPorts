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
        // `.git/HEAD` marks the root as a real repo so the default
        // `requireGit=true` doesn't skip the .gitignore. Same shape
        // ripgrep needs to honor a checked-in gitignore.
        let paths = try walk([
            ".git/HEAD": "ref: refs/heads/main\n",
            ".gitignore": "*.log\n",
            "a.txt": "x",
            "b.log": "y",
        ])
        #expect(paths == ["a.txt"])
    }

    @Test func gitignoreNegation() throws {
        let paths = try walk([
            ".git/HEAD": "ref: refs/heads/main\n",
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
            ".git/HEAD": "ref: refs/heads/main\n",
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

    @Test func parentGitignoreApplies() throws {
        // /repo/.gitignore says *.log; we search /repo/sub. The
        // parent rule must reach down and ignore b.log. `.git/HEAD`
        // marks parent as a real repo so the VCS scope includes it —
        // without it, parent-`.gitignore` would be out-of-repo and
        // correctly skipped (see parentGitignoreStopsAtRepoBoundary).
        let parent = makeTree([
            ".git/HEAD": "ref: refs/heads/main\n",
            ".gitignore": "*.log\n",
            "sub/a.txt": "x",
            "sub/b.log": "y",
        ])
        defer { try? FileManager.default.removeItem(at: parent) }

        let searchRoot = parent.appendingPathComponent("sub")
        var paths: [String] = []
        try Walker(options: WalkerOptions())
            .walk(roots: [Walker.Root(url: searchRoot, display: ".")]) { e in
                paths.append(e.relativePath)
            }
        #expect(paths.sorted() == ["a.txt"])
    }

    @Test func noIgnoreParentDisablesWalkUp() throws {
        let parent = makeTree([
            ".git/HEAD": "ref: refs/heads/main\n",
            ".gitignore": "*.log\n",
            "sub/a.txt": "x",
            "sub/b.log": "y",
        ])
        defer { try? FileManager.default.removeItem(at: parent) }

        var opts = WalkerOptions()
        opts.respectParentIgnore = false
        let searchRoot = parent.appendingPathComponent("sub")
        var paths: [String] = []
        try Walker(options: opts)
            .walk(roots: [Walker.Root(url: searchRoot, display: ".")]) { e in
                paths.append(e.relativePath)
            }
        #expect(paths.sorted() == ["a.txt", "b.log"])
    }

    @Test func parentGitignoreStopsAtRepoBoundary() throws {
        // outer/.gitignore claims *.log, but outer is NOT a git repo.
        // inner IS (has .git/), so when we search inner/sub the
        // walker's VCS scope is inner — outer's gitignore lives in a
        // different (or no) repo and must NOT silently hide keep.log.
        let outer = makeTree([
            ".gitignore": "*.log\n",
            "inner/.git/HEAD": "ref: refs/heads/main\n",
            "inner/sub/keep.log": "x",
            "inner/sub/a.txt": "y",
        ])
        defer { try? FileManager.default.removeItem(at: outer) }

        let searchRoot = outer.appendingPathComponent("inner/sub")
        var paths: [String] = []
        try Walker(options: WalkerOptions())
            .walk(roots: [Walker.Root(url: searchRoot, display: ".")]) { e in
                paths.append(e.relativePath)
            }
        #expect(paths.sorted() == ["a.txt", "keep.log"])
    }

    @Test func parentDotIgnoreCrossesRepoBoundary() throws {
        // .ignore is NOT VCS-scoped — outer's .ignore must apply even
        // when inner is its own repo. Mirrors upstream ripgrep, where
        // only `.gitignore` / `.git/info/exclude` are gated on the
        // repo boundary.
        let outer = makeTree([
            ".ignore": "*.log\n",
            "inner/.git/HEAD": "ref: refs/heads/main\n",
            "inner/sub/drop.log": "x",
            "inner/sub/a.txt": "y",
        ])
        defer { try? FileManager.default.removeItem(at: outer) }

        let searchRoot = outer.appendingPathComponent("inner/sub")
        var paths: [String] = []
        try Walker(options: WalkerOptions())
            .walk(roots: [Walker.Root(url: searchRoot, display: ".")]) { e in
                paths.append(e.relativePath)
            }
        #expect(paths == ["a.txt"])
    }

    @Test func parentAnchoredPatternStaysAnchored() throws {
        // /repo/.gitignore anchors `secret.txt` to /repo. A file with
        // the same name under /repo/sub must NOT be ignored. `.git/`
        // brings parent inside the VCS scope so the rule loads at all.
        let parent = makeTree([
            ".git/HEAD": "ref: refs/heads/main\n",
            ".gitignore": "/secret.txt\n",
            "secret.txt": "top",
            "sub/secret.txt": "nested",
        ])
        defer { try? FileManager.default.removeItem(at: parent) }

        let searchRoot = parent.appendingPathComponent("sub")
        var paths: [String] = []
        try Walker(options: WalkerOptions())
            .walk(roots: [Walker.Root(url: searchRoot, display: ".")]) { e in
                paths.append(e.relativePath)
            }
        #expect(paths == ["secret.txt"])
    }

    @Test func globalIgnoreApplies() throws {
        // Stage a global ignore file pointing at *.log; the walker
        // should pick it up via WalkerOptions.globalIgnoreFile.
        let root = makeTree([
            "a.txt": "x", "b.log": "y",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let globalFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("rg-global-\(UUID().uuidString)")
        try Data("*.log\n".utf8).write(to: globalFile)
        defer { try? FileManager.default.removeItem(at: globalFile) }

        var opts = WalkerOptions()
        opts.globalIgnoreFile = globalFile
        var paths: [String] = []
        try Walker(options: opts)
            .walk(roots: [Walker.Root(url: root, display: ".")]) { e in
                paths.append(e.relativePath)
            }
        #expect(paths == ["a.txt"])
    }

    @Test func noIgnoreGlobalDisablesGlobalFile() throws {
        let root = makeTree([
            "a.txt": "x", "b.log": "y",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let globalFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("rg-global-\(UUID().uuidString)")
        try Data("*.log\n".utf8).write(to: globalFile)
        defer { try? FileManager.default.removeItem(at: globalFile) }

        var opts = WalkerOptions()
        opts.globalIgnoreFile = globalFile
        opts.respectGlobalIgnore = false
        var paths: [String] = []
        try Walker(options: opts)
            .walk(roots: [Walker.Root(url: root, display: ".")]) { e in
                paths.append(e.relativePath)
            }
        #expect(paths.sorted() == ["a.txt", "b.log"])
    }

    @Test func requireGitSkipsRootGitignoreOutsideRepo() throws {
        // A non-repo dir with a stray .gitignore: under the default
        // requireGit=true, that file should NOT filter results — it's
        // a config quirk, not a checked-in repo policy. (Matches
        // ripgrep's `require_git: true` default.)
        let root = makeTree([
            ".gitignore": "*.log\n",
            "a.txt": "x",
            "b.log": "y",
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        var paths: [String] = []
        try Walker(options: WalkerOptions())
            .walk(roots: [Walker.Root(url: root, display: ".")]) { e in
                paths.append(e.relativePath)
            }
        #expect(paths.sorted() == ["a.txt", "b.log"])
    }

    @Test func noRequireGitAppliesParentGitignoreOutsideRepo() throws {
        // Codex caught this: when --no-require-git is set, parent
        // .gitignore should also apply, even without a VCS marker
        // anywhere in the chain. Otherwise files leak into results
        // despite the flag.
        let parent = makeTree([
            ".gitignore": "*.log\n",
            "sub/a.txt": "x",
            "sub/drop.log": "y",
        ])
        defer { try? FileManager.default.removeItem(at: parent) }

        var opts = WalkerOptions()
        opts.requireGit = false
        let searchRoot = parent.appendingPathComponent("sub")
        var paths: [String] = []
        try Walker(options: opts)
            .walk(roots: [Walker.Root(url: searchRoot, display: ".")]) { e in
                paths.append(e.relativePath)
            }
        #expect(paths == ["a.txt"])
    }

    @Test func noRequireGitAppliesRootGitignoreEverywhere() throws {
        // With --no-require-git, the stray .gitignore is honored even
        // outside a repo. Mirrors upstream's `--no-require-git`.
        let root = makeTree([
            ".gitignore": "*.log\n",
            "a.txt": "x",
            "b.log": "y",
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        var opts = WalkerOptions()
        opts.requireGit = false
        var paths: [String] = []
        try Walker(options: opts)
            .walk(roots: [Walker.Root(url: root, display: ".")]) { e in
                paths.append(e.relativePath)
            }
        #expect(paths == ["a.txt"])
    }

    @Test func dotIgnoreAppliesEvenOutsideRepo() throws {
        // .ignore is not VCS-scoped, so requireGit shouldn't affect it.
        let root = makeTree([
            ".ignore": "*.log\n",
            "a.txt": "x",
            "b.log": "y",
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        var paths: [String] = []
        try Walker(options: WalkerOptions())
            .walk(roots: [Walker.Root(url: root, display: ".")]) { e in
                paths.append(e.relativePath)
            }
        #expect(paths == ["a.txt"])
    }

    @Test func worktreeGitFileCountsAsRepoMarker() throws {
        // `git worktree add` creates `.git` as a *file* with
        // `gitdir: /path/to/real`. Upstream rg treats that as a valid
        // repo marker; the root's .gitignore must apply.
        let root = makeTree([
            ".git": "gitdir: /elsewhere/.git/worktrees/feature\n",
            ".gitignore": "*.log\n",
            "a.txt": "x",
            "b.log": "y",
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        var paths: [String] = []
        try Walker(options: WalkerOptions())
            .walk(roots: [Walker.Root(url: root, display: ".")]) { e in
                paths.append(e.relativePath)
            }
        #expect(paths == ["a.txt"])
    }

    @Test func jjMarkerCountsAsRepoMarker() throws {
        // Jujutsu marks a repo root with `.jj/` instead of `.git/`.
        // Treat it the same way — `.gitignore` at the root applies.
        let root = makeTree([
            ".jj/repo/store/type": "git\n",
            ".gitignore": "*.log\n",
            "a.txt": "x",
            "b.log": "y",
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        var paths: [String] = []
        try Walker(options: WalkerOptions())
            .walk(roots: [Walker.Root(url: root, display: ".")]) { e in
                paths.append(e.relativePath)
            }
        #expect(paths == ["a.txt"])
    }

    @Test func ignoreCaseInsensitiveMatchesMixedCase() throws {
        // `ignoreCaseInsensitive` applies to gitignore-style matching.
        // With it on, `*.LOG` in .gitignore matches `bug.log`.
        let root = makeTree([
            ".git/HEAD": "ref: refs/heads/main\n",
            ".gitignore": "*.LOG\n",
            "a.txt": "x",
            "bug.log": "y",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        var opts = WalkerOptions()
        opts.ignoreCaseInsensitive = true
        var paths: [String] = []
        try Walker(options: opts)
            .walk(roots: [Walker.Root(url: root, display: ".")]) { e in
                paths.append(e.relativePath)
            }
        #expect(paths == ["a.txt"])
    }

    @Test func jjDirectoryIsNotDescendedInto() throws {
        // We should never recurse into `.jj/` — its contents are VCS
        // internals, not user files. (Same treatment as `.git/`.)
        let root = makeTree([
            ".jj/repo/store/type": "git\n",
            ".jj/working_copy/data": "secrets",
            "a.txt": "x",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        var opts = WalkerOptions()
        opts.hidden = true   // even with hidden enabled, .jj is skipped
        var paths: [String] = []
        try Walker(options: opts)
            .walk(roots: [Walker.Root(url: root, display: ".")]) { e in
                paths.append(e.relativePath)
            }
        #expect(paths == ["a.txt"])
    }
}
