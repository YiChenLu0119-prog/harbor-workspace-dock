import SwiftUI
import AppKit

struct HarborMenuContent: View {
    let controller: PanelController
    @ObservedObject var model: LauncherModel

    var body: some View {
        Button(model.t("Show Harbor  ⌃⌥Space")) { controller.show() }
        Button(model.t("Add Entry…")) { controller.show(); model.beginAddEntry() }.disabled(!model.canEdit)
        Button(model.undoAction.map { model.t("Undo: %@", $0) } ?? model.t("Undo Workspace Change")) { model.undo() }
            .disabled(model.undoAction == nil || !model.canEdit)
            .help(model.t("⌘Z · Undo history lasts for this session only"))
        Button(model.t("Settings…")) { controller.showSettings() }.keyboardShortcut(",")
        Divider()
        Button(model.t("Show Data Folder")) { NSWorkspace.shared.activateFileViewerSelecting([model.dataURL.deletingLastPathComponent()]) }
        Divider()
        Button(model.t("Quit Harbor")) { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }
}
