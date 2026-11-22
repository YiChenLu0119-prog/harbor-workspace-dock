import XCTest
@testable import HarborCore

final class PreferencesRepositoryTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("HarborPreferencesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testDefaultsAndPersistenceDoNotTouchWorkspaceData() throws {
        let workspaceURL = directory.appendingPathComponent("workspace.json")
        let original = Data(#"{"schemaVersion":1,"projects":[{"privateData":"leave this untouched"}]}"#.utf8)
        try original.write(to: workspaceURL)
        let repository = PreferencesRepository(directory: directory)
        var preferences = try repository.load()
        var legacyDefaults = HarborPreferences()
        legacyDefaults.language = .simplifiedChinese
        XCTAssertEqual(preferences, legacyDefaults)
        XCTAssertEqual(preferences.appearance, .system)
        preferences.appearance = .dark
        preferences.accent = .blue
        preferences.density = .compact
        preferences.startView = .favorites
        try repository.save(preferences)
        XCTAssertEqual(try PreferencesRepository(directory: directory).load(), preferences)
        XCTAssertEqual(try Data(contentsOf: workspaceURL), original)
    }

    func testCorruptPreferencesArePreservedAndCannotBeOverwritten() throws {
        let repository = PreferencesRepository(directory: directory)
        let original = Data("{broken".utf8)
        try original.write(to: repository.fileURL)
        XCTAssertThrowsError(try repository.load())
        XCTAssertThrowsError(try repository.save(HarborPreferences()))
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), original)
    }

    func testFuturePreferencesSchemaIsProtectedBeforeDecodingValues() throws {
        let repository = PreferencesRepository(directory: directory)
        let future = Data(#"{"schemaVersion":99,"appearance":"future"}"#.utf8)
        try future.write(to: repository.fileURL)
        XCTAssertThrowsError(try repository.load()) { error in
            guard case PreferencesError.unsupportedVersion(99) = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertThrowsError(try repository.save(HarborPreferences()))
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), future)
    }

    func testPreferenceSaveRequiresLoadAndDoesNotCreateDataOnRead() throws {
        let repository = PreferencesRepository(directory: directory)
        XCTAssertThrowsError(try repository.save(HarborPreferences()))
        _ = try repository.load()
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.fileURL.path))
    }

    func testPreferenceWriteFailureLeavesThePreviousValueUntouched() throws {
        let repository = PreferencesRepository(directory: directory)
        _ = try repository.load()
        try FileManager.default.createDirectory(at: repository.fileURL, withIntermediateDirectories: true)
        let sentinel = repository.fileURL.appendingPathComponent("keep")
        try Data("preserve".utf8).write(to: sentinel)
        XCTAssertThrowsError(try repository.save(HarborPreferences()))
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("preserve".utf8))
    }
}

final class PresentationPolicyTests: XCTestCase {
    func testOnlyEnabledSystemStatusCountsAsEnabled() {
        XCTAssertTrue(LoginItemState.enabled.isEnabled)
        for state: LoginItemState in [.notRegistered, .requiresApproval, .notFound, .unknown] {
            XCTAssertFalse(state.isEnabled)
        }
    }

    func testLoginLaunchStaysQuietAndManualLaunchShowsPanel() {
        XCTAssertFalse(LaunchPresentation.shouldShowPanel(isLoginItem: true, arguments: []))
        XCTAssertTrue(LaunchPresentation.shouldShowPanel(isLoginItem: false, arguments: []))
        XCTAssertTrue(LaunchPresentation.shouldShowPanel(isLoginItem: true, arguments: ["--show"]))
        XCTAssertFalse(LaunchPresentation.shouldShowPanel(isLoginItem: false, arguments: ["--hidden"]))
        XCTAssertFalse(LaunchPresentation.shouldShowPanel(isLoginItem: true, arguments: ["--show", "--hidden"]))
    }

    func testSearchAndScopeChangesKeepSelectionOnAVisibleEntry() {
        let first = UUID(), second = UUID(), hidden = UUID()
        XCTAssertEqual(EntrySelection.reconciled(current: second, visibleIDs: [first, second]), second)
        XCTAssertEqual(EntrySelection.reconciled(current: hidden, visibleIDs: [first, second]), first)
        XCTAssertEqual(EntrySelection.reconciled(current: nil, visibleIDs: [first, second]), first)
        XCTAssertNil(EntrySelection.reconciled(current: first, visibleIDs: []))
    }
}
