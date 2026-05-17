import Foundation
import Testing
@testable import RipgrepKit

@Suite struct TypeRegistryTests {

    @Test func resolvesDefaultType() {
        let r = TypeRegistry.default
        let g = r.globs(forType: "swift")
        #expect(g == ["*.swift"])
    }

    @Test func aliasesShareGlobs() {
        let r = TypeRegistry.default
        #expect(r.globs(forType: "py") == r.globs(forType: "python"))
        #expect(r.globs(forType: "md") == r.globs(forType: "markdown"))
    }

    @Test func addUserTypespec() throws {
        var r = TypeRegistry.default
        try r.add("foo:*.foo")
        try r.add("foo:*.fool")
        let globs = r.globs(forType: "foo")
        #expect(globs?.contains("*.foo") == true)
        #expect(globs?.contains("*.fool") == true)
    }

    @Test func addIncludeChain() throws {
        var r = TypeRegistry.default
        try r.add("frontend:include:js")
        #expect(r.globs(forType: "frontend")?.contains("*.js") == true)
    }

    @Test func clearRemovesType() throws {
        var r = TypeRegistry.default
        r.clear("swift")
        #expect(r.globs(forType: "swift") == nil)
    }

    @Test func invalidSpecThrows() {
        var r = TypeRegistry.default
        do {
            try r.add("no-colon")
            Issue.record("expected throw")
        } catch is TypeRegistryError {
            // ok
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }
}
