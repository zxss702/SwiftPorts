import Foundation
import Testing
@testable import FdKit

@Suite struct PatternMatcherTests {

    @Test func emptyPatternMatchesEverything() throws {
        let m = try PatternMatcher(PatternOptions())
        #expect(m.matches(basename: "foo.txt", relativePath: "a/foo.txt"))
        #expect(m.matches(basename: "bar", relativePath: "bar"))
    }

    @Test func regexAgainstBasename() throws {
        var opts = PatternOptions()
        opts.pattern = "txt$"
        let m = try PatternMatcher(opts)
        #expect(m.matches(basename: "foo.txt", relativePath: "a/foo.txt"))
        #expect(!m.matches(basename: "foo.md", relativePath: "a/foo.md"))
    }

    @Test func smartCaseLowercaseIsCaseInsensitive() throws {
        var opts = PatternOptions()
        opts.pattern = "foo"
        opts.caseMode = .smartCase
        let m = try PatternMatcher(opts)
        #expect(m.matches(basename: "FOO.txt", relativePath: "FOO.txt"))
    }

    @Test func smartCaseUppercaseIsCaseSensitive() throws {
        var opts = PatternOptions()
        opts.pattern = "Foo"
        opts.caseMode = .smartCase
        let m = try PatternMatcher(opts)
        #expect(m.matches(basename: "Foo.txt", relativePath: "Foo.txt"))
        #expect(!m.matches(basename: "foo.txt", relativePath: "foo.txt"))
    }

    @Test func fixedStringEscapesMetachars() throws {
        var opts = PatternOptions()
        opts.pattern = "a.c"
        opts.syntax = .fixedString
        opts.caseMode = .caseSensitive
        let m = try PatternMatcher(opts)
        #expect(m.matches(basename: "xa.cy", relativePath: "xa.cy"))
        #expect(!m.matches(basename: "abc", relativePath: "abc"))
    }

    @Test func globAgainstBasename() throws {
        var opts = PatternOptions()
        opts.pattern = "*.swift"
        opts.syntax = .glob
        let m = try PatternMatcher(opts)
        #expect(m.matches(basename: "foo.swift", relativePath: "a/foo.swift"))
        #expect(!m.matches(basename: "foo.txt", relativePath: "a/foo.txt"))
    }

    @Test func fullPathSwitchUsesRelativePath() throws {
        var opts = PatternOptions()
        opts.pattern = "src/.*\\.swift"
        opts.matchFullPath = true
        let m = try PatternMatcher(opts)
        #expect(m.matches(basename: "foo.swift", relativePath: "src/foo.swift"))
        #expect(!m.matches(basename: "foo.swift", relativePath: "lib/foo.swift"))
    }

    @Test func extensionFilterAcceptsExtensionOnly() throws {
        var opts = PatternOptions()
        opts.extensions = ["swift"]
        let m = try PatternMatcher(opts)
        #expect(m.matches(basename: "foo.swift", relativePath: "foo.swift"))
        #expect(!m.matches(basename: "foo.txt", relativePath: "foo.txt"))
    }

    @Test func extensionFilterIsCaseInsensitive() throws {
        var opts = PatternOptions()
        opts.extensions = ["SWIFT"]
        let m = try PatternMatcher(opts)
        #expect(m.matches(basename: "Foo.swift", relativePath: "Foo.swift"))
    }

    @Test func compoundExtensionMatchTarGz() throws {
        var opts = PatternOptions()
        opts.extensions = ["tar.gz"]
        let m = try PatternMatcher(opts)
        #expect(m.matches(basename: "backup.tar.gz",
                          relativePath: "backup.tar.gz"))
        #expect(!m.matches(basename: "backup.zip",
                           relativePath: "backup.zip"))
    }

    @Test func invalidRegexThrows() {
        var opts = PatternOptions()
        opts.pattern = "("
        opts.caseMode = .caseSensitive
        #expect(throws: FdPatternError.self) {
            _ = try PatternMatcher(opts)
        }
    }
}
