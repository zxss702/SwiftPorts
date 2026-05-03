import Foundation

/// Successful response from `POST /login/oauth/access_token`.
public struct AccessToken: Codable, Sendable {
    public let accessToken: String
    public let tokenType: String
    public let scope: String?
}

/// In-flight response: same endpoint can return `{"error": "..."}` while
/// still waiting for the user to authorize. Decoded separately so we
/// can disambiguate without throwing a JSON decode error.
struct AccessTokenErrorEnvelope: Codable, Sendable {
    let error: String?
    let errorDescription: String?
    let errorUri: URL?
}
