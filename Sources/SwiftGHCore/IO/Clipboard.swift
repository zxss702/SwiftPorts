import Foundation

/// Write to / read from the system clipboard via the platform helper:
/// `pbcopy`/`pbpaste` on macOS, `xclip`/`wl-copy` on Linux,
/// `clip`/`Get-Clipboard` on Windows. Same minimal-dep approach as
/// ``Browser`` — no AppKit / UIKit needed.
public enum Clipboard {
    public static func write(_ string: String) async throws {
        #if os(macOS)
        try await pipe(to: "/usr/bin/pbcopy", input: string)
        #elseif os(Linux)
        // Prefer wl-copy on Wayland, fall back to xclip on X11.
        let waylandDisplay = ProcessInfo.processInfo.environment["WAYLAND_DISPLAY"]
        if let waylandDisplay, !waylandDisplay.isEmpty {
            try await pipe(to: "/usr/bin/env",
                           input: string,
                           args: ["wl-copy"])
        } else {
            try await pipe(to: "/usr/bin/env",
                           input: string,
                           args: ["xclip", "-selection", "clipboard"])
        }
        #elseif os(Windows)
        try await pipe(to: "C:\\Windows\\System32\\clip.exe", input: string)
        #else
        throw ClipboardError.unsupportedPlatform
        #endif
    }

    private static func pipe(
        to executable: String,
        input: String,
        args: [String] = []
    ) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args
                let inPipe = Pipe()
                process.standardInput = inPipe
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                process.terminationHandler = { proc in
                    if proc.terminationStatus == 0 {
                        cont.resume()
                    } else {
                        cont.resume(throwing: ClipboardError.helperFailed(
                            executable: executable,
                            exitCode: proc.terminationStatus))
                    }
                }
                try process.run()
                inPipe.fileHandleForWriting.write(Data(input.utf8))
                try? inPipe.fileHandleForWriting.close()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}

public enum ClipboardError: Error, LocalizedError, Sendable {
    case unsupportedPlatform
    case helperFailed(executable: String, exitCode: Int32)

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            return "Don't know how to talk to the clipboard on this platform."
        case .helperFailed(let exe, let code):
            return "\(exe) exited with code \(code)"
        }
    }
}
