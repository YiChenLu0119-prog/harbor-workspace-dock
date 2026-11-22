import Foundation

public struct NativeAppIdentity: Codable, Equatable {
    public var bundleID: String
    public var version: String
    public init(bundleID: String, version: String) {
        self.bundleID = bundleID
        self.version = version
    }
}

public struct VerificationRecord: Codable, Equatable {
    public var url: String
    public var application: NativeAppIdentity
    public var confirmedAt: Date
    public init(url: String, application: NativeAppIdentity, confirmedAt: Date = Date()) {
        self.url = url
        self.application = application
        self.confirmedAt = confirmedAt
    }
}

public struct ChatEntry: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var url: String {
        didSet { if oldValue != url { verification = nil } }
    }
    public var isFavorite: Bool
    public var verification: VerificationRecord?

    public init(id: UUID = UUID(), title: String, url: String, isFavorite: Bool = false, verification: VerificationRecord? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.isFavorite = isFavorite
        self.verification = verification
    }

    public func isVerified(for application: NativeAppIdentity) -> Bool {
        guard case .localCodex = LinkPolicy.classify(url), let verification else { return false }
        return verification.url == url && verification.application == application
    }
}

public struct Project: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var entries: [ChatEntry]
    public init(id: UUID = UUID(), title: String, entries: [ChatEntry] = []) {
        self.id = id
        self.title = title
        self.entries = entries
    }
}

public struct Workspace: Codable, Equatable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var projects: [Project]
    public init(projects: [Project] = []) {
        self.schemaVersion = Self.currentSchemaVersion
        self.projects = projects
    }
}
