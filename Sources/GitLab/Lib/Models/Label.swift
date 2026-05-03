import Foundation

/// A GitLab project (or group) label. Color is the hex string without
/// the leading `#` (e.g. `"FF0000"`); GitLab also exposes a derived
/// `text_color` for contrast.
public struct Label: Codable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let description: String?
    public let color: String
    public let textColor: String?
    public let priority: Int?
    public let isProjectLabel: Bool?
}
