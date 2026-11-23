import SwiftUI
import AppKit
import HarborCore

struct HarborMenuContent: View {
    let controller: PanelController
    @ObservedObject var model: LauncherModel

    private var favorites: [MenuBarFavorite] { MenuBarQuickAccess.favorites(in: model.workspace) }
    private var busy: Bool { model.isOpening || model.isReceivingDrop }
    private var contentHeight: CGFloat {
        let favoriteHeight = favorites.isEmpty ? 82 : 28 + favorites.count * 52
        let projectHeight = model.workspace.projects.isEmpty ? 82 : 28 + model.workspace.projects.count * 38
        return CGFloat(min(340, favoriteHeight + projectHeight + 20))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.readOnly {
                attention(model.t("Your library needs attention"), icon: "exclamationmark.triangle")
            } else {
                if model.pending != nil {
                    attention(model.t("Confirmation waiting"), icon: "checkmark.bubble")
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        favoritesSection
                        projectsSection
                    }.padding(12)
                }.frame(height: contentHeight)
            }
            Divider()
            footer
        }
        .frame(width: 360)
        .background(.regularMaterial)
        .tint(model.preferences.tint)
        .preferredColorScheme(model.preferences.colorScheme)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 19)).foregroundColor(model.preferences.tint)
                    .frame(width: 36, height: 36)
                    .background(model.preferences.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.t("Harbor")).font(.system(size: 15, weight: .semibold))
                    Text(model.readOnly ? model.t("Library unavailable") : model.t("%@ projects · %@ entries", String(model.workspace.projects.count), String(model.totalEntries)))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button { controller.show() } label: {
                    HStack {
                        Text(model.t("Open Workspace"))
                        Spacer(minLength: 4)
                        Text("⌃⌥Space").font(.system(size: 10)).opacity(0.8)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.vertical, 5).frame(maxWidth: .infinity).contentShape(Rectangle())
                }.buttonStyle(.borderedProminent)
                    .accessibilityLabel(model.t("Open Workspace"))
                Button { controller.showAddEntry() } label: {
                    Image(systemName: "plus").frame(width: 22, height: 24).contentShape(Rectangle())
                }.buttonStyle(.bordered).disabled(!model.canEdit)
                    .help(model.t("Add Entry"))
                    .accessibilityLabel(model.t("Add Entry"))
            }
        }.padding(16)
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                sectionTitle(model.t("Favorites"), count: model.favoriteCount)
                Spacer(minLength: 0)
                if model.favoriteCount > 0 {
                    Button(model.t("View all")) { controller.showFavorites() }
                        .buttonStyle(.link).font(.system(size: 11))
                        .accessibilityLabel(model.t("View all favorites"))
                }
            }.padding(.horizontal, 6).padding(.bottom, 3)
            if favorites.isEmpty {
                Text(model.t("Favorite an entry from its More menu to keep it here."))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6).padding(.vertical, 8)
            } else {
                ForEach(favorites) { item in
                    MenuBarShortcutRow(title: item.entry.title, subtitle: item.projectTitle,
                                       symbol: "star.fill", detail: actionLabel(item.entry), tint: model.preferences.tint) {
                        controller.showQuickEntry(item.id)
                    }
                    .disabled(busy)
                    .help(item.entry.title + " · " + item.projectTitle + "\n" + model.stateLabel(item.entry))
                }
            }
        }
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle(model.t("Projects"), count: model.workspace.projects.count)
                .padding(.horizontal, 6).padding(.bottom, 3)
            if model.workspace.projects.isEmpty {
                Text(model.t("Create a project in your workspace to keep related entries together."))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6).padding(.vertical, 8)
            } else {
                ForEach(model.workspace.projects) { project in
                    MenuBarShortcutRow(title: project.title, subtitle: nil, symbol: "folder",
                                       detail: String(project.entries.count), tint: model.preferences.tint) {
                        controller.showProject(project.id)
                    }
                    .help(project.title)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button { controller.showSettings() } label: {
                Label(model.t("Settings"), systemImage: "gearshape")
                    .padding(.vertical, 7).padding(.horizontal, 4).contentShape(Rectangle())
            }.buttonStyle(.plain).keyboardShortcut(",")
            Spacer()
            Text(model.t("Local only")).foregroundColor(.secondary)
            Menu {
                Button(model.undoAction.map { model.t("Undo: %@", $0) } ?? model.t("Undo Workspace Change")) {
                    controller.show(); model.undo()
                }.disabled(model.undoAction == nil || !model.canEdit || model.showEntryEditor || model.showProjectEditor || model.showSettings)
                    .help(model.t("⌘Z · Undo history lasts for this session only"))
                Button(model.t("Show Data Folder")) {
                    controller.dismissMenuBar()
                    NSWorkspace.shared.activateFileViewerSelecting([model.dataURL.deletingLastPathComponent()])
                }
                Divider()
                Button(model.t("Quit Harbor")) { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis.circle").frame(width: 24, height: 26)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel(model.t("More actions"))
                .help(model.t("More actions"))
        }.font(.system(size: 11)).padding(.horizontal, 16).padding(.vertical, 8)
    }

    private func attention(_ title: String, icon: String) -> some View {
        Button { controller.show() } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title).font(.system(size: 11, weight: .medium))
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 9))
            }.padding(12).frame(maxWidth: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundColor(model.preferences.tint)
            .background(model.preferences.tint.opacity(0.08))
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack(spacing: 5) {
            Text(title).font(.system(size: 11, weight: .semibold))
            Text(String(count)).font(.system(size: 10)).foregroundColor(.secondary)
        }
    }

    private func actionLabel(_ entry: ChatEntry) -> String {
        if model.pending != nil || model.showEntryEditor || model.showProjectEditor || model.showSettings { return model.t("View") }
        guard LinkPolicy.nativeCandidateURL(entry.url) != nil else { return model.t("Info") }
        guard let application = model.currentApplication else { return model.t("Info") }
        return model.t(entry.isVerified(for: application.identity) ? "Open" : "Verify…")
    }
}

private struct MenuBarShortcutRow: View {
    let title: String
    let subtitle: String?
    let symbol: String
    let detail: String
    let tint: Color
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 12)).foregroundColor(tint).frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    if let subtitle { Text(subtitle).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 8)
                Text(detail).font(.system(size: 10)).foregroundColor(.secondary)
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 8).frame(maxWidth: .infinity).frame(height: subtitle == nil ? 34 : 48)
            .contentShape(Rectangle())
            .background(hovered ? tint.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
            .onHover { hovered = $0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([title, subtitle, detail].compactMap { $0 }.joined(separator: ", "))
    }
}
