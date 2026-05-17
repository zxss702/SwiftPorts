import Foundation
import Testing
@testable import RipgrepKit

@Suite struct PatternMatcherTests {

    @Test func plainRegexHits() throws {
        var opts = PatternOptions()
        opts.patterns = ["fo+"]
        let m = try PatternMatcher(opts)
        let hits = m.findAll(in: "foo bar foo")
        #expect(hits.count == 2)
        #expect(hits[0].utf8Start == 0)
        #expect(hits[0].utf8End == 3)
        #expect(hits[1].utf8Start == 8)
        #expect(hits[1].utf8End == 11)
    }

    @Test func fixedStringsEscape() throws {
        var opts = PatternOptions()
        opts.patterns = ["a.c"]
        opts.fixedStrings = true
        let m = try PatternMatcher(opts)
        #expect(m.findAll(in: "a.c").count == 1)
        #expect(m.findAll(in: "abc").isEmpty)
    }

    @Test func ignoreCaseOverridesCase() throws {
        var opts = PatternOptions()
        opts.patterns = ["Beta"]
        opts.caseMode = .ignoreCase
        let m = try PatternMatcher(opts)
        #expect(m.isMatch(line: "BETA"))
        #expect(m.isMatch(line: "beta"))
    }

    @Test func smartCaseRespectsUppercase() throws {
        var lower = PatternOptions()
        lower.patterns = ["beta"]
        lower.caseMode = .smartCase
        let lowerM = try PatternMatcher(lower)
        #expect(lowerM.isMatch(line: "BETA"))

        var upper = PatternOptions()
        upper.patterns = ["Beta"]
        upper.caseMode = .smartCase
        let upperM = try PatternMatcher(upper)
        #expect(!upperM.isMatch(line: "beta"))
        #expect(upperM.isMatch(line: "Beta"))
    }

    @Test func wordBoundary() throws {
        var opts = PatternOptions()
        opts.patterns = ["beta"]
        opts.wordRegexp = true
        let m = try PatternMatcher(opts)
        #expect(m.isMatch(line: "beta line"))
        #expect(!m.isMatch(line: "alphabeta"))
    }

    @Test func lineAnchored() throws {
        var opts = PatternOptions()
        opts.patterns = ["hello"]
        opts.lineRegexp = true
        let m = try PatternMatcher(opts)
        #expect(m.isMatch(line: "hello"))
        #expect(!m.isMatch(line: "hello world"))
    }

    @Test func multiPatternOR() throws {
        var opts = PatternOptions()
        opts.patterns = ["foo", "bar"]
        let m = try PatternMatcher(opts)
        #expect(m.isMatch(line: "foo"))
        #expect(m.isMatch(line: "bar"))
        #expect(!m.isMatch(line: "baz"))
    }

    @Test func invertMatch() throws {
        var opts = PatternOptions()
        opts.patterns = ["foo"]
        opts.invertMatch = true
        let m = try PatternMatcher(opts)
        #expect(!m.isMatch(line: "foobar"))
        #expect(m.isMatch(line: "alphabet"))
    }
}
