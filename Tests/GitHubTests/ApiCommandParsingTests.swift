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

    @Test func recognizesGraphQLEndpoint() {
        #expect(ApiCommand.isGraphQLEndpoint("graphql"))
        #expect(ApiCommand.isGraphQLEndpoint("/graphql"))
        #expect(!ApiCommand.isGraphQLEndpoint("repos/cli/cli"))
    }

    @Test func graphqlBodyShapeWithVariablesObject() throws {
        let reshaped = ApiCommand.reshapeGraphQLBody([
            "query": "mutation { x }",
            "variables": ["id": "abc"],
        ])
        let query = reshaped["query"] as? String
        let vars = reshaped["variables"] as? [String: Any]
        #expect(query == "mutation { x }")
        #expect((vars?["id"] as? String) == "abc")
    }

    @Test func graphqlBodyParsesVariablesJSONString() throws {
        let reshaped = ApiCommand.reshapeGraphQLBody([
            "query": "q",
            "variables": #"{"id":42,"draft":true}"#,
        ])
        let vars = reshaped["variables"] as? [String: Any]
        #expect((vars?["id"] as? Int) == 42)
        #expect((vars?["draft"] as? Bool) == true)
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
}
