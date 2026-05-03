import Foundation
import Testing
@testable import SwiftGHCore

@Suite struct PaginationTests {
    @Test func parsesNextRel() {
        let header = """
            <https://api.github.com/repos/cli/cli/issues?page=2>; rel="next", \
            <https://api.github.com/repos/cli/cli/issues?page=10>; rel="last"
            """
        let next = LinkHeader.url(for: "next", in: header)
        #expect(next?.absoluteString == "https://api.github.com/repos/cli/cli/issues?page=2")
    }

    @Test func parsesLastRel() {
        let header = """
            <https://api.github.com/x?page=2>; rel="next", \
            <https://api.github.com/x?page=10>; rel="last"
            """
        #expect(LinkHeader.url(for: "last", in: header)?.absoluteString
                == "https://api.github.com/x?page=10")
    }

    @Test func returnsNilWhenRelMissing() {
        let header = #"<https://api.github.com/x?page=2>; rel="next""#
        #expect(LinkHeader.url(for: "prev", in: header) == nil)
    }

    @Test func handlesEmptyHeader() {
        #expect(LinkHeader.url(for: "next", in: "") == nil)
    }
}
