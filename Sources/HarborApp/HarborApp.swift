import AppKit
import SwiftUI
import Carbon
import Combine
import HarborCore
import Darwin

@main
struct HarborApp: App {
    @NSApplicationDelegateAdaptor(HarborDelegate.self) private var delegate
    init() {
        if let code = LoginItemController.runCommandIfRequested(arguments: ProcessInfo.processInfo.arguments) { exit(code) }
    }
    var body: some Scene {
        MenuBarExtra {
            if let controller = delegate.controller { HarborMenuContent(controller: controller, model: controller.model) }
        } label: {
            if let controller = delegate.controller {
                HarborMenuBarLabel(preferences: controller.model.preferences)
            } else {
                Image(systemName: "square.grid.2x2.fill")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class HarborDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var controller: PanelController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = PanelController(directory: Self.dataDirectory())
        let event = NSAppleEventManager.shared().currentAppleEvent
        let loginLaunch = event?.eventID == kAEOpenApplication && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if LaunchPresentation.shouldShowPanel(isLoginItem: loginLaunch, arguments: ProcessInfo.processInfo.arguments) { controller?.show() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.show()
        return false
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
    private weak var menuBarWindow: NSWindow?

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
    func attachMenuBarWindow(_ window: NSWindow?) {
        guard window !== panel else { return }
        menuBarWindow = window
        window?.title = model.t("Harbor Quick Access")
    }
    func dismissMenuBar() { menuBarWindow?.orderOut(nil) }
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
