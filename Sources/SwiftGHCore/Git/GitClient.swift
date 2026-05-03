import Foundation

/// Read + write access to the surrounding git repository.
///
/// Default impl `ProcessGitClient` shells out to `git` via `Process`,
/// which gives us the user's actual ssh-agent, credential helper,
/// commit-signing config, and hooks for free. iOS / sandboxed
/// embedders inject `NoGitClient` and the git-aware commands fail
/// fast with a clear message.
///
/// Read methods (`remoteURL`, `currentBranch`) return `nil` when the
/// info isn't available (not in a repo, missing remote, detached HEAD).
/// Write methods throw — they're called from contexts where success
/// is required.
public protocol GitClient: Sendable {
    // MARK: Read
    func remoteURL(named: String) async throws -> URL?
    func currentBranch() async throws -> String?
    func upstreamBranch(of localBranch: String) async throws -> String?

    // MARK: Write
    func clone(url: URL, directory: URL?) async throws
    func fetch(remote: String, refspec: String) async throws
    func checkout(ref: String) async throws
    func push(remote: String, refspec: String, setUpstream: Bool) async throws
    func addRemote(name: String, url: URL) async throws
}

extension GitClient {
    /// Convenience: parse `remoteURL(named:)` into a
    /// `RepositoryReference`. Returns `nil` if the remote doesn't
    /// resolve to a `host:owner/name`-style URL.
    public func currentRepository(remote: String = "origin") async throws -> RepositoryReference? {
        guard let url = try await remoteURL(named: remote) else { return nil }
        return RepositoryReference(parsingRemoteURL: url)
    }
}

/// Errors thrown by ``GitClient`` write paths.
public enum GitClientError: Error, LocalizedError, Sendable {
    /// Git isn't available in this environment (sandboxed iOS,
    /// embedder injected `NoGitClient`, etc.).
    case gitUnavailable
    /// The `git` invocation exited non-zero. Carries stderr so the
    /// caller can surface the underlying error to the user.
    case gitFailed(args: [String], exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .gitUnavailable:
            return "This command requires the git binary, which isn't available in this environment."
        case .gitFailed(let args, let code, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "git \(args.joined(separator: " ")) failed (exit \(code))" +
                (trimmed.isEmpty ? "" : ": \(trimmed)")
        }
    }
}
