import XCTest
@testable import HarborCore

final class MenuBarPreferenceTests: XCTestCase {
    func testExistingPreferencesGainVisibleMenuBarNameWithoutChangingStoredValues() throws {
        let original = Data(#"{"schemaVersion":1,"appearance":"dark","density":"compact","startView":"favorites","accent":"blue","language":"zh-Hans"}"#.utf8)
        let preferences = try JSONDecoder().decode(HarborPreferences.self, from: original)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as? [String: Any])
        XCTAssertEqual(encoded["showsMenuBarName"] as? Bool, true)
        XCTAssertEqual(preferences.language, .simplifiedChinese)
        XCTAssertEqual(preferences.appearance, .dark)
        XCTAssertEqual(preferences.density, .compact)
        XCTAssertEqual(preferences.startView, .favorites)
        XCTAssertEqual(preferences.accent, .blue)
    }

    func testIconOnlyPreferencePersistsWithoutRewritingWorkspaceOrLegacyFileOnRead() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HarborMenuBarTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let workspaceURL = directory.appendingPathComponent("workspace.json")
        let workspaceBytes = Data(#"{"schemaVersion":1,"projects":[]}"#.utf8)
        try workspaceBytes.write(to: workspaceURL)
        let original = Data(#"{"schemaVersion":1,"appearance":"system","density":"comfortable","startView":"all","accent":"teal","language":"en","showsMenuBarName":false}"#.utf8)
        let repository = PreferencesRepository(directory: directory)
        try original.write(to: repository.fileURL)
        let preferences = try repository.loadOrCreate()
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), original)
        try repository.save(preferences)
        let reread = try PreferencesRepository(directory: directory).load()
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(reread)) as? [String: Any])
        XCTAssertEqual(encoded["showsMenuBarName"] as? Bool, false)
        XCTAssertEqual(reread.language, .english)
        XCTAssertEqual(try Data(contentsOf: workspaceURL), workspaceBytes)
    }
}

final class MenuBarQuickAccessTests: XCTestCase {
    private let native = NativeAppIdentity(bundleID: "com.openai.codex", version: "1 (1)")
    private let localURL = "codex://threads/11111111-1111-4111-8111-111111111111"

    func testFavoritesKeepWorkspaceOrderProjectIdentityAndSixItemLimit() {
        let firstEntries = (0..<5).map { ChatEntry(title: "Same title", url: "saved-\($0)", isFavorite: $0 != 1) }
        let secondEntries = (0..<5).map { ChatEntry(title: "中文 \($0)", url: "other-\($0)", isFavorite: true) }
        let first = Project(title: "First", entries: firstEntries)
        let second = Project(title: "Second", entries: secondEntries)
        let workspace = Workspace(projects: [first, second])
        let items = MenuBarQuickAccess.favorites(in: workspace)
        XCTAssertEqual(items.map(\.id), firstEntries.filter(\.isFavorite).map(\.id) + secondEntries.prefix(2).map(\.id))
        XCTAssertEqual(items.count, 6)
        XCTAssertEqual(items.first?.projectID, first.id)
        XCTAssertEqual(items.last?.projectID, second.id)
        XCTAssertEqual(items.last?.projectTitle, "Second")
        XCTAssertEqual(workspace.projects[1].entries, secondEntries)
    }

    func testEmptyAndNonpositiveLimitsStayEmpty() {
        let workspace = Workspace(projects: [Project(title: "Empty"), Project(title: "Not starred", entries: [ChatEntry(title: "Entry", url: localURL)])])
        XCTAssertTrue(MenuBarQuickAccess.favorites(in: workspace).isEmpty)
        let starred = Workspace(projects: [Project(title: "Starred", entries: [ChatEntry(title: "Entry", url: localURL, isFavorite: true)])])
        XCTAssertTrue(MenuBarQuickAccess.favorites(in: starred, limit: 0).isEmpty)
        XCTAssertTrue(MenuBarQuickAccess.favorites(in: starred, limit: -1).isEmpty)
    }

    func testMovingFavoriteChangesItsParentWithoutLosingEntryIdentity() throws {
        let entry = ChatEntry(title: "Shared name", url: localURL, isFavorite: true)
        let first = Project(title: "From", entries: [entry])
        let second = Project(title: "To")
        var workspace = Workspace(projects: [first, second])
        try WorkspaceEditing.move(entryID: entry.id, to: second.id, in: &workspace)
        let item = try XCTUnwrap(MenuBarQuickAccess.favorites(in: workspace).first)
        XCTAssertEqual(item.id, entry.id)
        XCTAssertEqual(item.projectID, second.id)
        XCTAssertEqual(item.projectTitle, "To")
    }

    func testOnlyVerifiedCurrentNativeDestinationCanOpenDirectly() {
        var entry = ChatEntry(title: "Local", url: localURL, isFavorite: true)
        XCTAssertEqual(MenuBarQuickAccess.route(for: entry, application: native), .workspace)
        entry.verification = VerificationRecord(url: localURL, application: native)
        XCTAssertEqual(MenuBarQuickAccess.route(for: entry, application: native), .verifiedNative)
        XCTAssertEqual(MenuBarQuickAccess.route(for: entry, application: nil), .workspace)
        let changedApp = NativeAppIdentity(bundleID: native.bundleID, version: "2 (2)")
        XCTAssertEqual(MenuBarQuickAccess.route(for: entry, application: changedApp), .workspace)
        entry.url = "codex://threads/22222222-2222-4222-8222-222222222222"
        XCTAssertEqual(MenuBarQuickAccess.route(for: entry, application: native), .workspace)
    }

    func testPendingConfirmationEditorsAndCloudLinksAlwaysReturnToWorkspace() {
        var entry = ChatEntry(title: "Local", url: localURL, isFavorite: true, verification: VerificationRecord(url: localURL, application: native))
        XCTAssertEqual(MenuBarQuickAccess.route(for: entry, application: native, hasPendingConfirmation: true), .workspace)
        XCTAssertEqual(MenuBarQuickAccess.route(for: entry, application: native, hasActiveEditor: true), .workspace)
        for url in ["https://chatgpt.com/c/11111111-1111-4111-8111-111111111111", "chatgpt-conversation://11111111-1111-4111-8111-111111111111", "https://example.com"] {
            entry.url = url
            entry.verification = VerificationRecord(url: url, application: native)
            XCTAssertEqual(MenuBarQuickAccess.route(for: entry, application: native), .workspace)
        }
    }
}
