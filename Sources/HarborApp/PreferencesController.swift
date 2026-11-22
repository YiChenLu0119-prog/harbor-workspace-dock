import AppKit
import SwiftUI
import HarborCore

@MainActor
final class PreferencesController: ObservableObject {
    @Published private(set) var value = HarborPreferences()
    @Published private var issue: LocalizedNotice?
    var errorMessage: String? { issue?.rendered(in: value.language) }
    @Published private(set) var readOnly = false
    private let repository: PreferencesRepository

    init(directory: URL) {
        repository = PreferencesRepository(directory: directory)
        do { value = try repository.loadOrCreate() }
        catch {
            readOnly = true
            issue = .failure("Could not read preferences. Using the default appearance; your projects are unaffected.\n%@", error)
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
            issue = nil
            return true
        } catch {
            issue = .failure("Preferences were not saved: %@", error)
            return false
        }
    }

    func t(_ english: String, _ arguments: String...) -> String {
        HarborLocalization.text(english, language: value.language, arguments: arguments)
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
