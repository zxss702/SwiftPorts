import Foundation
import Testing
@testable import RipgrepKit

@Suite struct IgnoreSetTests {

    @Test func parsesBlankAndCommentLines() {
        let text = """
        # comment
        node_modules/

        *.log
        !important.log
        """
        let entries = IgnoreSet.parse(contents: text, baseRelativeToRoot: "")
        #expect(entries.count == 3)
        #expect(entries[0].glob.originalPattern == "node_modules/")
        #expect(entries[1].glob.originalPattern == "*.log")
        #expect(entries[2].glob.originalPattern == "!important.log")
        #expect(entries[2].glob.isNegation)
    }

    @Test func decidesIgnoredAndAllowedPaths() throws {
        var set = IgnoreSet()
        set.append(contentsOf: IgnoreSet.parse(
            contents: "*.log\n!keep.log\n", baseRelativeToRoot: ""))
        #expect(set.decide(pathRelativeToRoot: "a.log",
                           isDirectory: false) == .ignore)
        #expect(set.decide(pathRelativeToRoot: "keep.log",
                           isDirectory: false) == .allow)
        #expect(set.decide(pathRelativeToRoot: "a.txt",
                           isDirectory: false) == .none)
    }

    @Test func subdirectoryIgnoreScopedToBase() throws {
        var set = IgnoreSet()
        set.append(contentsOf: IgnoreSet.parse(
            contents: "/secret.txt\n", baseRelativeToRoot: "sub"))
        #expect(set.decide(pathRelativeToRoot: "sub/secret.txt",
                           isDirectory: false) == .ignore)
        // Pattern is anchored to `sub`; root-level secret.txt isn't matched.
        #expect(set.decide(pathRelativeToRoot: "secret.txt",
                           isDirectory: false) == .none)
    }
}
