import SwiftUI
import AppKit
import HarborCore
import UniformTypeIdentifiers

struct HarborEntryRowView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var preferences: PreferencesController
    let row: EntryRow
    @State private var dropPlacement: EntryPlacement?

    private var selected: Bool { model.selectedEntryID == row.id }
    private var local: Bool { LinkPolicy.nativeCandidateURL(row.entry.url) != nil }
    private var verified: Bool { model.currentApplication.map { row.entry.isVerified(for: $0.identity) } ?? false }
    private var rowHeight: CGFloat { preferences.value.density == .compact ? 46 : 58 }
    private var actionTitle: String { verified ? model.t("Open") : (local ? model.t("Verify") : model.t("Info")) }
    private var statusTitle: String { verified ? model.t("Verified") : (local ? (model.pending?.entryID == row.id ? model.t("Confirm") : model.t("Unverified")) : model.t("Unsupported")) }

    var body: some View {
        Group {
            if model.canEdit { decoratedRow.onDrag { model.dragProvider(for: row.id) } }
            else { decoratedRow }
        }
        .onDrop(of: [.harborEntry], delegate: EntryRowDropDelegate(model: model, anchorID: row.id, rowHeight: rowHeight, placement: $dropPlacement))
        .overlay(alignment: dropPlacement == .after ? .bottom : .top) {
            if dropPlacement != nil { Rectangle().fill(preferences.tint).frame(height: 2).padding(.horizontal, 5).allowsHitTesting(false) }
        }
    }

    private var decoratedRow: some View {
        rowContent
            .padding(.horizontal, 12).frame(maxWidth: .infinity).frame(height: rowHeight)
            .background(selected ? preferences.tint.opacity(0.12) : Color.primary.opacity(0.025))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle()).onTapGesture { model.selectEntry(row.id) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(row.entry.title)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityAction { model.selectEntry(row.id) }
            .accessibilityAction(named: Text(model.t("Select Entry"))) { model.selectEntry(row.id) }
            .help(model.canReorder ? model.t("Drag above or below an entry to reorder; drag to a project to move.") : model.t("Reordering is paused while filtered. You can still drag to a project to move."))
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: local ? "bubble.left.and.bubble.right" : "link")
                .foregroundColor(preferences.tint).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(row.entry.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).help(row.entry.title)
                    if row.entry.isFavorite {
                        Image(systemName: "star.fill").font(.system(size: 9)).foregroundColor(preferences.tint).accessibilityLabel(model.t("Favorited"))
                    }
                }
                Text(model.t(LinkPolicy.classify(row.entry.url).sourceLabel)).font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
            Text(statusTitle).font(.system(size: 10, weight: .medium)).foregroundColor(verified ? preferences.tint : .secondary)
                .help(model.stateLabel(row.entry))
            if selected {
                Button(actionTitle) { model.activate(row.entry) }
                    .font(.system(size: 11)).buttonStyle(.bordered).disabled(model.isOpening)
            }
            entryMenu
        }
    }

    private var entryMenu: some View {
        Menu {
            Button(verified ? model.t("Open Entry") : (local ? model.t("Verify Entry") : model.t("View Details"))) {
                model.selectedEntryID = row.id
                model.activate(row.entry)
            }.disabled(model.isOpening)
            Divider()
            Button(row.entry.isFavorite ? model.t("Remove Favorite") : model.t("Favorite Entry")) { model.toggleFavorite(row.id) }.disabled(!model.canEdit)
            Button(model.t("Edit Entry")) { model.stopSearching(); model.editingEntry = row; model.showEntryEditor = true }.disabled(!model.canEdit)
            Menu(model.t("Move to…")) {
                ForEach(model.workspace.projects) { project in
                    Button(project.title) { model.moveEntry(row.id, to: project.id) }.disabled(project.id == row.project.id)
                }
            }.disabled(!model.canEdit)
            Button(model.t("Move Up")) { model.stepEntry(row.id, by: -1) }.disabled(!model.canStepEntry(row.id, by: -1))
            Button(model.t("Move Down")) { model.stepEntry(row.id, by: 1) }.disabled(!model.canStepEntry(row.id, by: 1))
            if !EntryReorderPolicy.allowsReorder(query: model.query, favoritesOnly: model.favoritesOnly) {
                Text(model.t("Clear search or leave Favorites to reorder"))
            }
            Divider()
            Button(model.t("Copy Link")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(row.entry.url, forType: .string)
            }
            Button(model.t("Delete Entry"), role: .destructive) { model.deleteEntry(row.id) }.disabled(!model.canEdit)
        } label: { Image(systemName: "ellipsis") }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20)
        .accessibilityLabel(model.t("More actions: %@", row.entry.title))
        .help(model.t("Open, favorite, move, reorder, or delete this entry"))
    }
}

struct ProjectNavigationRow: View {
    @ObservedObject var model: LauncherModel
    let project: Project
    let tint: Color
    @State private var dropTargeted = false

    var body: some View {
        SidebarNavigationButton(title: project.title, icon: "folder", count: project.entries.count,
            selected: model.selectedProjectID == project.id && !model.favoritesOnly, tint: tint) {
                model.selectedProjectID = project.id
                model.favoritesOnly = false
                model.stopSearching()
            }
            .overlay { RoundedRectangle(cornerRadius: 7).stroke(tint, lineWidth: dropTargeted ? 2 : 0).allowsHitTesting(false) }
            .onDrop(of: [.harborEntry], delegate: ProjectDropDelegate(model: model, projectID: project.id, targeted: $dropTargeted))
    }
}

struct SidebarNavigationButton: View {
    let title: String
    let icon: String
    let count: Int?
    let selected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon).frame(width: 14)
                Text(title).lineLimit(1)
                Spacer(minLength: 2)
                if let count { Text("\(count)").font(.caption).foregroundColor(.secondary) }
            }
            .font(.system(size: 12, weight: selected ? .semibold : .regular))
            .padding(.horizontal, 10).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? tint.opacity(0.12) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
