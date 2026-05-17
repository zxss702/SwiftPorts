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

            // Bootstrap ignore-file harvest at the root before descending.
            try loadIgnoreFiles(
                at: state.rootURL,
                relativeBase: "",
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
            // Skip the directory's own ignore files from the emitted
            // set — they'd never match by themselves anyway.
            if name == ".git" {
                // Always skip the .git internals — even with
                // --no-ignore-vcs, ripgrep doesn't walk into them.
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
            // ignored path; `.ignore` skips.
            let ignoreDecision = state.ignores.decide(
                pathRelativeToRoot: childRelative,
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
        into ignores: inout IgnoreSet
    ) throws {
        if !options.respectGitignore && !options.respectDotIgnore
            && !options.respectExclude { return }

        if options.respectGitignore {
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
        if options.respectExclude && relativeBase.isEmpty {
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
            baseRelativeToRoot: relativeBase)
        ignores.append(contentsOf: entries)
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
