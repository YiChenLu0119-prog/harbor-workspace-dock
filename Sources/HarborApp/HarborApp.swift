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
        MenuBarExtra("Harbor", systemImage: "square.grid.2x2.fill") {
            if let controller = delegate.controller { HarborMenuContent(controller: controller, model: controller.model) }
        }
        .menuBarExtraStyle(.menu)
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
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        model.stopSearching()
    }
    func hide() { panel.orderOut(nil) }
    func showSettings() {
        show()
        model.loginItem.refresh()
        model.showSettings = true
    }
    func toggle() { panel.isVisible && panel.isKeyWindow ? hide() : show() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hide(); return false }

    deinit { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) } }
}
