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
                    Text("泊岸设置").font(.title3.weight(.semibold))
                    Text("让入口适合你的工作习惯").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(22)
            TabView {
                general.tabItem { Label("常规", systemImage: "gearshape") }
                appearance.tabItem { Label("外观", systemImage: "paintpalette") }
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
            VStack(alignment: .leading, spacing: 9) {
                Toggle("登录 Mac 时启动泊岸", isOn: Binding(get: { loginItem.state.isEnabled }, set: { loginItem.setEnabled($0) }))
                    .toggleStyle(.switch).disabled(!loginItem.canManage)
                HStack(spacing: 6) {
                    Image(systemName: loginItem.state.isEnabled ? "checkmark.circle.fill" : "info.circle")
                        .foregroundColor(loginItem.state.isEnabled ? preferences.tint : .secondary)
                    Text(loginItem.statusText).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("刷新") { loginItem.refresh() }.buttonStyle(.link).font(.caption)
                }
                Text("登录时只在菜单栏待命；手动打开时显示面板。")
                    .font(.caption).foregroundColor(.secondary)
                if let restriction = loginItem.restriction { Text(restriction).font(.caption).foregroundColor(.secondary) }
                if loginItem.state == .requiresApproval {
                    HStack {
                        Button("打开系统设置") { loginItem.openSystemSettings() }
                        Button("撤销请求") { loginItem.setEnabled(false) }.disabled(!loginItem.canManage)
                    }
                    Text("请求已经登记，系统允许后才会自动启动。")
                        .font(.caption).foregroundColor(.secondary)
                }
                if let error = loginItem.errorMessage { Text(error).font(.caption).foregroundColor(.red).fixedSize(horizontal: false, vertical: true) }
            }
            Divider()
            Picker("启动时显示", selection: Binding(get: { preferences.value.startView }, set: { choice in preferences.update { $0.startView = choice } })) {
                Text("所有入口").tag(HarborStartView.all)
                Text("收藏").tag(HarborStartView.favorites)
            }.disabled(preferences.readOnly)
            Text("下次启动生效。当前项目和搜索内容会保留到退出。")
                .font(.caption).foregroundColor(.secondary)
            HStack {
                Text("呼出快捷键")
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
                Text("外观").font(.system(size: 12, weight: .medium))
                Picker("外观", selection: Binding(get: { preferences.value.appearance }, set: { choice in preferences.update { $0.appearance = choice } })) {
                    Text("跟随系统").tag(HarborAppearance.system)
                    Text("浅色").tag(HarborAppearance.light)
                    Text("深色").tag(HarborAppearance.dark)
                }.pickerStyle(.segmented).labelsHidden()
            }
            Picker("点缀颜色", selection: Binding(get: { preferences.value.accent }, set: { choice in preferences.update { $0.accent = choice } })) {
                Text("青绿").tag(HarborAccent.teal)
                Text("蓝色").tag(HarborAccent.blue)
                Text("石墨").tag(HarborAccent.graphite)
            }
            Picker("列表密度", selection: Binding(get: { preferences.value.density }, set: { choice in preferences.update { $0.density = choice } })) {
                Text("舒适").tag(HarborDensity.comfortable)
                Text("紧凑").tag(HarborDensity.compact)
            }
            Text("即刻应用到面板和设置。项目与聊天链接不会改变。")
                .font(.caption).foregroundColor(.secondary)
            Spacer(minLength: 0)
            Button("恢复默认外观") {
                preferences.update { $0.appearance = .system; $0.accent = .teal; $0.density = .comfortable }
            }.buttonStyle(.link)
        }.padding(18).disabled(preferences.readOnly)
    }
}
