import Foundation

/// Options that shape `Walker`'s traversal.
public struct WalkerOptions: Sendable {

    /// Include or exclude file paths. `-g <pattern>` for include,
    /// `-g '!<pattern>'` for exclude. Matched against the path
    /// relative to the search root.
    public var globs: [String] = []

    /// Treat `globs` as case-insensitive.
    public var globsCaseInsensitive: Bool = false

    /// Only include files whose name matches at least one of these
    /// types' globs. `-t TYPE` adds one to this list.
    public var includeTypes: [String] = []

    /// Skip files whose name matches any of these types' globs.
    /// `-T TYPE` adds one to this list.
    public var excludeTypes: [String] = []

    /// Registry resolving type names to globs. Defaults to the
    /// upstream ripgrep table.
    public var typeRegistry: TypeRegistry = .default

    /// Include hidden files (paths beginning with `.`). Real ripgrep
    /// hides them by default.
    public var hidden: Bool = false

    /// Follow symlinks (`-L`).
    public var followLinks: Bool = false

    /// Skip files larger than this (`--max-filesize`). `nil` = unlimited.
    public var maxFilesize: Int? = nil

    /// Stop descending after this many directory levels
    /// (`--max-depth`). `nil` = unlimited. The walker root counts as
    /// depth 0.
    public var maxDepth: Int? = nil

    /// Respect `.gitignore` (default true). Disabled by
    /// `--no-ignore-vcs` and `--no-ignore`.
    public var respectGitignore: Bool = true

    /// Respect `.ignore` / `.rgignore` files (default true). Disabled
    /// by `--no-ignore-dot` and `--no-ignore`.
    public var respectDotIgnore: Bool = true

    /// Respect `.git/info/exclude` and the global git excludes file.
    /// Disabled by `--no-ignore-exclude`.
    public var respectExclude: Bool = true

    /// Additional ignore files to load at the root (`--ignore-file`).
    public var extraIgnoreFiles: [URL] = []

    /// Skip directories that lie on a different filesystem
    /// (`--one-file-system`).
    public var oneFileSystem: Bool = false

    /// Treat any path passed explicitly on the command line as a
    /// "must search" override that bypasses gitignore. Mirrors
    /// upstream's behaviour. Always true.
    public var explicitPathsOverrideFilters: Bool = true

    public init() {}
}
