import AppKit
import SwiftUI
import HarborCore

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
    @Published var message: String?
    @Published var hotkeyWarning: String?
    @Published var pending: PendingVerification?
    @Published var isOpening = false
    @Published private(set) var readOnly = false
    @Published var showEntryEditor = false
    @Published var showProjectEditor = false
    @Published var editingEntry: EntryRow?
    @Published var focusRequest = 0
    @Published var showSettings = false
    let preferences: PreferencesController
    let loginItem: LoginItemController
    private let repository: WorkspaceRepository
    private let opener = NativeLinkOpener()
    var closePanel: (() -> Void)?
    var showPanel: (() -> Void)?

    init(directory: URL) {
        preferences = PreferencesController(directory: directory)
        loginItem = LoginItemController()
        repository = WorkspaceRepository(directory: directory)
        do { workspace = try repository.load() }
        catch {
            readOnly = true
            message = "读取本地资料失败，已暂停编辑以保护原文件。\n\(error.localizedDescription)"
        }
        showDefaultSection()
    }

    var dataURL: URL { repository.fileURL }
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
        if favoritesOnly { return "收藏" }
        return workspace.projects.first(where: { $0.id == selectedProjectID })?.title ?? "所有入口"
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
        guard case .localCodex = LinkPolicy.classify(entry.url) else { return "暂不支持原生打开" }
        if pending?.entryID == entry.id { return "等待你的确认" }
        if let app = currentApplication, entry.isVerified(for: app.identity) { return "已确认原生" }
        return "待验证"
    }

    func addProject(title: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        let project = Project(title: title)
        let success = change { $0.projects.append(project) }
        if success { selectedProjectID = project.id; favoritesOnly = false }
        return success
    }

    func saveEntry(projectID: UUID, title: String, url: String, existingID: UUID?) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !url.isEmpty else { return false }
        var found = false
        let success = change { value in
            guard let projectIndex = value.projects.firstIndex(where: { $0.id == projectID }) else { return }
            if let existingID, let entryIndex = value.projects[projectIndex].entries.firstIndex(where: { $0.id == existingID }) {
                value.projects[projectIndex].entries[entryIndex].title = title
                value.projects[projectIndex].entries[entryIndex].url = url
            } else if existingID == nil {
                value.projects[projectIndex].entries.append(ChatEntry(title: title, url: url))
            } else { return }
            found = true
        }
        if success && found { pending = nil }
        return success && found
    }

    func toggleFavorite(_ id: UUID) {
        _ = change { value in
            for p in value.projects.indices {
                if let e = value.projects[p].entries.firstIndex(where: { $0.id == id }) {
                    value.projects[p].entries[e].isFavorite.toggle()
                }
            }
        }
    }

    func beginAddEntry() {
        guard !readOnly else { return }
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
        guard !isOpening else { return }
        guard LinkPolicy.nativeCandidateURL(entry.url) != nil else {
            message = "此链接已保存在泊岸。普通 ChatGPT 云端对话和聊天引用尚未确认可从外部准确进入原生 App，请暂时在 ChatGPT 中查找。泊岸不会把它改成 Codex 链接或转到浏览器。"
            return
        }
        guard let app = currentApplication else { message = NativeOpenError.unavailable.localizedDescription; return }
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
                self.message = "未能打开入口：\(error.localizedDescription)"
                self.showPanel?()
            }
        }
    }

    func confirmPending() {
        guard let pending, let app = currentApplication, app.identity == pending.application else {
            self.pending = nil; message = "原生 App 已变更，请重新测试入口。"; return
        }
        guard workspace.projects.flatMap(\.entries).contains(where: { $0.id == pending.entryID && $0.url == pending.url }) else {
            self.pending = nil; message = "入口已变更，请重新测试。"; return
        }
        let success = change { value in
            for p in value.projects.indices {
                if let e = value.projects[p].entries.firstIndex(where: { $0.id == pending.entryID && $0.url == pending.url }) {
                    value.projects[p].entries[e].verification = VerificationRecord(url: pending.url, application: pending.application)
                }
            }
        }
        if success { self.pending = nil; message = "已记录你的确认。以后可直接打开；链接或 App 版本变化后会重新验证。" }
    }

    func rejectPending() {
        pending = nil
        message = "此入口仍为待验证。请在目标对话中复制链接，再编辑入口重试。"
    }

    @discardableResult
    private func change(_ mutation: (inout Workspace) -> Void) -> Bool {
        guard !readOnly else { return false }
        var next = workspace
        mutation(&next)
        do {
            try repository.save(next)
            workspace = next
            reconcileSelection()
            return true
        } catch {
            message = "无法保存，刚才的修改尚未写入。\n\(error.localizedDescription)"
            return false
        }
    }
}
