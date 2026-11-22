import Foundation

public enum RepositoryError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidLibrary
    case notLoaded
    case protectedAfterReadFailure

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "Data version \(version) is unsupported. The original file is preserved."
        case .invalidLibrary: return "The library is invalid or contains duplicate IDs. The original file is preserved."
        case .notLoaded: return "Load the library before saving."
        case .protectedAfterReadFailure: return "Saving is paused to protect the unreadable library."
        }
    }
}

public final class WorkspaceRepository {
    public let fileURL: URL
    private var didLoad = false
    private var readFailed = false
    private let fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) {
        self.fileURL = directory.appendingPathComponent("workspace.json")
        self.fileManager = fileManager
    }

    public func load() throws -> Workspace {
        do {
            // Reading first distinguishes an absent file from an inaccessible file.
            let data: Data
            do { data = try Data(contentsOf: fileURL) }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
                didLoad = true
                readFailed = false
                return Workspace()
            }
            let header = try JSONDecoder().decode(SchemaHeader.self, from: data)
            guard header.schemaVersion == Workspace.currentSchemaVersion else {
                throw RepositoryError.unsupportedVersion(header.schemaVersion)
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let value = try decoder.decode(Workspace.self, from: data)
            try validate(value)
            didLoad = true
            readFailed = false
            return value
        } catch {
            readFailed = true
            throw error
        }
    }

    public func save(_ workspace: Workspace) throws {
        guard !readFailed else { throw RepositoryError.protectedAfterReadFailure }
        guard didLoad else { throw RepositoryError.notLoaded }
        try validate(workspace)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(workspace)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    private func validate(_ workspace: Workspace) throws {
        guard workspace.schemaVersion == Workspace.currentSchemaVersion else {
            throw RepositoryError.unsupportedVersion(workspace.schemaVersion)
        }
        let projectIDs = workspace.projects.map(\.id)
        let entryIDs = workspace.projects.flatMap(\.entries).map(\.id)
        guard Set(projectIDs).count == projectIDs.count, Set(entryIDs).count == entryIDs.count,
              workspace.projects.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              workspace.projects.flatMap(\.entries).allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw RepositoryError.invalidLibrary
        }
    }

    private struct SchemaHeader: Decodable { var schemaVersion: Int }
}
