import XCTest
@testable import HarborCore

final class LocalizationTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("HarborLanguageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testFreshInstallDefaultsToEnglishAndStaysEnglishAfterCreatingAWorkspace() throws {
        XCTAssertEqual(HarborPreferences().language, .english)
        let repository = PreferencesRepository(directory: directory)
        XCTAssertEqual(try repository.loadOrCreate().language, .english)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.fileURL.path))
        let workspaceRepository = WorkspaceRepository(directory: directory)
        _ = try workspaceRepository.load()
        try workspaceRepository.save(Workspace(projects: [Project(title: "User project")]))
        XCTAssertEqual(try PreferencesRepository(directory: directory).loadOrCreate().language, .english)
    }

    func testExistingPreferencesWithoutLanguageStayChineseAndPreserveOtherChoices() throws {
        let old = Data(#"{"schemaVersion":1,"appearance":"dark","density":"compact","startView":"favorites","accent":"blue"}"#.utf8)
        let repository = PreferencesRepository(directory: directory)
        try old.write(to: repository.fileURL)
        let decoded = try repository.loadOrCreate()
        XCTAssertEqual(decoded.language, .simplifiedChinese)
        XCTAssertEqual(decoded.appearance, .dark)
        XCTAssertEqual(decoded.density, .compact)
        XCTAssertEqual(decoded.startView, .favorites)
        XCTAssertEqual(decoded.accent, .blue)
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), old, "Reading a valid legacy file does not rewrite it")
    }

    func testWorkspaceOnlyLegacyInstallGetsAStableChinesePreference() throws {
        let workspace = directory.appendingPathComponent("workspace.json")
        let original = Data(#"{"schemaVersion":1,"projects":[]}"#.utf8)
        try original.write(to: workspace)
        let repository = PreferencesRepository(directory: directory)
        XCTAssertEqual(try repository.loadOrCreate().language, .simplifiedChinese)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.fileURL.path))
        XCTAssertEqual(try Data(contentsOf: workspace), original)
    }

    func testLanguageSwitchPersistsWithoutChangingUserNamesOrWorkspaceBytes() throws {
        let repository = PreferencesRepository(directory: directory)
        var preferences = try repository.loadOrCreate()
        let workspaceURL = directory.appendingPathComponent("workspace.json")
        let original = Data(#"{"schemaVersion":1,"projects":[{"name":"自定义 User %@"}]}"#.utf8)
        try original.write(to: workspaceURL)
        preferences.language = .simplifiedChinese
        try repository.save(preferences)
        XCTAssertEqual(try PreferencesRepository(directory: directory).load().language, .simplifiedChinese)
        preferences.language = .english
        try repository.save(preferences)
        XCTAssertEqual(try PreferencesRepository(directory: directory).load().language, .english)
        XCTAssertEqual(try Data(contentsOf: workspaceURL), original)
    }

    func testUnknownLanguageIsProtectedInsteadOfSilentlyOverwritten() throws {
        let repository = PreferencesRepository(directory: directory)
        let original = Data(#"{"schemaVersion":1,"appearance":"system","density":"comfortable","startView":"all","accent":"teal","language":"future-language"}"#.utf8)
        try original.write(to: repository.fileURL)
        XCTAssertThrowsError(try repository.loadOrCreate())
        XCTAssertThrowsError(try repository.save(HarborPreferences()))
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), original)
    }

    func testInitialPreferenceWriteFailureIsReported() throws {
        let blocked = directory.appendingPathComponent("not-a-directory")
        try Data("occupied".utf8).write(to: blocked)
        XCTAssertThrowsError(try PreferencesRepository(directory: blocked).loadOrCreate())
        XCTAssertEqual(try Data(contentsOf: blocked), Data("occupied".utf8))
    }

    func testUndoTextRendersAgainAfterSwitchingLanguageWithoutTranslatingUserText() {
        let action = HarborText("Move “%@” to “%@”", "自定义 %@ entry", "Project 中文")
        let restored = HarborText.restored(action.archived)
        XCTAssertEqual(restored.rendered(in: .english), "Move “自定义 %@ entry” to “Project 中文”")
        XCTAssertEqual(restored.rendered(in: .simplifiedChinese), "将「自定义 %@ entry」移到「Project 中文」")
        XCTAssertEqual(HarborText.restored("Legacy action").rendered(in: .english), "Legacy action")
    }

    func testEveryChineseTranslationKeepsTheSourceArgumentCount() {
        XCTAssertGreaterThan(HarborLocalization.chinese.count, 150)
        for (english, chinese) in HarborLocalization.chinese {
            XCTAssertEqual(english.components(separatedBy: "%@").count, chinese.components(separatedBy: "%@").count, english)
            XCTAssertFalse(chinese.isEmpty)
        }
    }

    func testKnownErrorsUseTheSelectedLanguage() {
        let error = RepositoryError.unsupportedVersion(99)
        XCTAssertEqual(HarborLocalization.errorDescription(error, language: .english), "Data version 99 is unsupported. The original file is preserved.")
        XCTAssertEqual(HarborLocalization.errorDescription(error, language: .simplifiedChinese), "资料版本 99 暂不支持，原文件已保留。")
    }
}
