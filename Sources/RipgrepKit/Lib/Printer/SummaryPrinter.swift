import Foundation
import ShellKit

/// Summary modes that print one line per file rather than per match:
///
///   * `-c`/`--count`         — `<path>:<n>` (line matches)
///   * `--count-matches`      — `<path>:<m>` (total submatches)
///   * `-l`/`--files-with-matches`   — just `<path>` for files w/ a hit
///   * `--files-without-match`       — just `<path>` for files w/o a hit
public struct SummaryPrinter: Printer {

    public enum Mode: Sendable {
        case count
        case countMatches
        case filesWithMatches
        case filesWithoutMatch
    }

    public var options: PrinterOptions
    public var mode: Mode

    public init(options: PrinterOptions, mode: Mode) {
        self.options = options
        self.mode = mode
    }

    public mutating func begin(to sink: OutputSink) {}
    public mutating func end(to sink: OutputSink) {}

    public mutating func emit(_ result: FileSearchResult, to sink: OutputSink) {
        if options.quiet { return }
        let path = PrinterUtil.formatPath(result.displayPath, opts: options)
        let coloredPath = PrinterUtil.wrap(
            path, with: options.colorSpec.path, enabled: options.color)
        let sep = options.matchFieldSeparator

        switch mode {
        case .count:
            if !result.hasMatch && !options.includeZero { return }
            sink.write("\(coloredPath)\(sep)\(result.lineMatches)\n")

        case .countMatches:
            if result.totalMatches == 0 && !options.includeZero { return }
            sink.write("\(coloredPath)\(sep)\(result.totalMatches)\n")

        case .filesWithMatches:
            guard result.hasMatch else { return }
            sink.write(coloredPath)
            if options.nullSeparator {
                sink.write(Data([0x00]))
            } else {
                sink.write("\n")
            }

        case .filesWithoutMatch:
            guard !result.hasMatch else { return }
            sink.write(coloredPath)
            if options.nullSeparator {
                sink.write(Data([0x00]))
            } else {
                sink.write("\n")
            }
        }
    }
}
