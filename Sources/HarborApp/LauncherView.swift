import SwiftUI
import AppKit
import HarborCore

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject private var preferences: PreferencesController
    @FocusState private var searchFocused: Bool
    private var harborTint: Color { preferences.tint }

    init(model: LauncherModel) {
        self.model = model
        preferences = model.preferences
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2.fill").foregroundColor(harborTint)
                Text(model.t("Harbor")).font(.headline)
                Divider().frame(height: 18)
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField(model.t("Search %@", model.scopeTitle), text: $model.query)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .accessibilityLabel(model.t("Search projects or entries"))
                if !model.query.isEmpty {
                    Button { model.query = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                        .buttonStyle(.plain).help(model.t("Clear search")).accessibilityLabel(model.t("Clear search"))
                }
                Button { model.beginAddEntry() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).help(model.t("Add Entry · ⌘N")).accessibilityLabel(model.t("Add Entry"))
                    .disabled(model.readOnly)
                Button { model.stopSearching(); model.loginItem.refresh(); model.showSettings = true } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless).help(model.t("Settings · ⌘,")).accessibilityLabel(model.t("Settings"))
            }.padding(.horizontal, 20).frame(height: 56)
            Divider()
            if let warning = model.hotkeyWarning {
                Text(warning).font(.caption).foregroundColor(.orange).padding(8)
            }
            if let banner = model.undoBanner {
                HStack(spacing: 10) {
                    Text(banner).font(.system(size: 11)).lineLimit(2)
                    Spacer(minLength: 0)
                    if let action = model.undoAction {
                        Button(model.t("Undo")) { model.undo() }.disabled(!model.canEdit)
                            .help(model.t("Undo: %@ · This session only", action)).accessibilityLabel(model.t("Undo: %@", action))
                    }
                    Button { model.undoBanner = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel(model.t("Dismiss action notice"))
                }.padding(.horizontal, 16).padding(.vertical, 9).background(harborTint.opacity(0.08))
            }
            if let message = model.message {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                    Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { model.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel(model.t("Dismiss notice"))
                }.padding(12).background(harborTint.opacity(0.08))
            }
            if let pending = model.pending {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.t("Did you reach the correct native chat for “%@ · %@”?", pending.projectTitle, pending.title)).font(.subheadline.weight(.semibold))
                    Text(model.t("The app accepted the link. Please check the exact conversation yourself.")).font(.caption).foregroundColor(.secondary)
                    HStack {
                        Button(model.t("Yes, that is the correct chat")) { model.confirmPending() }.buttonStyle(.borderedProminent)
                        Button(model.t("No, keep it unverified")) { model.rejectPending() }.buttonStyle(.bordered)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(harborTint.opacity(0.08))
            }
            HStack(spacing: 0) {
                sidebar
                Divider()
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text(model.scopeTitle).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(model.t(model.query.isEmpty ? "Entries: %@" : "Results: %@", String(model.rows.count))).font(.system(size: 11)).foregroundColor(.secondary)
                        Spacer()
                        if !model.query.isEmpty && (model.selectedProjectID != nil || model.favoritesOnly) {
                            Button(model.t("Search All Entries")) { model.selectedProjectID = nil; model.favoritesOnly = false }
                                .buttonStyle(.link).font(.system(size: 11))
                        }
                    }.padding(.horizontal, 16).frame(height: 36)
                    mainList
                        .background { Color.clear.contentShape(Rectangle()).onTapGesture { model.stopSearching() } }
                }
            }
            Divider()
            HStack(spacing: 10) {
                Text(EntryReorderPolicy.allowsReorder(query: model.query, favoritesOnly: model.favoritesOnly) ? model.t("↑↓ Select   ↩ Open / Verify   ⌘Z Undo") : model.t("Reordering paused while filtered · Drag to a project to move"))
                Spacer()
                Text(model.t("Local only · %@ saved", String(model.totalEntries)))
            }.font(.system(size: 10)).foregroundColor(.secondary).padding(.horizontal, 16).frame(height: 32)
        }
        .frame(width: 720, height: 500)
        .background(.regularMaterial)
        .tint(harborTint)
        .preferredColorScheme(preferences.colorScheme)
        .sheet(isPresented: $model.showProjectEditor) { ProjectEditor(model: model) }
        .sheet(isPresented: $model.showEntryEditor) { EntryEditor(model: model, row: model.editingEntry) }
        .sheet(isPresented: $model.showSettings) { SettingsView(preferences: preferences, loginItem: model.loginItem) }
        .onChange(of: model.focusRequest) { _ in searchFocused = true }
        .onChange(of: model.blurSearchRequest) { _ in searchFocused = false }
        .onChange(of: searchFocused) { focused in if focused { model.listNavigationActive = false } }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            navigationButton(model.t("All Entries"), icon: "square.grid.2x2", count: model.totalEntries, selected: model.selectedProjectID == nil && !model.favoritesOnly) {
                model.selectedProjectID = nil; model.favoritesOnly = false
            }
            navigationButton(model.t("Favorites"), icon: "star", count: model.favoriteCount, selected: model.favoritesOnly) {
                model.selectedProjectID = nil; model.favoritesOnly = true
            }
            Text(model.t("Projects")).font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary).padding(.top, 16).padding(.leading, 10)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(model.workspace.projects) { project in
                        ProjectNavigationRow(model: model, project: project, tint: harborTint)
                    }
                }
            }
            Spacer(minLength: 0)
            Button { model.stopSearching(); model.showProjectEditor = true } label: {
                HStack { Label(model.t("New Project"), systemImage: "folder.badge.plus"); Spacer(minLength: 0) }
                    .padding(10).frame(maxWidth: .infinity).contentShape(Rectangle())
            }.buttonStyle(.plain).font(.system(size: 12)).foregroundColor(harborTint).disabled(!model.canEdit)
        }.padding(10).frame(width: 172).background(Color.primary.opacity(0.025))
    }

    private func navigationButton(_ title: String, icon: String, count: Int?, selected: Bool, action: @escaping () -> Void) -> some View {
        SidebarNavigationButton(title: title, icon: icon, count: count, selected: selected, tint: harborTint) {
            action()
            model.stopSearching()
        }
    }

    @ViewBuilder private var mainList: some View {
        if model.rows.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: model.query.isEmpty ? "tray" : "magnifyingglass").font(.system(size: 30, weight: .light)).foregroundColor(harborTint)
                Text(model.query.isEmpty ? (model.favoritesOnly ? model.t("No favorites yet") : model.t("Give your work a home")) : model.t("No matching entries")).font(.headline)
                Text(model.query.isEmpty ? (model.favoritesOnly ? model.t("Favorite an entry from its More menu to keep it here.") : model.t("Create a project, then paste chat links.\nKeep chatting in the native ChatGPT app.")) : model.t("Try another name or switch to All Entries."))
                    .font(.system(size: 12)).foregroundColor(.secondary).multilineTextAlignment(.center)
                if model.query.isEmpty && model.favoritesOnly {
                    Button(model.t("Browse All Entries")) { model.favoritesOnly = false; model.selectedProjectID = nil; model.stopSearching() }.buttonStyle(.bordered)
                } else if model.query.isEmpty {
                    Button(model.workspace.projects.isEmpty ? model.t("Create Your First Project") : model.t("Add Chat Entry")) { model.beginAddEntry() }
                        .buttonStyle(.borderedProminent).disabled(model.readOnly)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.workspace.projects) { project in
                            let projectRows = model.rows.filter { $0.project.id == project.id }
                            if !projectRows.isEmpty {
                                if model.selectedProjectID == nil {
                                    HStack {
                                        Text(project.title).font(.system(size: 11, weight: .semibold))
                                        Spacer()
                                        Text("\(projectRows.count)").font(.system(size: 10))
                                    }.foregroundColor(.secondary).padding(.horizontal, 10).padding(.top, 7).padding(.bottom, 2)
                                }
                                ForEach(projectRows) { row in entryView(row).id(row.id) }
                            }
                        }
                    }.padding(12)
                }.onChange(of: model.selectedEntryID) { id in
                    if let id { proxy.scrollTo(id, anchor: .center) }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func entryView(_ row: EntryRow) -> some View {
        HarborEntryRowView(model: model, preferences: preferences, row: row)
    }

}

struct ProjectEditor: View {
    @ObservedObject var model: LauncherModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var saveError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.t("New Project")).font(.title3.weight(.semibold))
            TextField(model.t("For example: Writing, Research, Development"), text: $title).textFieldStyle(.roundedBorder).accessibilityLabel(model.t("Project name"))
            if let saveError { Text(saveError).font(.caption).foregroundColor(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button(model.t("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(model.t("Create Project")) {
                    if model.addProject(title: title) { dismiss() }
                    else { saveError = model.message ?? model.t("Could not create the project. Try again.") }
                }
                    .keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 400)
    }
}

struct EntryEditor: View {
    @ObservedObject var model: LauncherModel
    let row: EntryRow?
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var url: String
    @State private var projectID: UUID?
    @State private var saveError: String?

    init(model: LauncherModel, row: EntryRow?) {
        self.model = model
        self.row = row
        _title = State(initialValue: row?.entry.title ?? "")
        _url = State(initialValue: row?.entry.url ?? "")
        _projectID = State(initialValue: row?.project.id ?? model.selectedProjectID ?? model.workspace.projects.first?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(row == nil ? model.t("Add Chat Entry") : model.t("Edit Entry")).font(.title3.weight(.semibold))
            Text(model.t("Copy the link from the target chat in the native ChatGPT app. Harbor saves names and links, not chat content."))
                .font(.caption).foregroundColor(.secondary)
            Picker(model.t("Project"), selection: $projectID) {
                ForEach(model.workspace.projects) { project in Text(project.title).tag(Optional(project.id)) }
            }.disabled(row != nil)
            TextField(model.t("Entry name"), text: $title).textFieldStyle(.roundedBorder).accessibilityLabel(model.t("Entry name"))
            TextField(model.t("Paste a chat link"), text: $url).textFieldStyle(.roundedBorder).accessibilityLabel(model.t("Chat link"))
            Text(linkExplanation).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            if let saveError { Text(saveError).font(.caption).foregroundColor(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button(model.t("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(model.t("Save Entry")) {
                    guard let projectID else { return }
                    if model.saveEntry(projectID: projectID, title: title, url: url, existingID: row?.id) { dismiss() }
                    else { saveError = model.message ?? model.t("Could not save the entry. Try again.") }
                }.keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || projectID == nil)
            }
        }.padding(24).frame(width: 470)
    }

    private var linkExplanation: String {
        switch LinkPolicy.classify(url.trimmingCharacters(in: .whitespacesAndNewlines)) {
        case .localCodex: return model.t("This is a local Codex chat. Save it, select Verify, check the exact native conversation, then return to Harbor to confirm.")
        case .cloudChatGPT, .conversationReference: return model.t("This is a cloud chat or chat reference. You can save it, but native navigation is not confirmed. Harbor will not open a browser.")
        case .unsupported: return url.isEmpty ? model.t("Paste the original link without changing its prefix.") : model.t("Unrecognized link. You can save it for reference, but Harbor will not open it.")
        }
    }
}
