import Foundation

/// Default `GitClient` impl that shells out to `git` via `Process`.
///
/// Mac and Linux only — embedders on iOS / sandboxed Mac processes
/// should inject `NoGitClient` instead.
public struct ProcessGitClient: GitClient {
    public let workingDirectory: URL
    public let gitPath: String

    public init(
        workingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
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
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ProcessResult, Error>) in
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: gitPath)
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
                        stdout: String(data: outData ?? Data(), encoding: .utf8) ?? "",
                        stderr: String(data: errData ?? Data(), encoding: .utf8) ?? ""
                    ))
                }

                try process.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}
