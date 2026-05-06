import ArgumentParser
import Foundation
import Testing
@testable import GitHub
@testable import GhCommand

@Suite struct ApiCommandParsingTests {
    @Test func defaultsToGet() throws {
        let cmd = try ApiCommand.parse(["repos/cli/cli"])
        #expect(cmd.endpoint == "repos/cli/cli")
        #expect(cmd.method == "GET")
        #expect(cmd.fields.isEmpty)
        #expect(cmd.rawFields.isEmpty)
        #expect(cmd.inputFile == nil)
    }

    @Test func acceptsMethodOverride() throws {
        let cmd = try ApiCommand.parse(["-X", "DELETE", "/x"])
        #expect(cmd.method == "DELETE")
    }

    @Test func collectsFields() throws {
        let cmd = try ApiCommand.parse([
            "x", "-F", "title=hi", "-F", "draft=true", "-f", "body=raw",
        ])
        #expect(cmd.fields == ["title=hi", "draft=true"])
        #expect(cmd.rawFields == ["body=raw"])
    }

    @Test func parsesJqShortAndLongFlags() throws {
        let short = try ApiCommand.parse(["repos/x", "-q", ".name"])
        #expect(short.jqFilter == ".name")
        let long = try ApiCommand.parse(["repos/x", "--jq", ".full_name"])
        #expect(long.jqFilter == ".full_name")
    }

    @Test func parsesInputFileFlag() throws {
        let path = try ApiCommand.parse(["graphql", "--input", "body.json"])
        #expect(path.inputFile == "body.json")
        let stdin = try ApiCommand.parse(["graphql", "--input", "-"])
        #expect(stdin.inputFile == "-")
    }

    @Test func recognizesGraphQLEndpoint() {
        #expect(ApiCommand.isGraphQLEndpoint("graphql"))
        #expect(ApiCommand.isGraphQLEndpoint("/graphql"))
        #expect(!ApiCommand.isGraphQLEndpoint("repos/cli/cli"))
    }

    @Test func graphqlBodyShapeWithVariablesObject() throws {
        // A variables value supplied as a Swift dictionary is passed
        // through to the variables map under the key `variables`. This
        // matches upstream: the `variables` field name is NOT special-
        // cased — only `query` and `operationName` are.
        let reshaped = ApiCommand.reshapeGraphQLBody([
            "query": "mutation { x }",
            "id": "abc",
        ])
        let query = reshaped["query"] as? String
        let vars = reshaped["variables"] as? [String: Any]
        #expect(query == "mutation { x }")
        #expect((vars?["id"] as? String) == "abc")
    }

    @Test func graphqlBodyTreatsVariablesKeyAsRegularVariable() throws {
        // Strict upstream parity: -F variables=<json> does NOT special-
        // parse. Object-shaped variables go through --input.
        let reshaped = ApiCommand.reshapeGraphQLBody([
            "query": "q",
            "variables": #"{"id":42}"#,
        ])
        let vars = reshaped["variables"] as? [String: Any]
        #expect((vars?["variables"] as? String) == #"{"id":42}"#)
    }

    @Test func graphqlBodyFoldsExtraFieldsIntoVariables() throws {
        let reshaped = ApiCommand.reshapeGraphQLBody([
            "query": "q",
            "id": 7,
            "title": "hello",
        ])
        let vars = reshaped["variables"] as? [String: Any]
        #expect((vars?["id"] as? Int) == 7)
        #expect((vars?["title"] as? String) == "hello")
    }

    @Test func graphqlBodyDefaultsMissingQueryToEmpty() throws {
        let reshaped = ApiCommand.reshapeGraphQLBody(["foo": "bar"])
        #expect((reshaped["query"] as? String) == "")
        let vars = reshaped["variables"] as? [String: Any]
        #expect((vars?["foo"] as? String) == "bar")
    }

    @Test func graphqlBodyOmitsVariablesWhenEmpty() throws {
        // Upstream omits `variables` from the request envelope when no
        // variables were supplied — matters for queries that take no
        // arguments.
        let reshaped = ApiCommand.reshapeGraphQLBody(["query": "{ viewer { login } }"])
        #expect(reshaped["variables"] == nil)
    }

    @Test func graphqlBodyPreservesOperationNameAtTopLevel() throws {
        // Multi-operation documents need operationName as a top-level
        // field, not as a variable.
        let reshaped = ApiCommand.reshapeGraphQLBody([
            "query": "query A { a } query B { b }",
            "operationName": "B",
            "id": 7,
        ])
        #expect((reshaped["operationName"] as? String) == "B")
        let vars = reshaped["variables"] as? [String: Any]
        #expect(vars?["operationName"] == nil)
        #expect((vars?["id"] as? Int) == 7)
    }

    @Test func graphqlBodyOmitsOperationNameWhenAbsent() throws {
        let reshaped = ApiCommand.reshapeGraphQLBody(["query": "{ a }"])
        #expect(reshaped["operationName"] == nil)
    }

    // MARK: --input round-trip

    @Test func inputFileReadsBytesVerbatimFromDisk() throws {
        // Round-trip parity check, mirroring the createCommitOnBranch
        // pattern from PR #19: a JSON body with a nested `input` object
        // goes through --input <file> and comes out byte-for-byte.
        let body = #"""
        {
          "query": "mutation($input: CreateCommitOnBranchInput!) { createCommitOnBranch(input: $input) { commit { oid } } }",
          "variables": {
            "input": {
              "branch": { "repositoryNameWithOwner": "Cocoanetics/SwiftPorts", "branchName": "main" },
              "message": { "headline": "test" },
              "expectedHeadOid": "0000000000000000000000000000000000000000",
              "fileChanges": { "additions": [] }
            }
          }
        }
        """#
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("api-input-\(UUID().uuidString).json")
        try body.data(using: .utf8)!.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let read = try ApiCommand.readInputFile(tmp.path)
        #expect(String(data: read, encoding: .utf8) == body)

        // The bytes must round-trip through JSONSerialization unchanged
        // in shape — i.e., the nested `input` object is still an
        // object, not a string. This is the assertion that demonstrates
        // the gap in -F is plugged by --input.
        let parsed = try JSONSerialization.jsonObject(with: read) as? [String: Any]
        let variables = parsed?["variables"] as? [String: Any]
        let input = variables?["input"] as? [String: Any]
        #expect(input != nil)
        #expect((input?["expectedHeadOid"] as? String) == "0000000000000000000000000000000000000000")
    }

    @Test func inputFileMissingPathThrows() throws {
        #expect(throws: (any Error).self) {
            _ = try ApiCommand.readInputFile("/definitely/not/a/real/path-\(UUID().uuidString).json")
        }
    }

    // MARK: queryStringValue serialisation (used when --input + -f/-F mix)

    @Test func queryStringValueSerialisesScalarsLikeUpstream() {
        // Mirrors upstream's addQueryParam: bool → "true"/"false",
        // int/double → decimal string, string → as-is, null → "".
        #expect(ApiCommand.queryStringValue("hi") == "hi")
        #expect(ApiCommand.queryStringValue(true) == "true")
        #expect(ApiCommand.queryStringValue(false) == "false")
        #expect(ApiCommand.queryStringValue(7) == "7")
        #expect(ApiCommand.queryStringValue(1.5) == "1.5")
        #expect(ApiCommand.queryStringValue(NSNull()) == "")
    }

    @Test func fieldFlagsBecomeQueryItemsWhenInputIsUsed() throws {
        // Per upstream `gh api` manual: with --input, field flags get
        // appended to the endpoint URL's query string instead of being
        // dropped. Order must match upstream: -f raw fields first, then
        // -F typed fields, with -F values coerced.
        let items = try ApiCommand.buildQueryItems(
            rawFields: ["q=swift"],
            fields: ["per_page=1", "draft=true"]
        )
        #expect(items.count == 3)
        #expect(items[0].name == "q" && items[0].value == "swift")
        #expect(items[1].name == "per_page" && items[1].value == "1")
        #expect(items[2].name == "draft" && items[2].value == "true")
    }
}
