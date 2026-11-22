import SwiftUI
import UniformTypeIdentifiers
import HarborCore

extension UTType {
    static let harborEntry = UTType(exportedAs: "local.harbor.workspace.entry", conformingTo: .data)
}

enum EntryDropDestination: Sendable {
    case project(UUID)
    case relative(UUID, EntryPlacement)
}

@MainActor
extension LauncherModel {
    func dragProvider(for entryID: UUID) -> NSItemProvider {
        guard canEdit, entry(entryID) != nil else { return NSItemProvider() }
        let payload = InternalEntryDrag(sessionID: dragSessionID, entryID: entryID)
        guard let data = try? JSONEncoder().encode(payload) else { return NSItemProvider() }
        activeDrag = payload
        selectEntry(entryID)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.harborEntry.identifier, visibility: .ownProcess) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    func canAcceptDrop(_ destination: EntryDropDestination) -> Bool {
        guard canEdit, let drag = activeDrag, let source = project(containing: drag.entryID) else { return false }
        switch destination {
        case .project(let projectID):
            return source.id != projectID && workspace.projects.contains(where: { $0.id == projectID })
        case .relative(let anchorID, _):
            return canReorder && anchorID != drag.entryID && source.entries.contains(where: { $0.id == anchorID })
        }
    }

    /// Consumes one active drag before loading data. Hover never mutates or saves the workspace.
    func acceptDrop(_ providers: [NSItemProvider], at destination: EntryDropDestination) -> Bool {
        guard providers.count == 1, canAcceptDrop(destination), let expected = activeDrag,
              providers[0].hasItemConformingToTypeIdentifier(UTType.harborEntry.identifier) else { return false }
        activeDrag = nil
        isReceivingDrop = true
        providers[0].loadDataRepresentation(forTypeIdentifier: UTType.harborEntry.identifier) { [weak self] data, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isReceivingDrop = false
                guard error == nil, let data, InternalEntryDrag.validated(data, active: expected) != nil,
                      self.entry(expected.entryID) != nil else {
                    self.showMessage(HarborText("The drag did not complete. Your library is unchanged."))
                    return
                }
                switch destination {
                case .project(let projectID):
                    _ = self.moveEntry(expected.entryID, to: projectID)
                case .relative(let anchorID, let placement):
                    guard self.canReorder else { self.showMessage(HarborText("Reordering is paused while filtered. Clear search or leave Favorites first.")); return }
                    _ = self.reorderEntry(expected.entryID, relativeTo: anchorID, placement: placement)
                }
            }
        }
        return true
    }
}

struct EntryRowDropDelegate: DropDelegate {
    let model: LauncherModel
    let anchorID: UUID
    let rowHeight: CGFloat
    @Binding var placement: EntryPlacement?

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.harborEntry]) && model.canAcceptDrop(.relative(anchorID, .before))
    }
    func dropEntered(info: DropInfo) { updateIndicator(info) }
    func dropExited(info: DropInfo) { placement = nil }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { placement = nil; return DropProposal(operation: .forbidden) }
        updateIndicator(info)
        return DropProposal(operation: .move)
    }
    func performDrop(info: DropInfo) -> Bool {
        defer { placement = nil }
        guard validateDrop(info: info) else { return false }
        let direction: EntryPlacement = info.location.y >= rowHeight / 2 ? .after : .before
        return model.acceptDrop(info.itemProviders(for: [.harborEntry]), at: .relative(anchorID, direction))
    }
    private func updateIndicator(_ info: DropInfo) {
        placement = validateDrop(info: info) ? (info.location.y >= rowHeight / 2 ? .after : .before) : nil
    }
}

struct ProjectDropDelegate: DropDelegate {
    let model: LauncherModel
    let projectID: UUID
    @Binding var targeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.harborEntry]) && model.canAcceptDrop(.project(projectID))
    }
    func dropEntered(info: DropInfo) { targeted = validateDrop(info: info) }
    func dropExited(info: DropInfo) { targeted = false }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        targeted = validateDrop(info: info)
        return DropProposal(operation: targeted ? .move : .forbidden)
    }
    func performDrop(info: DropInfo) -> Bool {
        defer { targeted = false }
        guard validateDrop(info: info) else { return false }
        return model.acceptDrop(info.itemProviders(for: [.harborEntry]), at: .project(projectID))
    }
}
