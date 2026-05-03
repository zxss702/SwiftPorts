import Foundation

/// Tiny helper that shells out to `unzip` to extract a ZIP archive
/// and concatenate every text entry to stdout. Used by
/// `gh run view --log` to render `/actions/runs/{id}/logs`, which
/// returns a ZIP of per-job log files.
///
/// macOS / Linux only. iOS / sandboxed embedders that need this
/// will inject their own log printer; for now `gh run view --log` is
/// gated behind `Process` availability.
public enum ZipExtractor {
    public static func printConcatenatedTextEntries(zipData: Data) async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swiftgh-logs-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let zipPath = tempDir.appendingPathComponent("archive.zip")
        try zipData.write(to: zipPath)

        try await unzip(zipPath: zipPath, into: tempDir)

        // Walk the unpacked tree and print every regular file that
        // looks like text. GitHub's log ZIP packs files like
        // `0_jobname.txt` at the root and per-step files in subdirs.
        // Collect into an Array first so we don't hold the (non-Sendable)
        // NSEnumerator across the print loop.
        let urls = collectFiles(under: tempDir)
        for url in urls {
            guard url.pathExtension != "zip" else { continue }
            let relative = url.path.replacingOccurrences(
                of: tempDir.path + "/", with: "")
            FileHandle.standardOutput.write(Data(
                "\n=== \(relative) ===\n".utf8))
            if let data = try? Data(contentsOf: url) {
                FileHandle.standardOutput.write(data)
            }
        }
    }

    private static func collectFiles(under root: URL) -> [URL] {
        var result: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey])
        else { return [] }
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            result.append(url)
        }
        return result.sorted { $0.path < $1.path }
    }

    private static func unzip(zipPath: URL, into destination: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [
                    "unzip", "-q", zipPath.path, "-d", destination.path,
                ]
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                process.terminationHandler = { proc in
                    // unzip exits 0 on success; 1 means warnings (non-fatal).
                    if proc.terminationStatus <= 1 {
                        cont.resume()
                    } else {
                        cont.resume(throwing: ZipExtractorError.unzipFailed(
                            exitCode: proc.terminationStatus))
                    }
                }
                try process.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}

public enum ZipExtractorError: Error, LocalizedError {
    case unzipFailed(exitCode: Int32)

    public var errorDescription: String? {
        switch self {
        case .unzipFailed(let code):
            return "unzip exited with code \(code)"
        }
    }
}
