import Foundation
import Sandbox

/// Open URLs in the user's default browser by shelling out to the
/// platform's URL opener (`open` on macOS, `xdg-open` on Linux,
/// `start` on Windows). No AppKit / UIKit dep — keeps `GitHub`
/// usable from non-app embedders.
///
/// Mirrors what `cli/browser` does for upstream gh.
public enum Browser {
    public static func open(_ url: URL) async throws {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw BrowserError.unsupportedScheme(url.scheme ?? "")
        }
        try await launch(url: url)
    }

    #if os(macOS) || os(Linux) || os(Windows)
    private static func launch(url: URL) async throws {
        let arg = url.absoluteString
        #if os(macOS)
        try await runProcess(executable: "/usr/bin/open", args: [arg])
        #elseif os(Linux)
        // Try xdg-open first, then fall back to gio + gnome-open + others.
        let candidates = ["xdg-open", "gio", "gnome-open", "kde-open"]
        for tool in candidates {
            do {
                let toolArgs = (tool == "gio") ? ["open", arg] : [arg]
                try await runProcess(
                    executable: "/usr/bin/env",
                    args: [tool] + toolArgs)
                return
            } catch {
                continue
            }
        }
        throw BrowserError.noOpener
        #elseif os(Windows)
        try await runProcess(
            executable: "C:\\Windows\\System32\\cmd.exe",
            args: ["/c", "start", "", arg])
        #endif
    }

    @discardableResult
    private static func runProcess(
        executable: String, args: [String]
    ) async throws -> Int32 {
        let executableURL = URL(fileURLWithPath: executable)
        // Sandbox boundary: ask the active sandbox whether this
        // executable may be launched. Under `Sandbox.rooted(at:)`,
        // platform binaries like `/usr/bin/open` aren't under root
        // and will be denied — embedders running in a sandbox don't
        // get browser-launching capability.
        try await Sandbox.authorize(executableURL)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int32, Error>) in
            do {
                let process = Process()
                process.executableURL = executableURL
                process.arguments = args
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                process.terminationHandler = { proc in
                    if proc.terminationStatus == 0 {
                        cont.resume(returning: proc.terminationStatus)
                    } else {
                        cont.resume(throwing: BrowserError.openerFailed(
                            executable: executable,
                            args: args,
                            exitCode: proc.terminationStatus))
                    }
                }
                try process.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
    #else
    // iOS / tvOS / watchOS: Process is unavailable. Browser.open exists
    // for compile-compat but always fails.
    private static func launch(url: URL) async throws {
        throw BrowserError.unsupportedPlatform
    }
    #endif
}

public enum BrowserError: Error, LocalizedError, Sendable {
    case unsupportedScheme(String)
    case unsupportedPlatform
    case noOpener
    case openerFailed(executable: String, args: [String], exitCode: Int32)

    public var errorDescription: String? {
        switch self {
        case .unsupportedScheme(let s):
            return "Refusing to open '\(s)://' URLs in a browser."
        case .unsupportedPlatform:
            return "Don't know how to open URLs on this platform."
        case .noOpener:
            return "No URL opener found (tried xdg-open, gio, gnome-open, kde-open)."
        case .openerFailed(let executable, let args, let code):
            return "\(executable) \(args.joined(separator: " ")) exited with code \(code)"
        }
    }
}
