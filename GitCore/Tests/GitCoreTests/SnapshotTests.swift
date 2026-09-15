import Foundation
import Testing
@testable import GitCore

@Suite struct SnapshotTests {
    @Test func openingAMissingRepositoryThrows() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(throws: GitError.self) { try GitRepository(url: missing) }
    }

    @Test func cleanRepositoryHasNoChanges() async throws {
        let fixture = try TestRepository()
        try fixture.write("README.md", "hello\n")
        try fixture.commitAll("Initial")

        let repo = try GitRepository(url: fixture.url)
        let snapshot = try await repo.snapshot()

        #expect(snapshot.currentBranch == "main")
        #expect(snapshot.staged.isEmpty)
        #expect(snapshot.unstaged.isEmpty)
        #expect(snapshot.branches.map(\.name) == ["main"])
        #expect(snapshot.branches.first?.isCurrent == true)
        #expect(snapshot.author == Author(name: "Test Author", email: "test@example.com"))
    }

    @Test func workingTreeChangesAreUnstagedWithStatusLetters() async throws {
        let fixture = try TestRepository()
        try fixture.write("keep.txt", "keep\n")
        try fixture.write("gone.txt", "gone\n")
        try fixture.write("Sources/App/edit.swift", "let a = 1\n")
        try fixture.commitAll("Initial")

        try fixture.write("Sources/App/edit.swift", "let a = 2\n")
        try fixture.write("new.txt", "new\n")
        try fixture.remove("gone.txt")

        let repo = try GitRepository(url: fixture.url)
        let snapshot = try await repo.snapshot()

        #expect(snapshot.staged.isEmpty)
        #expect(snapshot.unstaged == [
            ChangedFile(path: "Sources/App/edit.swift", status: .modified, side: .unstaged),
            ChangedFile(path: "gone.txt", status: .deleted, side: .unstaged),
            ChangedFile(path: "new.txt", status: .added, side: .unstaged),
        ])
    }

    @Test func indexChangesAreStaged() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "a\n")
        try fixture.commitAll("Initial")
        try fixture.write("a.txt", "b\n")
        try fixture.write("c.txt", "c\n")
        try fixture.git("add", "-A")

        let repo = try GitRepository(url: fixture.url)
        let snapshot = try await repo.snapshot()

        #expect(snapshot.unstaged.isEmpty)
        #expect(snapshot.staged == [
            ChangedFile(path: "a.txt", status: .modified, side: .staged),
            ChangedFile(path: "c.txt", status: .added, side: .staged),
        ])
    }

    @Test func fileWithChangesOnBothSidesAppearsInBothLists() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "one\n")
        try fixture.commitAll("Initial")
        try fixture.write("a.txt", "two\n")
        try fixture.git("add", "a.txt")
        try fixture.write("a.txt", "three\n")

        let repo = try GitRepository(url: fixture.url)
        let snapshot = try await repo.snapshot()

        #expect(snapshot.staged == [ChangedFile(path: "a.txt", status: .modified, side: .staged)])
        #expect(snapshot.unstaged == [ChangedFile(path: "a.txt", status: .modified, side: .unstaged)])
    }

    @Test func branchesReportAheadOfOrigin() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "a\n")
        try fixture.commitAll("Initial")
        try fixture.addOrigin()
        try fixture.write("a.txt", "b\n")
        try fixture.commitAll("Second")
        try fixture.git("branch", "feature/x")

        let repo = try GitRepository(url: fixture.url)
        let snapshot = try await repo.snapshot()

        #expect(snapshot.branches == [
            BranchInfo(name: "feature/x", isCurrent: false, ahead: nil),
            BranchInfo(name: "main", isCurrent: true, ahead: 1),
        ])
        #expect(snapshot.remoteBranches == ["origin/main"])
    }
}
