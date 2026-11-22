# Changelog

## 0.3.0

### Added

- Delete entries with up to 50 steps of undo during the current app session.
- Move entries between projects through the menu or by dropping onto the sidebar.
- Reorder entries within a project by dragging or using Move up / Move down.
- Immediate English / Simplified Chinese switching in Settings, with persisted language preferences.
- English-first documentation and a separate Chinese guide.

### Fixed

- Sidebar rows respond across their full width, including icons, counts, and blank space.
- Entry row bodies select the entry while action buttons remain independent.
- Opening the panel and selecting projects no longer activate a blinking search caret. Click Search or press Command-F to enter text.

### Behavior notes

- New installations default to English. Existing Chinese preferences keep their language. Custom names are never translated.
- Search and Favorites disable reordering because they hide entries. Moving between projects remains available.
- Library changes save before updating the interface. Undo restores full entry metadata; failed writes retain current data and history.
- Undo history clears on quit. Deletion affects only the Harbor bookmark, never the underlying conversation.
- Cloud ChatGPT links remain save-only. Exact native destination confirmation is still required for local Codex thread links.
- This remains an ad-hoc signed development build, without Developer ID signing or Apple notarization.

## 0.2.0

Native menu-bar launcher, global shortcut, projects, search, favorites, entry editing, local storage, explicit native-link verification, launch at login, and appearance preferences.
