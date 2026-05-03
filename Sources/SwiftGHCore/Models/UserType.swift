import Foundation

public enum UserType: String, Codable, Sendable {
    case user = "User"
    case organization = "Organization"
    case bot = "Bot"
    case mannequin = "Mannequin"
}
