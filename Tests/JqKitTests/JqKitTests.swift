import Foundation
import Testing
@testable import JqKit

@Suite struct JqKitTests {

    // MARK: - Public Jq facade

    @Test func evalIdentity() throws {
        let input = Data(#"{"a":1}"#.utf8)
        let out = try Jq.eval(filter: ".", on: input)
        #expect(String(decoding: out, as: UTF8.self) == "{\n  \"a\": 1\n}\n")
    }

    @Test func evalFieldAccess() throws {
        let input = Data(#"{"full_name":"Cocoanetics/SwiftPorts"}"#.utf8)
        let out = try Jq.eval(filter: ".full_name", on: input)
        #expect(String(decoding: out, as: UTF8.self) == "\"Cocoanetics/SwiftPorts\"\n")
    }

    @Test func evalStringStripsQuotes() throws {
        let input = Data(#"{"name":"alice"}"#.utf8)
        let out = try Jq.evalString(filter: ".name", on: input)
        #expect(out == ["alice"])
    }

    @Test func evalStringMultipleResults() throws {
        let input = Data(#"[1,2,3]"#.utf8)
        let out = try Jq.evalString(filter: ".[]", on: input)
        #expect(out == ["1", "2", "3"])
    }

    @Test func parseAndEvaluateReuseAcrossInputs() throws {
        let filter = try Jq.parseFilter(".items[] | select(.kind == \"a\") | .id")
        let v1 = try JqJSON.parse(#"{"items":[{"kind":"a","id":1},{"kind":"b","id":2}]}"#)
        let v2 = try JqJSON.parse(#"{"items":[{"kind":"a","id":7},{"kind":"a","id":8}]}"#)
        let r1 = try Jq.evaluate(filter, on: v1).map { JqFormatter.compact($0) }
        let r2 = try Jq.evaluate(filter, on: v2).map { JqFormatter.compact($0) }
        #expect(r1 == ["1"])
        #expect(r2 == ["7", "8"])
    }

    // MARK: - Filter coverage spot checks

    @Test func selectAndFieldFromGitHubLikePayload() throws {
        let payload = Data("""
        {"items":[{"name":"a","draft":true},{"name":"b","draft":false}]}
        """.utf8)
        let names = try Jq.evalString(
            filter: ".items[] | select(.draft == false) | .name",
            on: payload)
        #expect(names == ["b"])
    }

    @Test func arrayConstructionAndArithmetic() throws {
        // evalString mirrors jq's -r: strings come back unquoted,
        // non-strings get the default pretty formatting.
        let out = try Jq.evalString(
            filter: "[.[] * 2]",
            on: Data("[1,2,3]".utf8))
        #expect(out == ["[\n  2,\n  4,\n  6\n]"])
    }

    @Test func lengthBuiltin() throws {
        let out = try Jq.evalString(
            filter: "length",
            on: Data("[10,20,30,40]".utf8))
        #expect(out == ["4"])
    }

    // MARK: - Error surfacing

    @Test func parseErrorsThrowJqError() {
        #expect(throws: JqError.self) {
            _ = try Jq.parseFilter(".a |")
        }
    }
}
