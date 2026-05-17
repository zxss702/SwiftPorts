import Foundation

/// Per-file/per-buffer search engine. Reads bytes (from a path or
/// in-memory buffer), splits them on the configured line terminator,
/// runs the `PatternMatcher`, and returns a `FileSearchResult` ready
/// for the printer.
///
/// Designed to be cheap to construct — the heavy state (compiled
/// regex) sits inside the `PatternMatcher` the caller passes in.
public struct Searcher: Sendable {

    public var matcher: PatternMatcher
    public var options: SearchOptions

    public init(matcher: PatternMatcher,
                options: SearchOptions = SearchOptions()) {
        self.matcher = matcher
        self.options = options
    }

    /// Search a file on disk. Returns `nil` if the file couldn't be
    /// opened (permission denied / vanished).
    public func searchFile(displayPath: String,
                           url: URL) throws -> FileSearchResult? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return search(displayPath: displayPath, data: data)
    }

    /// Search an in-memory buffer. Suitable for stdin or for unit
    /// tests that don't want to touch disk.
    public func search(displayPath: String, data: Data) -> FileSearchResult {
        // Binary detection — look for NUL in the first 8 KiB.
        let probe = data.prefix(8 * 1024)
        let isBinary = probe.contains(0x00)
        if isBinary && !options.binaryAsText && !options.searchBinary {
            // Run the match just to know if it matched; if so, emit
            // the terse "binary file matches" chunk via a zero-length
            // line match so the printer can format it.
            if let text = decode(data: data, lossy: true),
               anyMatchInWholeFile(text: text) {
                return FileSearchResult(
                    displayPath: displayPath,
                    lineMatches: 1,
                    totalMatches: 1,
                    chunks: [],
                    binary: true,
                    bytesSearched: data.count)
            }
            return FileSearchResult(displayPath: displayPath,
                                    lineMatches: 0, totalMatches: 0,
                                    chunks: [], binary: true,
                                    bytesSearched: data.count)
        }

        guard let text = decode(data: data, lossy: true) else {
            return FileSearchResult(displayPath: displayPath,
                                    lineMatches: 0, totalMatches: 0,
                                    chunks: [], binary: false,
                                    bytesSearched: data.count)
        }
        return scan(displayPath: displayPath, text: text, totalBytes: data.count)
    }

    /// Run the matcher over the whole file text — used by binary-file
    /// fast-path detection, which doesn't need per-line splitting.
    private func anyMatchInWholeFile(text: String) -> Bool {
        if matcher.options.invertMatch { return true }
        return matcher.isMatch(line: text)
    }

    /// Single-line scan. Splits `text` into logical lines, runs the
    /// matcher, and collates chunks with their requested context.
    private func scan(displayPath: String,
                      text: String,
                      totalBytes: Int) -> FileSearchResult {
        // Logical line terminator. nullData replaces the standard
        // `\n` split.
        let terminator: Character = options.nullData ? "\0" : "\n"
        var lines: [String] = []
        if options.nullData {
            lines = text.split(separator: "\0",
                               omittingEmptySubsequences: false)
                .map(String.init)
        } else {
            lines = text.split(separator: "\n",
                               omittingEmptySubsequences: false)
                .map(String.init)
        }
        // `split` produces a trailing empty element when the file ends
        // with a terminator. Drop it so we don't report a phantom
        // last line.
        if lines.last == "" { lines.removeLast() }

        // Byte offsets per logical line: cumulative running byte count.
        var byteOffsets: [Int] = []
        byteOffsets.reserveCapacity(lines.count)
        var running = 0
        for line in lines {
            byteOffsets.append(running)
            running += line.utf8.count + 1
            // +1 for the terminator byte the split stripped.
            _ = terminator
        }

        struct LineEval {
            var line: String
            var lineNumber: Int
            var byteOffset: Int
            var hits: [PatternMatcher.Hit]
            var isMatch: Bool
        }

        var evals: [LineEval] = []
        evals.reserveCapacity(lines.count)
        var totalMatched = 0
        var totalHits = 0

        for (idx, raw) in lines.enumerated() {
            var lineText = raw
            if options.crlf && lineText.hasSuffix("\r") {
                lineText.removeLast()
            }
            // For invert-match we still run the regex to know if the
            // line matches — we just flip the decision and drop the
            // hits (an inverted match has no highlight regions).
            let rawHits = matcher.findAll(in: lineText)
            let actualMatch = !rawHits.isEmpty
            let matched = matcher.options.invertMatch ? !actualMatch : actualMatch
            let displayHits = matcher.options.invertMatch ? [] : rawHits
            if matched {
                if let cap = options.maxCount, totalMatched >= cap {
                    break
                }
                totalMatched += 1
                totalHits += matcher.options.invertMatch ? 1 : rawHits.count
            }
            if options.stopOnNonmatch && !matched && totalMatched > 0 {
                break
            }
            evals.append(LineEval(line: lineText,
                                  lineNumber: idx + 1,
                                  byteOffset: byteOffsets[idx],
                                  hits: displayHits,
                                  isMatch: matched))
        }

        // Build chunks. For each matching line, gather the requested
        // before/after context. Adjacent matches with overlapping
        // context share the same printer chunk to avoid duplicates,
        // but for simplicity we emit independent chunks here — the
        // printer can collapse separators.
        var chunks: [SearchChunk] = []
        var lastEmittedIndex = -1
        for (i, eval) in evals.enumerated() {
            guard eval.isMatch else { continue }

            // before-context: previous N evals (capped at lastEmittedIndex)
            var before: [ContextLine] = []
            let beforeStart = max(0, i - options.beforeContext,
                                  lastEmittedIndex + 1)
            if beforeStart < i {
                for j in beforeStart..<i {
                    let e = evals[j]
                    before.append(ContextLine(lineNumber: e.lineNumber,
                                              byteOffset: e.byteOffset,
                                              line: e.line))
                }
            }
            // after-context: next N evals
            var after: [ContextLine] = []
            let afterEnd = min(evals.count, i + 1 + options.afterContext)
            if afterEnd > i + 1 {
                for j in (i + 1)..<afterEnd {
                    let e = evals[j]
                    // Don't include a future match line here — it'll
                    // be its own chunk.
                    if e.isMatch { break }
                    after.append(ContextLine(lineNumber: e.lineNumber,
                                             byteOffset: e.byteOffset,
                                             line: e.line))
                }
            }
            let matchLine = LineMatch(
                lineNumber: eval.lineNumber,
                byteOffset: eval.byteOffset,
                line: eval.line,
                hits: eval.hits)
            chunks.append(SearchChunk(before: before,
                                      match: matchLine,
                                      after: after))
            lastEmittedIndex = i + after.count
        }

        return FileSearchResult(displayPath: displayPath,
                                lineMatches: totalMatched,
                                totalMatches: totalHits,
                                chunks: chunks,
                                binary: false,
                                bytesSearched: totalBytes)
    }

    /// Decode `data` to a `String` honoring `options.encoding` and BOM
    /// sniffing. Falls back to lossy UTF-8 if the encoding can't be
    /// determined.
    private func decode(data: Data, lossy: Bool) -> String? {
        if let enc = options.encoding {
            return String(data: data, encoding: enc)
        }
        // BOM sniffing.
        if data.count >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        if data.count >= 2, data[0] == 0xFF, data[1] == 0xFE {
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        }
        if data.count >= 2, data[0] == 0xFE, data[1] == 0xFF {
            return String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        }
        // Lossy UTF-8.
        return String(decoding: data, as: UTF8.self)
    }
}
