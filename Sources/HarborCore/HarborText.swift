import Foundation

/// Stores semantic English text plus untouched user arguments, so notices and undo history
/// can be rendered again immediately after a language change.
public struct HarborText: Codable, Equatable {
    public let template: String
    public let arguments: [String]
    public init(_ template: String, _ arguments: String...) {
        self.template = template; self.arguments = arguments
    }
    public func rendered(in language: HarborLanguage) -> String {
        HarborLocalization.text(template, language: language, arguments: arguments)
    }
    public var archived: String {
        guard let data = try? JSONEncoder().encode(self), let string = String(data: data, encoding: .utf8) else { return template }
        return string
    }
    public static func restored(_ string: String) -> Self {
        guard let data = string.data(using: .utf8), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self(string) }
        return value
    }
}

public enum HarborLocalization {
    public static func text(_ english: String, language: HarborLanguage, arguments: [String] = []) -> String {
        let template = language == .simplifiedChinese ? (chinese[english] ?? english) : english
        guard !arguments.isEmpty else { return template }
        let parts = template.components(separatedBy: "%@")
        guard parts.count == arguments.count + 1 else { return template }
        return arguments.enumerated().reduce(parts[0]) { result, pair in result + pair.element + parts[pair.offset + 1] }
    }

    public static func errorDescription(_ error: Error, language: HarborLanguage) -> String {
        let message: HarborText
        switch error {
        case RepositoryError.unsupportedVersion(let version): message = HarborText("Data version %@ is unsupported. The original file is preserved.", String(version))
        case RepositoryError.invalidLibrary: message = HarborText("The library is invalid or contains duplicate IDs. The original file is preserved.")
        case RepositoryError.notLoaded: message = HarborText("Load the library before saving.")
        case RepositoryError.protectedAfterReadFailure: message = HarborText("Saving is paused to protect the unreadable library.")
        case PreferencesError.unsupportedVersion(let version): message = HarborText("Preferences version %@ is unsupported. The original file is preserved.", String(version))
        case PreferencesError.notLoaded: message = HarborText("Load preferences before saving.")
        case PreferencesError.protectedAfterReadFailure: message = HarborText("Saving is paused to protect unreadable preferences.")
        case WorkspaceEditingError.missingEntry: message = HarborText("This entry no longer exists. Select another entry.")
        case WorkspaceEditingError.missingProject: message = HarborText("The destination project no longer exists. Select another project.")
        case WorkspaceEditingError.invalidAnchor: message = HarborText("Reorder within one project. Use Move to for another project.")
        case WorkspaceEditingError.invalidStep: message = HarborText("Invalid reorder direction.")
        default: return text(error.localizedDescription, language: language)
        }
        return message.rendered(in: language)
    }
}
