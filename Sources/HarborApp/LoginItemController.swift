import AppKit
import ServiceManagement
import HarborCore

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var state: LoginItemState = .unknown
    @Published private(set) var errorMessage: String?
    let canManage: Bool
    let restriction: String?

    init(arguments: [String] = ProcessInfo.processInfo.arguments, environment: [String: String] = ProcessInfo.processInfo.environment) {
        let directory = Bundle.main.bundleURL.deletingLastPathComponent().standardizedFileURL
        let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let userApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        let installed = Bundle.main.bundleURL.pathExtension == "app" && [systemApplications, userApplications].contains(directory)
        let isolated = arguments.contains("--data-dir") || environment["HARBOR_DATA_DIR"] != nil
        canManage = installed && !isolated
        restriction = isolated ? "隔离验收模式不会修改系统登录项。" : (installed ? nil : "请先把泊岸放进「应用程序」文件夹，再设置登录启动。")
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
        guard canManage else { errorMessage = restriction; refresh(); return }
        errorMessage = nil
        do {
            if enabled {
                // An existing approval request is not active, and re-registering won't approve it.
                if SMAppService.mainApp.status == .notRegistered || SMAppService.mainApp.status == .notFound {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
        } catch { errorMessage = "系统未完成设置：\(error.localizedDescription)" }
        refresh()
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }

    var statusText: String {
        switch state {
        case .notRegistered: return "未开启"
        case .enabled: return "已启用"
        case .requiresApproval: return "等待系统允许"
        case .notFound: return "系统未找到此应用"
        case .unknown: return "状态未知"
        }
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
            "error": controller.errorMessage as Any? ?? NSNull(),
            "restriction": controller.restriction as Any? ?? NSNull()
        ]
        if let data = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]), let string = String(data: data, encoding: .utf8) { print(string) }
        if flag == "--login-item-status" { return 0 }
        if controller.errorMessage != nil { return 1 }
        if flag == "--enable-login-item" { return controller.state.isEnabled ? 0 : (controller.state == .requiresApproval ? 2 : 1) }
        return controller.state == .notRegistered ? 0 : 1
    }
}
