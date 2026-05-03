import ArgumentParser
import Foundation
import HTTPTypes
import SwiftGHCore

struct RunView: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "view",
        abstract: "View a workflow run.",
        discussion: """
        Default output: run-level summary.

        --jobs           Lists each job in the run with its status / conclusion.
        --job ID         Drills into a single job, listing each step.
        --log            Streams the run's full logs (downloads, unzips, prints).
        --log-failed     Like --log but only the failed jobs' logs.
        --exit-status    Exit non-zero if the run's conclusion isn't 'success'.
                         Useful in scripts: `gh run view ID --exit-status && deploy`.
        """
    )

    @Option(name: [.short, .long],
            help: "Repository as OWNER/REPO. Defaults to the current directory's git remote.")
    var repo: RepositoryReference?

    @Argument(help: "Run ID.")
    var id: Int

    @Flag(name: .long, help: "Print the JSON response body.")
    var json: Bool = false

    @Flag(name: .long, help: "List each job in the run.")
    var jobs: Bool = false

    @Option(name: .customLong("job"),
            help: "Drill into a single job by ID; lists its steps.")
    var jobId: Int?

    @Flag(name: .long, help: "Print all job logs to stdout.")
    var log: Bool = false

    @Flag(name: .customLong("log-failed"),
          help: "Print only the failed jobs' logs.")
    var logFailed: Bool = false

    @Flag(name: .customLong("exit-status"),
          help: "Exit non-zero if conclusion != 'success'.")
    var exitStatus: Bool = false

    func run() async throws {
        let target = try await RepositoryResolver.resolve(flag: repo)
        let client = try await CommandContext.apiClient()

        if let jobId {
            let job: WorkflowJob = try await client.get(
                "repos/\(target.slug)/actions/jobs/\(jobId)")
            if json {
                print(try CodableOutput.prettyJSON(job))
                return
            }
            renderJob(job)
            return
        }

        let run: WorkflowRun = try await client.get(
            "repos/\(target.slug)/actions/runs/\(id)")

        if log || logFailed {
            try await downloadAndPrintLogs(
                client: client, slug: target.slug, runId: id, failedOnly: logFailed)
            if exitStatus {
                try enforceExit(run.conclusion)
            }
            return
        }

        if json {
            print(try CodableOutput.prettyJSON(run))
            if exitStatus { try enforceExit(run.conclusion) }
            return
        }

        renderRunSummary(run)

        if jobs {
            let envelope: WorkflowJobList = try await client.get(
                "repos/\(target.slug)/actions/runs/\(id)/jobs")
            print("")
            print(ANSI.bold("Jobs (\(envelope.jobs.count)):"))
            for job in envelope.jobs {
                let glyph = conclusionGlyph(job.conclusion ?? job.status)
                let dur = job.startedAt.flatMap { start in
                    job.completedAt.map { end in
                        Self.formatDuration(end.timeIntervalSince(start))
                    }
                } ?? "-"
                print("  \(glyph) \(job.name)\t#\(job.id)\t\(dur)")
            }
        }

        if exitStatus { try enforceExit(run.conclusion) }
    }

    // MARK: Rendering

    private func renderRunSummary(_ run: WorkflowRun) {
        print("\(ANSI.bold("Run #\(run.runNumber)")): \(run.displayTitle ?? run.name ?? "?")")
        let status = run.conclusion ?? run.status ?? "-"
        print("status: \(conclusionGlyph(status)) \(status)")
        print("event: \(run.event)  branch: \(run.headBranch ?? "-")  sha: \(String(run.headSha.prefix(7)))")
        if let actor = run.actor { print("actor: @\(actor.login)") }
        if let started = run.runStartedAt {
            print("started: \(ISO8601DateFormatter().string(from: started))")
        }
        print("url: \(run.htmlUrl.absoluteString)")
    }

    private func renderJob(_ job: WorkflowJob) {
        let status = job.conclusion ?? job.status
        print("\(ANSI.bold("Job #\(job.id)")): \(job.name)")
        print("status: \(conclusionGlyph(status)) \(status)")
        if let workflow = job.workflowName {
            print("workflow: \(workflow)")
        }
        if let started = job.startedAt, let ended = job.completedAt {
            print("duration: \(Self.formatDuration(ended.timeIntervalSince(started)))")
        }
        if let url = job.htmlUrl {
            print("url: \(url.absoluteString)")
        }
        if let steps = job.steps, !steps.isEmpty {
            print("")
            print(ANSI.bold("Steps:"))
            for step in steps {
                let stepGlyph = conclusionGlyph(step.conclusion ?? step.status)
                print("  \(stepGlyph) \(step.number). \(step.name)")
            }
        }
    }

    private func conclusionGlyph(_ value: String) -> String {
        switch value {
        case "success": return ANSI.green("✓")
        case "failure", "cancelled", "timed_out", "action_required":
            return ANSI.red("✗")
        case "skipped", "neutral", "stale": return ANSI.dim("-")
        case "in_progress", "queued", "pending", "waiting":
            return ANSI.yellow("…")
        default: return "?"
        }
    }

    private func enforceExit(_ conclusion: String?) throws {
        if conclusion != "success" {
            throw ExitCode(1)
        }
    }

    // MARK: Logs

    private func downloadAndPrintLogs(
        client: APIClient, slug: String, runId: Int, failedOnly: Bool
    ) async throws {
        let path = failedOnly
            ? "repos/\(slug)/actions/runs/\(runId)/attempts/latest/logs"
            : "repos/\(slug)/actions/runs/\(runId)/logs"
        // GitHub returns a 302 to a signed S3 URL. URLSession follows
        // redirects by default; the body we get back IS the zip.
        let response = try await client.raw(method: .get, path: path)
        guard !response.body.isEmpty else {
            FileHandle.standardError.write(Data("No log archive returned (run still in progress?).\n".utf8))
            return
        }
        try await ZipExtractor.printConcatenatedTextEntries(zipData: response.body)
    }

    // MARK: Helpers

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        return "\(s / 60)m\(s % 60)s"
    }
}
