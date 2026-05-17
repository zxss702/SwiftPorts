import Foundation
import ShellKit

/// `--json` printer. Emits ripgrep's JSON Lines schema:
///
///   {"type":"begin", "data":{"path":{"text":"path"}}}
///   {"type":"context"|"match", "data":{"path":..., "lines":..., "line_number":N, "absolute_offset":N, "submatches":[...]}}
///   {"type":"end", "data":{"path":..., "binary_offset":null, "stats":{...}}}
///   {"type":"summary", "data":{...}}    once at end-of-run
///
/// Each line is a complete JSON object terminated by `\n`. Downstream
/// consumers like Pi's grep tool stream-parse one object per line.
public struct JSONPrinter: Printer {

    public var options: PrinterOptions
    private var totalMatches = 0
    private var totalMatchedLines = 0
    private var totalBytes = 0
    private var totalFiles = 0
    private var totalFilesWithMatch = 0
    private var elapsedStart: Date = Date()

    public init(options: PrinterOptions) {
        self.options = options
    }

    public mutating func begin(to sink: OutputSink) {
        elapsedStart = Date()
    }

    public mutating func end(to sink: OutputSink) {
        let summary: [String: Any] = [
            "type": "summary",
            "data": [
                "elapsed_total": elapsedField(seconds: -elapsedStart.timeIntervalSinceNow),
                "stats": [
                    "elapsed": elapsedField(seconds: -elapsedStart.timeIntervalSinceNow),
                    "searches": totalFiles,
                    "searches_with_match": totalFilesWithMatch,
                    "bytes_searched": totalBytes,
                    "bytes_printed": 0,
                    "matched_lines": totalMatchedLines,
                    "matches": totalMatches,
                ],
            ],
        ]
        writeJSON(summary, to: sink)
    }

    public mutating func emit(_ result: FileSearchResult, to sink: OutputSink) {
        totalFiles += 1
        totalBytes += result.bytesSearched
        totalMatchedLines += result.lineMatches
        totalMatches += result.totalMatches
        if result.hasMatch { totalFilesWithMatch += 1 }

        if options.quiet { return }
        if !result.hasMatch { return }

        // BEGIN event.
        let begin: [String: Any] = [
            "type": "begin",
            "data": ["path": ["text": result.displayPath]],
        ]
        writeJSON(begin, to: sink)

        for chunk in result.chunks {
            for ctx in chunk.before {
                writeJSON(makeLineEvent(type: "context",
                                        path: result.displayPath,
                                        line: ctx.line,
                                        lineNumber: ctx.lineNumber,
                                        byteOffset: ctx.byteOffset,
                                        hits: [],
                                        isMatch: false),
                          to: sink)
            }
            writeJSON(makeLineEvent(type: "match",
                                    path: result.displayPath,
                                    line: chunk.match.line,
                                    lineNumber: chunk.match.lineNumber,
                                    byteOffset: chunk.match.byteOffset,
                                    hits: chunk.match.hits,
                                    isMatch: true),
                      to: sink)
            for ctx in chunk.after {
                writeJSON(makeLineEvent(type: "context",
                                        path: result.displayPath,
                                        line: ctx.line,
                                        lineNumber: ctx.lineNumber,
                                        byteOffset: ctx.byteOffset,
                                        hits: [],
                                        isMatch: false),
                          to: sink)
            }
        }

        // END event.
        let end: [String: Any] = [
            "type": "end",
            "data": [
                "path": ["text": result.displayPath],
                "binary_offset": NSNull(),
                "stats": [
                    "elapsed": elapsedField(seconds: 0),
                    "searches": 1,
                    "searches_with_match": 1,
                    "bytes_searched": result.bytesSearched,
                    "bytes_printed": 0,
                    "matched_lines": result.lineMatches,
                    "matches": result.totalMatches,
                ],
            ],
        ]
        writeJSON(end, to: sink)
    }

    private func makeLineEvent(type: String,
                               path: String,
                               line: String,
                               lineNumber: Int,
                               byteOffset: Int,
                               hits: [PatternMatcher.Hit],
                               isMatch: Bool) -> [String: Any] {
        let lineBytes = Array(line.utf8)
        let submatches: [[String: Any]] = hits.map { hit in
            let matchBytes = Array(lineBytes[hit.utf8Start..<hit.utf8End])
            let matchText = String(decoding: matchBytes, as: UTF8.self)
            return [
                "match": ["text": matchText],
                "start": hit.utf8Start,
                "end": hit.utf8End,
            ]
        }
        return [
            "type": type,
            "data": [
                "path": ["text": path],
                "lines": ["text": line + "\n"],
                "line_number": lineNumber,
                "absolute_offset": byteOffset,
                "submatches": submatches,
            ],
        ]
    }

    private func writeJSON(_ object: [String: Any], to sink: OutputSink) {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.fragmentsAllowed, .withoutEscapingSlashes])
        else { return }
        sink.write(data)
        sink.write("\n")
    }

    /// ripgrep's `elapsed` field shape: `{"secs":N, "nanos":N, "human":"..."}`.
    private func elapsedField(seconds: TimeInterval) -> [String: Any] {
        let secs = Int(seconds)
        let nanos = Int((seconds - Double(secs)) * 1_000_000_000)
        let humanMs = String(format: "%.4fms", seconds * 1000)
        return [
            "secs": secs,
            "nanos": nanos,
            "human": humanMs,
        ]
    }
}
