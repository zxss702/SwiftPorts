import Foundation
import ShellKit

/// Top-level convenience entry point for the engine. Bundles the
/// `Walker`, `Searcher` and `Printer` so callers can drive a search
/// run with a single `Ripgrep.run(...)` call.
///
/// The CLI in `RgCommand` is a thin wrapper around this — but
/// `Ripgrep` itself doesn't depend on ArgumentParser so embedders
/// can use it from any host.
public enum Ripgrep {

    /// Aggregated run-level configuration.
    public struct Configuration: Sendable {
        public var pattern: PatternOptions
        public var search: SearchOptions
        public var walker: WalkerOptions
        public var printer: PrinterOptions
        public var output: OutputMode

        public init(pattern: PatternOptions = PatternOptions(),
                    search: SearchOptions = SearchOptions(),
                    walker: WalkerOptions = WalkerOptions(),
                    printer: PrinterOptions = PrinterOptions(),
                    output: OutputMode = .standard) {
            self.pattern = pattern
            self.search = search
            self.walker = walker
            self.printer = printer
            self.output = output
        }
    }

    /// Which printer drives the run.
    public enum OutputMode: Sendable {
        case standard
        case json
        case summary(SummaryPrinter.Mode)
    }

    /// Final outcome of a run — drives the exit code at the CLI layer.
    public struct Outcome: Sendable {
        public let filesSearched: Int
        public let filesWithMatch: Int
        public let lineMatches: Int
        public let totalMatches: Int
        public let bytesSearched: Int

        public init(filesSearched: Int,
                    filesWithMatch: Int,
                    lineMatches: Int,
                    totalMatches: Int,
                    bytesSearched: Int) {
            self.filesSearched = filesSearched
            self.filesWithMatch = filesWithMatch
            self.lineMatches = lineMatches
            self.totalMatches = totalMatches
            self.bytesSearched = bytesSearched
        }

        public var hadMatch: Bool { lineMatches > 0 }
    }

    /// Search `roots` and stream results into `stdout`.
    /// `stdin` is consumed when `roots` is empty (`-` reads from there
    /// too). `stderr` receives warnings.
    @discardableResult
    public static func run(
        configuration config: Configuration,
        roots: [Walker.Root],
        stdin: InputSource,
        stdout: OutputSink,
        stderr: OutputSink
    ) async throws -> Outcome {

        let matcher = try PatternMatcher(config.pattern)
        let searcher = Searcher(matcher: matcher, options: config.search)

        // Decide if multiple sources are in play — drives implicit
        // `-H` behaviour. Reading stdin counts as "one source".
        let multipleSources: Bool = {
            if roots.count > 1 { return true }
            if roots.isEmpty { return false }
            let only = roots[0].url
            let isDir = (try? only.resourceValues(forKeys: [.isDirectoryKey]))?
                .isDirectory ?? false
            return isDir
        }()

        var printer: any Printer = {
            switch config.output {
            case .standard:
                return StandardPrinter(options: config.printer,
                                       multipleSources: multipleSources)
            case .json:
                return JSONPrinter(options: config.printer)
            case .summary(let mode):
                return SummaryPrinter(options: config.printer, mode: mode)
            }
        }()

        printer.begin(to: stdout)

        var filesSearched = 0
        var filesWithMatch = 0
        var totalMatchedLines = 0
        var totalSubmatches = 0
        var totalBytes = 0

        // Stdin source case — `rg PATTERN` with no path / `rg PATTERN -`.
        let stdinPaths = roots.filter { $0.url.path == "-" }
        let realPaths = roots.filter { $0.url.path != "-" }
        let consumeStdin = roots.isEmpty || !stdinPaths.isEmpty

        if consumeStdin {
            let data = await stdin.readAllData()
            let result = searcher.search(displayPath: "<stdin>", data: data)
            filesSearched += 1
            totalBytes += result.bytesSearched
            if result.hasMatch { filesWithMatch += 1 }
            totalMatchedLines += result.lineMatches
            totalSubmatches += result.totalMatches
            printer.emit(result, to: stdout)
        }

        if !realPaths.isEmpty {
            let walker = Walker(options: config.walker)
            try walker.walk(roots: realPaths) { entry in
                guard let result = try searcher.searchFile(
                    displayPath: entry.displayPath,
                    url: entry.url) else {
                    return
                }
                filesSearched += 1
                totalBytes += result.bytesSearched
                if result.hasMatch { filesWithMatch += 1 }
                totalMatchedLines += result.lineMatches
                totalSubmatches += result.totalMatches
                printer.emit(result, to: stdout)
            }
        }

        printer.end(to: stdout)

        return Outcome(filesSearched: filesSearched,
                       filesWithMatch: filesWithMatch,
                       lineMatches: totalMatchedLines,
                       totalMatches: totalSubmatches,
                       bytesSearched: totalBytes)
    }
}
