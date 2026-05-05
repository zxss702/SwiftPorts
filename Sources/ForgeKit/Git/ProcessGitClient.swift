import Foundation
import Sandbox

#if os(macOS) || os(Linux) || os(Windows)
/// Default `GitClient` impl that shells out to `git` via `Process`.
///
/// Available only where `Process` is launchable — macOS, Linux, and
/// Windows. iOS / tvOS / watchOS embedders should use ``NoGitClient``
/// (or now `SwiftGit.GitClient` for full functionality).
public struct ProcessGitClient: GitClient {
    public let workingDirectory: URL
    public let gitPath: String

    public init(
        workingDirectory: URL = Sandbox.currentDirectory,
        gitPath: String = "/usr/bin/env"
    ) {
        self.workingDirectory = workingDirectory
        self.gitPath = gitPath
    }

    // MARK: Read

    public func remoteURL(named name: String) async throws -> URL? {
        let result = try await runGit(["remote", "get-url", name])
        // `git remote get-url` exits 2 with empty stdout when missing.
        guard result.exitCode == 0 else { return nil }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    public func currentBranch() async throws -> String? {
        let result = try await runGit(["symbolic-ref", "--short", "HEAD"])
        guard result.exitCode == 0 else { return nil }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func upstreamBranch(of localBranch: String) async throws -> String? {
        let result = try await runGit([
            "rev-parse", "--abbrev-ref", "--symbolic-full-name",
            "\(localBranch)@{upstream}",
        ])
        guard result.exitCode == 0 else { return nil }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: Write

    public func clone(url: URL, directory: URL?) async throws {
        var args = ["clone", url.absoluteString]
        if let directory { args.append(directory.path) }
        try await runOrThrow(args)
    }

    public func fetch(remote: String, refspec: String) async throws {
        try await runOrThrow(["fetch", remote, refspec])
    }

    public func checkout(ref: String) async throws {
        try await runOrThrow(["checkout", ref])
    }

    public func push(remote: String, refspec: String, setUpstream: Bool) async throws {
        var args = ["push"]
        if setUpstream { args.append("-u") }
        args.append(contentsOf: [remote, refspec])
        try await runOrThrow(args)
    }

    public func addRemote(name: String, url: URL) async throws {
        try await runOrThrow(["remote", "add", name, url.absoluteString])
    }

    public func add(paths: [String]) async throws {
        if paths.isEmpty {
            try await runOrThrow(["add", "-A"])
        } else {
            try await runOrThrow(["add", "--"] + paths)
        }
    }

    @discardableResult
    public func commit(message: String, author: GitSignature?, allowEmpty: Bool) async throws -> String {
        // Mirror libgit2's "stage everything then commit" semantics with
        // `git add -A` so both impls behave the same to the caller.
        try await runOrThrow(["add", "-A"])

        var args = ["commit", "-m", message]
        if allowEmpty { args.append("--allow-empty") }
        if let author { args.append(contentsOf: ["--author", "\(author.name) <\(author.email)>"]) }
        try await runOrThrow(args)

        let result = try await runGit(["rev-parse", "HEAD"])
        guard result.exitCode == 0 else {
            throw GitClientError.gitFailed(
                args: ["rev-parse", "HEAD"],
                exitCode: result.exitCode, stderr: result.stderr)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Process invocation

    struct ProcessResult: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private func runOrThrow(_ args: [String]) async throws {
        let result = try await runGit(args)
        guard result.exitCode == 0 else {
            throw GitClientError.gitFailed(
                args: args, exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    private func runGit(_ args: [String]) async throws -> ProcessResult {
        let executableURL = URL(fileURLWithPath: gitPath)
        // Sandbox boundary: under Sandbox.rooted(at:) the system git
        // binary won't be under root and this denies — embedders
        // wanting in-process git use SwiftGit.GitClient (libgit2).
        try await Sandbox.authorize(executableURL)
        // Also gate the working directory — the git command will
        // open files there, so refusing now beats refusing later.
        try await Sandbox.authorize(workingDirectory)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ProcessResult, Error>) in
            do {
                let process = Process()
                process.executableURL = executableURL
                process.arguments = ["git"] + args
                process.currentDirectoryURL = workingDirectory

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                process.terminationHandler = { proc in
                    let outData = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
                    let errData = (try? stderr.fileHandleForReading.readToEnd()) ?? Data()
                    cont.resume(returning: ProcessResult(
                        exitCode: proc.terminationStatus,
                        stdout: String(data: outData, encoding: .utf8) ?? "",
                        stderr: String(data: errData, encoding: .utf8) ?? ""
                    ))
                }

                try process.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}
#endif
