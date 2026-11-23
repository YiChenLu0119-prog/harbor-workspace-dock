import Foundation

public struct MenuBarFavorite: Identifiable, Equatable {
    public let projectID: UUID
    public let projectTitle: String
    public let entry: ChatEntry
    public var id: UUID { entry.id }
}

public enum MenuBarEntryRoute: Equatable {
    case verifiedNative
    case workspace
}

public enum MenuBarQuickAccess {
    /// Uses library order, independent of the full workspace's current search/filter.
    public static func favorites(in workspace: Workspace, limit: Int = 6) -> [MenuBarFavorite] {
        guard limit > 0 else { return [] }
        var result: [MenuBarFavorite] = []
        for project in workspace.projects {
            for entry in project.entries where entry.isFavorite {
                result.append(MenuBarFavorite(projectID: project.id, projectTitle: project.title, entry: entry))
                if result.count == limit { return result }
            }
        }
        return result
    }

    /// Confirmation and editing stay in the full workspace; never bypass its link policy.
    public static func route(for entry: ChatEntry, application: NativeAppIdentity?, hasPendingConfirmation: Bool = false, hasActiveEditor: Bool = false) -> MenuBarEntryRoute {
        guard !hasPendingConfirmation, !hasActiveEditor, let application, entry.isVerified(for: application) else { return .workspace }
        return .verifiedNative
    }
}
