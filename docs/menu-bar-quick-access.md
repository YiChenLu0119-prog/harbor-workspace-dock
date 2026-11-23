# Harbor v0.4: Menu Bar Quick Access

The menu bar gives Harbor a visible identity and a compact place for frequently used entries. The complete workspace remains available through the existing global shortcut and an explicit **Open Workspace** action. This document describes the design and source review; native behavior requires separate on-device acceptance.

## Display and hierarchy

- Show the system symbol plus the localized Harbor name by default. **Show name in menu bar** allows an icon-only appearance without removing access to the app.
- Use a compact, stable-width panel. Its header identifies Harbor and summarizes saved content. Opening the complete workspace is the primary command.
- Show at most six favorites in stored library order. Include each entry's project name, because identical titles can belong to different projects. Provide **View all** when the collection exceeds that limit.
- Keep project shortcuts in a bounded scrolling region. Each row shows its title and entry count; selecting a row opens that project in the complete workspace.
- Keep existing Add Entry, Undo, Settings, data-folder, and Quit commands reachable. Avoid hiding essential controls beneath a long list.

## Interaction and states

Every favorite and project row is a full-width native button. Icons, text, counts, padding, and blank space perform the same action. Apply the content shape inside the expanded button label; no separate transparent hit layer is needed. Truncate long names visually, retaining their full text in accessible labels and help.

The compact panel contains no text field, so opening it never starts search editing. Search remains in the workspace, where clicking Search or pressing Command–F is explicit. The existing global shortcut continues to open the full workspace.

Favorite actions reuse native-link policy and exact-destination verification. A cloud link must not acquire an Open claim because it appears here. Unsupported entries lead to their explanation in the workspace; a pending confirmation returns to that confirmation without opening the link again. Close the compact panel before presenting another Harbor surface or opening a confirmed native destination.

Empty favorites explain how to add favorites. An empty library offers the existing creation flow. A failed library read must show its protected/error state instead of suggesting the user's library is simply empty. Disabled actions remain identifiable. Saved preference changes apply immediately; a failed save keeps the previous value.

## Platform evidence

The original v0.4 implementation used SwiftUI `MenuBarExtra`. Apple documents that an app with only this scene quits when the item is removed. On-device testing reproduced that exit, so v0.4.1 moves application lifetime to AppKit and retains an `NSStatusItem` and `NSPopover`, while keeping the SwiftUI content. The item allows removal but does not enable `terminationOnRemoval`. [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra), [terminationOnRemoval](https://developer.apple.com/documentation/appkit/nsstatusitem/behavior-swift.struct/terminationonremoval)

Apple's menu-bar guidance favors symbols and simple menus, while allowing richer presentation when needed. macOS may hide extras when space is tight. Harbor therefore keeps the name optional and preserves its independent hotkey. [The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)

Transient panels should contain a small set of related tasks, remain compact, and close when the user moves elsewhere. Harbor keeps editing and confirmation in its full workspace rather than layering additional panels over quick access. [Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers)

## Acceptance review

Source review completed on 2026-11-23. The implementation uses a 360 pt panel with a body capped at 340 pt; its header and command footer remain outside the scrolling content. Source checks found the following requirements represented:

| Requirement | Source review result |
| --- | --- |
| Visible name and icon-only preference | Status-item label observes persisted preferences; missing fields default to showing the name |
| Favorite ordering and overflow | Six favorites in workspace order, including parent labels and a View all action |
| Row click areas and long text | Expanded button labels include rectangular hit areas; full names remain in accessibility labels/help |
| Existing commands and full workspace | Workspace, Add Entry, Undo, Settings, data folder, and Quit remain reachable |
| Read error | Explicit unavailable state replaces misleading zero counts; original data protection is retained |
| Pending confirmation and active sheets | Quick entry routing preserves pending confirmation; project, favorites, add, and settings paths protect active editors |
| Undo during a sheet | Quick-access Undo is disabled while an editing or settings sheet is active |
| Action wording | Unverified native entries use Verify… to indicate the next workspace step; unsupported destinations use Info |

Review corrections were applied before acceptance: protect project/Favorites navigation beneath an active sheet, disable menu Undo during a sheet, clarify Verify…, display unreadable-library status instead of zero counts, and include Settings padding within its clickable label. A missing native app also leads to the existing workspace explanation.

No unresolved source-level design blocker was identified in this review. This does not establish native behavior: on-device acceptance is still pending for English and Chinese; name/icon changes and relaunch; full-width clicks; zero, six, and more than six favorites; long titles; many projects; protected data; pending confirmation; popup dismissal; and all existing workspace commands. Use fictional data for screenshots.

## v0.4.1 lifecycle follow-up

The delegate retains the workspace and quick-access controller independently of status-item visibility. Explicit launch and reopen present the workspace and request visibility for Harbor's own item. Login and `--hidden` launches respect the saved visibility. System-level menu-bar restrictions still take precedence. Closing the quick-access popover uses its public close action.

Installed-app checks on macOS 26.6.2 confirmed normal launch, Quit followed by a second launch, and continued process lifetime while Harbor was switched off in System Settings → Menu Bar. The system switch was restored afterward. Physical menu-bar visibility, the popup's visual layout, and global shortcut delivery still need separate on-device confirmation; the automation's app-raising behavior does not establish those results.
