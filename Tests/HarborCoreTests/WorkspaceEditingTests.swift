import XCTest
@testable import HarborCore

private func fixture() -> Workspace {
    let url = "codex://threads/00000000-0000-4000-8000-000000000001"
    let identity = NativeAppIdentity(bundleID: "com.openai.codex", version: "test (1)")
    let record = VerificationRecord(url: url, application: identity, confirmedAt: Date(timeIntervalSince1970: 1_000))
    return Workspace(projects: [
        Project(title: "Alpha", entries: [
            ChatEntry(title: "A", url: url, isFavorite: true, verification: record),
            ChatEntry(title: "B", url: url), ChatEntry(title: "C", url: url), ChatEntry(title: "D", url: url)
        ]),
        Project(title: "Beta", entries: [ChatEntry(title: "E", url: url)]),
        Project(title: "Empty")
    ])
}

final class WorkspaceEditingTests: XCTestCase {
    func testCrossProjectMovePreservesIdentityFavoriteAndNativeVerification() throws {
        var workspace = fixture()
        let source = workspace.projects[0].entries[0]
        let targetID = workspace.projects[1].id
        try WorkspaceEditing.move(entryID: source.id, to: targetID, in: &workspace)
        XCTAssertEqual(workspace.projects[0].entries.map(\.title), ["B", "C", "D"])
        XCTAssertEqual(workspace.projects[1].entries.map(\.title), ["E", "A"])
        XCTAssertEqual(workspace.projects[1].entries.last, source)
        XCTAssertTrue(workspace.projects[1].entries.last!.isVerified(for: source.verification!.application))
        XCTAssertEqual(workspace.schemaVersion, 1)
    }

    func testMoveIntoEmptyProjectAndSameProjectNoOp() throws {
        var workspace = fixture()
        let entryID = workspace.projects[0].entries[1].id
        let original = workspace
        try WorkspaceEditing.move(entryID: entryID, to: workspace.projects[0].id, in: &workspace)
        XCTAssertEqual(workspace, original)
        try WorkspaceEditing.move(entryID: entryID, to: workspace.projects[2].id, in: &workspace)
        XCTAssertEqual(workspace.projects[2].entries.map(\.title), ["B"])
        XCTAssertEqual(workspace.projects[2].entries[0].id, entryID)
    }

    func testAnchorReorderHandlesBothDirectionsWithoutIndexDrift() throws {
        var workspace = fixture()
        let entries = workspace.projects[0].entries
        try WorkspaceEditing.reorder(entryID: entries[0].id, relativeTo: entries[2].id, placement: .after, in: &workspace)
        XCTAssertEqual(workspace.projects[0].entries.map(\.title), ["B", "C", "A", "D"])
        try WorkspaceEditing.reorder(entryID: entries[3].id, relativeTo: entries[1].id, placement: .before, in: &workspace)
        XCTAssertEqual(workspace.projects[0].entries.map(\.title), ["D", "B", "C", "A"])
        try WorkspaceEditing.reorder(entryID: entries[1].id, relativeTo: entries[3].id, placement: .before, in: &workspace)
        XCTAssertEqual(workspace.projects[0].entries.map(\.title), ["B", "D", "C", "A"])
        XCTAssertEqual(workspace.projects[0].entries.last, entries[0])
    }

    func testReorderSelfAndAlreadyAdjacentAreNoOps() throws {
        var workspace = fixture()
        let original = workspace
        let a = workspace.projects[0].entries[0].id, b = workspace.projects[0].entries[1].id
        try WorkspaceEditing.reorder(entryID: a, relativeTo: a, placement: .after, in: &workspace)
        XCTAssertEqual(workspace, original)
        try WorkspaceEditing.reorder(entryID: a, relativeTo: b, placement: .before, in: &workspace)
        XCTAssertEqual(workspace, original)
    }

    func testStepsRespectGroupEdgesAndRejectInvalidDirection() throws {
        var workspace = fixture()
        let original = workspace
        let a = workspace.projects[0].entries[0].id, d = workspace.projects[0].entries[3].id
        try WorkspaceEditing.step(entryID: a, by: -1, in: &workspace)
        try WorkspaceEditing.step(entryID: d, by: 1, in: &workspace)
        XCTAssertEqual(workspace, original)
        XCTAssertThrowsError(try WorkspaceEditing.step(entryID: a, by: 0, in: &workspace))
        XCTAssertEqual(workspace, original)
        try WorkspaceEditing.step(entryID: d, by: -1, in: &workspace)
        XCTAssertEqual(workspace.projects[0].entries.map(\.title), ["A", "B", "D", "C"])
    }

    func testMissingTargetsAndCrossGroupAnchorsDoNotPartiallyMutate() throws {
        var workspace = fixture()
        let original = workspace
        let source = workspace.projects[0].entries[0].id, foreignAnchor = workspace.projects[1].entries[0].id
        XCTAssertThrowsError(try WorkspaceEditing.move(entryID: source, to: UUID(), in: &workspace))
        XCTAssertThrowsError(try WorkspaceEditing.move(entryID: UUID(), to: workspace.projects[1].id, in: &workspace))
        XCTAssertThrowsError(try WorkspaceEditing.reorder(entryID: source, relativeTo: foreignAnchor, placement: .after, in: &workspace))
        XCTAssertThrowsError(try WorkspaceEditing.delete(entryID: UUID(), in: &workspace))
        XCTAssertEqual(workspace, original)
    }

    func testFilteredViewsCannotReorderHiddenItems() {
        XCTAssertTrue(EntryReorderPolicy.allowsReorder(query: "", favoritesOnly: false))
        XCTAssertFalse(EntryReorderPolicy.allowsReorder(query: "A", favoritesOnly: false))
        XCTAssertFalse(EntryReorderPolicy.allowsReorder(query: " ", favoritesOnly: false))
        XCTAssertFalse(EntryReorderPolicy.allowsReorder(query: "", favoritesOnly: true))
    }

    func testDragPayloadRequiresExactActiveDragAndRejectsExternalOrStaleData() throws {
        let active = InternalEntryDrag(sessionID: UUID(), entryID: UUID())
        XCTAssertEqual(InternalEntryDrag.validated(try JSONEncoder().encode(active), active: active), active)
        let outsiders = [
            InternalEntryDrag(sessionID: UUID(), dragID: active.dragID, entryID: active.entryID),
            InternalEntryDrag(sessionID: active.sessionID, dragID: UUID(), entryID: active.entryID),
            InternalEntryDrag(sessionID: active.sessionID, dragID: active.dragID, entryID: UUID())
        ]
        for outsider in outsiders { XCTAssertNil(InternalEntryDrag.validated(try JSONEncoder().encode(outsider), active: active)) }
        XCTAssertNil(InternalEntryDrag.validated(try JSONEncoder().encode(active), active: nil))
        XCTAssertNil(InternalEntryDrag.validated(Data("not JSON".utf8), active: active))
        XCTAssertNil(InternalEntryDrag.validated(Data(repeating: 0, count: 1025), active: active))
    }
}

final class WorkspaceSessionTests: XCTestCase {
    private enum SaveFailure: Error { case simulated }

    func testDeleteUndoPersistsFullEntryAtItsOriginalPosition() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HarborUndoTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = WorkspaceRepository(directory: directory)
        _ = try repository.load()
        let original = fixture()
        try repository.save(original)
        let session = WorkspaceSession(workspace: original, save: repository.save)
        let id = original.projects[0].entries[0].id
        XCTAssertTrue(try session.commit(action: "Delete A") { try WorkspaceEditing.delete(entryID: id, in: &$0) })
        XCTAssertEqual(try WorkspaceRepository(directory: directory).load(), session.workspace)
        XCTAssertEqual(session.undoAction, "Delete A")
        XCTAssertTrue(try session.undo())
        XCTAssertEqual(session.workspace, original)
        XCTAssertEqual(try WorkspaceRepository(directory: directory).load(), original)
        XCTAssertNil(session.undoAction)
    }

    func testInterveningEditIsUndoneBeforeDeletionWithoutLosingWork() throws {
        let original = fixture()
        var saves: [Workspace] = []
        let session = WorkspaceSession(workspace: original) { saves.append($0) }
        let id = original.projects[0].entries[0].id
        try session.commit(action: "Delete A") { try WorkspaceEditing.delete(entryID: id, in: &$0) }
        try session.commit(action: "Edit B") { $0.projects[0].entries[0].title = "B edited" }
        XCTAssertEqual(session.undoAction, "Edit B")
        try session.undo()
        XCTAssertEqual(session.workspace.projects[0].entries.map(\.title), ["B", "C", "D"])
        XCTAssertEqual(session.undoAction, "Delete A")
        try session.undo()
        XCTAssertEqual(session.workspace, original)
        XCTAssertEqual(saves.count, 4)
    }

    func testFailedSaveDoesNotChangeStateOrHistory() throws {
        let original = fixture()
        var shouldFail = false
        let session = WorkspaceSession(workspace: original) { _ in if shouldFail { throw SaveFailure.simulated } }
        try session.commit(action: "Favorite B") { $0.projects[0].entries[1].isFavorite = true }
        let beforeFailure = session.workspace
        shouldFail = true
        XCTAssertThrowsError(try session.commit(action: "Delete A") { try WorkspaceEditing.delete(entryID: original.projects[0].entries[0].id, in: &$0) })
        XCTAssertEqual(session.workspace, beforeFailure)
        XCTAssertEqual(session.undoAction, "Favorite B")
        XCTAssertEqual(session.undoDepth, 1)
    }

    func testFailedUndoRetainsHistoryAndCanBeRetried() throws {
        let original = fixture()
        var shouldFail = false
        let session = WorkspaceSession(workspace: original) { _ in if shouldFail { throw SaveFailure.simulated } }
        try session.commit(action: "Move A") { try WorkspaceEditing.move(entryID: original.projects[0].entries[0].id, to: original.projects[2].id, in: &$0) }
        let moved = session.workspace
        shouldFail = true
        XCTAssertThrowsError(try session.undo())
        XCTAssertEqual(session.workspace, moved)
        XCTAssertEqual(session.undoAction, "Move A")
        XCTAssertEqual(session.undoDepth, 1)
        shouldFail = false
        XCTAssertTrue(try session.undo())
        XCTAssertEqual(session.workspace, original)
    }

    func testNoOpsDoNotSaveOrCreateHistoryAndHistoryIsBounded() throws {
        var saveCount = 0
        let session = WorkspaceSession(workspace: fixture(), historyLimit: 2) { _ in saveCount += 1 }
        XCTAssertFalse(try session.commit(action: "No change") { _ in })
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(session.undoDepth, 0)
        for title in ["First", "Second", "Third"] { try session.commit(action: title) { $0.projects[0].title = title } }
        XCTAssertEqual(session.undoDepth, 2)
        try session.undo()
        XCTAssertEqual(session.workspace.projects[0].title, "Second")
        try session.undo()
        XCTAssertEqual(session.workspace.projects[0].title, "First")
        XCTAssertFalse(try session.undo())
        XCTAssertEqual(saveCount, 5)
    }

    func testThrowingMutationCannotLeakPartialChanges() throws {
        let original = fixture()
        var saveCount = 0
        let session = WorkspaceSession(workspace: original) { _ in saveCount += 1 }
        XCTAssertThrowsError(try session.commit(action: "Invalid edit") { value in
            value.projects[0].title = "Changed locally"
            throw SaveFailure.simulated
        })
        XCTAssertEqual(session.workspace, original)
        XCTAssertEqual(session.undoDepth, 0)
        XCTAssertEqual(saveCount, 0)
    }

    func testArrayOrderSurvivesPersistenceAndUndo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HarborOrderTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = WorkspaceRepository(directory: directory)
        _ = try repository.load()
        let original = fixture()
        try repository.save(original)
        let session = WorkspaceSession(workspace: original, save: repository.save)
        try session.commit(action: "Reorder") { try WorkspaceEditing.reorder(entryID: original.projects[0].entries[3].id, relativeTo: original.projects[0].entries[0].id, placement: .before, in: &$0) }
        let restored = try WorkspaceRepository(directory: directory).load()
        XCTAssertEqual(restored.projects[0].entries.map(\.title), ["D", "A", "B", "C"])
        XCTAssertEqual(restored.schemaVersion, 1)
        try session.undo()
        XCTAssertEqual(try WorkspaceRepository(directory: directory).load(), original)
    }
}
