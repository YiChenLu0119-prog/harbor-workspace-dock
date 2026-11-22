import AppKit
import HarborCore

struct NativeApplication {
    let url: URL
    let identity: NativeAppIdentity
}

enum NativeOpenError: LocalizedError {
    case unavailable
    case unsupported
    case notAccepted
    var errorDescription: String? {
        switch self {
        case .unavailable: return "找不到支持 Codex 链接的原生 ChatGPT / Codex App。请先安装并打开该 App。"
        case .unsupported: return "此入口尚无已确认的原生打开方式。链接已保存在本机，不会转到浏览器。"
        case .notAccepted: return "原生 App 没有接收此链接，请稍后重试。"
        }
    }
}

@MainActor
final class NativeLinkOpener {
    func application() -> NativeApplication? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex"),
              let bundle = Bundle(url: url), bundle.bundleIdentifier == "com.openai.codex",
              let types = bundle.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]],
              types.contains(where: { ($0["CFBundleURLSchemes"] as? [String])?.contains("codex") == true }),
              let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
              let build = bundle.infoDictionary?["CFBundleVersion"] as? String else { return nil }
        return NativeApplication(url: url, identity: NativeAppIdentity(bundleID: "com.openai.codex", version: "\(version) (\(build))"))
    }

    func open(_ rawURL: String, application: NativeApplication, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = LinkPolicy.nativeCandidateURL(rawURL) else {
            completion(.failure(NativeOpenError.unsupported)); return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // Always target the known native application, never the default URL handler.
        NSWorkspace.shared.open([url], withApplicationAt: application.url, configuration: configuration) { app, error in
            DispatchQueue.main.async {
                if let error { completion(.failure(error)) }
                else if app == nil { completion(.failure(NativeOpenError.notAccepted)) }
                else { completion(.success(())) }
            }
        }
    }
}
