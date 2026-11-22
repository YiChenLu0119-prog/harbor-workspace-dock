import AppKit
import SwiftUI
import HarborCore
import Combine

struct EntryRow: Identifiable {
    let project: Project
    let entry: ChatEntry
    var id: UUID { entry.id }
}

struct PendingVerification {
    let entryID: UUID
    let title: String
    let projectTitle: String
    let url: String
    let application: NativeAppIdentity
}

@MainActor
final class LauncherModel: ObservableObject {
    @Published private(set) var workspace = Workspace()
    @Published var query = "" { didSet { reconcileSelection() } }
    @Published var selectedProjectID: UUID? { didSet { reconcileSelection() } }
    @Published var selectedEntryID: UUID?
    @Published var favoritesOnly = false { didSet { reconcileSelection() } }
    @Published private var notice: LocalizedNotice?
    var message: String? {
        get { notice?.rendered(in: preferences.value.language) }
        set { notice = newValue.map { .text(HarborText($0)) } }
    }
    @Published var hotkeyUnavailable = false
    var hotkeyWarning: String? { hotkeyUnavailable ? t("⌃⌥Space could not be registered; it may be in use. You can still open Harbor from the menu bar.") : nil }
    @Published var pending: PendingVerification?
    @Published var isOpening = false
    @Published private(set) var readOnly = false
    @Published var showEntryEditor = false
    @Published var showProjectEditor = false
    @Published var editingEntry: EntryRow?
    @Published var focusRequest = 0
    @Published var blurSearchRequest = 0
    var listNavigationActive = true
    var endSearchEditing: (() -> Void)?
    @Published var showSettings = false
    var undoAction: String? { session?.undoAction.map { HarborText.restored($0).rendered(in: preferences.value.language) } }
    private enum UndoNotice { case completed(HarborText), undone(HarborText) }
    @Published private var undoNotice: UndoNotice?
    var undoBanner: String? {
        get {
            guard let undoNotice else { return nil }
            switch undoNotice {
            case .completed(let action): return t("Completed: %@", action.rendered(in: preferences.value.language))
            case .undone(let action):
                return t("Undone: %@", action.rendered(in: preferences.value.language)) + (undoAction.map { " · " + t("Next undo: %@", $0) } ?? "")
            }
        }
        set { if newValue == nil { undoNotice = nil } }
    }
    @Published var activeDrag: InternalEntryDrag?
    @Published var isReceivingDrop = false
    let dragSessionID = UUID()
    let preferences: PreferencesController
    let loginItem: LoginItemController
    private let repository: WorkspaceRepository
    private let opener = NativeLinkOpener()
    private var session: WorkspaceSession?
    private var preferencesSubscription: AnyCancellable?
    var closePanel: (() -> Void)?
    var showPanel: (() -> Void)?

    init(directory: URL) {
        preferences = PreferencesController(directory: directory)
        loginItem = LoginItemController()
        repository = WorkspaceRepository(directory: directory)
        do {
            workspace = try repository.load()
            session = WorkspaceSession(workspace: workspace, save: repository.save)
        }
        catch {
            readOnly = true
            notice = .failure("Could not read the local library. Editing is paused to protect the original file.\n%@", error)
        }
        preferencesSubscription = preferences.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        showDefaultSection()
    }

    func t(_ english: String, _ arguments: String...) -> String {
        HarborLocalization.text(english, language: preferences.value.language, arguments: arguments)
    }
    func showMessage(_ text: HarborText) { notice = .text(text) }
    func showError(_ template: String, _ error: Error) { notice = .failure(template, error) }
    func stopSearching() {
        blurSearchRequest += 1
        listNavigationActive = true
        endSearchEditing?()
    }
    func selectEntry(_ id: UUID) { selectedEntryID = id; stopSearching() }

    var dataURL: URL { repository.fileURL }
    var canEdit: Bool { !readOnly && !isOpening && !isReceivingDrop }
    var canReorder: Bool { canEdit && EntryReorderPolicy.allowsReorder(query: query, favoritesOnly: favoritesOnly) }
    var rows: [EntryRow] {
        workspace.projects.filter { selectedProjectID == nil || $0.id == selectedProjectID }.flatMap { project in
            project.entries.filter { entry in
                (!favoritesOnly || entry.isFavorite) && (query.isEmpty || "\(entry.title) \(project.title)".localizedCaseInsensitiveContains(query))
            }.map { EntryRow(project: project, entry: $0) }
        }
    }
    var totalEntries: Int { workspace.projects.flatMap(\.entries).count }
    var favoriteCount: Int { workspace.projects.flatMap(\.entries).filter(\.isFavorite).count }
    var currentApplication: NativeApplication? { opener.application() }
    var scopeTitle: String {
        if favoritesOnly { return t("Favorites") }
        return workspace.projects.first(where: { $0.id == selectedProjectID })?.title ?? t("All Entries")
    }
    func showDefaultSection() {
        selectedProjectID = nil
        favoritesOnly = preferences.value.startView == .favorites
        selectedEntryID = rows.first?.id
    }
    func reconcileSelection() {
        selectedEntryID = EntrySelection.reconciled(current: selectedEntryID, visibleIDs: rows.map(\.id))
    }

    func stateLabel(_ entry: ChatEntry) -> String {
        guard case .localCodex = LinkPolicy.classify(entry.url) else { return t("Native opening unavailable") }
        if pending?.entryID == entry.id { return t("Waiting for your confirmation") }
        if let app = currentApplication, entry.isVerified(for: app.identity) { return t("Native destination confirmed") }
        return t("Unverified")
    }

    func addProject(title: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        let project = Project(title: title)
        let success = change(action: HarborText("Create project “%@”", title)) { $0.projects.append(project) }
        if success { selectedProjectID = project.id; favoritesOnly = false }
        return success
    }

    func saveEntry(projectID: UUID, title: String, url: String, existingID: UUID?) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !url.isEmpty else { return false }
        var found = false
        let success = change(action: HarborText(existingID == nil ? "Add “%@”" : "Edit “%@”", title)) { value in
            guard let projectIndex = value.projects.firstIndex(where: { $0.id == projectID }) else { return }
            if let existingID, let entryIndex = value.projects[projectIndex].entries.firstIndex(where: { $0.id == existingID }) {
                value.projects[projectIndex].entries[entryIndex].title = title
                value.projects[projectIndex].entries[entryIndex].url = url
            } else if existingID == nil {
                value.projects[projectIndex].entries.append(ChatEntry(title: title, url: url))
            } else { return }
            found = true
        }
        return success && found
    }

    func toggleFavorite(_ id: UUID) {
        guard let entry = entry(id) else { return }
        _ = change(action: HarborText(entry.isFavorite ? "Unfavorite “%@”" : "Favorite “%@”", entry.title)) { value in
            for p in value.projects.indices {
                if let e = value.projects[p].entries.firstIndex(where: { $0.id == id }) {
                    value.projects[p].entries[e].isFavorite.toggle()
                }
            }
        }
    }

    func beginAddEntry() {
        guard canEdit else { return }
        stopSearching()
        if workspace.projects.isEmpty { showProjectEditor = true }
        else { editingEntry = nil; showEntryEditor = true }
    }

    func activateSelected() {
        guard let row = rows.first(where: { $0.id == selectedEntryID }) ?? rows.first else { return }
        selectedEntryID = row.id
        activate(row.entry)
    }

    func moveSelection(_ delta: Int) {
        let current = rows
        guard !current.isEmpty else { return }
        let index = current.firstIndex(where: { $0.id == selectedEntryID }) ?? (delta > 0 ? -1 : current.count)
        selectedEntryID = current[min(max(index + delta, 0), current.count - 1)].id
    }

    func activate(_ entry: ChatEntry) {
        guard !isOpening && !isReceivingDrop else { return }
        stopSearching()
        guard LinkPolicy.nativeCandidateURL(entry.url) != nil else {
            showMessage(HarborText("This link is saved locally. Exact native navigation for ChatGPT cloud chats and references is not confirmed. Find the chat in ChatGPT for now; Harbor will not rewrite it as a Codex link or open a browser."))
            return
        }
        guard let app = currentApplication else { showMessage(HarborText(NativeOpenError.unavailable.localizedDescription)); return }
        let isVerified = entry.isVerified(for: app.identity)
        guard isVerified || !readOnly else { return }
        pending = nil
        isOpening = true
        message = nil
        opener.open(entry.url, application: app) { [weak self] result in
            guard let self else { return }
            self.isOpening = false
            switch result {
            case .success:
                if isVerified { self.closePanel?() }
                else {
                    let projectTitle = self.workspace.projects.first(where: { $0.entries.contains(where: { $0.id == entry.id }) })?.title ?? ""
                    self.pending = PendingVerification(entryID: entry.id, title: entry.title, projectTitle: projectTitle, url: entry.url, application: app.identity)
                    // The user checks the native destination, then returns via menu or hotkey.
                    self.closePanel?()
                }
            case .failure(let error):
                self.pending = nil
                self.showError("Could not open the entry: %@", error)
                self.showPanel?()
            }
        }
    }

    func confirmPending() {
        guard let pending, let app = currentApplication, app.identity == pending.application else {
            self.pending = nil; showMessage(HarborText("The native app changed. Verify this entry again.")); return
        }
        guard workspace.projects.flatMap(\.entries).contains(where: { $0.id == pending.entryID && $0.url == pending.url }) else {
            self.pending = nil; showMessage(HarborText("The entry changed. Verify it again.")); return
        }
        let success = change(action: HarborText("Confirm native entry “%@”", pending.title)) { value in
            for p in value.projects.indices {
                if let e = value.projects[p].entries.firstIndex(where: { $0.id == pending.entryID && $0.url == pending.url }) {
                    value.projects[p].entries[e].verification = VerificationRecord(url: pending.url, application: pending.application)
                }
            }
        }
        if success { self.pending = nil; showMessage(HarborText("Your confirmation was saved. Changes to the link or native app version require a new verification.")) }
    }

    func rejectPending() {
        pending = nil
        showMessage(HarborText("This entry is still unverified. Copy the link from the target chat, then edit the entry and try again."))
    }

    func entry(_ id: UUID) -> ChatEntry? { workspace.projects.flatMap(\.entries).first(where: { $0.id == id }) }
    func project(containing id: UUID) -> Project? { workspace.projects.first(where: { $0.entries.contains(where: { $0.id == id }) }) }

    func deleteEntry(_ id: UUID) {
        guard let entry = entry(id) else { return }
        _ = change(action: HarborText("Delete “%@”", entry.title)) { try WorkspaceEditing.delete(entryID: id, in: &$0) }
    }

    @discardableResult
    func moveEntry(_ id: UUID, to projectID: UUID) -> Bool {
        guard let entry = entry(id), let destination = workspace.projects.first(where: { $0.id == projectID }) else { return false }
        guard project(containing: id)?.id != projectID else { return true }
        let success = change(action: HarborText("Move “%@” to “%@”", entry.title, destination.title)) {
            try WorkspaceEditing.move(entryID: id, to: projectID, in: &$0)
        }
        if success {
            query = ""
            favoritesOnly = false
            selectedProjectID = projectID
            selectedEntryID = id
            stopSearching()
        }
        return success
    }

    @discardableResult
    func reorderEntry(_ id: UUID, relativeTo anchorID: UUID, placement: EntryPlacement) -> Bool {
        guard canReorder, let entry = entry(id) else { return false }
        return change(action: HarborText("Reorder “%@”", entry.title)) {
            try WorkspaceEditing.reorder(entryID: id, relativeTo: anchorID, placement: placement, in: &$0)
        }
    }

    func stepEntry(_ id: UUID, by offset: Int) {
        guard canReorder, let entry = entry(id) else { return }
        _ = change(action: HarborText(offset < 0 ? "Move “%@” up" : "Move “%@” down", entry.title)) {
            try WorkspaceEditing.step(entryID: id, by: offset, in: &$0)
        }
    }

    func canStepEntry(_ id: UUID, by offset: Int) -> Bool {
        guard canReorder, let project = project(containing: id), let index = project.entries.firstIndex(where: { $0.id == id }) else { return false }
        return project.entries.indices.contains(index + offset)
    }

    func undo() {
        guard canEdit, let session, let action = session.undoAction else { return }
        do {
            guard try session.undo() else { return }
            workspace = session.workspace
            undoNotice = .undone(HarborText.restored(action))
            pending = nil
            activeDrag = nil
            if let selectedProjectID, !workspace.projects.contains(where: { $0.id == selectedProjectID }) { self.selectedProjectID = nil }
            reconcileSelection()
        } catch {
            showError("Could not save the undo. Your library and undo history are unchanged.\n%@", error)
        }
    }

    @discardableResult
    private func change(action: HarborText, _ mutation: (inout Workspace) throws -> Void) -> Bool {
        guard canEdit, let session else { return false }
        do {
            guard try session.commit(action: action.archived, mutate: mutation) else { return true }
            workspace = session.workspace
            undoNotice = .completed(action)
            pending = nil
            activeDrag = nil
            reconcileSelection()
            return true
        } catch {
            showError("Could not save the change. Nothing was changed.\n%@", error)
            return false
        }
    }
}
