# Harbor: Native Launcher Design Research

Researched on November 22, 2026. Updated on November 23, 2026 with the v0.3 focus and language decisions. This public document contains only first-party product references and Harbor's design choices.

## Direction

Use a visible search field, a project sidebar, and a compact entry list. Entry names carry the hierarchy. Verification appears as a short status; explanations and secondary actions appear on demand. Keep personalization small: appearance, accent, density, language, and login behavior.

Harbor organizes saved references and returns people to the native ChatGPT app. It does not become a general-purpose launcher or a replacement chat client.

## What the Sources Establish

The facts below were checked against the linked first-party pages. The final column is a Harbor design inference, not a vendor requirement.

| Source | Observed guidance or behavior | Harbor decision |
| --- | --- | --- |
| [Raycast — Search Bar](https://manual.raycast.com/search-bar) | A single search field is the main entry point; results update while typing. The hotkey focuses search. Compact Mode can collapse the window to search alone. | Keep one search field and fast filtering, but retain visible projects. Harbor v0.3 deliberately uses explicit search focus, as specified below. |
| [Raycast — Action Panel](https://manual.raycast.com/action-panel) | Enter runs the primary action; contextual actions are grouped in an action panel with shortcut hints. | Show one primary action for the selected entry. Put edit, copy, favorite, move, and delete in a native More menu rather than displaying every action in each row. |
| [Raycast — Settings](https://manual.raycast.com/settings) | Command–Comma opens settings. Appearance, interface size, compact mode, and launch-at-login controls are available. | Keep infrequent preferences together. Use a few clear presets and immediate preview rather than a theme editor. |
| [Alfred — Appearance](https://www.alfredapp.com/help/appearance/) | Appearance controls affect result presentation, visible result count, screen placement, and theme typography, spacing, and color. | Prioritize useful density and light/dark choices. Keep system fonts. Free-form themes and screen-placement configuration are outside this release. |
| [Apple HIG — Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields) | Explain the search scope, update results as people type, simplify results, and let people narrow a broad initial scope. | Start with All entries on a new installation. Show the current project scope and offer Search all entries when filtering a project produces limited results. |
| [Apple HIG — Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables) | Lists suit scannable text. Keep row content concise, reveal longer content in detail, and communicate selection clearly. | Use two-line rows with stable selection, short status text, and full-title help. Avoid repeating long compatibility explanations in each row. |
| [Apple HIG — Settings](https://developer.apple.com/design/human-interface-guidelines/settings) | Offer a restrained set of preferences, respect system settings, and follow standard settings-menu and Command–Comma conventions. | Group preferences into General and Appearance. Do not duplicate system accessibility or scrolling controls. |
| [Apple — SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) and [Status](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum) | Login-item registration and authorization are separate states; the API exposes enabled, not registered, approval required, and not found. | Show the actual system state. A registration request is not proof that automatic launch is enabled. |

For visual reference, Alfred publishes an [appearance-options screenshot](https://www.alfredapp.com/help/appearance/appearance-options.png); the Raycast Settings page includes launcher screenshots. Harbor borrows interaction principles, not those products' branding or artwork.

## Compact Layout

These measurements are Harbor choices, not official Apple, Raycast, or Alfred dimensions. Use native materials, SF Symbols, semantic text colors, and system fonts.

| Element | Baseline |
| --- | --- |
| Main panel | 720 × 500 pt; layout should remain useful between 680 and 760 pt wide |
| Search/header | About 56 pt high, with 18–20 pt horizontal inset |
| Sidebar | 164–172 pt wide; full-row hit areas |
| Entry row | About 58 pt comfortable or 46 pt compact |
| Typography | 13 pt entry title, 11 pt source, 10–11 pt short status |
| Row icon | 18–20 pt; avoid a large icon tile |
| Footer | 32–36 pt, showing relevant keyboard or filtering guidance |
| Settings | Compact grouped form; scroll when errors or approval instructions require extra space |

Use teal as the default accent, with blue and graphite alternatives. Light-mode teal starts near `#245E70`; dark mode needs a lighter counterpart. Status meaning must be conveyed by text, not color alone. Density changes spacing, not the minimum readable text size.

All entries groups rows by project. A project view avoids repeating the project name on every row. Long titles truncate without pushing the status, primary action, or More control outside the row.

## Search Focus: v0.3 User Decision

This intentionally differs from the auto-focused search behavior of the reference launchers:

- Opening or reopening Harbor does **not** automatically focus search or show a blinking insertion cursor.
- Switching projects or selecting Favorites/All entries does **not** focus search.
- Search starts only when the person clicks the field or presses Command–F. Clearing search may keep focus when it is part of an active editing action.
- Clicking an entry or blank list area ends search editing and removes the insertion cursor. Child action buttons and menus keep their own native interaction.
- Keep the query and visible results when focus leaves the field. Ending editing is not a request to clear the query.
- Command–F restores editing. Input-method composition and text undo retain native priority; list navigation and workspace undo must still work outside text editing.

The goal is a quiet panel that supports project browsing without a permanently blinking cursor. Do not reintroduce automatic focus in window-show, project-selection, or row-selection callbacks.

## Status and Feedback

| Entry state | Short label | Primary action |
| --- | --- | --- |
| Confirmed native destination | Verified | Open |
| Recognized native candidate | Unverified | Verify |
| Native route not supported | Unsupported | Details |
| Open request accepted, awaiting inspection | Confirm needed | Confirm result |

A pending confirmation names the exact project and entry. Receiving an open request does not verify the destination. Starting another native open or changing the affected entry must not leave an old confirmation available.

Keep routine explanations small or reveal them on demand. Persistence failures and pending confirmation may use visible dedicated regions. Neither should be silently replaced by a success toast. Undo feedback describes the next real history action.

## Preferences and Language

Appearance follows the system by default, with explicit Light and Dark options. Accent and density apply immediately and persist. Restoring appearance defaults does not delete entries or verification records.

English is the default for new installations. Existing valid preferences without a language field migrate to Simplified Chinese. The English / 简体中文 selector changes app-owned labels, menus, help, accessibility text, dialogs, state messages, and undo descriptions immediately after a successful save. It never translates user project names, entry titles, URLs, or verification evidence.

Login at launch is a system-backed preference. Show Enabled only for the actual enabled state; show Awaiting system approval with a system-settings action when approval is required. Refresh on return to the app. Automatic login launch should remain in the menu bar; manually launching the app may show the panel. A true login test is separate from reading the enabled state.

## Focused Acceptance Checks

- Light and dark screenshots: readable titles, source text, selection, status, and controls.
- Comfortable and compact screenshots: more rows fit in compact mode without smaller unreadable text or overlapping controls.
- Pointer hit areas: blank space in sidebar and entry rows behaves like the visible row, without stealing child controls.
- Focus: open, reopen, project switch, and row click show no search cursor; click search or Command–F enters editing; clicking list blank space exits without clearing results.
- Keyboard: input methods and text undo work normally; selection, primary actions, and workspace undo work outside editing.
- Language: new/legacy preference defaults are correct; English and Chinese fit the same layout; switching persists and preserves custom content.
- State: pending verification names its target; errors preserve data; login approval state is reported honestly.

Publish only fictional demonstration data in screenshots. Never include real chat titles, IDs, account names, or private filesystem paths. This document records research and requirements; it does not claim every acceptance scenario has been tested.
