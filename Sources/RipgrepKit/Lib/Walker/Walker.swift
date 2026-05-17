import Foundation

/// Recursive directory walker that produces the candidate file paths
/// `Searcher` will scan.
///
/// The walker is iterator-shaped (a `walk(roots:emit:)` closure-based
/// API) so the caller can stream files into the search pipeline
/// without materialising the whole list. Ignore rules are loaded
/// lazily — each entered directory checks for its own
/// `.gitignore` / `.ignore` / `.rgignore` and pushes the parsed
/// entries onto the live stack.
public struct Walker: Sendable {

    public var options: WalkerOptions

    public init(options: WalkerOptions = WalkerOptions()) {
        self.options = options
    }

    /// Result entry yielded for each candidate path.
    public struct Entry: Sendable {
        public let url: URL
        /// Path relative to the search root (forward slashes).
        public let relativePath: String
        /// Display path, the form that should appear in output. Usually
        /// the joined `<rootDisplay>/<relative>` so the user sees the
        /// same shape they typed.
        public let displayPath: String
        public let isDirectory: Bool

        public init(url: URL,
                    relativePath: String,
                    displayPath: String,
                    isDirectory: Bool) {
            self.url = url
            self.relativePath = relativePath
            self.displayPath = displayPath
            self.isDirectory = isDirectory
        }
    }

    /// A walker root pairs the resolved on-disk URL with the *display*
    /// form (typically the literal string the user typed). Display
    /// strings drive printer output so search results show paths in
    /// the same shape the user supplied.
    public struct Root: Sendable {
        public let url: URL
        public let display: String

        public init(url: URL, display: String) {
            self.url = url
            self.display = display
        }
    }

    /// Walk one or more search roots, invoking `emit` for each file
    /// that survives every filter. Directories are not emitted; the
    /// walker descends into them silently.
    ///
    /// Returns the number of files emitted. The closure may throw
    /// `CancellationError` to short-circuit (we propagate it).
    @discardableResult
    public func walk(
        roots: [Root],
        emit: (Entry) throws -> Void
    ) throws -> Int {
        var emitted = 0
        // Global ignore is read once and seeded into every root's
        // stack — it doesn't change between roots and re-reading would
        // be wasteful. We treat global patterns as if loaded at the
        // walker root (no absolute base) so they apply universally
        // with normal gitignore semantics.
        var globalEntries: [IgnoreSet.Entry] = []
        if options.respectGlobalIgnore && options.respectGitignore {
            globalEntries = loadGlobalIgnoreEntries()
        }
        for root in roots {
            let isDir = (try? root.url.resourceValues(forKeys: [.isDirectoryKey]))?
                .isDirectory ?? false
            // A root that's a single file just goes straight through.
            if !isDir {
                let entry = Entry(url: root.url,
                                  relativePath: root.url.lastPathComponent,
                                  displayPath: root.display,
                                  isDirectory: false)
                try emit(entry)
                emitted += 1
                continue
            }

            var state = WalkState()
            state.rootURL = root.url.standardizedFileURL
            state.rootDisplay = root.display

            // Determine whether this root is inside a git/jj repo (an
            // ancestor or the root itself has `.git`/`.jj`). Used to
            // gate VCS ignore loading under `requireGit` — even when
            // parent walking is off, we still need this answer.
            state.insideVcsRepo = isInsideVcsRepo(rootPath: state.rootURL
                .standardizedFileURL.path)

            // Seed the stack with global ignore (applies under every
            // directory) and parent-directory ignore files (loaded
            // shallowest-first so deeper rules override shallower ones
            // — mirrors ripgrep's add_parents).
            state.ignores.append(contentsOf: globalEntries)
            if options.respectParentIgnore {
                try loadParentIgnoreFiles(
                    rootURL: state.rootURL,
                    into: &state.ignores)
            }

            // Bootstrap ignore-file harvest at the root before descending.
            try loadIgnoreFiles(
                at: state.rootURL,
                relativeBase: "",
                insideVcsRepo: state.insideVcsRepo,
                into: &state.ignores)
            for extra in options.extraIgnoreFiles {
                try loadIgnoreFile(at: extra,
                                   relativeBase: "",
                                   into: &state.ignores)
            }

            try descend(
                directory: state.rootURL,
                relative: "",
                depth: 0,
                state: &state,
                emit: { entry in
                    try emit(entry)
                    emitted += 1
                })
        }
        return emitted
    }

    /// Convenience shim for callers that haven't switched to the
    /// `Root` API. The display path matches `url.path` for each URL.
    @discardableResult
    public func walk(
        roots: [URL],
        emit: (Entry) throws -> Void
    ) throws -> Int {
        try walk(roots: roots.map { Root(url: $0, display: $0.path) },
                 emit: emit)
    }

    // MARK: - Internal

    /// Per-root mutable state.
    private struct WalkState {
        var rootURL: URL = URL(fileURLWithPath: ".")
        var rootDisplay: String = "."
        var ignores: IgnoreSet = IgnoreSet()
        var rootDeviceID: UInt64? = nil
        /// True when the search root sits inside a git/jj repository
        /// (an ancestor or the root itself carries `.git` or `.jj`).
        /// When `WalkerOptions.requireGit` is true, `.gitignore` and
        /// `.git/info/exclude` loading is gated on this.
        var insideVcsRepo: Bool = false
    }

    private func descend(
        directory: URL,
        relative: String,
        depth: Int,
        state: inout WalkState,
        emit: (Entry) throws -> Void
    ) throws {
        try Task.checkCancellation()

        // Per real ripgrep: `--max-depth=N` limits the depth of
        // *descent* from each starting path. The starting directory
        // itself is depth 0. Its immediate children are depth 1.
        // We check `depth + 1 > max` here so we skip iterating children
        // when we've hit the limit; the children-emit/descend logic
        // below uses `depth + 1` as the child depth.
        if let max = options.maxDepth, depth + 1 > max { return }

        // Snapshot the parent ignore set so popping is a re-assignment
        // rather than an array trim.
        let parentIgnoreCount = state.ignores.entries.count
        defer { state.ignores.truncate(to: parentIgnoreCount) }

        // Harvest this directory's own ignore files before reading its
        // children — patterns defined here apply to siblings inside it.
        try loadIgnoreFiles(
            at: directory,
            relativeBase: relative,
            insideVcsRepo: state.insideVcsRepo,
            into: &state.ignores)

        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .volumeIdentifierKey,
            .isRegularFileKey,
        ]
        let opts: FileManager.DirectoryEnumerationOptions = []

        let children: [URL]
        do {
            children = try fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: keys,
                options: opts)
        } catch {
            // Permission denied / I/O error — skip the directory
            // silently. Real ripgrep emits a warning on stderr; we
            // mirror that at the engine level, not here.
            return
        }

        // Sort for stable test output.
        let sorted = children.sorted { $0.lastPathComponent < $1.lastPathComponent }

        for child in sorted {
            try Task.checkCancellation()

            let name = child.lastPathComponent
            // Always skip the VCS metadata dirs — even with
            // --no-ignore-vcs, ripgrep doesn't walk into them.
            if name == ".git" || name == ".jj" {
                continue
            }

            let resourceValues = try? child.resourceValues(forKeys: Set(keys))
            let isDir = resourceValues?.isDirectory ?? false
            let isSymlink = resourceValues?.isSymbolicLink ?? false

            // Hidden file gate.
            if !options.hidden, name.hasPrefix(".") {
                continue
            }

            let childRelative = relative.isEmpty ? name : "\(relative)/\(name)"

            // Symlink behaviour: by default we skip them entirely
            // (matching real rg's default), unless --follow.
            if isSymlink && !options.followLinks {
                continue
            }

            // Build the display path the user sees. We try to match
            // real rg's shape: a root of `.` is dropped (so output is
            // `a.txt`, not `./a.txt`); other roots prefix the relative
            // component with the right separator.
            let displayPath: String = {
                if state.rootDisplay == "." || state.rootDisplay.isEmpty {
                    return childRelative
                }
                if state.rootDisplay.hasSuffix("/") {
                    return state.rootDisplay + childRelative
                }
                return state.rootDisplay + "/" + childRelative
            }()

            // Ignore-set decision. `.allow` un-ignores a previously
            // ignored path; `.ignore` skips. Pass the absolute path
            // too so parent-directory entries (which strip an absolute
            // prefix) can match.
            let ignoreDecision = state.ignores.decide(
                pathRelativeToRoot: childRelative,
                pathAbsolute: child.standardizedFileURL.path,
                isDirectory: isDir)
            if ignoreDecision == .ignore {
                continue
            }

            if isDir {
                // one-file-system check.
                if options.oneFileSystem {
                    let childDev = (resourceValues?.volumeIdentifier
                                    as? NSNumber)?.uint64Value
                    if state.rootDeviceID == nil {
                        state.rootDeviceID = childDev
                    } else if let rootDev = state.rootDeviceID,
                              let childDev,
                              rootDev != childDev {
                        continue
                    }
                }
                try descend(directory: child,
                            relative: childRelative,
                            depth: depth + 1,
                            state: &state,
                            emit: emit)
                continue
            }

            // File. Apply file-level filters.
            if let max = options.maxFilesize,
               let size = resourceValues?.fileSize, size > max {
                continue
            }

            if !passesGlobFilters(relativePath: childRelative) {
                continue
            }
            if !passesTypeFilters(name: name, relativePath: childRelative) {
                continue
            }

            try emit(Entry(url: child,
                           relativePath: childRelative,
                           displayPath: displayPath,
                           isDirectory: false))
        }
    }

    // MARK: - Ignore loading

    private func loadIgnoreFiles(
        at directory: URL,
        relativeBase: String,
        insideVcsRepo: Bool,
        into ignores: inout IgnoreSet
    ) throws {
        if !options.respectGitignore && !options.respectDotIgnore
            && !options.respectExclude { return }

        // Under `requireGit`, VCS ignore handling is gated on actually
        // being inside a git/jj repo — without that, a stray
        // `.gitignore` in a non-repo directory must not filter results.
        let vcsActive = !options.requireGit || insideVcsRepo

        if options.respectGitignore && vcsActive {
            try loadIgnoreFile(
                at: directory.appendingPathComponent(".gitignore"),
                relativeBase: relativeBase,
                into: &ignores)
        }
        if options.respectDotIgnore {
            try loadIgnoreFile(
                at: directory.appendingPathComponent(".ignore"),
                relativeBase: relativeBase,
                into: &ignores)
            try loadIgnoreFile(
                at: directory.appendingPathComponent(".rgignore"),
                relativeBase: relativeBase,
                into: &ignores)
        }
        if options.respectExclude && vcsActive && relativeBase.isEmpty {
            // .git/info/exclude lives at the repo root.
            let exclude = directory
                .appendingPathComponent(".git/info/exclude")
            try loadIgnoreFile(
                at: exclude,
                relativeBase: "",
                into: &ignores)
        }
    }

    private func loadIgnoreFile(
        at fileURL: URL,
        relativeBase: String,
        into ignores: inout IgnoreSet
    ) throws {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let text = String(decoding: data, as: UTF8.self)
        let entries = IgnoreSet.parse(
            contents: text,
            baseRelativeToRoot: relativeBase,
            caseInsensitive: options.ignoreCaseInsensitive)
        ignores.append(contentsOf: entries)
    }

    /// Walk from `rootURL`'s parent up to the filesystem root,
    /// loading `.gitignore` / `.ignore` / `.rgignore` (and
    /// `.git/info/exclude`) from each ancestor.
    ///
    /// VCS ignores (`.gitignore`, `.git/info/exclude`) are scoped to
    /// the *current* repository — they only load from ancestors at or
    /// below the deepest ancestor containing `.git`. Otherwise an
    /// unrelated `~/.gitignore` could silently hide matches when
    /// searching a nested repo. `.ignore` / `.rgignore` aren't
    /// VCS-bound and load from every ancestor.
    ///
    /// Parent entries match against the candidate's absolute path, so
    /// anchored patterns (`/build`) keep their meaning relative to
    /// the ancestor they came from — not the walker root.
    ///
    /// Loaded shallowest-first so deeper ancestors override shallower
    /// ones — matches `gitignore(5)` precedence.
    private func loadParentIgnoreFiles(
        rootURL: URL,
        into ignores: inout IgnoreSet
    ) throws {
        if !options.respectGitignore && !options.respectDotIgnore
            && !options.respectExclude { return }

        // Work on the path string directly. `URL.deletingLastPathComponent`
        // round-trips through `_CFURLCreateWithURLString` each call and
        // accumulates `..` segments on directory URLs (created with
        // `isDirectory: true`), so a parent walk via URL becomes
        // pathologically slow — observed as a hang under the test
        // runner. Stay in path-string land where the operation is O(1).
        let rootPath = rootURL.standardizedFileURL.path
        var parents: [String] = []
        var current = rootPath
        while true {
            guard let slash = current.lastIndex(of: "/") else { break }
            let next = slash == current.startIndex
                ? "/"
                : String(current[..<slash])
            if next == current { break }
            parents.append(next)
            if next == "/" { break }
            current = next
        }

        // Shallow → deep so deeper rules override shallower (gitignore
        // precedence).
        let ordered = Array(parents.reversed())

        // VCS boundary: the deepest ancestor (closest to the search
        // root) carrying a VCS marker (`.git` dir/file or `.jj` dir).
        // If the search root itself carries one, that's its own repo
        // and no parent contributes VCS ignore. If nothing in the
        // chain has a marker, there's no boundary and VCS ignores
        // don't apply to any parent.
        let vcsBoundaryIndex: Int? = {
            guard options.respectGitignore || options.respectExclude
            else { return nil }
            if containsVcsMarker(at: rootPath) { return nil }
            for i in stride(from: ordered.count - 1, through: 0, by: -1)
            where containsVcsMarker(at: ordered[i]) {
                return i
            }
            return nil
        }()

        for (i, parent) in ordered.enumerated() {
            let prefix = parent == "/" ? "/" : parent + "/"
            let withinRepo = vcsBoundaryIndex.map { i >= $0 } ?? false
            // With `--no-require-git`, parent `.gitignore` applies
            // universally — same loosening upstream's `require_git=false`
            // does. With `requireGit=true` (default) it stays scoped
            // to the current repo.
            let applyParentGitignore = !options.requireGit || withinRepo

            if options.respectGitignore && applyParentGitignore {
                loadParentIgnoreFile(
                    at: URL(fileURLWithPath: prefix + ".gitignore"),
                    baseAbsolute: parent,
                    into: &ignores)
            }
            if options.respectDotIgnore {
                loadParentIgnoreFile(
                    at: URL(fileURLWithPath: prefix + ".ignore"),
                    baseAbsolute: parent,
                    into: &ignores)
                loadParentIgnoreFile(
                    at: URL(fileURLWithPath: prefix + ".rgignore"),
                    baseAbsolute: parent,
                    into: &ignores)
            }
            // `.git/info/exclude` lives once per repo — at the VCS
            // boundary itself, not at every ancestor below it. Even
            // under `--no-require-git`, the file only exists if `.git`
            // is actually present, so the boundary check stands.
            if options.respectExclude && i == vcsBoundaryIndex {
                loadParentIgnoreFile(
                    at: URL(fileURLWithPath: prefix + ".git/info/exclude"),
                    baseAbsolute: parent,
                    into: &ignores)
            }
        }
    }

    /// True when `path` itself looks like a VCS repository root: it
    /// contains `.git` (as a directory or a worktree-style file with
    /// `gitdir:` content) or a `.jj` directory.
    ///
    /// Worktrees: `git worktree add` writes a `.git` *file* containing
    /// `gitdir: /path/to/real/.git`. Upstream ripgrep accepts that as
    /// a valid repo marker — so do we.
    private func containsVcsMarker(at path: String) -> Bool {
        let prefix = path == "/" ? "/" : path + "/"
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: prefix + ".git", isDirectory: &isDir) {
            return true
        }
        if fm.fileExists(atPath: prefix + ".jj", isDirectory: &isDir),
           isDir.boolValue {
            return true
        }
        return false
    }

    /// True when `rootPath` or any of its ancestors carries a VCS
    /// marker. Walked path-string-style for the same reason
    /// `loadParentIgnoreFiles` does — `URL.deletingLastPathComponent`
    /// is pathological on directory URLs.
    private func isInsideVcsRepo(rootPath: String) -> Bool {
        if containsVcsMarker(at: rootPath) { return true }
        var current = rootPath
        while true {
            guard let slash = current.lastIndex(of: "/") else { break }
            let next = slash == current.startIndex
                ? "/"
                : String(current[..<slash])
            if next == current { break }
            if containsVcsMarker(at: next) { return true }
            if next == "/" { break }
            current = next
        }
        return false
    }

    private func loadParentIgnoreFile(
        at fileURL: URL,
        baseAbsolute: String,
        into ignores: inout IgnoreSet
    ) {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let text = String(decoding: data, as: UTF8.self)
        let entries = IgnoreSet.parse(
            contents: text,
            baseRelativeToRoot: "",
            baseAbsolute: baseAbsolute,
            caseInsensitive: options.ignoreCaseInsensitive)
        ignores.append(contentsOf: entries)
    }

    /// Read the user's global gitignore. Lookup order:
    ///   1. `WalkerOptions.globalIgnoreFile` (explicit override).
    ///   2. `core.excludesfile` in `$HOME/.gitconfig` or
    ///      `$XDG_CONFIG_HOME/git/config` (whichever exists; values
    ///      in the former take precedence per `git-config(1)`).
    ///   3. `$XDG_CONFIG_HOME/git/ignore`, defaulting to
    ///      `$HOME/.config/git/ignore`.
    ///
    /// Returned entries have an empty `baseRelativeToRoot` and no
    /// absolute base, so they behave like an unanchored gitignore
    /// loaded at every walker root — the standard semantics for a
    /// "global" file.
    func loadGlobalIgnoreEntries() -> [IgnoreSet.Entry] {
        let url: URL? = {
            if let explicit = options.globalIgnoreFile { return explicit }
            if let configured = globalIgnoreFromGitConfig() { return configured }
            return defaultGlobalIgnoreFile()
        }()
        guard let url else { return [] }
        guard let data = try? Data(contentsOf: url) else { return [] }
        let text = String(decoding: data, as: UTF8.self)
        return IgnoreSet.parse(
            contents: text,
            baseRelativeToRoot: "",
            caseInsensitive: options.ignoreCaseInsensitive)
    }

    /// Search `~/.gitconfig` then `$XDG_CONFIG_HOME/git/config` for a
    /// `core.excludesfile` value. The lookup is intentionally
    /// lightweight — git's full INI parser isn't worth reimplementing
    /// here, and the directive's grammar is well constrained.
    private func globalIgnoreFromGitConfig() -> URL? {
        let env = ProcessInfo.processInfo.environment
        let home = env["HOME"].flatMap { $0.isEmpty ? nil : $0 }
        var candidates: [URL] = []
        if let home {
            candidates.append(URL(fileURLWithPath: home)
                .appendingPathComponent(".gitconfig"))
        }
        let xdg = env["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? home.map { $0 + "/.config" }
        if let xdg {
            candidates.append(URL(fileURLWithPath: xdg)
                .appendingPathComponent("git/config"))
        }
        for cfg in candidates {
            guard let data = try? Data(contentsOf: cfg) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            if let path = parseCoreExcludesFile(text), !path.isEmpty {
                return URL(fileURLWithPath: expandTilde(path, home: home))
            }
        }
        return nil
    }

    /// Default global ignore path when `core.excludesfile` is unset:
    /// `$XDG_CONFIG_HOME/git/ignore` or `$HOME/.config/git/ignore`.
    private func defaultGlobalIgnoreFile() -> URL? {
        let env = ProcessInfo.processInfo.environment
        let home = env["HOME"].flatMap { $0.isEmpty ? nil : $0 }
        let xdg = env["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? home.map { $0 + "/.config" }
        guard let xdg else { return nil }
        return URL(fileURLWithPath: xdg)
            .appendingPathComponent("git/ignore")
    }

    /// Return the value of `core.excludesfile` (case-insensitive) from
    /// a git-config-format INI file. Comments (`#` / `;`) and
    /// surrounding whitespace / quotes are stripped.
    private func parseCoreExcludesFile(_ contents: String) -> String? {
        var inCore = false
        for rawLine in contents.split(separator: "\n",
                                      omittingEmptySubsequences: false) {
            var line = String(rawLine)
            // Drop comments.
            if let hash = line.firstIndex(where: { $0 == "#" || $0 == ";" }) {
                line = String(line[..<hash])
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let header = trimmed.dropFirst().dropLast()
                    .trimmingCharacters(in: .whitespaces)
                inCore = header.lowercased() == "core"
                continue
            }
            guard inCore, let eq = trimmed.firstIndex(of: "=") else {
                continue
            }
            let key = trimmed[..<eq]
                .trimmingCharacters(in: .whitespaces).lowercased()
            guard key == "excludesfile" else { continue }
            var value = trimmed[trimmed.index(after: eq)...]
                .trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            return String(value)
        }
        return nil
    }

    private func expandTilde(_ path: String, home: String?) -> String {
        guard path.hasPrefix("~"), let home, !home.isEmpty else { return path }
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + String(path.dropFirst(1)) }
        return path
    }

    // MARK: - Filter helpers

    /// Apply user-supplied `-g`/`--iglob` patterns. A path is included
    /// if it matches any positive include glob (or none are set) and
    /// is not excluded by a negation glob.
    func passesGlobFilters(relativePath: String) -> Bool {
        if options.globs.isEmpty { return true }
        var hasInclude = false
        var includeMatched = false
        var excludeMatched = false
        for raw in options.globs {
            var p = raw
            var negate = false
            if p.hasPrefix("!") {
                negate = true
                p.removeFirst()
            }
            if !negate { hasInclude = true }
            guard let glob = try? GitignoreGlob(
                pattern: p,
                caseInsensitive: options.globsCaseInsensitive)
            else { continue }
            if glob.matches(relativePath, isDirectory: false) {
                if negate {
                    excludeMatched = true
                } else {
                    includeMatched = true
                }
            }
        }
        if excludeMatched { return false }
        if hasInclude && !includeMatched { return false }
        return true
    }

    /// Apply `-t` / `-T` filters.
    func passesTypeFilters(name: String, relativePath: String) -> Bool {
        if !options.includeTypes.isEmpty {
            var any = false
            for type in options.includeTypes {
                if matchesTypeGlobs(type: type, name: name) { any = true; break }
            }
            if !any { return false }
        }
        for type in options.excludeTypes {
            if matchesTypeGlobs(type: type, name: name) { return false }
        }
        return true
    }

    private func matchesTypeGlobs(type: String, name: String) -> Bool {
        guard let globs = options.typeRegistry.globs(forType: type) else {
            return false
        }
        for g in globs {
            // File-type globs are bash-style (operate on the basename),
            // not gitignore-style. We compile each through our
            // GitignoreGlob with anchored disabled so they match
            // against the basename.
            if let glob = try? GitignoreGlob(pattern: g),
               glob.matches(name, isDirectory: false) {
                return true
            }
        }
        return false
    }
}
