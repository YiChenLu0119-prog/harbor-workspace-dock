import Foundation

public enum LinkKind: Equatable {
    case localCodex(UUID)
    case cloudChatGPT
    case conversationReference
    case unsupported

    public var sourceLabel: String {
        switch self {
        case .localCodex: return "Local Codex"
        case .cloudChatGPT: return "ChatGPT Cloud"
        case .conversationReference: return "Chat Reference"
        case .unsupported: return "Other Link"
        }
    }
}

public enum LinkPolicy {
    public static func classify(_ text: String) -> LinkKind {
        guard !text.isEmpty, text == text.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !text.contains("\\"), let parts = URLComponents(string: text),
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil, let scheme = parts.scheme?.lowercased(),
              let host = parts.host?.lowercased() else { return .unsupported }

        // Escaped separators/IDs are unnecessary here and can obscure the actual target.
        guard !parts.percentEncodedPath.contains("%"), !text.contains(" ") else { return .unsupported }
        let components = parts.path.split(separator: "/", omittingEmptySubsequences: false)
        if scheme == "codex", host == "threads", components.count == 2,
           components[0].isEmpty, let id = UUID(uuidString: String(components[1])) {
            return .localCodex(id)
        }
        if scheme == "chatgpt-conversation", UUID(uuidString: host) != nil, parts.path.isEmpty {
            return .conversationReference
        }
        if scheme == "https", host == "chatgpt.com" || host == "chat.openai.com" {
            if components.count == 3, components[0].isEmpty, components[1] == "c",
               UUID(uuidString: String(components[2])) != nil { return .cloudChatGPT }
            // ChatGPT project/custom-GPT conversation routes remain cloud links.
            if components.count == 5, components[0].isEmpty, components[1] == "g",
               !components[2].isEmpty, components[3] == "c",
               UUID(uuidString: String(components[4])) != nil { return .cloudChatGPT }
        }
        return .unsupported
    }

    public static func nativeCandidateURL(_ text: String) -> URL? {
        guard case .localCodex = classify(text) else { return nil }
        return URL(string: text)
    }
}
