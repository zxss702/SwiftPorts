import Foundation
import ForgeKit
import GitLab

/// Helpers shared across `glab ci` subcommands.
enum CiSupport {
    /// Resolve a target pipeline IID, falling back to the latest pipeline
    /// for `branch` (or the cwd's current branch) when none is given.
    static func resolvePipelineId(
        explicit: Int?,
        repo: RepositoryReference,
        client: APIClient,
        branch: String?,
        gitClient: any ForgeKit.GitClient
    ) async throws -> Int {
        if let explicit { return explicit }
        let ref = try await pickRef(branch: branch, gitClient: gitClient)
        let pipeline: Pipeline = try await client.get(
            "projects/\(repo.encodedPath)/pipelines/latest",
            query: [URLQueryItem(name: "ref", value: ref)])
        return pipeline.id
    }

    /// Pick the ref to operate against: explicit `--branch` flag wins,
    /// otherwise ask the local git client.
    static func pickRef(
        branch: String?,
        gitClient: any ForgeKit.GitClient
    ) async throws -> String {
        if let branch, !branch.isEmpty { return branch }
        if let cwd = try? await gitClient.currentBranch(), !cwd.isEmpty {
            return cwd
        }
        throw CiSupportError.noBranchAvailable
    }

    /// Resolve a job from `<id-or-name>`. If integer, fetch by ID. If
    /// not, look up the latest pipeline's jobs for the cwd branch and
    /// match by name.
    static func resolveJob(
        argument: String,
        repo: RepositoryReference,
        client: APIClient,
        branch: String?,
        gitClient: any ForgeKit.GitClient
    ) async throws -> Job {
        if let id = Int(argument) {
            return try await client.get(
                "projects/\(repo.encodedPath)/jobs/\(id)")
        }
        let ref = try await pickRef(branch: branch, gitClient: gitClient)
        let latest: Pipeline = try await client.get(
            "projects/\(repo.encodedPath)/pipelines/latest",
            query: [URLQueryItem(name: "ref", value: ref)])
        let jobs: [Job] = try await client.get(
            "projects/\(repo.encodedPath)/pipelines/\(latest.id)/jobs",
            query: [URLQueryItem(name: "per_page", value: "100")])
        guard let match = jobs.first(where: { $0.name == argument }) else {
            throw CiSupportError.jobNotFound(name: argument, pipelineId: latest.id)
        }
        return match
    }

    /// Render an ANSI-coloured 1-letter glyph + text for a status.
    /// Pass `enabled: false` (e.g. from `--color=never`) for plain
    /// text; otherwise mostly routes through `StatusBadge` so the
    /// `success` / `failure` / `in-progress` semantics line up with
    /// the rest of SwiftPorts' tools.
    static func renderStatus(_ status: PipelineStatus, enabled: Bool = true) -> String {
        let label = status.rawValue
        switch status {
        case .success:
            return StatusBadge.success("✓ \(label)", enabled: enabled)
        case .failed:
            return StatusBadge.failure("✗ \(label)", enabled: enabled)
        case .canceled, .canceling, .skipped:
            return StatusBadge.draft("✗ \(label)", enabled: enabled)
        case .running, .pending, .preparing,
             .waitingForResource, .created:
            return enabled ? ANSI.cyan("● \(label)") : "● \(label)"
        case .manual:
            return enabled ? ANSI.magenta("⏸ \(label)") : "⏸ \(label)"
        case .scheduled:
            return enabled ? ANSI.blue("⏰ \(label)") : "⏰ \(label)"
        case .unknown:
            return StatusBadge.muted(label, enabled: enabled)
        }
    }

    static func formatDuration(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        if m > 0 { return "\(m)m\(s)s" }
        return "\(s)s"
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

enum CiSupportError: Error, LocalizedError {
    case noBranchAvailable
    case jobNotFound(name: String, pipelineId: Int)

    var errorDescription: String? {
        switch self {
        case .noBranchAvailable:
            return "No branch given and the current directory is not on a tracked branch. Pass --branch <name>."
        case .jobNotFound(let name, let pipelineId):
            return "No job named \"\(name)\" in pipeline #\(pipelineId)."
        }
    }
}
