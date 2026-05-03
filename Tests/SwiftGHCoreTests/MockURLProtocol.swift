import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// `URLProtocol` you register on a `URLSessionConfiguration` to
/// intercept all requests and return canned responses.
///
/// ```swift
/// let config = URLSessionConfiguration.ephemeral
/// config.protocolClasses = [MockURLProtocol.self]
/// MockURLProtocol.handler = { request in
///     (HTTPURLResponse(url: request.url!, statusCode: 200, ...)!, jsonData)
/// }
/// let session = URLSession(configuration: config)
/// ```
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: NSError(
                domain: "MockURLProtocol", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "no handler set"]))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response,
                                cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}
