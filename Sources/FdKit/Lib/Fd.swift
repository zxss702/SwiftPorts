import Foundation
import RipgrepKit
import ShellKit

/// Top-level convenience entry point for the engine — bundles the
/// `Walker`, the pattern matcher, the entry filter, and the printer so
/// callers can run a search with one call.
///
/// Mirrors the shape of `RipgrepKit.Ripgrep.run(...)` so embedders that
/// already use ripgrep get a familiar API.
public enum Fd {

    /// Aggregated configuration for a single fd run.
    public struct Configuration: Sendable {
        public var pattern: PatternOptions
        public var filter: FilterOptions
        public var walker: WalkerOptions
        public var printer: PrinterOptions

        public init(pattern: PatternOptions = PatternOptions(),
                    filter: FilterOptions = FilterOptions(),
                    walker: WalkerOptions = Fd.defaultWalkerOptions(),
                    printer: PrinterOptions = PrinterOptions()) {
            self.pattern = pattern
            self.filter = filter
            self.walker = walker
            self.printer = printer
        }
    }

    /// `WalkerOptions` preconfigured for fd: dot-ignore filenames swap
    /// from ripgrep's `.rgignore` to fd's `.fdignore`, and directory
    /// emission is on so the walker yields the items fd lists.
    public static func defaultWalkerOptions() -> WalkerOptions {
        var w = WalkerOptions()
        w.dotIgnoreFilenames = [".ignore", ".fdignore"]
        w.emitDirectories = true
        return w
    }

    /// Outcome of a run — drives the CLI exit code.
    public struct Outcome: Sendable {
        public let entriesPrinted: Int
        public init(entriesPrinted: Int) {
            self.entriesPrinted = entriesPrinted
        }
        public var hadMatch: Bool { entriesPrinted > 0 }
    }

    /// `CancellationError`-shaped sentinel the engine raises to break
    /// out of the walker when `--max-results` is reached. Kept private
    /// so the walker's caller can catch it without polluting the
    /// public surface.
    struct ResultCapReached: Error {}

    /// Walk `searchPaths` and print matching entries to `stdout`.
    ///
    /// `searchPaths` follows the fd convention: when empty, the engine
    /// searches the current working directory.
    @discardableResult
    public static func run(
        configuration config: Configuration,
        searchPaths: [Walker.Root],
        stdout: OutputSink,
        stderr: OutputSink
    ) async throws -> Outcome {

        var walkerOptions = config.walker
        // Ensure directory emission is on; the configuration default
        // sets this but callers handing us raw WalkerOptions might
        // miss it.
        walkerOptions.emitDirectories = true

        let matcher = try PatternMatcher(config.pattern)
        let filter = EntryFilter(options: config.filter)
        let printer = Printer(options: config.printer)

        let roots: [Walker.Root] = searchPaths.isEmpty
            ? [Walker.Root(url: Shell.currentDirectory, display: ".")]
            : searchPaths

        var printed = 0
        let walker = Walker(options: walkerOptions)
        let maxResults = config.filter.maxResults

        do {
            try walker.walk(roots: roots) { entry in
                let metadata = EntryFilter.Metadata(url: entry.url)
                if !filter.passes(entry: entry,
                                  metadata: metadata,
                                  depth: entry.depth) {
                    return
                }
                if !matcher.matches(basename: entry.url.lastPathComponent,
                                    relativePath: entry.relativePath) {
                    return
                }
                printer.emit(entry, metadata: metadata, to: stdout)
                printed += 1
                if let max = maxResults, printed >= max {
                    throw ResultCapReached()
                }
            }
        } catch is ResultCapReached {
            // Normal early-stop — propagate via the outcome, not the
            // error channel.
        }

        return Outcome(entriesPrinted: printed)
    }
}
