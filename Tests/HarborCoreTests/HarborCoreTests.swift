import XCTest
@testable import HarborCore

final class LinkPolicyTests: XCTestCase {
    private let id = "00000000-0000-4000-8000-000000000001"

    func testRecognizesOnlyExactLocalThreadRoute() {
        XCTAssertEqual(LinkPolicy.classify("codex://threads/\(id)"), .localCodex(UUID(uuidString: id)!))
        for link in ["codex://threads/new", "codex://new", "codex://threads/not-an-id", "codex://threads/\(id)/", "codex://threads//\(id)", "codex://threads/\(id)?prompt=execute", "codex://threads/\(id)#fragment", "codex://user@threads/\(id)", "codex://threads:42/\(id)", "codex://threads/%30\(id.dropFirst())", "codex://threads/\(id)\n", " codex://threads/\(id)", "file:///tmp/test", "javascript:alert(1)"] {
            XCTAssertEqual(LinkPolicy.classify(link), .unsupported, link)
            XCTAssertNil(LinkPolicy.nativeCandidateURL(link), link)
        }
    }

    func testCloudAndInternalReferencesNeverBecomeNativeCandidates() {
        let cloud = "https://chatgpt.com/c/\(id)"
        let reference = "chatgpt-conversation://\(id)"
        XCTAssertEqual(LinkPolicy.classify(cloud), .cloudChatGPT)
        XCTAssertEqual(LinkPolicy.classify("https://chatgpt.com/g/g-p-project/c/\(id)"), .cloudChatGPT)
        XCTAssertEqual(LinkPolicy.classify(reference), .conversationReference)
        XCTAssertNil(LinkPolicy.nativeCandidateURL(cloud))
        XCTAssertNil(LinkPolicy.nativeCandidateURL(reference))
        for link in ["https://chatgpt.com.evil.example/c/\(id)", "https://chatgpt.com@evil.example/c/\(id)", "http://chatgpt.com/c/\(id)", "https://chatgpt.com/c/\(id)?redirect=evil", "https://evil.example/c/\(id)"] {
            XCTAssertEqual(LinkPolicy.classify(link), .unsupported)
        }
    }

    func testVerificationIsBoundToExactURLAndApplicationVersion() {
        let identity = NativeAppIdentity(bundleID: "com.openai.codex", version: "1 (1)")
        let url = "codex://threads/\(id)"
        var entry = ChatEntry(title: "Test", url: url)
        XCTAssertFalse(entry.isVerified(for: identity))
        entry.verification = VerificationRecord(url: url, application: identity)
        XCTAssertTrue(entry.isVerified(for: identity))
        XCTAssertFalse(entry.isVerified(for: NativeAppIdentity(bundleID: identity.bundleID, version: "2 (2)")))
        XCTAssertFalse(entry.isVerified(for: NativeAppIdentity(bundleID: "com.other.app", version: identity.version)))
        entry.url = "codex://threads/\(UUID().uuidString)"
        XCTAssertNil(entry.verification)
        XCTAssertFalse(entry.isVerified(for: identity))
        entry.verification = VerificationRecord(url: url, application: identity)
        XCTAssertFalse(entry.isVerified(for: identity), "Mismatched serialized verification must not be trusted")
    }

    func testCloudCannotGainNativeStatusFromImportedVerification() {
        let identity = NativeAppIdentity(bundleID: "com.openai.codex", version: "1")
        let url = "https://chatgpt.com/c/\(id)"
        let entry = ChatEntry(title: "Cloud", url: url, verification: VerificationRecord(url: url, application: identity))
        XCTAssertFalse(entry.isVerified(for: identity))
    }
}

final class WorkspaceRepositoryTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("HarborTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testMissingLibraryStartsEmptyAndRoundTripsUnicodeMetadata() throws {
        let repository = WorkspaceRepository(directory: directory)
        XCTAssertEqual(try repository.load(), Workspace())
        let app = NativeAppIdentity(bundleID: "com.openai.codex", version: "26 (1)")
        let url = "codex://threads/\(UUID().uuidString)"
        let record = VerificationRecord(url: url, application: app, confirmedAt: Date(timeIntervalSince1970: 1_000))
        let workspace = Workspace(projects: [Project(title: "音乐剧 🎭", entries: [ChatEntry(title: "剧本 · 第二幕", url: url, isFavorite: true, verification: record)])])
        try repository.save(workspace)
        XCTAssertEqual(try WorkspaceRepository(directory: directory).load(), workspace)
    }

    func testCorruptFileIsNeverOverwrittenByEmptyLibrary() throws {
        let repository = WorkspaceRepository(directory: directory)
        let damaged = Data("{broken JSON".utf8)
        try damaged.write(to: repository.fileURL)
        XCTAssertThrowsError(try repository.load())
        XCTAssertThrowsError(try repository.save(Workspace()))
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), damaged)
    }

    func testFutureSchemaIsPreservedWithoutAttemptingToDecodeNewFields() throws {
        let repository = WorkspaceRepository(directory: directory)
        let future = Data(#"{"schemaVersion":99,"newField":"future data"}"#.utf8)
        try future.write(to: repository.fileURL)
        XCTAssertThrowsError(try repository.load()) { error in
            guard case RepositoryError.unsupportedVersion(99) = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertThrowsError(try repository.save(Workspace()))
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), future)
    }

    func testSaveRequiresSuccessfulLoadAndRejectsDuplicateIDs() throws {
        let repository = WorkspaceRepository(directory: directory)
        XCTAssertThrowsError(try repository.save(Workspace()))
        _ = try repository.load()
        let project = Project(title: "one")
        XCTAssertThrowsError(try repository.save(Workspace(projects: [project, project])))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.fileURL.path))
    }

    func testStorageWriteFailureDoesNotReplaceExistingLibrary() throws {
        let repository = WorkspaceRepository(directory: directory)
        _ = try repository.load()
        try repository.save(Workspace(projects: [Project(title: "Keep")]))
        let original = try Data(contentsOf: repository.fileURL)
        // A directory in the file position reliably produces a write failure, even as an elevated user.
        try FileManager.default.removeItem(at: repository.fileURL)
        try FileManager.default.createDirectory(at: repository.fileURL, withIntermediateDirectories: false)
        let sentinel = repository.fileURL.appendingPathComponent("keep.json")
        try original.write(to: sentinel)
        XCTAssertThrowsError(try repository.save(Workspace()))
        XCTAssertEqual(try Data(contentsOf: sentinel), original)
    }
}
