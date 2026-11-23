# Build and run Harbor

Harbor is a native macOS menu-bar launcher for project-organized chat links. It keeps the ChatGPT app as your chat client. Requires macOS 13+ and Xcode with Swift 5.9 or newer; no third-party packages are used.

```sh
bash scripts/test.sh
bash scripts/build.sh
open dist/Harbor.app
```

The scripts use `/Applications/Xcode.app` for that command only. Override it with `HARBOR_DEVELOPER_DIR` if needed; they do not change the system-wide developer selection. Open `Package.swift` in Xcode to work on the executable and core library. The build script creates `dist/Harbor.app` with an ad-hoc signature and verifies it. It packages `Resources/AppIcon.png` into an ICNS with all standard macOS icon sizes using `sips` and `iconutil`. It does not install, publish, or register a login item. This development build is not notarized.

## Everyday use

- Open Harbor manually to show the panel. Use the menu-bar icon or `⌃⌥Space` to bring it back; `Esc` hides it.
- Search starts only when you click the search field or press `⌘F`. Opening the panel and choosing a project or entry do not automatically start a blinking text cursor. Selecting an entry leaves search editing while preserving your query.
- Use `↑` / `↓` to select and `Return` to open, verify, or show details while the list or search field has focus. Tab-focused controls and input-method composition retain their own keyboard behavior.
- `⌘N` adds an entry; `⌘,` opens Settings. Quit from the menu-bar menu.

Harbor v0.4.1 stays running when its menu-bar item is removed or hidden. Launch Harbor again from Applications or Spotlight to show the workspace. macOS can still suppress its item when menu-bar space is limited or the app is disabled in System Settings → Menu Bar.

If `⌃⌥Space` is assigned to **Select next source in Input menu**, disable or change that assignment in System Settings → Keyboard → Keyboard Shortcuts → Input Sources. Other input shortcuts can remain enabled. Harbor never changes system input-source shortcuts automatically.

Create a project, then add a name and the original chat link. Harbor stores metadata, not chat content. Do not rewrite a cloud conversation ID as a Codex link.

Only the exact `codex://threads/<UUID>` route is a native candidate. Select **Verify**, inspect the exact conversation in the native ChatGPT / Codex app, return to Harbor, and confirm that it is correct. The system accepting a URL is not verification. Changes to the URL or native app version require another check.

ChatGPT cloud HTTPS links and `chatgpt-conversation://` references can be saved, but native navigation is not confirmed. Harbor does not silently open a browser or convert their identifiers.

## Organize entries

Sidebar items have full-row hit areas. Clicking an entry selects it; its action button opens or verifies it. The More menu provides favorite, edit, move, reorder, copy, and delete actions.

Move an entry with **Move to…** or drag it onto a project in the sidebar. Harbor then selects that project and entry. IDs, favorites, and verification records are preserved. Dropping on the current project is a no-op.

Within a complete project group, drop above or below another entry to place it before or after that entry. **Move Up** and **Move Down** provide a keyboard-accessible alternative. Search and Favorites views disable reordering so hidden entries cannot be accidentally rearranged; cross-project moves remain available. Hovering only shows an insertion indicator. A completed drop commits once; a canceled drag changes nothing. Only Harbor's current in-process drag payload is accepted.

Deleting an entry shows an Undo notice after saving. The same bounded history covers every successful workspace change, including edits and verification. Use the notice, the menu-bar menu, or `⌘Z`. Text editors receive their own undo first when they have text or text-undo history. The workspace history keeps at most 50 steps for the current run; quitting clears it. It is not a persistent recycle bin. Failed saves and failed undos leave both current data and history unchanged.

## Local files and languages

The default data directory is `~/Library/Application Support/HarborWorkspaceDock/`:

- `workspace.json` stores projects, entries, array order, and native verification records. Its schema remains version 1.
- `preferences.json` stores language, appearance, accent, density, and the startup view. It is independent of the workspace.

New installations start in **English**. Valid preferences from earlier Chinese-only versions without a language field keep **Simplified Chinese**. An older workspace without preferences also keeps Chinese. The first selected default is saved before a new workspace is created, so a fresh English installation stays English after restarting.

Choose **Settings → General → Language** to switch immediately. Names, URLs, and other user-provided content are never translated. Notices and undo action descriptions retain semantic templates and original arguments, allowing them to update with the chosen language. macOS-provided error details can follow the system language.

Appearance options include System / Light / Dark, Teal / Blue / Graphite, and Comfortable / Compact rows. Choose All Entries or Favorites for the next launch. **Reset Appearance** changes only appearance, accent, and density, never entries, language, or login items. Unreadable or newer data is protected instead of being replaced by an empty library.

English source text and its Chinese translations live in `HarborText.swift` and `HarborTranslations.swift`. Keep user text in arguments rather than translation keys. Localization tests cover legacy defaults, persistence, argument preservation, and translation placeholder parity.

## Launch at login

Install the app in a stable location such as `/Applications/Harbor.app` or `~/Applications/Harbor.app`, then enable **Launch Harbor at login** in Settings. The toggle reads the real `SMAppService.mainApp.status`; only `enabled` means it is active. A `requiresApproval` response is shown as **Waiting for System Approval** with a System Settings button.

On a login-item launch, Harbor stays in the menu bar. Manual launches show the panel. The implementation reads the launch Apple Event in `applicationDidFinishLaunching`, using `keyAEPropData == keyAELaunchedAsLogInItem`. A real logout/login remains a separate manual acceptance check; unit tests verify the presentation policy.

Installed-app diagnostics:

```sh
/Applications/Harbor.app/Contents/MacOS/Harbor --login-item-status
/Applications/Harbor.app/Contents/MacOS/Harbor --enable-login-item
/Applications/Harbor.app/Contents/MacOS/Harbor --disable-login-item
```

These commands print JSON with the actual system status and exit without showing the panel. Enabling returns 0 only for `enabled`, 2 when approval is still required, and 1 on failure. Querying status is read-only. Development locations and isolated data mode cannot change login items. Build and test scripts never register a login item.

References: [Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), [register](https://developer.apple.com/documentation/servicemanagement/smappservice/register()), and [requiresApproval](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/requiresapproval). The SDK's `AERegistry.h` documents the login-launch marker.

## Isolated acceptance testing

Run one instance at a time to avoid hotkey conflicts:

```sh
open -n dist/Harbor.app --args --data-dir /tmp/harbor-acceptance
```

Alternatively, run `HARBOR_DATA_DIR=/tmp/harbor-acceptance dist/Harbor.app/Contents/MacOS/Harbor`. This directory contains test preferences and data without changing the normal library. `--hidden` tests menu-bar-only presentation; `--show` forces the panel visible. Neither flag registers a login item.
