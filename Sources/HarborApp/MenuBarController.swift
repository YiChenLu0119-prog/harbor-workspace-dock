import AppKit
import Combine
import SwiftUI
import HarborCore

/// The status item is an optional way into Harbor, not the owner of its lifetime.
@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var preferenceSubscription: AnyCancellable?

    init(controller: PanelController) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()

        // A sole SwiftUI MenuBarExtra enables terminationOnRemoval. Removing or hiding
        // this item must leave the workspace, global shortcut, and manual reopen alive.
        statusItem.behavior = [.removalAllowed]
        statusItem.autosaveName = "Item-0"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))
        let image = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: nil)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageLeading

        let hostingController = NSHostingController(rootView: HarborMenuContent(controller: controller, model: controller.model))
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
        popover.behavior = .transient
        popover.animates = false
        controller.dismissQuickAccess = { [weak self] in self?.close() }
        preferenceSubscription = controller.model.preferences.$value.sink { [weak self] value in
            self?.updateAppearance(value)
        }
    }

    /// An explicit Finder/Spotlight launch restores Harbor's entry without resetting
    /// other preferences. Login and --hidden launches keep the system's saved visibility.
    func revealForManualOpen() { statusItem.isVisible = true }

    func close() { popover.performClose(nil) }

    @objc private func togglePopover(_ sender: Any?) {
        guard !popover.isShown else { close(); return }
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func updateAppearance(_ value: HarborPreferences) {
        // @Published sends the next value before it is assigned to the preferences object.
        func t(_ text: String) -> String { HarborLocalization.text(text, language: value.language) }
        statusItem.button?.title = value.showsMenuBarName ? " " + t("Harbor") : ""
        statusItem.button?.toolTip = t("Harbor Quick Access")
        statusItem.button?.setAccessibilityLabel(t("Harbor Quick Access"))
        popover.contentViewController?.title = t("Harbor Quick Access")
        switch value.appearance {
        case .system: popover.appearance = nil
        case .light: popover.appearance = NSAppearance(named: .aqua)
        case .dark: popover.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
