import Foundation

public enum WorkspaceEditingError: LocalizedError {
    case missingEntry, missingProject, invalidAnchor, invalidStep
    public var errorDescription: String? {
        switch self {
        case .missingEntry: return "This entry no longer exists. Select another entry."
        case .missingProject: return "The destination project no longer exists. Select another project."
        case .invalidAnchor: return "Reorder within one project. Use Move to for another project."
        case .invalidStep: return "Invalid reorder direction."
        }
    }
}

public enum EntryPlacement: Equatable, Sendable { case before, after }

public enum WorkspaceEditing {
    public static func delete(entryID: UUID, in workspace: inout Workspace) throws {
        let source = try location(of: entryID, in: workspace)
        workspace.projects[source.project].entries.remove(at: source.entry)
    }

    /// A cross-project move appends to the target; dropping on the current project is a no-op.
    public static func move(entryID: UUID, to projectID: UUID, in workspace: inout Workspace) throws {
        let source = try location(of: entryID, in: workspace)
        guard let target = workspace.projects.firstIndex(where: { $0.id == projectID }) else { throw WorkspaceEditingError.missingProject }
        guard target != source.project else { return }
        let entry = workspace.projects[source.project].entries.remove(at: source.entry)
        workspace.projects[target].entries.append(entry)
    }

    /// Anchors describe the final order, avoiding off-by-one indices after source removal.
    public static func reorder(entryID: UUID, relativeTo anchorID: UUID, placement: EntryPlacement, in workspace: inout Workspace) throws {
        let source = try location(of: entryID, in: workspace)
        let anchor = try location(of: anchorID, in: workspace)
        guard source.project == anchor.project else { throw WorkspaceEditingError.invalidAnchor }
        guard entryID != anchorID else { return }
        let entry = workspace.projects[source.project].entries.remove(at: source.entry)
        let newAnchorIndex = workspace.projects[source.project].entries.firstIndex(where: { $0.id == anchorID })!
        let insertion = newAnchorIndex + (placement == .after ? 1 : 0)
        workspace.projects[source.project].entries.insert(entry, at: insertion)
    }

    public static func step(entryID: UUID, by offset: Int, in workspace: inout Workspace) throws {
        guard offset == -1 || offset == 1 else { throw WorkspaceEditingError.invalidStep }
        let source = try location(of: entryID, in: workspace)
        let destination = source.entry + offset
        guard workspace.projects[source.project].entries.indices.contains(destination) else { return }
        workspace.projects[source.project].entries.swapAt(source.entry, destination)
    }

    private static func location(of id: UUID, in workspace: Workspace) throws -> (project: Int, entry: Int) {
        for p in workspace.projects.indices {
            if let e = workspace.projects[p].entries.firstIndex(where: { $0.id == id }) { return (p, e) }
        }
        throw WorkspaceEditingError.missingEntry
    }
}

public enum EntryReorderPolicy {
    public static func allowsReorder(query: String, favoritesOnly: Bool) -> Bool { query.isEmpty && !favoritesOnly }
}

public struct InternalEntryDrag: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let dragID: UUID
    public let entryID: UUID
    public init(sessionID: UUID, dragID: UUID = UUID(), entryID: UUID) {
        self.sessionID = sessionID; self.dragID = dragID; self.entryID = entryID
    }

    public static func validated(_ data: Data, active: InternalEntryDrag?) -> InternalEntryDrag? {
        guard data.count <= 1024, let active,
              let decoded = try? JSONDecoder().decode(Self.self, from: data), decoded == active else { return nil }
        return decoded
    }
}
