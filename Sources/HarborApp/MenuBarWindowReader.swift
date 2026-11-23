import AppKit
import SwiftUI

/// Captures only the window hosting the menu-bar view, never whichever window happens to be key.
struct MenuBarWindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowObserverView {
        let view = WindowObserverView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: WindowObserverView, context: Context) {
        view.onWindow = onWindow
    }

    final class WindowObserverView: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }
}
