import ArgumentParser
import Foundation
import HTTPTypes
import GitHub
import JqKit

struct ApiCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "api",
        abstract: "Make an authenticated GitHub API request.",
        discussion: """
        Send a request to the GitHub REST API and print the response.

        Without -X, GET is used; supplying -F or --input switches to POST.

        --jq <filter> runs the response body through an in-process jq
        engine (JqKit) and prints the filter result instead of the raw
        JSON response.

        When the endpoint is `graphql`, -f/-F build a GraphQL request
        body of the form `{"query": ..., "variables": {...}}`. `-f
        query=...` supplies the query string; `-F variables=...` sets
        the variables object (parsed from JSON if the value looks like
        an object), and any remaining -f/-F fields are merged into
        `variables`.

        Examples:
          gh api repos/cli/cli
          gh api repos/cli/cli/releases/latest
          gh api -X POST repos/{owner}/{repo}/issues -f title="Hi" -f body="…"
          gh api repos/cli/cli --jq '.full_name'
          gh api graphql -f query='query { viewer { login } }'
        """
    )

    @Argument(help: "API endpoint, e.g. 'repos/cli/cli' or '/users/octocat'.")
    var endpoint: String

    @Option(name: [.customShort("X"), .customLong("method")],
            help: "HTTP method (GET, POST, PATCH, PUT, DELETE, HEAD).")
    var method: String = "GET"

    @Option(name: [.customShort("F"), .customLong("field")],
            parsing: .singleValue,
            help: "Add a typed field to the request body. KEY=VALUE; values 'true'/'false'/numerics are encoded as such.")
    var fields: [String] = []

    @Option(name: [.customShort("f"), .customLong("raw-field")],
            parsing: .singleValue,
            help: "Add a string field to the request body. KEY=VALUE.")
    var rawFields: [String] = []

    @Option(name: .customLong("hostname"),
            help: "GitHub host. Defaults to github.com (or $GH_HOST).")
    var hostname: String?

    @Flag(name: [.customShort("i"), .customLong("include")],
          help: "Include HTTP response status line and headers.")
    var includeHeaders: Bool = false

    @Option(name: [.customShort("q"), .customLong("jq")],
            help: "Run a jq filter over the response body before printing.")
    var jqFilter: String?

    func run() async throws {
        let client = try await CommandContext.apiClient(host: hostname)

        let body = try buildBody()

        // GraphQL is always POST. -f / -F also implies POST when the
        // user didn't override the method. Matches upstream gh.
        let effectiveMethod: String
        if method == "GET" && (body != nil || Self.isGraphQLEndpoint(endpoint)) {
            effectiveMethod = "POST"
        } else {
            effectiveMethod = method
        }

        let httpMethod = HTTPRequest.Method(effectiveMethod.uppercased())
            ?? HTTPRequest.Method(effectiveMethod)
        guard let httpMethod else {
            throw ValidationError("Unsupported method: \(method)")
        }
        let response = try await client.raw(
            method: httpMethod,
            path: endpoint,
            body: body
        )

        if includeHeaders {
            print("HTTP \(response.status)")
            if let ct = response.contentType { print("Content-Type: \(ct)") }
            print("")
        }

        let isJSON = response.contentType?.contains("json") ?? false

        if let filter = jqFilter, isJSON {
            do {
                let lines = try Jq.evalString(filter: filter, on: response.body)
                for line in lines { print(line) }
            } catch let e as JqError {
                throw ValidationError("jq: \(e.message)")
            }
            return
        }

        if isJSON {
            print(JSONPretty.string(from: response.body))
        } else {
            print(String(data: response.body, encoding: .utf8) ?? "")
        }
    }

    private func buildBody() throws -> Data? {
        guard !fields.isEmpty || !rawFields.isEmpty else { return nil }
        var dict: [String: Any] = [:]
        for raw in rawFields {
            let (k, v) = try splitField(raw)
            dict[k] = v
        }
        for typed in fields {
            let (k, v) = try splitField(typed)
            dict[k] = coerce(v)
        }

        if Self.isGraphQLEndpoint(endpoint) {
            dict = Self.reshapeGraphQLBody(dict)
        }

        return try JSONSerialization.data(withJSONObject: dict, options: [])
    }

    static func isGraphQLEndpoint(_ endpoint: String) -> Bool {
        let trimmed = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed == "graphql"
    }

    /// Reshape `{query: ..., variables: ..., operationName: ..., ...rest}`
    /// into the GraphQL request envelope `{query, variables, operationName}`.
    /// Mirrors upstream `gh api`'s GraphQL handling: `query` and
    /// `operationName` stay at the top level (operationName is needed
    /// for multi-operation documents like `query A {…} query B {…}`),
    /// `variables` is treated as the variables object (parsed from a
    /// JSON string when the user passes `-F variables='{…}'`), and any
    /// remaining `-f`/`-F` fields fold into variables.
    static func reshapeGraphQLBody(_ dict: [String: Any]) -> [String: Any] {
        var rest = dict
        let query = rest.removeValue(forKey: "query") ?? ""
        let operationName = rest.removeValue(forKey: "operationName")

        var variables: [String: Any] = [:]
        if let rawVars = rest.removeValue(forKey: "variables") {
            if let obj = rawVars as? [String: Any] {
                variables = obj
            } else if let s = rawVars as? String,
                      let data = s.data(using: .utf8),
                      let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                variables = parsed
            }
        }
        for (k, v) in rest { variables[k] = v }

        var body: [String: Any] = ["query": query, "variables": variables]
        if let operationName { body["operationName"] = operationName }
        return body
    }

    private func splitField(_ s: String) throws -> (String, String) {
        guard let eq = s.firstIndex(of: "=") else {
            throw ValidationError("Field '\(s)' must be KEY=VALUE")
        }
        let key = String(s[..<eq])
        let value = String(s[s.index(after: eq)...])
        return (key, value)
    }

    private func coerce(_ value: String) -> Any {
        switch value.lowercased() {
        case "true": return true
        case "false": return false
        case "null": return NSNull()
        default: break
        }
        if let i = Int(value) { return i }
        if let d = Double(value) { return d }
        return value
    }
}
