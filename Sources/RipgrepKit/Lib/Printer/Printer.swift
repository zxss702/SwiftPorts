import Foundation
import ShellKit

/// Protocol every output format implements. The engine drives one
/// printer for the whole run.
public protocol Printer: Sendable {
    /// Called once before any file is searched.
    mutating func begin(to sink: OutputSink)

    /// Called for each searched file (whether or not it had matches).
    mutating func emit(_ result: FileSearchResult, to sink: OutputSink)

    /// Called once at the end. Drains buffered state (e.g. JSON
    /// summary, stats line).
    mutating func end(to sink: OutputSink)
}

/// Helpers shared by the concrete printers.
enum PrinterUtil {
    static func wrap(_ s: String,
                     with prefix: String,
                     enabled: Bool) -> String {
        guard enabled, !prefix.isEmpty else { return s }
        return prefix + s + ColorSpec.reset
    }

    /// Highlight match spans with the configured color escapes.
    /// `line` is the source line; `hits` are UTF-8 byte spans into it.
    /// `replace` substitutes match text when set.
    static func renderLine(_ line: String,
                           hits: [PatternMatcher.Hit],
                           opts: PrinterOptions) -> String {
        // Trim if requested — adjust hits accordingly.
        var work = line
        var hitOffsets = hits
        if opts.trim {
            let before = work
            work = String(work.drop(while: { $0 == " " || $0 == "\t" }))
            let dropped = before.utf8.count - work.utf8.count
            hitOffsets = hits.map {
                PatternMatcher.Hit(utf8Start: max(0, $0.utf8Start - dropped),
                                   utf8End: max(0, $0.utf8End - dropped))
            }
        }

        // Long-line guard.
        if let max = opts.maxColumns, work.count > max {
            if opts.maxColumnsPreview {
                return String(work.prefix(max)) + "[..]"
            }
            return "[Omitted long line with \(work.count) characters]"
        }

        // No highlight requested → just substitute and return.
        if opts.replace != nil || !opts.color || hitOffsets.isEmpty {
            return applyReplace(line: work, hits: hitOffsets, opts: opts)
        }

        // Highlight in original-text order.
        let lineBytes = Array(work.utf8)
        var out = ""
        out.reserveCapacity(work.count + hitOffsets.count * 16)
        var cursor = 0
        for hit in hitOffsets.sorted(by: { $0.utf8Start < $1.utf8Start }) {
            if hit.utf8Start > cursor {
                out += String(decoding: lineBytes[cursor..<hit.utf8Start],
                              as: UTF8.self)
            }
            out += opts.colorSpec.matched
            out += String(decoding: lineBytes[hit.utf8Start..<hit.utf8End],
                          as: UTF8.self)
            out += ColorSpec.reset
            cursor = hit.utf8End
        }
        if cursor < lineBytes.count {
            out += String(decoding: lineBytes[cursor..<lineBytes.count],
                          as: UTF8.self)
        }
        return out
    }

    /// Apply `--replace` text without highlighting.
    private static func applyReplace(line: String,
                                     hits: [PatternMatcher.Hit],
                                     opts: PrinterOptions) -> String {
        guard let rep = opts.replace, !hits.isEmpty else { return line }
        let bytes = Array(line.utf8)
        var out = ""
        out.reserveCapacity(line.count)
        var cursor = 0
        for hit in hits.sorted(by: { $0.utf8Start < $1.utf8Start }) {
            if hit.utf8Start > cursor {
                out += String(decoding: bytes[cursor..<hit.utf8Start], as: UTF8.self)
            }
            out += rep
            cursor = hit.utf8End
        }
        if cursor < bytes.count {
            out += String(decoding: bytes[cursor..<bytes.count], as: UTF8.self)
        }
        return out
    }

    /// Resolve the path printed in output, honoring `--path-separator`.
    static func formatPath(_ path: String, opts: PrinterOptions) -> String {
        guard let sep = opts.pathSeparator else { return path }
        return path.replacingOccurrences(of: "/", with: sep)
    }
}
