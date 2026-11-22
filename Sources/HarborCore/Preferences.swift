import Foundation

public enum HarborAppearance: String, Codable, CaseIterable { case system, light, dark }
public enum HarborDensity: String, Codable, CaseIterable { case comfortable, compact }
public enum HarborStartView: String, Codable, CaseIterable { case all, favorites }
public enum HarborAccent: String, Codable, CaseIterable { case teal, blue, graphite }

public struct HarborPreferences: Codable, Equatable {
    public static let currentSchemaVersion = 1
    public var schemaVersion = Self.currentSchemaVersion
    public var appearance: HarborAppearance = .system
    public var density: HarborDensity = .comfortable
    public var startView: HarborStartView = .all
    public var accent: HarborAccent = .teal
    public init() {}
}

public enum PreferencesError: LocalizedError {
    case unsupportedVersion(Int)
    case protectedAfterReadFailure
    case notLoaded
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "此偏好文件使用未支持的版本 \(version)，原文件已保留。"
        case .protectedAfterReadFailure: return "偏好读取失败，已暂停保存以保护原文件。"
        case .notLoaded: return "尚未读取偏好，无法保存。"
        }
    }
}

/// Preferences are deliberately separate from workspace.json and its schema.
public final class PreferencesRepository {
    public let fileURL: URL
    private var loaded = false
    private var readFailed = false
    public init(directory: URL) { fileURL = directory.appendingPathComponent("preferences.json") }

    public func load() throws -> HarborPreferences {
        do {
            let data: Data
            do { data = try Data(contentsOf: fileURL) }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
                loaded = true; readFailed = false
                return HarborPreferences()
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
