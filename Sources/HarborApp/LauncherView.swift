import SwiftUI
import AppKit
import HarborCore

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject private var preferences: PreferencesController
    @FocusState private var searchFocused: Bool
    private var harborTint: Color { preferences.tint }

    init(model: LauncherModel) {
        self.model = model
        preferences = model.preferences
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2.fill").foregroundColor(harborTint)
                Text("泊岸").font(.headline)
                Divider().frame(height: 18)
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("搜索\(model.scopeTitle)", text: $model.query)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .accessibilityLabel("搜索项目或聊天入口")
                if !model.query.isEmpty {
                    Button { model.query = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                        .buttonStyle(.plain).help("清除搜索").accessibilityLabel("清除搜索")
                }
                Button { model.beginAddEntry() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).help("添加入口 · ⌘N").accessibilityLabel("添加入口")
                    .disabled(model.readOnly)
                Button { model.loginItem.refresh(); model.showSettings = true } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless).help("设置 · ⌘,").accessibilityLabel("设置")
            }.padding(.horizontal, 20).frame(height: 56)
            Divider()
            if let warning = model.hotkeyWarning {
                Text(warning).font(.caption).foregroundColor(.orange).padding(8)
            }
            if let message = model.message {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                    Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { model.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("关闭提示")
                }.padding(12).background(harborTint.opacity(0.08))
            }
            if let pending = model.pending {
                VStack(alignment: .leading, spacing: 8) {
                    Text("已打开「\(pending.projectTitle) · \(pending.title)」对应的原生对话吗？").font(.subheadline.weight(.semibold))
                    Text("系统已接收链接，但还需要你检查具体打开的对话。").font(.caption).foregroundColor(.secondary)
                    HStack {
                        Button("我已进入正确对话") { model.confirmPending() }.buttonStyle(.borderedProminent)
                        Button("没有，保持待验证") { model.rejectPending() }.buttonStyle(.bordered)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(harborTint.opacity(0.08))
            }
            HStack(spacing: 0) {
                sidebar
                Divider()
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text(model.scopeTitle).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text("\(model.rows.count) 个\(model.query.isEmpty ? "入口" : "结果")").font(.system(size: 11)).foregroundColor(.secondary)
                        Spacer()
                        if !model.query.isEmpty && (model.selectedProjectID != nil || model.favoritesOnly) {
                            Button("搜索所有入口") { model.selectedProjectID = nil; model.favoritesOnly = false }
                                .buttonStyle(.link).font(.system(size: 11))
                        }
                    }.padding(.horizontal, 16).frame(height: 36)
                    mainList
                }
            }
            Divider()
            HStack(spacing: 10) {
                Text("↑↓ 选择   ↩ 打开 / 验证   esc 收起")
                Spacer()
                Text("仅存本机 · \(model.totalEntries) 个入口")
            }.font(.system(size: 10)).foregroundColor(.secondary).padding(.horizontal, 16).frame(height: 32)
        }
        .frame(width: 720, height: 500)
        .background(.regularMaterial)
        .tint(harborTint)
        .preferredColorScheme(preferences.colorScheme)
        .sheet(isPresented: $model.showProjectEditor) { ProjectEditor(model: model) }
        .sheet(isPresented: $model.showEntryEditor) { EntryEditor(model: model, row: model.editingEntry) }
        .sheet(isPresented: $model.showSettings) { SettingsView(preferences: preferences, loginItem: model.loginItem) }
        .onAppear { searchFocused = true }
        .onChange(of: model.focusRequest) { _ in searchFocused = true }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            navigationButton("所有入口", icon: "square.grid.2x2", count: model.totalEntries, selected: model.selectedProjectID == nil && !model.favoritesOnly) {
                model.selectedProjectID = nil; model.favoritesOnly = false
            }
            navigationButton("收藏", icon: "star", count: model.favoriteCount, selected: model.favoritesOnly) {
                model.selectedProjectID = nil; model.favoritesOnly = true
            }
            Text("项目").font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary).padding(.top, 16).padding(.leading, 10)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(model.workspace.projects) { project in
                        navigationButton(project.title, icon: "folder", count: project.entries.count, selected: model.selectedProjectID == project.id && !model.favoritesOnly) {
                            model.selectedProjectID = project.id; model.favoritesOnly = false
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Button { model.showProjectEditor = true } label: { Label("新建项目", systemImage: "folder.badge.plus") }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundColor(harborTint).padding(10).disabled(model.readOnly)
        }.padding(10).frame(width: 172).background(Color.primary.opacity(0.025))
    }

    private func navigationButton(_ title: String, icon: String, count: Int?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon).frame(width: 14)
                Text(title).lineLimit(1)
                Spacer(minLength: 2)
                if let count { Text("\(count)").font(.caption).foregroundColor(.secondary) }
            }.font(.system(size: 12, weight: selected ? .semibold : .regular)).padding(.horizontal, 10).padding(.vertical, 9)
                .background(selected ? harborTint.opacity(0.12) : .clear).clipShape(RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder private var mainList: some View {
        if model.rows.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: model.query.isEmpty ? "tray" : "magnifyingglass").font(.system(size: 30, weight: .light)).foregroundColor(harborTint)
                Text(model.query.isEmpty ? (model.favoritesOnly ? "还没有收藏入口" : "为工作留一个入口") : "没有找到入口").font(.headline)
                Text(model.query.isEmpty ? (model.favoritesOnly ? "在入口的「更多操作」中收藏，把常用工作放在这里。" : "先建立项目，再粘贴聊天链接。\n聊天仍在原生 ChatGPT 中进行。") : "试试其他名称，或切换到所有入口。")
                    .font(.system(size: 12)).foregroundColor(.secondary).multilineTextAlignment(.center)
                if model.query.isEmpty && model.favoritesOnly {
                    Button("浏览所有入口") { model.favoritesOnly = false; model.selectedProjectID = nil }.buttonStyle(.bordered)
                } else if model.query.isEmpty {
                    Button(model.workspace.projects.isEmpty ? "建立第一个项目" : "添加聊天入口") { model.beginAddEntry() }
                        .buttonStyle(.borderedProminent).disabled(model.readOnly)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.workspace.projects) { project in
                            let projectRows = model.rows.filter { $0.project.id == project.id }
                            if !projectRows.isEmpty {
                                if model.selectedProjectID == nil {
                                    HStack {
                                        Text(project.title).font(.system(size: 11, weight: .semibold))
                                        Spacer()
                                        Text("\(projectRows.count)").font(.system(size: 10))
                                    }.foregroundColor(.secondary).padding(.horizontal, 10).padding(.top, 7).padding(.bottom, 2)
                                }
                                ForEach(projectRows) { row in entryView(row).id(row.id) }
                            }
                        }
                    }.padding(12)
                }.onChange(of: model.selectedEntryID) { id in
                    if let id { proxy.scrollTo(id, anchor: .center) }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func entryView(_ row: EntryRow) -> some View {
        let kind = LinkPolicy.classify(row.entry.url)
        let local = LinkPolicy.nativeCandidateURL(row.entry.url) != nil
        let verified = model.currentApplication.map { row.entry.isVerified(for: $0.identity) } ?? false
        let selected = model.selectedEntryID == row.id
        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: local ? "bubble.left.and.bubble.right" : "link").foregroundColor(harborTint).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(row.entry.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).help(row.entry.title)
                    if row.entry.isFavorite { Image(systemName: "star.fill").font(.system(size: 9)).foregroundColor(harborTint).accessibilityLabel("已收藏") }
                }
                Text(kind.sourceLabel).font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
            Text(verified ? "已确认" : (local ? (model.pending?.entryID == row.id ? "待确认" : "待验证") : "暂不支持"))
                .font(.system(size: 10, weight: .medium)).foregroundColor(verified ? harborTint : .secondary)
                .help(model.stateLabel(row.entry))
            if selected {
                Button(verified ? "打开" : (local ? "验证" : "说明")) { model.activate(row.entry) }
                    .font(.system(size: 11)).buttonStyle(.bordered).disabled(model.isOpening)
            }
            Menu {
                Button(verified ? "打开入口" : (local ? "验证入口" : "查看说明")) {
                    model.selectedEntryID = row.id
                    model.activate(row.entry)
                }.disabled(model.isOpening)
                Divider()
                Button(row.entry.isFavorite ? "取消收藏" : "收藏入口") { model.toggleFavorite(row.id) }.disabled(model.readOnly)
                Button("编辑入口") { model.editingEntry = row; model.showEntryEditor = true }.disabled(model.readOnly)
                Button("复制链接") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(row.entry.url, forType: .string) }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20)
                .accessibilityLabel("更多操作：\(row.entry.title)").help("收藏、编辑或复制链接")
        }.padding(.horizontal, 12).frame(height: preferences.value.density == .compact ? 46 : 58)
            .background(model.selectedEntryID == row.id ? harborTint.opacity(0.12) : Color.primary.opacity(0.025))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle()).onTapGesture { model.selectedEntryID = row.id }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(row.entry.title)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityAction { model.selectedEntryID = row.id }
            .accessibilityAction(named: Text("选择入口")) { model.selectedEntryID = row.id }
    }
}

struct ProjectEditor: View {
    @ObservedObject var model: LauncherModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var saveError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新建项目").font(.title3.weight(.semibold))
            TextField("例如：网站开发、音乐剧、学业", text: $title).textFieldStyle(.roundedBorder).accessibilityLabel("项目名称")
            if let saveError { Text(saveError).font(.caption).foregroundColor(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("建立项目") {
                    if model.addProject(title: title) { dismiss() }
                    else { saveError = model.message ?? "未能建立项目，请重试。" }
                }
                    .keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 400)
    }
}

struct EntryEditor: View {
    @ObservedObject var model: LauncherModel
    let row: EntryRow?
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var url: String
    @State private var projectID: UUID?
    @State private var saveError: String?

    init(model: LauncherModel, row: EntryRow?) {
        self.model = model
        self.row = row
        _title = State(initialValue: row?.entry.title ?? "")
        _url = State(initialValue: row?.entry.url ?? "")
        _projectID = State(initialValue: row?.project.id ?? model.selectedProjectID ?? model.workspace.projects.first?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(row == nil ? "添加聊天入口" : "编辑入口").font(.title3.weight(.semibold))
            Text("从原生 ChatGPT 的目标对话复制链接。只保存名称和链接，不读取聊天内容。")
                .font(.caption).foregroundColor(.secondary)
            Picker("所属项目", selection: $projectID) {
                ForEach(model.workspace.projects) { project in Text(project.title).tag(Optional(project.id)) }
            }.disabled(row != nil)
            TextField("入口名称", text: $title).textFieldStyle(.roundedBorder).accessibilityLabel("入口名称")
            TextField("粘贴聊天链接", text: $url).textFieldStyle(.roundedBorder).accessibilityLabel("聊天链接")
            Text(linkExplanation).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            if let saveError { Text(saveError).font(.caption).foregroundColor(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存入口") {
                    guard let projectID else { return }
                    if model.saveEntry(projectID: projectID, title: title, url: url, existingID: row?.id) { dismiss() }
                    else { saveError = model.message ?? "未能保存入口，请重试。" }
                }.keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || projectID == nil)
            }
        }.padding(24).frame(width: 470)
    }

    private var linkExplanation: String {
        switch LinkPolicy.classify(url.trimmingCharacters(in: .whitespacesAndNewlines)) {
        case .localCodex: return "识别为本地 Codex 对话。保存后请选中入口并点「验证」，检查是否进入正确对话，再回到泊岸确认。"
        case .cloudChatGPT, .conversationReference: return "这是云端聊天或聊天引用。目前可保存，但原生跳转尚未确认，不会自动用浏览器打开。"
        case .unsupported: return url.isEmpty ? "请直接粘贴原始链接；不要修改链接开头。" : "暂未识别此链接。可以保存备查，但不会执行打开。"
        }
    }
}
