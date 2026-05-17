import Foundation
import Testing
@testable import RipgrepKit

@Suite struct SearcherTests {

    private func matcher(_ patterns: String..., literal: Bool = false) throws -> PatternMatcher {
        var opts = PatternOptions()
        opts.patterns = patterns
        opts.fixedStrings = literal
        return try PatternMatcher(opts)
    }

    @Test func findsMultiLineMatches() throws {
        let s = Searcher(matcher: try matcher("beta"))
        let r = s.search(displayPath: "x",
                         data: Data("alpha\nbeta\ngamma\nbeta-2\n".utf8))
        #expect(r.lineMatches == 2)
        #expect(r.totalMatches == 2)
        #expect(r.chunks.count == 2)
        #expect(r.chunks[0].match.line == "beta")
        #expect(r.chunks[1].match.line == "beta-2")
    }

    @Test func contextBeforeAfter() throws {
        var so = SearchOptions()
        so.beforeContext = 1
        so.afterContext = 1
        let s = Searcher(matcher: try matcher("beta"), options: so)
        let r = s.search(displayPath: "x",
                         data: Data("a\nbeta\nc\nd\nbeta\nf\n".utf8))
        // Two matches at line 2 and 5. before=[a], after=[c]; before=[d], after=[f].
        #expect(r.chunks.count == 2)
        #expect(r.chunks[0].before.map(\.line) == ["a"])
        #expect(r.chunks[0].after.map(\.line) == ["c"])
        #expect(r.chunks[1].before.map(\.line) == ["d"])
        #expect(r.chunks[1].after.map(\.line) == ["f"])
    }

    @Test func maxCountStopsScan() throws {
        var so = SearchOptions()
        so.maxCount = 2
        let s = Searcher(matcher: try matcher("x"), options: so)
        let r = s.search(displayPath: "y",
                         data: Data("x\nx\nx\nx\nx\n".utf8))
        #expect(r.lineMatches == 2)
    }

    @Test func binaryDetection() throws {
        let s = Searcher(matcher: try matcher("hi"))
        var bytes: [UInt8] = Array("hi there".utf8)
        bytes.append(0x00) // NUL → binary
        bytes.append(contentsOf: Array("more".utf8))
        let r = s.search(displayPath: "b", data: Data(bytes))
        #expect(r.binary)
        // Binary file with a match emits a summary chunk-less result.
        #expect(r.hasMatch)
        #expect(r.chunks.isEmpty)
    }

    @Test func binaryAsTextPassesThrough() throws {
        var so = SearchOptions()
        so.binaryAsText = true
        let s = Searcher(matcher: try matcher("hi"), options: so)
        var bytes: [UInt8] = Array("hi there".utf8)
        bytes.append(0x00)
        bytes.append(contentsOf: Array("\nbye\n".utf8))
        let r = s.search(displayPath: "b", data: Data(bytes))
        #expect(!r.binary)
        #expect(r.hasMatch)
    }

    @Test func crlfHandling() throws {
        var so = SearchOptions()
        so.crlf = true
        let s = Searcher(matcher: try matcher("end$"), options: so)
        let r = s.search(displayPath: "x",
                         data: Data("foo end\r\nbar\r\n".utf8))
        #expect(r.lineMatches == 1)
    }

    @Test func invertMatchReportsNonMatches() throws {
        var pat = PatternOptions()
        pat.patterns = ["b"]
        pat.invertMatch = true
        let s = Searcher(matcher: try PatternMatcher(pat))
        let r = s.search(displayPath: "x", data: Data("a\nb\nc\n".utf8))
        #expect(r.lineMatches == 2)
        #expect(r.chunks.map(\.match.line) == ["a", "c"])
    }
}
