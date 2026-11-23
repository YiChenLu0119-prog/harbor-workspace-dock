import AppKit
import SwiftUI
import Carbon
import Combine
import HarborCore
import Darwin

@main
enum HarborApp {
    @MainActor
    static func main() {
        if let code = LoginItemController.runCommandIfRequested(arguments: ProcessInfo.processInfo.arguments) { exit(code) }
        let application = NSApplication.shared
        let delegate = HarborDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class HarborDelegate: NSObject, NSApplicationDelegate {
    private var controller: PanelController?
    private var menuBar: MenuBarController?
    private var menuSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let controller = PanelController(directory: Self.dataDirectory())
        self.controller = controller
        menuBar = MenuBarController(controller: controller)
        menuSubscription = controller.model.preferences.$value.sink { [weak self] value in
            self?.installMainMenu(language: value.language)
        }
        let event = NSAppleEventManager.shared().currentAppleEvent
        let loginLaunch = event?.eventID == kAEOpenApplication && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if LaunchPresentation.shouldShowPanel(isLoginItem: loginLaunch, arguments: ProcessInfo.processInfo.arguments) {
            menuBar?.revealForManualOpen()
            controller.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBar?.revealForManualOpen()
        controller?.show()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func showWorkspace(_ sender: Any?) { controller?.show() }
    @objc private func showSettings(_ sender: Any?) { controller?.showSettings() }

    private func installMainMenu(language: HarborLanguage) {
        func t(_ text: String) -> String { HarborLocalization.text(text, language: language) }
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: t("Harbor"))
        let open = NSMenuItem(title: t("Open Workspace"), action: #selector(showWorkspace(_:)), keyEquivalent: "")
        open.target = self
        appMenu.addItem(open)
        let settings = NSMenuItem(title: t("Settings…"), action: #selector(showSettings(_:)), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: t("Quit Harbor"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)

        // AppKit owns the application lifecycle; keep text-field keyboard commands in the responder chain.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: t("Edit"))
        editMenu.addItem(withTitle: t("Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: t("Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: t("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: t("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: t("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: t("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    private static func dataDirectory() -> URL {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--data-dir"), arguments.indices.contains(index + 1) {
            return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        }
        if let override = ProcessInfo.processInfo.environment["HARBOR_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HarborWorkspaceDock", isDirectory: true)
    }
}

private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class LauncherHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let model: LauncherModel
    private let panel: LauncherPanel
    private var hotkey: HotkeyManager?
    private var keyMonitor: Any?
    private var preferenceSubscription: AnyCancellable?
    var dismissQuickAccess: (() -> Void)?

    init(directory: URL) {
        model = LauncherModel(directory: directory)
        panel = LauncherPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 500), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        panel.title = "Harbor"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = LauncherHostingView(rootView: LauncherView(model: model))
        panel.delegate = self
        panel.center()
        model.closePanel = { [weak self] in self?.hide() }
        model.showPanel = { [weak self] in self?.show() }
        model.endSearchEditing = { [weak self] in
            guard let self else { return }
            self.panel.makeFirstResponder(self.panel.contentView)
        }
        preferenceSubscription = model.preferences.$value.sink { [weak self] value in
            switch value.appearance {
            case .system: self?.panel.appearance = nil
            case .light: self?.panel.appearance = NSAppearance(named: .aqua)
            case .dark: self?.panel.appearance = NSAppearance(named: .darkAqua)
            }
        }
        hotkey = HotkeyManager { [weak self] in self?.toggle() }
        if let status = hotkey?.register(), status != noErr {
            model.hotkeyUnavailable = true
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel, self.panel.attachedSheet == nil else { return event }
            // Leave input-method candidate navigation/commit untouched (Chinese, Japanese, etc.).
            if let editor = self.panel.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            if event.keyCode == 48 { self.model.listNavigationActive = false; return event }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if modifiers == .command, event.charactersIgnoringModifiers == "z" {
                // Typed text gets its own undo first. An empty, untouched search field doesn't swallow workspace undo.
                if let editor = self.panel.firstResponder as? NSTextView,
                   !editor.string.isEmpty || (editor.undoManager?.canUndo ?? false) { return event }
                self.model.undo()
                return nil
            }
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command), event.charactersIgnoringModifiers == "n" {
                self.model.beginAddEntry(); return nil
            }
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command), event.charactersIgnoringModifiers == "f" {
                self.model.focusRequest += 1; return nil
            }
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command), event.charactersIgnoringModifiers == "," {
                self.showSettings(); return nil
            }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            if event.keyCode == 53 { self.hide(); return nil }
            // Search and explicit list focus own result navigation. Tab-focused controls retain their keys.
            let listHasFocus = self.panel.firstResponder === self.panel.contentView && self.model.listNavigationActive
            guard self.panel.firstResponder is NSTextView || listHasFocus else { return event }
            switch event.keyCode {
            case 125: self.model.moveSelection(1); return nil
            case 126: self.model.moveSelection(-1); return nil
            case 36, 76: self.model.activateSelected(); return nil
            default: return event
            }
        }
    }

    func show() {
        dismissMenuBar()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        model.stopSearching()
    }
    func hide() { dismissMenuBar(); panel.orderOut(nil) }
    func dismissMenuBar() { dismissQuickAccess?() }
    private var hasActiveEditor: Bool { model.showEntryEditor || model.showProjectEditor || model.showSettings }
    func showProject(_ id: UUID) {
        guard model.workspace.projects.contains(where: { $0.id == id }) else { return }
        guard !hasActiveEditor else { show(); return }
        model.query = ""
        model.favoritesOnly = false
        model.selectedProjectID = id
        show()
    }
    func showFavorites() {
        guard !hasActiveEditor else { show(); return }
        model.query = ""
        model.selectedProjectID = nil
        model.favoritesOnly = true
        show()
    }
    func showQuickEntry(_ id: UUID) {
        guard !model.isOpening, !model.isReceivingDrop,
              let entry = model.entry(id), let project = model.project(containing: id) else { return }
        let activeEditor = hasActiveEditor
        let route = MenuBarQuickAccess.route(for: entry, application: model.currentApplication?.identity,
                                            hasPendingConfirmation: model.pending != nil, hasActiveEditor: activeEditor)
        dismissMenuBar()
        if route == .verifiedNative {
            model.activate(entry)
            return
        }
        if !activeEditor {
            model.query = ""
            model.favoritesOnly = false
            model.selectedProjectID = project.id
            model.selectEntry(id)
        }
        show()
        // Unsupported links explain their limit in the workspace. Unverified native links
        // wait for the existing Verify action; a pending confirmation is never replaced.
        if !activeEditor, model.pending == nil,
           LinkPolicy.nativeCandidateURL(entry.url) == nil || model.currentApplication == nil {
            model.activate(entry)
        }
    }
    func showAddEntry() {
        let activeEditor = hasActiveEditor
        show()
        if !activeEditor { model.beginAddEntry() }
    }
    func showSettings() {
        show()
        guard !model.showEntryEditor && !model.showProjectEditor else { return }
        model.loginItem.refresh()
        model.showSettings = true
    }
    func toggle() { panel.isVisible && panel.isKeyWindow ? hide() : show() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hide(); return false }

    deinit { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) } }
}
