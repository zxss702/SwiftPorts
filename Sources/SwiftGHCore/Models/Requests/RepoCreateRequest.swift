import Foundation

/// Body for `POST /user/repos` (your own) or `POST /orgs/{org}/repos`.
public struct RepoCreateRequest: Codable, Sendable {
    public var name: String
    public var description: String?
    public var homepage: String?
    public var `private`: Bool?
    public var visibility: Visibility?
    public var hasIssues: Bool?
    public var hasProjects: Bool?
    public var hasWiki: Bool?
    public var autoInit: Bool?
    public var gitignoreTemplate: String?
    public var licenseTemplate: String?

    public init(
        name: String,
        description: String? = nil,
        homepage: String? = nil,
        private isPrivate: Bool? = nil,
        visibility: Visibility? = nil,
        hasIssues: Bool? = nil,
        hasProjects: Bool? = nil,
        hasWiki: Bool? = nil,
        autoInit: Bool? = nil,
        gitignoreTemplate: String? = nil,
        licenseTemplate: String? = nil
    ) {
        self.name = name
        self.description = description
        self.homepage = homepage
        self.private = isPrivate
        self.visibility = visibility
        self.hasIssues = hasIssues
        self.hasProjects = hasProjects
        self.hasWiki = hasWiki
        self.autoInit = autoInit
        self.gitignoreTemplate = gitignoreTemplate
        self.licenseTemplate = licenseTemplate
    }
}
