import ArgumentParser
import Foundation
import HTTPTypes
import GitLab

struct ApiCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "api",
        abstract: "Make an authenticated GitLab REST API request.",
        discussion: """
        Send a request to the GitLab REST API and print the response.

        Without -X, GET is used. Field flags switch to POST automatically.

        Examples:
          glab api projects/group%2Frepo
          glab api -X POST projects/123/issues -f title="Hi" -f body="…"
        """
    )

    @Argument(help: "API endpoint, e.g. 'projects/123' or '/user'.")
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
            help: "GitLab host. Defaults to gitlab.com (or $GITLAB_HOST).")
    var hostname: String?

    @Flag(name: [.customShort("i"), .customLong("include")],
          help: "Include HTTP response status line and headers.")
    var includeHeaders: Bool = false

    func run() async throws {
        let client = try await CommandContext.apiClient(host: hostname)

        let httpMethod = HTTPRequest.Method(method.uppercased())
            ?? HTTPRequest.Method(method)
        guard let httpMethod else {
            throw ValidationError("Unsupported method: \(method)")
        }

        let body = try buildBody()
        let response = try await client.raw(
            method: httpMethod,
            path: endpoint,
            body: body)

        if includeHeaders {
            print("HTTP \(response.status)")
            if let ct = response.contentType { print("Content-Type: \(ct)") }
            print("")
        }

        let isJSON = response.contentType?.contains("json") ?? false
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
        return try JSONSerialization.data(withJSONObject: dict, options: [])
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
