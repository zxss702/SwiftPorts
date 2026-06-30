import Foundation
import HTTPTypes
import HTTPTypesFoundation
import Logging
import ShellKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Posts GraphQL queries / mutations to GitHub's `/graphql` endpoint.
///
/// Mirrors `api.Client.GraphQL` from upstream `gh`. Hand-rolled — no
/// Apollo, no shurcooL/graphql equivalent. The whole point is that
/// GitHub's GraphQL is a single endpoint that takes
/// `{query, variables, operationName}` and returns
/// `{data, errors}`; ~80 LOC of HTTP + JSON suffices.
///
/// Decoding uses the same `JSONDecoder.gitHub()` strategy as the REST
/// client so models can be shared across both transports where
/// shapes overlap (issues, PRs, repos, users).
public actor GraphQLClient {
    public let configuration: Configuration
    private let session: URLSession
    private let logger: Logger

    public init(
        configuration: Configuration = .live(),
        session: URLSession = .shared,
        logger: Logger = Loggers.api
    ) {
        self.configuration = configuration
        self.session = session
        self.logger = logger
    }

    /// Execute a query and return the typed `data` payload.
    ///
    /// Throws ``GraphQLAggregateError`` if the response carries any
    /// `errors`, even if `data` is also present (partial failures).
    /// Use ``rawQuery(_:variables:operationName:)`` to opt out of
    /// strict error handling.
    public func query<Payload: Decodable & Sendable>(
        _ query: String,
        variables: [String: GraphQLValue]? = nil,
        operationName: String? = nil,
        as: Payload.Type = Payload.self
    ) async throws -> Payload {
        let envelope: GraphQLResponse<Payload> = try await rawQuery(
            query, variables: variables, operationName: operationName)
        if let errors = envelope.errors, !errors.isEmpty {
            throw GraphQLAggregateError(errors: errors)
        }
        guard let data = envelope.data else {
            throw GraphQLAggregateError(errors: [
                GraphQLError(message: "GraphQL response has no data and no errors.",
                             path: nil, locations: nil, type: nil, extensions: nil)
            ])
        }
        return data
    }

    /// Lower-level: returns the full envelope (`data` and `errors`)
    /// without throwing on partial failures. Use when you want to
    /// inspect both halves.
    public func rawQuery<Payload: Decodable & Sendable>(
        _ query: String,
        variables: [String: GraphQLValue]? = nil,
        operationName: String? = nil,
        as: Payload.Type = Payload.self
    ) async throws -> GraphQLResponse<Payload> {
        let request = GraphQLRequest(
            query: query, variables: variables, operationName: operationName)
        let body = try JSONEncoder.gitHub().encode(request)

        var httpRequest = HTTPRequest(method: .post, scheme: configuration.graphQLURL.scheme, authority: configuration.graphQLURL.host, path: configuration.graphQLURL.path + (configuration.graphQLURL.query.map { "?\($0)" } ?? ""))
        httpRequest.headerFields[.accept] = "application/json"
        httpRequest.headerFields[.contentType] = "application/json; charset=utf-8"
        httpRequest.headerFields[.userAgent] = configuration.userAgent
        if let token = configuration.token {
            httpRequest.headerFields[.authorization] = "Bearer \(token)"
        }

        // Sandbox boundary for the GraphQL endpoint.
        try await Shell.authorize(configuration.graphQLURL)

        logger.debug("GraphQL POST \(configuration.graphQLURL.absoluteString)")

        let (data, response): (Data, HTTPResponse)
        do {
            (data, response) = try await session.upload(for: httpRequest, from: body)
        } catch {
            throw APIError.transport(underlying: error)
        }

        logger.debug("GraphQL HTTP \(response.status.code) (\(data.count) bytes)")

        // Reuse REST-style error mapping for non-2xx — covers 401 / 403
        // / 404 / rate-limited cases identically.
        if !(200..<300).contains(response.status.code) {
            switch response.status.code {
            case 401: throw APIError.unauthenticated(url: configuration.graphQLURL)
            case 404: throw APIError.notFound(url: configuration.graphQLURL)
            default:
                let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let message = parsed?["message"] as? String ?? ""
                throw APIError.http(status: response.status.code,
                                    message: message,
                                    url: configuration.graphQLURL)
            }
        }

        do {
            return try JSONDecoder.gitHub().decode(
                GraphQLResponse<Payload>.self, from: data)
        } catch {
            logger.debug("GraphQL decode failed; body: \(String(data: data, encoding: .utf8) ?? "<binary>")")
            throw APIError.decoding(underlying: error, url: configuration.graphQLURL)
        }
    }
}
