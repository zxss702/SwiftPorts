import Foundation

/// Errors raised by ``OAuthDeviceFlow``.
public enum OAuthDeviceFlowError: Error, Sendable {
    /// Polling state: keep polling.
    case authorizationPending
    /// Polling state: server asked us to back off.
    case slowDown
    /// Terminal: codes expired before the user finished. Restart the flow.
    case expiredToken
    /// Terminal: user denied authorization.
    case accessDenied
    /// Terminal: device_code or client_id rejected by the server.
    case invalidGrant(reason: String)
    /// Terminal: an OAuth error code we don't have a special case for.
    case unknownError(code: String, description: String?)
    /// Transport/HTTP failure while talking to GitHub's OAuth endpoints.
    case networkError(status: Int, body: String)
}

extension OAuthDeviceFlowError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .authorizationPending:
            return "OAuth authorization still pending."
        case .slowDown:
            return "OAuth server asked us to slow down polling."
        case .expiredToken:
            return "OAuth device code expired. Run the login flow again."
        case .accessDenied:
            return "OAuth authorization denied by the user."
        case .invalidGrant(let reason):
            return "OAuth invalid grant: \(reason)"
        case .unknownError(let code, let description):
            return "OAuth error: \(code)" + (description.map { " — \($0)" } ?? "")
        case .networkError(let status, let body):
            return "OAuth HTTP \(status): \(body.prefix(200))"
        }
    }
}
