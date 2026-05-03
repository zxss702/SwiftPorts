import Foundation

/// Response from `POST /login/device/code`.
public struct DeviceCode: Codable, Sendable {
    /// The opaque code we send back to `/login/oauth/access_token`
    /// to redeem for an access token.
    public let deviceCode: String
    /// The 6-character code the human types into the browser.
    public let userCode: String
    /// Where the human goes (typically `https://github.com/login/device`).
    public let verificationUri: URL
    /// Lifetime of the codes, in seconds (typically 900 = 15 min).
    public let expiresIn: Int
    /// Minimum poll interval, in seconds (typically 5).
    public let interval: Int
}
