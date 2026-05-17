import Foundation
import FdKit
import ForgeKit
import RipgrepKit
import ShellKit

/// Argv-level entry point. Builds an `Fd.Configuration` from the
/// command-line arguments and runs the engine. Returns the process
/// exit code (0 = match found, 1 = no match, 2 = error). Kept in its
/// own enum (mirroring `RgExecutable`) so embedders can drive the CLI
/// behavior in-process.
public enum FdExecutable {

    @discardableResult
    public static func run(argv: [String],
                           stdin: InputSource,
                           stdout: OutputSink,
                           stderr: OutputSink) async throws -> Int32 {
        do {
            let parsed = try Parser.parse(argv)

            switch parsed.specialMode {
            case .help:
                stdout.write(Parser.helpText)
                return 0
            case .version:
                stdout.write("fd 0.1.0 (swift-ports)\n")
                return 0
            case .none:
                break
            }

            // Resolve the user-supplied search paths to (URL, displayed)
            // pairs. An empty list defaults to the cwd.
            let resolvedRoots: [(URL, String)] = parsed.paths.isEmpty
                ? [(Shell.currentDirectory, ".")]
                : parsed.paths.map { p in (Shell.resolve(p), p) }

            // Validate every supplied path *before* running the search.
            // Real fd exits with code 2 on a missing path; scripts that
            // gate on the exit code rely on that distinction.
            var sawMissingPath = false
            for (url, display) in resolvedRoots {
                try await Shell.authorize(url)
                if !FileManager.default.fileExists(atPath: url.path) {
                    stderr.write(
                        "fd: '\(display)' is not a directory or file\n")
                    sawMissingPath = true
                }
            }

            let outcome = try await Fd.run(
                configuration: parsed.config,
                searchPaths: resolvedRoots.map {
                    Walker.Root(url: $0.0, display: $0.1)
                },
                stdout: stdout,
                stderr: stderr)

            if sawMissingPath { return 2 }
            return outcome.hadMatch ? 0 : 1
        } catch let err as Parser.ArgError {
            stderr.write("fd: \(err.message)\n")
            return 2
        } catch let err as FdPatternError {
            stderr.write("fd: \(err.description)\n")
            return 2
        } catch {
            stderr.write("fd: \(error)\n")
            return 2
        }
    }
}
