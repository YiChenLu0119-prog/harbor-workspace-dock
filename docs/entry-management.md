# Harbor v0.3: Entry Management and Interaction

This release adds delete and undo, project moves, and ordering within a project. It also makes the entire visible sidebar row clickable. Native link verification and local storage rules remain unchanged. All example names in this document are fictional.

## Hit Areas and Gestures

| Area | Pointer behavior | Keyboard and accessibility |
| --- | --- | --- |
| All entries, Favorites, and project rows | The icon, name, count, padding, and blank space select the same destination | Preserve native button and selected semantics |
| New project row | The entire row creates a project | Accessible label and native button activation |
| Entry row outside its controls | Select the entry; do not open it | Expose Select entry and the selected state |
| Primary action | Open, verify, or show details only | Include the entry name in the accessible action where needed |
| More menu | Open the menu or run its selected action only | Include the primary action even on an unselected row |
| Entry drag | Drag after the system threshold; dropping must not also open the entry | Provide menu alternatives for moving and ordering |

For sidebar buttons, expand the label and its padding to the full row width, then apply the content shape inside that label. Do not cover child controls with a transparent full-row button. Do not use a parent gesture that takes precedence over menus or primary buttons. Content dragging must not move the window.

Test the icon, text, count, blank center, and trailing padding separately. Test with populated projects so an unchanged empty view cannot hide a missed click.

## Move Between Projects

The More menu includes **Move to**, listing real projects. Disable or mark the current project. Moving preserves the entry ID, name, URL, favorite state, and still-valid verification record, and appends the entry to the destination.

Dragging onto a sidebar project performs the same operation. All entries, Favorites, and blank sidebar space are not project drop targets. Highlight only a valid destination; clear the highlight on exit or cancellation. Dropping onto the current project is a no-op with no history record.

Accept only a validated internal drag payload for an entry that still exists in the current workspace. External text, files, and URLs must not trigger moves. After a successful move, switch to the destination and select the moved entry. A failed save keeps the original position and must not show success.

## Order Within a Project

An entry can be placed before or after another entry in the same project. This works in a single-project view and within one project section in All entries. Use sidebar project drops or Move to for cross-project moves.

Allow ordering only when the complete group is visible: the search query is empty and Favorites is not filtering the list. Disable both drag ordering and Move up / Move down under filters; explain that clearing the filter restores ordering. Project moves remain available.

Show a clear insertion line. The top and bottom halves of an anchor row mean before and after. First and last positions must both be reachable. Hover changes only the indicator or a temporary preview. Commit and save once on the final valid drop; a cancelled drag changes nothing and adds no history.

Move up and Move down are native menu alternatives. Each moves one position within the same project, retains selection, and is disabled at the corresponding boundary. Optional shortcuts must not take over text-editing shortcuts.

## Delete and Session Undo

Delete entry removes only Harbor's saved reference; it never deletes the original ChatGPT conversation. Use a destructive menu action with immediate visible undo. Update the list and show success only after the file is saved.

After deleting **Example entry**, show a message identifying it and an Undo action. Move selection to a reasonable visible neighbor, or show the empty state if none remains.

Maintain one in-memory history for every successful workspace mutation, including add, edit, favorite, move, reorder, delete, and verification changes. This implementation retains up to 50 steps in the current run. Preferences are separate. Failed saves and no-ops add no history.

The banner, menu title, and accessibility label must describe the next actual undo action. Delete A, then edit B: the first undo reverses B's edit; the second restores A. A stale Delete message must not claim that the next action restores A while it actually reverses B.

Undo saves its target state before changing the UI or removing the history record. A failed undo leaves both data and history unchanged so it can be retried. History disappears when the app exits; saved data does not.

Changes and undo clear pending verification when its target or context may have changed. Restored verification still requires the original URL and matching native app identity.

## Command–Z Ownership

Marked text, editor sheets, and native text undo have priority. In the search field, pass Command–Z through when text is present or the text undo manager can undo. An empty search field with no native text undo may fall back to workspace undo. Opening the panel or switching projects does not automatically focus search; focus begins only by clicking the field or pressing Command–F. Clicking an entry or blank list space ends editing without clearing the query.

Keep explicit Undo buttons and a menu item available for workspace undo. Do not intercept Shift–Command–Z unless redo is implemented. Menu and banner labels follow the current history action, not a permanent Delete label.

## English-First Release and Language Switching

- English is the default for a new installation with no saved preferences.
- Existing valid preferences without a language field migrate to Simplified Chinese, preserving the language experienced by previous users. Do not infer migration from the system locale.
- Settings offers **English** and **简体中文**. A successful change applies immediately and persists across relaunch. A failed preference save keeps the previous language and displays a useful error.
- Translate app-owned navigation, menus, tooltips, accessibility labels, settings, editors, status, validation, errors, and undo descriptions. Pending confirmations and visible operation history must remain understandable after a switch.
- Never translate or rewrite user-created project names, entry titles, URLs, or verification evidence. Format app-owned sentences around those values without changing them.
- Use equivalent actions in both languages. English copy must fit the same compact layout; do not reduce text to unreadable sizes to avoid wrapping.
- Publish the main documentation and release-facing screenshots in English. Localized product UI remains available in both languages. Example data and screenshots contain no private chat titles, IDs, account names, or private paths.

## Acceptance Matrix

| Scenario | Expected result |
| --- | --- |
| Click blank space, count, and padding in Favorites or a project row | Same destination as clicking its text |
| Click empty space inside an entry | Select only; do not launch |
| Click a child menu or action, or cancel a drag | No competing selection/open action |
| Delete, edit another entry, then undo twice | Reverse the edit first, then the deletion; accurate labels throughout |
| Save fails during delete, move, or reorder | Data, position, and history remain unchanged |
| Undo save fails, then succeeds on retry | Retain the history until successful persistence |
| Drag to first or last position | Indicator matches final order; one drop is one undo step |
| Drop onto another sidebar project | Append once, retain all entry fields, reveal and select the destination entry |
| Drop onto the same project, Favorites, All entries, or invalid input | No mutation, success message, or history step |
| Search or Favorites filter is active | Ordering disabled; hidden items retain their order |
| Use Move to, Move up, or Move down from the menu | Same data behavior without dragging |
| Command–Z in text or an editor sheet | Native text undo; no workspace mutation |
| Command–Z in empty search with no text undo | Workspace undo when available |
| Open/reopen, switch project, click entry or list blank space | No automatic search cursor; preserve the query |
| Click search or press Command–F | Begin search editing |
| Restart after saved mutations | Data persists; session history is empty |
| Fresh preferences / old preferences without language | English / Simplified Chinese respectively |
| Switch language, then restart | Immediate UI update and persistent choice; user content unchanged |

These are implementation and acceptance requirements, not claims of completed testing. Pointer gestures, drag feedback, text undo, and localized layouts require native UI verification.
