import Foundation
import Testing
@testable import SwiftGHCore

@Suite(.serialized) struct APIClientTests {
    @Test func decodesGetResponse() async throws {
        let session = MockURLProtocol.session()
        let json = try FixtureLoader.data("repo_octocat_hello_world")
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/vnd.github+json"])!
            return (response, json)
        }
        let client = APIClient(
            configuration: Configuration(),
            session: session
        )
        let repo: Repository = try await client.get("repos/octocat/Hello-World")
        #expect(repo.fullName == "octocat/Hello-World")
    }

    @Test func mapsNotFound() async throws {
        let session = MockURLProtocol.session()
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: nil)!
            return (response, Data(#"{"message":"Not Found"}"#.utf8))
        }
        let client = APIClient(
            configuration: Configuration(),
            session: session
        )
        await #expect(throws: APIError.self) {
            let _: Repository = try await client.get("repos/no/such")
        }
    }

    @Test func mapsRateLimited() async throws {
        let session = MockURLProtocol.session()
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 403,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "X-RateLimit-Remaining": "0",
                    "X-RateLimit-Reset": "1700000000",
                ])!
            return (response, Data(#"{"message":"API rate limit exceeded"}"#.utf8))
        }
        let client = APIClient(
            configuration: Configuration(),
            session: session
        )
        do {
            let _: Repository = try await client.get("repos/x/y")
            Issue.record("expected throw")
        } catch let APIError.rateLimited(resetAt, remaining, _) {
            #expect(remaining == 0)
            #expect(resetAt != nil)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func paginatesLinkHeader() async throws {
        let session = MockURLProtocol.session()
        var pageNumber = 0
        MockURLProtocol.handler = { request in
            pageNumber += 1
            let body: Data
            var headers: [String: String] = ["Content-Type": "application/json"]
            if pageNumber == 1 {
                body = Data(#"[{"id":1,"name":"a"}]"#.utf8)
                headers["Link"] = #"<https://api.github.com/x?page=2>; rel="next""#
            } else {
                body = Data(#"[{"id":2,"name":"b"}]"#.utf8)
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: headers)!
            return (response, body)
        }
        let client = APIClient(
            configuration: Configuration(),
            session: session
        )
        struct Item: Codable, Sendable { let id: Int; let name: String }
        let items: [Item] = try await client.paginate("x")
        #expect(items.count == 2)
        #expect(items.map(\.id) == [1, 2])
    }
}
