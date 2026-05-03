import Foundation

/// Raw response from ``APIClient``: the body plus selected headers
/// the higher layers care about.
public struct APIResponse: Sendable {
    public let status: Int
    public let body: Data
    public let nextPageURL: URL?
    public let rateLimitRemaining: Int?
    public let rateLimitResetAt: Date?
    public let contentType: String?
    public let url: URL

    public init(
        status: Int,
        body: Data,
        nextPageURL: URL?,
        rateLimitRemaining: Int?,
        rateLimitResetAt: Date?,
        contentType: String?,
        url: URL
    ) {
        self.status = status
        self.body = body
        self.nextPageURL = nextPageURL
        self.rateLimitRemaining = rateLimitRemaining
        self.rateLimitResetAt = rateLimitResetAt
        self.contentType = contentType
        self.url = url
    }
}
