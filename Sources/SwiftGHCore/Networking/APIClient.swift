import Foundation
import Logging
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal GitHub REST/GraphQL client.
///
/// Mirrors what the upstream `gh` does in `api/client.go` +
/// `api/http_client.go`, stripped to the parts the no-auth surface
/// needs: pagination, rate-limit awareness, JSON decoding.
public actor APIClient {
    public let configuration: Configuration
    private let session: URLSession
    private let logger: Logger

    public init(
        configuration: Configuration = .fromEnvironment(),
        session: URLSession = .shared,
        logger: Logger = Loggers.api
    ) {
        self.configuration = configuration
        self.session = session
        self.logger = logger
    }

    // MARK: REST

    /// `GET path` → decode body as `T`. `path` is relative to the
    /// configured API root (e.g. `"repos/cli/cli"`).
    public func get<T: Decodable>(
        _ path: String,
        as type: T.Type = T.self,
        query: [URLQueryItem] = []
    ) async throws -> T {
        let url = makeURL(path: path, query: query)
        let response = try await perform(method: .get, url: url, body: nil)
        return try decode(T.self, from: response)
    }

    /// `GET path` returning every page of a paginated list, walking
    /// `Link: rel="next"` headers until exhausted.
    public func paginate<T: Decodable>(
        _ path: String,
        as elementType: T.Type = T.self,
        query: [URLQueryItem] = [],
        maxPages: Int = 100
    ) async throws -> [T] {
        var url: URL? = makeURL(path: path, query: query)
        var pages = 0
        var collected: [T] = []
        while let next = url, pages < maxPages {
            let response = try await perform(method: .get, url: next, body: nil)
            let page: [T] = try decode([T].self, from: response)
            collected.append(contentsOf: page)
            url = response.nextPageURL
            pages += 1
        }
        return collected
    }

    /// Low-level entry: arbitrary method, raw body, raw response. Used
    /// by `gh api` and by anything that needs Link/headers visibility.
    public func raw(
        method: HTTPMethod,
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        extraHeaders: [String: String] = [:]
    ) async throws -> APIResponse {
        let url = makeURL(path: path, query: query)
        return try await perform(
            method: method,
            url: url,
            body: body,
            extraHeaders: extraHeaders
        )
    }

    // MARK: URL building

    func makeURL(path: String, query: [URLQueryItem]) -> URL {
        // Absolute URL passed in (e.g. a paginated `next` link from GitHub).
        if let absolute = URL(string: path), absolute.scheme != nil {
            return absolute
        }
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var components = URLComponents(
            url: configuration.apiRoot.appendingPathComponent(trimmed),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    // MARK: HTTP

    private func perform(
        method: HTTPMethod,
        url: URL,
        body: Data?,
        extraHeaders: [String: String] = [:]
    ) async throws -> APIResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        if let token = configuration.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if body != nil {
            request.setValue("application/json; charset=utf-8",
                             forHTTPHeaderField: "Content-Type")
        }
        for (k, v) in extraHeaders {
            request.setValue(v, forHTTPHeaderField: k)
        }

        logger.debug("HTTP \(method.rawValue) \(url.absoluteString)")

        let (data, urlResponse): (Data, URLResponse)
        do {
            (data, urlResponse) = try await session.data(for: request)
        } catch {
            throw APIError.transport(underlying: error)
        }

        guard let http = urlResponse as? HTTPURLResponse else {
            throw APIError.transport(
                underlying: NSError(domain: "SwiftGH", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "non-HTTP response"]))
        }

        let nextPage = http.value(forHTTPHeaderField: "Link")
            .flatMap { LinkHeader.url(for: "next", in: $0) }
        let remaining = http.value(forHTTPHeaderField: "X-RateLimit-Remaining")
            .flatMap(Int.init)
        let resetAt = http.value(forHTTPHeaderField: "X-RateLimit-Reset")
            .flatMap(TimeInterval.init)
            .map { Date(timeIntervalSince1970: $0) }
        let contentType = http.value(forHTTPHeaderField: "Content-Type")

        logger.debug(
            "HTTP \(http.statusCode) (\(data.count) bytes; rate-remaining=\(remaining.map(String.init) ?? "?"))")

        let response = APIResponse(
            status: http.statusCode,
            body: data,
            nextPageURL: nextPage,
            rateLimitRemaining: remaining,
            rateLimitResetAt: resetAt,
            contentType: contentType,
            url: url
        )

        try checkStatus(response)
        return response
    }

    // MARK: Status mapping

    private func checkStatus(_ r: APIResponse) throws {
        if (200..<300).contains(r.status) { return }
        if r.status == 404 { throw APIError.notFound(url: r.url) }
        if r.status == 401 { throw APIError.unauthenticated(url: r.url) }
        if r.status == 403,
           let remaining = r.rateLimitRemaining, remaining == 0 {
            throw APIError.rateLimited(
                resetAt: r.rateLimitResetAt,
                remaining: remaining,
                url: r.url)
        }
        let message = parseMessage(from: r.body) ?? ""
        throw APIError.http(status: r.status, message: message, url: r.url)
    }

    private func parseMessage(from body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return nil }
        return object["message"] as? String
    }

    // MARK: Decoding

    private func decode<T: Decodable>(_ type: T.Type, from r: APIResponse) throws -> T {
        do {
            return try JSONDecoder.gitHub().decode(T.self, from: r.body)
        } catch {
            throw APIError.decoding(underlying: error, url: r.url)
        }
    }
}
