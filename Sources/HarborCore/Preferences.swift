import Foundation

public enum HarborAppearance: String, Codable, CaseIterable { case system, light, dark }
public enum HarborDensity: String, Codable, CaseIterable { case comfortable, compact }
public enum HarborStartView: String, Codable, CaseIterable { case all, favorites }
public enum HarborAccent: String, Codable, CaseIterable { case teal, blue, graphite }
public enum HarborLanguage: String, Codable, CaseIterable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
}

public struct HarborPreferences: Codable, Equatable {
    public static let currentSchemaVersion = 1
    public var schemaVersion = Self.currentSchemaVersion
    public var appearance: HarborAppearance = .system
    public var density: HarborDensity = .comfortable
    public var startView: HarborStartView = .all
    public var accent: HarborAccent = .teal
    public var language: HarborLanguage = .english
    public var showsMenuBarName = true
    public init() {}

    private enum CodingKeys: String, CodingKey { case schemaVersion, appearance, density, startView, accent, language, showsMenuBarName }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        appearance = try values.decode(HarborAppearance.self, forKey: .appearance)
        density = try values.decode(HarborDensity.self, forKey: .density)
        startView = try values.decode(HarborStartView.self, forKey: .startView)
        accent = try values.decode(HarborAccent.self, forKey: .accent)
        // v0.1/v0.2 were Chinese-only; an absent language preserves that experience.
        language = try values.decodeIfPresent(HarborLanguage.self, forKey: .language) ?? .simplifiedChinese
        showsMenuBarName = try values.decodeIfPresent(Bool.self, forKey: .showsMenuBarName) ?? true
    }
}

public enum PreferencesError: LocalizedError {
    case unsupportedVersion(Int)
    case protectedAfterReadFailure
    case notLoaded
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "Preferences version \(version) is unsupported. The original file is preserved."
        case .protectedAfterReadFailure: return "Saving is paused to protect unreadable preferences."
        case .notLoaded: return "Load preferences before saving."
        }
    }
}

/// Preferences are deliberately separate from workspace.json and its schema.
public final class PreferencesRepository {
    public let fileURL: URL
    private var loaded = false
    private var readFailed = false
    public init(directory: URL) { fileURL = directory.appendingPathComponent("preferences.json") }

    /// Persist the initial language before a newly created workspace could look like a legacy install.
    public func loadOrCreate() throws -> HarborPreferences {
        let preferences = try load()
        if !FileManager.default.fileExists(atPath: fileURL.path) { try save(preferences) }
        return preferences
    }

    public func load() throws -> HarborPreferences {
        do {
            let data: Data
            do { data = try Data(contentsOf: fileURL) }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
                loaded = true; readFailed = false
                var preferences = HarborPreferences()
                // A pre-preferences installation may already have a workspace but no settings file.
                if FileManager.default.fileExists(atPath: fileURL.deletingLastPathComponent().appendingPathComponent("workspace.json").path) {
                    preferences.language = .simplifiedChinese
                }
                return preferences
            }
            let header = try JSONDecoder().decode(Header.self, from: data)
            guard header.schemaVersion == HarborPreferences.currentSchemaVersion else {
                throw PreferencesError.unsupportedVersion(header.schemaVersion)
            }
            let result = try JSONDecoder().decode(HarborPreferences.self, from: data)
            loaded = true; readFailed = false
            return result
        } catch { readFailed = true; throw error }
    }

    public func save(_ preferences: HarborPreferences) throws {
        guard !readFailed else { throw PreferencesError.protectedAfterReadFailure }
        guard loaded else { throw PreferencesError.notLoaded }
        guard preferences.schemaVersion == HarborPreferences.currentSchemaVersion else {
            throw PreferencesError.unsupportedVersion(preferences.schemaVersion)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(preferences)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    private struct Header: Decodable { var schemaVersion: Int }
}

public enum LoginItemState: String, Codable {
    case notRegistered, enabled, requiresApproval, notFound, unknown
    public var isEnabled: Bool { self == .enabled }
}

public enum LaunchPresentation {
    public static func shouldShowPanel(isLoginItem: Bool, arguments: [String]) -> Bool {
        if arguments.contains("--hidden") { return false }
        if arguments.contains("--show") { return true }
        return !isLoginItem
    }
}

public enum EntrySelection {
    public static func reconciled(current: UUID?, visibleIDs: [UUID]) -> UUID? {
        if let current, visibleIDs.contains(current) { return current }
        return visibleIDs.first
    }
}
