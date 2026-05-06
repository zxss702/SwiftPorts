import Foundation

/// A per-task confinement policy that SwiftPorts code consults before
/// touching URLs, environment variables, or process arguments.
///
/// `Sandbox` is the boundary contract embedders install on a task to
/// describe what filesystem regions, network hosts, and process
/// resources are reachable. SwiftPorts code reads `Sandbox.current`
/// (a `@TaskLocal`); when it's `nil`, every existing call works as
/// before. When it's set, every gated I/O site authorizes through
/// `Sandbox.authorize(_:)` and every ambient reach (env, argv, region
/// directories) consults the sandbox's own values.
///
/// Embedders typically don't construct `Sandbox` directly — they call
/// the built-in factories ``rooted(at:allowedHosts:environment:arguments:)``
/// for single-folder confinement on macOS / Linux, or
/// ``appContainer(id:allowedHosts:environment:arguments:)`` for iOS /
/// sandboxed-macOS embedding.
///
/// ### Default-deny posture
///
/// When `Sandbox.current != nil`, the embedder is fully in charge:
/// - The default `environment` closure returns `[:]`. SwiftPorts sees
///   no env. Embedders who want host passthrough write
///   `environment: { ProcessInfo.processInfo.environment }` explicitly.
/// - The default `arguments` closure returns `[]`. Same posture.
/// - Every URL handed to ``authorize(_:)`` must pass the policy or
///   throws ``Denial``.
///
/// When `Sandbox.current == nil`, every static accessor falls back
/// to the equivalent process-global API (`FileManager.default.*`,
/// `ProcessInfo.processInfo.*`, etc.), preserving existing behavior
/// for unsandboxed callers.
///
/// ### Honest scope
///
/// `Sandbox.environment` and ``arguments-swift.type.property`` shadow
/// `ProcessInfo.processInfo` reads **by code convention**, not as a
/// runtime hook. They control what migrated SwiftPorts sources see.
/// Foundation internals, libgit2's own `getenv()` calls, and any
/// third-party Swift dependency still read the real process env.
/// Embedders needing stronger isolation should `unsetenv` sensitive
/// variables at process startup.
///
/// libgit2's internal HTTP / SSH / packfile network and scratch-FS
/// access happens below the Swift boundary and is not gated by v1.
/// `Sandbox` only authorizes URLs handed to libgit2 at the Swift call
/// site (clone source, repo open path, etc.).
public struct Sandbox: Sendable {

    // MARK: - TaskLocal

    /// The active sandbox for the current Task scope, or `nil` if no
    /// confinement is in effect. Set via `Sandbox.$current.withValue(_:)`.
    @TaskLocal public static var current: Sandbox?

    // MARK: - Region URLs (mirror Foundation's URL static-directory surface)

    public let documentsDirectory: URL
    public let downloadsDirectory: URL
    public let libraryDirectory: URL
    public let moviesDirectory: URL
    public let musicDirectory: URL
    public let picturesDirectory: URL
    public let sharedPublicDirectory: URL
    public let temporaryDirectory: URL
    public let trashDirectory: URL
    public let userDirectory: URL

    /// User home directory; defaults to `documentsDirectory` if not
    /// supplied to the initializer.
    public let homeDirectory: URL

    /// User caches directory.
    public let cachesDirectory: URL

    // MARK: - ProcessInfo shadow

    /// Read view of the sandbox's environment. Closure-based so that
    /// an embedder backing the env in mutable storage (e.g. a future
    /// `Shell` class) can return live state on each call without
    /// rebinding the `@TaskLocal`.
    public let environment: @Sendable () -> [String: String]

    /// Read view of the sandbox's program arguments (analogue of
    /// `ProcessInfo.processInfo.arguments` / `CommandLine.arguments`).
    public let arguments: @Sendable () -> [String]

    // MARK: - URL gate

    private let _authorize: @Sendable (URL) async throws -> Void

    /// Authorize a URL against this sandbox's policy. Throws ``Denial``
    /// to deny. Sync-throwing variants are not provided; every gated
    /// SwiftPorts site is async-throws or trivially convertible.
    public func authorize(_ url: URL) async throws {
        try await _authorize(url)
    }

    // MARK: - Init

    /// Construct a sandbox with explicit values for every region and
    /// closure-based ProcessInfo shadow. Most callers should use
    /// ``rooted(at:allowedHosts:environment:arguments:)`` or
    /// ``appContainer(id:allowedHosts:environment:arguments:)`` instead.
    public init(
        documentsDirectory: URL,
        downloadsDirectory: URL,
        libraryDirectory: URL,
        moviesDirectory: URL,
        musicDirectory: URL,
        picturesDirectory: URL,
        sharedPublicDirectory: URL,
        temporaryDirectory: URL,
        trashDirectory: URL,
        userDirectory: URL,
        cachesDirectory: URL,
        homeDirectory: URL? = nil,
        environment: @escaping @Sendable () -> [String: String] = { [:] },
        arguments: @escaping @Sendable () -> [String] = { [] },
        authorize: @escaping @Sendable (URL) async throws -> Void
    ) {
        self.documentsDirectory = documentsDirectory
        self.downloadsDirectory = downloadsDirectory
        self.libraryDirectory = libraryDirectory
        self.moviesDirectory = moviesDirectory
        self.musicDirectory = musicDirectory
        self.picturesDirectory = picturesDirectory
        self.sharedPublicDirectory = sharedPublicDirectory
        self.temporaryDirectory = temporaryDirectory
        self.trashDirectory = trashDirectory
        self.userDirectory = userDirectory
        self.cachesDirectory = cachesDirectory
        self.homeDirectory = homeDirectory ?? documentsDirectory
        self.environment = environment
        self.arguments = arguments
        self._authorize = authorize
    }

    // MARK: - Static ambient accessors
    //
    // These consult `Sandbox.current` and fall back to the equivalent
    // process-global API when no sandbox is set. Migrated SwiftPorts
    // call sites read through these accessors instead of reaching for
    // FileManager.default / ProcessInfo.processInfo directly.

    public static func authorize(_ url: URL) async throws {
        try await current?.authorize(url)
    }

    /// Snapshot of the active sandbox's environment, or
    /// `ProcessInfo.processInfo.environment` if none is active.
    public static var environment: [String: String] {
        current?.environment() ?? ProcessInfo.processInfo.environment
    }

    /// Single-key environment lookup. Faster than reading the whole
    /// `environment` snapshot when the embedder backs the env with
    /// mutable storage.
    public static func env(_ key: String) -> String? {
        if let current { return current.environment()[key] }
        return ProcessInfo.processInfo.environment[key]
    }

    /// Snapshot of the active sandbox's arguments, or
    /// `ProcessInfo.processInfo.arguments` (== `CommandLine.arguments`)
    /// if none is active.
    public static var arguments: [String] {
        current?.arguments() ?? ProcessInfo.processInfo.arguments
    }

    /// Current working directory. Derived from the active sandbox's
    /// environment `PWD` key when a sandbox is set; otherwise reads
    /// the OS CWD directly via
    /// `FileManager.default.currentDirectoryPath`.
    ///
    /// **Why the asymmetry**: `PWD` in the host process env is a
    /// shell convention, not an OS guarantee — an embedder that
    /// calls `chdir(2)` / `FileManager.changeCurrentDirectoryPath(_:)`
    /// without also rewriting `PWD` will leave the variable stale.
    /// Outside a sandbox we want the actual OS CWD so relative-path
    /// resolution stays consistent with what `getcwd(3)` reports.
    /// Inside a sandbox the embedder owns the env semantics — it's
    /// expected to keep `environment()["PWD"]` in sync with whatever
    /// notion of CWD it presents to SwiftPorts code.
    ///
    /// CLI commands resolving relative argv paths should use this
    /// (or `resolve(_:)`) instead of `FileManager.default.currentDirectoryPath`
    /// so embedders can confine path resolution to the sandbox.
    public static var currentDirectory: URL {
        if let current,
           let pwd = current.environment()["PWD"], !pwd.isEmpty {
            return URL(fileURLWithPath: pwd, isDirectory: true)
        }
        return URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true)
    }

    /// Resolve a (possibly relative) path string into an absolute
    /// `URL`. Absolute paths are returned as-is; relative paths
    /// resolve against ``currentDirectory``. Use this instead of
    /// `URL(fileURLWithPath:)` directly for any path that originates
    /// from user input (CLI argv, config files, etc.) so the result
    /// honors the sandbox's PWD rather than the process CWD.
    public static func resolve(_ path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        #if os(Windows)
        if path.count >= 2,
           let second = path.dropFirst().first, second == ":" {
            return URL(fileURLWithPath: path)  // e.g. "C:\..."
        }
        #endif
        return currentDirectory.appendingPathComponent(path)
    }

    public static var homeDirectory: URL {
        if let current { return current.homeDirectory }
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        #else
        return FileManager.default.homeDirectoryForCurrentUser
        #endif
    }

    public static var temporaryDirectory: URL {
        current?.temporaryDirectory ?? FileManager.default.temporaryDirectory
    }

    public static var cachesDirectory: URL {
        if let current { return current.cachesDirectory }
        return FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    public static var documentsDirectory: URL {
        if let current { return current.documentsDirectory }
        return FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Documents", isDirectory: true)
    }

    public static var downloadsDirectory: URL {
        if let current { return current.downloadsDirectory }
        return FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? homeDirectory.appendingPathComponent("Downloads", isDirectory: true)
    }

    public static var libraryDirectory: URL {
        if let current { return current.libraryDirectory }
        return FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? homeDirectory.appendingPathComponent("Library", isDirectory: true)
    }

    public static var moviesDirectory: URL {
        if let current { return current.moviesDirectory }
        return FileManager.default
            .urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? homeDirectory.appendingPathComponent("Movies", isDirectory: true)
    }

    public static var musicDirectory: URL {
        if let current { return current.musicDirectory }
        return FileManager.default
            .urls(for: .musicDirectory, in: .userDomainMask).first
            ?? homeDirectory.appendingPathComponent("Music", isDirectory: true)
    }

    public static var picturesDirectory: URL {
        if let current { return current.picturesDirectory }
        return FileManager.default
            .urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? homeDirectory.appendingPathComponent("Pictures", isDirectory: true)
    }

    public static var sharedPublicDirectory: URL {
        if let current { return current.sharedPublicDirectory }
        return FileManager.default
            .urls(for: .sharedPublicDirectory, in: .userDomainMask).first
            ?? homeDirectory.appendingPathComponent("Public", isDirectory: true)
    }

    public static var trashDirectory: URL {
        if let current { return current.trashDirectory }
        return FileManager.default
            .urls(for: .trashDirectory, in: .userDomainMask).first
            ?? homeDirectory.appendingPathComponent(".Trash", isDirectory: true)
    }

    public static var userDirectory: URL {
        if let current { return current.userDirectory }
        return FileManager.default
            .urls(for: .userDirectory, in: .userDomainMask).first
            ?? homeDirectory
    }

    // MARK: - Denial

    /// Thrown by ``authorize(_:)`` when policy denies a URL.
    ///
    /// `suggestion` is an *implementer-defined hint* and never a
    /// guarantee — re-calling `authorize(suggestion)` is not
    /// guaranteed to succeed. Callers MAY inspect it for diagnostics
    /// or opt-in recovery; SwiftPorts internals never inspect it and
    /// never retry.
    public struct Denial: Error, Sendable {
        public let url: URL
        public let reason: String
        public let suggestion: URL?

        public init(url: URL, reason: String, suggestion: URL? = nil) {
            self.url = url
            self.reason = reason
            self.suggestion = suggestion
        }
    }
}
