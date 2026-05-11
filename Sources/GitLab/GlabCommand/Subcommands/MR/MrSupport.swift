import Foundation
import ForgeKit
import GitLab

/// Helpers shared across `glab mr` subcommands.
enum MrSupport {
    /// Resolve `(target, iid)` from either an explicit MR argument or the
    /// repo-resolution + iid fallback chain.
    static func resolveTarget(
        argument: String,
        explicitRepo: RepositoryReference?
    ) async throws -> (RepositoryReference, Int) {
        let parsed = try MrArgument.parse(argument)
        let target: RepositoryReference
        if let fromURL = parsed.repoFromURL {
            target = fromURL
        } else {
            target = try await CommandContext.resolveRepo(flag: explicitRepo)
        }
        return (target, parsed.iid)
    }

    /// Look up a single user's numeric ID by username.
    static func userIdLookup(client: APIClient, username: String) async throws -> Int {
        let users: [User] = try await client.get(
            "users", query: [URLQueryItem(name: "username", value: username)])
        guard let id = users.first?.id else {
            throw MrSupportError.userNotFound(username)
        }
        return id
    }

    /// Render an MR state as a colored badge. Pass `enabled: false`
    /// (typically from `--color=never` / `NO_COLOR`) for plain text.
    static func renderState(_ state: MergeRequestState, enabled: Bool = true) -> String {
        switch state {
        case .opened:        return StatusBadge.open("opened",   enabled: enabled)
        case .merged:        return StatusBadge.merged(enabled: enabled)
        case .closed:        return StatusBadge.closed(enabled: enabled)
        case .locked:        return StatusBadge.draft("locked",  enabled: enabled)
        case .unknown(let s): return StatusBadge.muted(s, enabled: enabled)
        }
    }

    static func ageInWords(from date: Date?) -> String {
        guard let date else { return "—" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "\(Int(interval))s ago" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}

enum MrSupportError: Error, LocalizedError {
    case userNotFound(String)
    var errorDescription: String? {
        switch self {
        case .userNotFound(let u): return "No user found with username \"\(u)\"."
        }
    }
}
