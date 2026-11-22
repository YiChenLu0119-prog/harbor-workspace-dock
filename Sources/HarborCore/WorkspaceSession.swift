import Foundation

/// A bounded, in-memory history for every workspace mutation, never just destructive actions.
/// Persistence always happens before state/history changes; a failed undo remains retryable.
public final class WorkspaceSession {
    public private(set) var workspace: Workspace
    public var undoAction: String? { history.last?.action }
    public var undoDepth: Int { history.count }
    private let save: (Workspace) throws -> Void
    private let historyLimit: Int
    private var history: [UndoRecord] = []

    public init(workspace: Workspace, historyLimit: Int = 50, save: @escaping (Workspace) throws -> Void) {
        self.workspace = workspace
        self.historyLimit = max(1, historyLimit)
        self.save = save
    }

    @discardableResult
    public func commit(action: String, mutate: (inout Workspace) throws -> Void) throws -> Bool {
        var next = workspace
        try mutate(&next)
        guard next != workspace else { return false }
        try save(next)
        history.append(UndoRecord(action: action, workspace: workspace))
        if history.count > historyLimit { history.removeFirst(history.count - historyLimit) }
        workspace = next
        return true
    }

    @discardableResult
    public func undo() throws -> Bool {
        guard let record = history.last else { return false }
        try save(record.workspace)
        history.removeLast()
        workspace = record.workspace
        return true
    }

    private struct UndoRecord { let action: String; let workspace: Workspace }
}
