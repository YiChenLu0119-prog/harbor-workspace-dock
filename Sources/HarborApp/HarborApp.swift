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
        MenuBarExtra("泊岸 Harbor", systemImage: "square.grid.2x2.fill") {
            Button("显示泊岸  ⌃⌥Space") { delegate.controller?.show() }
            Button("添加入口…") { delegate.controller?.show(); delegate.controller?.model.beginAddEntry() }
            Button("设置…") { delegate.controller?.showSettings() }.keyboardShortcut(",")
            Divider()
            Button("显示本地资料位置") {
                if let url = delegate.controller?.model.dataURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
                }
            }
            Divider()
            Button("退出泊岸") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class HarborDelegate: NSObject, NSApplicationDelegate {
    var controller: PanelController?
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
        panel.title = "泊岸 Harbor"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: LauncherView(model: model))
        panel.delegate = self
        panel.center()
        model.closePanel = { [weak self] in self?.hide() }
        model.showPanel = { [weak self] in self?.show() }
        preferenceSubscription = model.preferences.$value.sink { [weak self] value in
            switch value.appearance {
            case .system: self?.panel.appearance = nil
            case .light: self?.panel.appearance = NSAppearance(named: .aqua)
            case .dark: self?.panel.appearance = NSAppearance(named: .darkAqua)
            }
        }
        hotkey = HotkeyManager { [weak self] in self?.toggle() }
        if let status = hotkey?.register(), status != noErr {
            model.hotkeyWarning = "⌃⌥Space 未能注册（可能被占用）。仍可使用菜单栏打开泊岸。"
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel, self.panel.attachedSheet == nil else { return event }
            // Leave input-method candidate navigation/commit untouched (Chinese, Japanese, etc.).
            if let editor = self.panel.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
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
            // Only the search field owns result navigation. Native buttons retain Return/arrow behavior.
            guard self.panel.firstResponder is NSTextView else { return event }
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
        model.focusRequest += 1
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
