import SwiftUI
import HarborCore

struct SettingsView: View {
    @ObservedObject var preferences: PreferencesController
    @ObservedObject var loginItem: LoginItemController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preferences.t("Harbor Settings")).font(.title3.weight(.semibold))
                    Text(preferences.t("Make your workspace feel familiar.")).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button(preferences.t("Done")) { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(22)
            TabView {
                general.tabItem { Label(preferences.t("General"), systemImage: "gearshape") }
                appearance.tabItem { Label(preferences.t("Appearance"), systemImage: "paintpalette") }
            }.padding(.horizontal, 18).padding(.bottom, 14)
            if let error = preferences.errorMessage {
                Text(error).font(.caption).foregroundColor(.red).padding(.horizontal, 22).padding(.bottom, 12)
            }
        }
        .frame(width: 520, height: 450)
        .tint(preferences.tint)
        .preferredColorScheme(preferences.colorScheme)
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginItem.refresh() }
    }

    private var general: some View {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            Picker(preferences.t("Language"), selection: Binding(get: { preferences.value.language }, set: { choice in preferences.update { $0.language = choice } })) {
                Text("English").tag(HarborLanguage.english)
                Text("简体中文").tag(HarborLanguage.simplifiedChinese)
            }.disabled(preferences.readOnly)
            Text(preferences.t("Changes apply immediately. Project and entry names stay as you wrote them."))
                .font(.caption).foregroundColor(.secondary)
            Divider()
            VStack(alignment: .leading, spacing: 9) {
                Toggle(preferences.t("Launch Harbor at login"), isOn: Binding(get: { loginItem.state.isEnabled }, set: { loginItem.setEnabled($0) }))
                    .toggleStyle(.switch).disabled(!loginItem.canManage)
                HStack(spacing: 6) {
                    Image(systemName: loginItem.state.isEnabled ? "checkmark.circle.fill" : "info.circle")
                        .foregroundColor(loginItem.state.isEnabled ? preferences.tint : .secondary)
                    Text(loginItem.statusText(in: preferences.value.language)).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button(preferences.t("Refresh")) { loginItem.refresh() }.buttonStyle(.link).font(.caption)
                }
                Text(preferences.t("At login, Harbor waits in the menu bar. Manual launches show the panel."))
                    .font(.caption).foregroundColor(.secondary)
                if let restriction = loginItem.restriction { Text(preferences.t(restriction)).font(.caption).foregroundColor(.secondary) }
                if loginItem.state == .requiresApproval {
                    HStack {
                        Button(preferences.t("Open System Settings")) { loginItem.openSystemSettings() }
                        Button(preferences.t("Cancel Request")) { loginItem.setEnabled(false) }.disabled(!loginItem.canManage)
                    }
                    Text(preferences.t("The request is registered. Automatic launch starts only after system approval."))
                        .font(.caption).foregroundColor(.secondary)
                }
                if let error = loginItem.errorMessage(in: preferences.value.language) { Text(error).font(.caption).foregroundColor(.red).fixedSize(horizontal: false, vertical: true) }
            }
            Divider()
            Picker(preferences.t("Show at launch"), selection: Binding(get: { preferences.value.startView }, set: { choice in preferences.update { $0.startView = choice } })) {
                Text(preferences.t("All Entries")).tag(HarborStartView.all)
                Text(preferences.t("Favorites")).tag(HarborStartView.favorites)
            }.disabled(preferences.readOnly)
            Text(preferences.t("Applies on the next launch. Your current project and search stay until you quit."))
                .font(.caption).foregroundColor(.secondary)
            HStack {
                Text(preferences.t("Global shortcut"))
                Spacer()
                Text("⌃⌥Space").font(.system(.body, design: .monospaced)).foregroundColor(.secondary)
            }.font(.system(size: 12))
            Spacer(minLength: 0)
          }.padding(18)
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 9) {
                Text(preferences.t("Appearance")).font(.system(size: 12, weight: .medium))
                Picker(preferences.t("Appearance"), selection: Binding(get: { preferences.value.appearance }, set: { choice in preferences.update { $0.appearance = choice } })) {
                    Text(preferences.t("System")).tag(HarborAppearance.system)
                    Text(preferences.t("Light")).tag(HarborAppearance.light)
                    Text(preferences.t("Dark")).tag(HarborAppearance.dark)
                }.pickerStyle(.segmented).labelsHidden()
            }
            Picker(preferences.t("Accent color"), selection: Binding(get: { preferences.value.accent }, set: { choice in preferences.update { $0.accent = choice } })) {
                Text(preferences.t("Teal")).tag(HarborAccent.teal)
                Text(preferences.t("Blue")).tag(HarborAccent.blue)
                Text(preferences.t("Graphite")).tag(HarborAccent.graphite)
            }
            Picker(preferences.t("List density"), selection: Binding(get: { preferences.value.density }, set: { choice in preferences.update { $0.density = choice } })) {
                Text(preferences.t("Comfortable")).tag(HarborDensity.comfortable)
                Text(preferences.t("Compact")).tag(HarborDensity.compact)
            }
            Text(preferences.t("Applies immediately to the panel and settings. Your entries are unchanged."))
                .font(.caption).foregroundColor(.secondary)
            Spacer(minLength: 0)
            Button(preferences.t("Reset Appearance")) {
                preferences.update { $0.appearance = .system; $0.accent = .teal; $0.density = .comfortable }
            }.buttonStyle(.link)
        }.padding(18).disabled(preferences.readOnly)
    }
}
