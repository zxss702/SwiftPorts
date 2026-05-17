import Foundation
import ShellKit

/// Real `rg`'s default output: one line per match, with optional
/// filename, line number, column, byte offset, color highlights and
/// context separators. The two "modes" — line-oriented (no heading)
/// vs grouped (`--heading`) — are both handled here.
public struct StandardPrinter: Printer {

    public var options: PrinterOptions
    public var multipleSources: Bool
    /// True when emitting in a "search many files" setup — drives the
    /// implicit `--with-filename` default.
    private var lastEmittedPath: String? = nil
    private var lastEmittedLineEnd: Int? = nil
    private var lastEmittedHadContext: Bool = false

    public init(options: PrinterOptions, multipleSources: Bool = true) {
        self.options = options
        self.multipleSources = multipleSources
    }

    public mutating func begin(to sink: OutputSink) {
        // No header emitted.
    }

    public mutating func end(to sink: OutputSink) {
        // Nothing buffered.
    }

    public mutating func emit(_ result: FileSearchResult, to sink: OutputSink) {
        if options.quiet { return }
        if result.binary && result.hasMatch {
            let path = PrinterUtil.formatPath(result.displayPath, opts: options)
            sink.write("Binary file \(path) matches\n")
            return
        }
        guard !result.chunks.isEmpty else { return }

        let withFilename = options.withFilename ?? multipleSources
        let separator = options.matchFieldSeparator
        let ctxSep = options.contextFieldSeparator

        if options.heading {
            // Blank line between different file groups.
            if lastEmittedPath != nil {
                sink.write("\n")
            }
            let path = PrinterUtil.formatPath(result.displayPath, opts: options)
            let coloredPath = PrinterUtil.wrap(
                path, with: options.colorSpec.path, enabled: options.color)
            sink.write(coloredPath)
            sink.write("\n")
        }

        var emittedAny = false
        var lastIdx: Int? = nil

        // A cross-file context boundary needs a `--` divider if context
        // is in play. We detect "context is in play" by seeing whether
        // any chunk in this file has before/after entries OR the
        // previous file emitted them — and emit the separator before
        // the first chunk of the new file.
        let fileHasContext = result.chunks.contains { !$0.before.isEmpty || !$0.after.isEmpty }
        if !options.heading,
           lastEmittedHadContext,
           fileHasContext,
           lastEmittedPath != nil,
           lastEmittedPath != result.displayPath {
            sink.write(options.contextSeparator + "\n")
        }

        for chunk in result.chunks {
            // Context separator between chunks within a file. Real rg
            // only emits `--` when context (-A/-B/-C) is in play AND
            // the chunks are non-adjacent. With zero context, we
            // suppress it entirely.
            let contextEnabled = !chunk.before.isEmpty
                || !chunk.after.isEmpty
            if let last = lastIdx, contextEnabled {
                let nextStart = chunk.before.first?.lineNumber
                    ?? chunk.match.lineNumber
                if nextStart > last + 1 {
                    sink.write(options.contextSeparator + "\n")
                }
            }

            for ctx in chunk.before {
                writeLine(path: result.displayPath,
                          lineNumber: ctx.lineNumber,
                          column: nil,
                          byteOffset: ctx.byteOffset,
                          body: ctx.line,
                          hits: [],
                          isContext: true,
                          withFilename: withFilename,
                          separator: ctxSep,
                          sink: sink)
                lastIdx = ctx.lineNumber
            }
            // Match.
            if options.onlyMatching {
                for hit in chunk.match.hits {
                    let bytes = Array(chunk.match.line.utf8)
                    let segment = String(decoding: bytes[hit.utf8Start..<hit.utf8End],
                                         as: UTF8.self)
                    // Column is only printed for -o when --column is on,
                    // matching real rg.
                    let col: Int? = options.column ? hit.utf8Start + 1 : nil
                    writeLine(path: result.displayPath,
                              lineNumber: chunk.match.lineNumber,
                              column: col,
                              byteOffset: chunk.match.byteOffset + hit.utf8Start,
                              body: segment,
                              hits: [PatternMatcher.Hit(utf8Start: 0,
                                                       utf8End: hit.utf8End - hit.utf8Start)],
                              isContext: false,
                              withFilename: withFilename,
                              separator: separator,
                              sink: sink)
                }
            } else {
                let col: Int? = options.column
                    ? (chunk.match.hits.first?.utf8Start ?? 0) + 1
                    : nil
                writeLine(path: result.displayPath,
                          lineNumber: chunk.match.lineNumber,
                          column: col,
                          byteOffset: chunk.match.byteOffset,
                          body: chunk.match.line,
                          hits: chunk.match.hits,
                          isContext: false,
                          withFilename: withFilename,
                          separator: separator,
                          sink: sink)
            }
            lastIdx = chunk.match.lineNumber

            for ctx in chunk.after {
                writeLine(path: result.displayPath,
                          lineNumber: ctx.lineNumber,
                          column: nil,
                          byteOffset: ctx.byteOffset,
                          body: ctx.line,
                          hits: [],
                          isContext: true,
                          withFilename: withFilename,
                          separator: ctxSep,
                          sink: sink)
                lastIdx = ctx.lineNumber
            }
            emittedAny = true
        }

        if emittedAny {
            lastEmittedPath = result.displayPath
            lastEmittedLineEnd = lastIdx
            lastEmittedHadContext = fileHasContext
        }
    }

    private mutating func writeLine(
        path: String,
        lineNumber: Int,
        column: Int?,
        byteOffset: Int,
        body: String,
        hits: [PatternMatcher.Hit],
        isContext: Bool,
        withFilename: Bool,
        separator: String,
        sink: OutputSink
    ) {
        var line = ""
        if withFilename && !options.heading {
            let p = PrinterUtil.formatPath(path, opts: options)
            line += PrinterUtil.wrap(
                p, with: options.colorSpec.path, enabled: options.color)
            line += separator
        }
        if options.lineNumber {
            let ln = String(lineNumber)
            line += PrinterUtil.wrap(
                ln, with: options.colorSpec.lineNumber, enabled: options.color)
            line += separator
        }
        if let column {
            line += "\(column)"
            line += separator
        }
        if options.byteOffset {
            line += "\(byteOffset)"
            line += separator
        }
        line += PrinterUtil.renderLine(body, hits: hits, opts: options)
        if options.nullSeparator && !isContext {
            sink.write(line)
            sink.write(Data([0x00]))
            sink.write("\n")
        } else {
            sink.write(line)
            sink.write("\n")
        }
    }
}
