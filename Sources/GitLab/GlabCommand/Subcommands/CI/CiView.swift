import ArgumentParser
import ShellKit
import Foundation
import ForgeKit
import GitLab

struct CiView: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "view",
        abstract: "Show a pipeline with its jobs grouped by stage.",
        aliases: ["show"]
    )

    @Option(name: [.customShort("R"), .long],
            help: "Repository as OWNER/REPO or GROUP/NAMESPACE/REPO.")
    var repo: RepositoryReference?

    @Argument(help: "Pipeline ID. Defaults to the latest pipeline for the resolved branch.")
    var pipelineId: Int?

    @Option(name: [.customShort("b"), .long],
            help: "Branch to look up the latest pipeline for. Defaults to the cwd's current branch.")
    var branch: String?

    @Flag(name: [.customShort("w"), .long],
          help: "Open the pipeline in your browser.")
    var web: Bool = false

    @Flag(name: .long, help: "Print as JSON.")
    var json: Bool = false

    func run() async throws {
        let target = try await CommandContext.resolveRepo(flag: repo)
        let client = try await CommandContext.apiClient(host: target.host)
        let gitClient: any ForgeKit.GitClient = CommandContext.gitClient()

        let id = try await CiSupport.resolvePipelineId(
            explicit: pipelineId,
            repo: target,
            client: client,
            branch: branch,
            gitClient: gitClient)

        let pipeline: Pipeline = try await client.get(
            "projects/\(target.encodedPath)/pipelines/\(id)")

        if web {
            try await Browser.open(pipeline.webUrl)
            Shell.print("Opening \(pipeline.webUrl.absoluteString) in your browser.")
            return
        }

        let jobs: [Job] = try await client.get(
            "projects/\(target.encodedPath)/pipelines/\(id)/jobs",
            query: [URLQueryItem(name: "per_page", value: "100")])

        if json {
            struct PipelineWithJobs: Encodable {
                let pipeline: Pipeline
                let jobs: [Job]
            }
            Shell.print(try CodableOutput.prettyJSON(
                PipelineWithJobs(pipeline: pipeline, jobs: jobs)))
            return
        }

        let on = TTY.isStdoutColorEnabled
        Self.printPipelineHeader(pipeline, enabled: on)
        Self.printJobsByStage(jobs, enabled: on)
    }

    static func printPipelineHeader(_ p: Pipeline, enabled on: Bool) {
        let idToken = OSC8.wrap("#\(p.id)", url: p.webUrl.absoluteString, enabled: on)
        Shell.print("\(ANSI.bold(idToken))  \(CiSupport.renderStatus(p.status, enabled: on))")
        Shell.print("ref: \(p.ref ?? "—")  sha: \(String(p.sha.prefix(8)))")
        Shell.print("started: \(StatusBadge.muted(CiSupport.ageInWords(from: p.startedAt ?? p.createdAt), enabled: on))  duration: \(CiSupport.formatDuration(p.duration))")
        Shell.print("url: \(p.webUrl.absoluteString)")
    }

    static func printJobsByStage(_ jobs: [Job], enabled on: Bool) {
        // Preserve first-seen stage order (the API returns jobs roughly
        // in stage order, sometimes interleaved by retry).
        var stageOrder: [String] = []
        var byStage: [String: [Job]] = [:]
        for j in jobs {
            if byStage[j.stage] == nil { stageOrder.append(j.stage) }
            byStage[j.stage, default: []].append(j)
        }
        for stage in stageOrder {
            Shell.print("\n\(ANSI.bold("[\(stage)]"))")
            for j in byStage[stage] ?? [] {
                let dur = CiSupport.formatDuration(j.duration)
                let tail = "(#\(j.id), \(dur))"
                Shell.print("  \(CiSupport.renderStatus(j.status, enabled: on))  \(j.name) \(StatusBadge.muted(tail, enabled: on))")
            }
        }
    }
}
