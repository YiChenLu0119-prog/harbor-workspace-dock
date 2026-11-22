# 泊岸 Harbor · Workspace Dock

A lightweight native macOS launcher for organizing links to your ChatGPT work. Built with SwiftUI and AppKit. Your conversations stay in the native ChatGPT app.

泊岸把分散的工作入口按项目收好。按 **⌃⌥Space**，搜索、选中，再回到原生 ChatGPT 继续工作。

## 功能

- 菜单栏与全局快捷键；项目分组、搜索、收藏、入口编辑。
- 原生浮动面板，键盘方向键选择、Return 操作、Esc 收起。
- 本地 JSON 保存，不读取聊天正文、账号或 Cookie。
- 每个原生入口由使用者确认准确对话后，才记录为已验证。
- 系统/浅色/深色外观、点缀色、列表密度和默认视图设置。
- macOS 登录时启动，可在设置中关闭，并显示系统实际状态。

## 快速开始

需要 macOS 13+、完整 Xcode 和 Swift 5.9 或更新版本。没有第三方依赖。

```sh
bash scripts/test.sh
bash scripts/build.sh
open dist/Harbor.app
```

把 `Harbor.app` 安装到 `/Applications` 或 `~/Applications` 后，再启用「登录时启动」。默认数据目录是 `~/Library/Application Support/HarborWorkspaceDock/`。详细构建说明见 [BUILDING.md](BUILDING.md)。当前是本机开发构建，尚未做 Developer ID 签名和 Apple 公证。

1. 新建项目，添加聊天名称和从原生 App 复制的链接。
2. 可测试的入口选择「验证入口」，观察是否进入正确对话，再回到泊岸确认。
3. 日常用 **⌃⌥Space** 呼出；输入关键词，按 **↑/↓** 选择、**Return** 操作。
4. 用 **⌘N** 添加入口、**⌘F** 回到搜索、**⌘,** 打开设置。

## 链接支持边界

| 链接 | 行为 |
| --- | --- |
| `codex://threads/<本地线程 UUID>` | 指定原生 App 测试打开；准确目标需逐项人工确认 |
| `https://chatgpt.com/c/…` 等云端聊天 | 可以保存；当前不执行原生打开 |
| `chatgpt-conversation://…` 内部引用 | 可以保存；当前不执行原生打开 |
| 其他地址或带额外参数的非标准原生链接 | 拒绝执行，并显示说明 |

[官方深链接说明](https://learn.chatgpt.com/docs/reference/commands#deep-links) 提供了本地聊天路由依据。注册了 URL scheme 或系统接受了请求，都不证明打开了正确对话。泊岸不会把云端聊天 ID 改写为本地线程 ID，也不会自动回退到网页。URL 或原生 App 版本变化后需重新确认。

## 设计与架构

- [UI 研究与设计决策](docs/design-research.md)
- [架构与数据保护](docs/ARCHITECTURE.md)
- [后续改进计划](docs/ROADMAP.md)

`HarborCore` 负责模型、存储与链接规则；`HarborApp` 负责 SwiftUI、菜单栏、窗口、快捷键、设置及原生打开。读取损坏或未知版本资料时会停止写入，保留原文件。

## 公开仓库与隐私

仓库只包含程序、虚构测试数据和公共文档。用户项目名称、聊天链接、验证记录、个人资料库和本地开发记录不包含在发布内容中。请勿在公开 issue 或截图中贴私人聊天链接。
