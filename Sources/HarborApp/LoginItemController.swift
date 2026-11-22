import AppKit
import ServiceManagement
import HarborCore

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var state: LoginItemState = .unknown
    @Published private var issue: LocalizedNotice?
    func errorMessage(in language: HarborLanguage) -> String? { issue?.rendered(in: language) }
    let canManage: Bool
    let restriction: String?

    init(arguments: [String] = ProcessInfo.processInfo.arguments, environment: [String: String] = ProcessInfo.processInfo.environment) {
        let directory = Bundle.main.bundleURL.deletingLastPathComponent().standardizedFileURL
        let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let userApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        let installed = Bundle.main.bundleURL.pathExtension == "app" && [systemApplications, userApplications].contains(directory)
        let isolated = arguments.contains("--data-dir") || environment["HARBOR_DATA_DIR"] != nil
        canManage = installed && !isolated
        restriction = isolated ? "Isolated test mode does not change login items." : (installed ? nil : "Move Harbor to Applications before setting up launch at login.")
        refresh()
    }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .notRegistered: state = .notRegistered
        case .enabled: state = .enabled
        case .requiresApproval: state = .requiresApproval
        case .notFound: state = .notFound
        @unknown default: state = .unknown
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard canManage else { issue = restriction.map { .text(HarborText($0)) }; refresh(); return }
        issue = nil
        do {
            if enabled {
                // An existing approval request is not active, and re-registering won't approve it.
                if SMAppService.mainApp.status == .notRegistered || SMAppService.mainApp.status == .notFound {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
        } catch { issue = .failure("The system could not complete the change: %@", error) }
        refresh()
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }

    func statusText(in language: HarborLanguage) -> String {
        let source: String
        switch state {
        case .notRegistered: source = "Off"
        case .enabled: source = "Enabled"
        case .requiresApproval: source = "Waiting for System Approval"
        case .notFound: source = "Application Not Found"
        case .unknown: source = "Unknown Status"
        }
        return HarborLocalization.text(source, language: language)
    }

    /// Runs only for explicit command-line management and returns actual system status.
    static func runCommandIfRequested(arguments: [String]) -> Int32? {
        let flags = ["--enable-login-item", "--disable-login-item", "--login-item-status"].filter(arguments.contains)
        guard !flags.isEmpty else { return nil }
        guard flags.count == 1 else {
            print("{\"error\":\"Choose exactly one login-item command\"}")
            return 1
        }
        let controller = LoginItemController(arguments: arguments)
        let flag = flags[0]
        if flag == "--enable-login-item" { controller.setEnabled(true) }
        if flag == "--disable-login-item" { controller.setEnabled(false) }
        let response: [String: Any] = [
            "status": controller.state.rawValue,
            "enabled": controller.state.isEnabled,
            "canManage": controller.canManage,
            "applicationPath": Bundle.main.bundlePath,
            "error": controller.errorMessage(in: .english) as Any? ?? NSNull(),
            "restriction": controller.restriction as Any? ?? NSNull()
        ]
        if let data = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]), let string = String(data: data, encoding: .utf8) { print(string) }
        if flag == "--login-item-status" { return 0 }
        if controller.errorMessage(in: .english) != nil { return 1 }
        if flag == "--enable-login-item" { return controller.state.isEnabled ? 0 : (controller.state == .requiresApproval ? 2 : 1) }
        return controller.state == .notRegistered ? 0 : 1
    }
}
