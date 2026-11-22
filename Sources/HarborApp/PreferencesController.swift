import AppKit
import SwiftUI
import HarborCore

@MainActor
final class PreferencesController: ObservableObject {
    @Published private(set) var value = HarborPreferences()
    @Published private(set) var errorMessage: String?
    @Published private(set) var readOnly = false
    private let repository: PreferencesRepository

    init(directory: URL) {
        repository = PreferencesRepository(directory: directory)
        do { value = try repository.load() }
        catch {
            readOnly = true
            errorMessage = "无法读取偏好，暂用默认外观；你的项目资料不受影响。\n\(error.localizedDescription)"
        }
    }

    @discardableResult
    func update(_ mutation: (inout HarborPreferences) -> Void) -> Bool {
        guard !readOnly else { return false }
        var next = value
        mutation(&next)
        do {
            try repository.save(next)
            value = next
            errorMessage = nil
            return true
        } catch {
            errorMessage = "偏好未保存：\(error.localizedDescription)"
            return false
        }
    }

    var colorScheme: ColorScheme? {
        switch value.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var appKitAppearance: NSAppearance? {
        switch value.appearance {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    var tint: Color {
        // Semantic light/dark variants keep text and selection contrast on native materials.
        let accent = value.accent
        return Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            switch accent {
            case .teal: return dark ? NSColor(red: 0.40, green: 0.76, blue: 0.79, alpha: 1) : NSColor(red: 0.14, green: 0.37, blue: 0.44, alpha: 1)
            case .blue: return dark ? .systemCyan : .systemBlue
            case .graphite: return dark ? .lightGray : .darkGray
            }
        })
    }
}
