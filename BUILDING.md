# 构建与运行泊岸

需要 macOS 13+ 和支持 Swift 5.9 或更新版本的完整 Xcode。当前机器使用 `/Applications/Xcode.app`。脚本只给本次构建指定 Xcode，不修改系统设置。

```sh
bash scripts/test.sh
bash scripts/build.sh
open dist/Harbor.app
```

也可以在 Xcode 中打开 `Package.swift`，选择 Harbor 可执行目标。Swift Package 是源工程入口；本地 `.app` 由构建脚本生成，无第三方包。

手动启动显示面板；以后点菜单栏四方格，或按 `⌃⌥Space` 呼出。按 `Esc` 收起，在菜单栏选「退出泊岸」结束运行。`⌘F` 聚焦搜索，`⌘N` 添加入口，`⌘,` 打开设置。

先新建项目，再添加聊天名称及原始链接。只支持 `codex://threads/<UUID>` 的显式原生测试。选中入口并点击「验证」，观察原生 App 中是否进入正确对话，再用菜单或快捷键返回泊岸，选择「我已进入正确对话」。系统接收链接不会自动把它标为已确认。URL 或原生 App 版本改变后需要重新验证。每行的「更多操作」菜单提供收藏、编辑和复制链接。

ChatGPT 云端 HTTPS 链接和 `chatgpt-conversation://` 引用可以保存，但原生打开暂不支持。不存在浏览器回退或聊天 ID 自动转换。

数据位于 `~/Library/Application Support/HarborWorkspaceDock/workspace.json`，仅包含项目、入口信息和本机确认记录。读取失败时停止编辑，保留原文件。没有导入、删除或自动同步。

v0.2 的设置单独写入同目录的 `preferences.json`，不改 `workspace.json` 或它的版本。可选系统/浅色/深色、青绿/蓝色/石墨点缀、舒适/紧凑密度，以及下次启动时默认显示所有入口或收藏。「恢复默认外观」只改变外观、颜色和密度，不清除资料，也不更改登录项。

## 登录自动启动

先把应用放到 `/Applications/Harbor.app` 或 `~/Applications/Harbor.app` 这样的稳定位置，再从设置打开「登录 Mac 时启动泊岸」。该开关读取系统真实状态：只有 `enabled` 是已启用；`requiresApproval` 会显示「等待系统允许」，并提供系统设置入口，不会误报成功。

登录自动启动使用 macOS 13+ 的 `SMAppService.mainApp`。登录启动时通过启动 Apple Event 识别为 login item，保持菜单栏待命；手动启动显示面板。实际注销再登录需要单独实测；单元测试只验证显示策略。

为安装后验收提供以下命令（不要从开发目录注册登录项）：

```sh
/Applications/Harbor.app/Contents/MacOS/Harbor --login-item-status
/Applications/Harbor.app/Contents/MacOS/Harbor --enable-login-item
/Applications/Harbor.app/Contents/MacOS/Harbor --disable-login-item
```

这些命令输出 JSON 的真实系统状态，然后退出，不打开面板。启用命令只有读到 `enabled` 才返回 0；等待系统允许返回 2，失败返回 1。查询状态不更改注册。开发目录及隔离数据模式均禁止修改登录项；注册动作不由构建或测试脚本触发。

参考：[Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)、[register](https://developer.apple.com/documentation/servicemanagement/smappservice/register())、[requiresApproval](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/requiresapproval)。本机 SDK 的 `AERegistry.h` 定义 `keyAELaunchedAsLogInItem` 作为登录启动标记；实现于 `applicationDidFinishLaunching` 读取启动事件。

## 隔离验收

从终端传入独立目录：

```sh
open -n dist/Harbor.app --args --data-dir /tmp/harbor-acceptance
```

或者直接运行 `HARBOR_DATA_DIR=/tmp/harbor-acceptance dist/Harbor.app/Contents/MacOS/Harbor`。测试时只运行一个实例，避免热键冲突。测试目录不会改变正式资料目录。

`--hidden` 可测试只驻留菜单栏，`--show` 可强制显示面板；两个参数不会注册登录项。

这是本机开发构建，仅有临时签名（ad-hoc），没有开发者公证。构建脚本不会自行安装、发布或注册登录项。快捷键注册失败会在面板提示，菜单栏仍可使用。
