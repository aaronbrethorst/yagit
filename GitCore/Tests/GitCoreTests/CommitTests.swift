import Foundation
import Testing
@testable import GitCore

@Suite struct CommitTests {
    @Test func commitContainsOnlyTheStagedHunk() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", twentyLines)
        try fixture.commitAll("Initial")
        try fixture.write("a.txt", editedTwentyLines())

        let repo = try GitRepository(url: fixture.url)
        let diff = try #require(try await repo.diff(path: "a.txt", side: .unstaged))
        try await repo.stageHunk(path: "a.txt", hunk: diff.hunks[0], fileStatus: .modified)
        let commit = try await repo.commit(message: "Change line 2\n\nBody text.")

        #expect(commit.summary == "Change line 2")
        #expect(commit.message == "Change line 2\n\nBody text.")
        #expect(commit.authorName == "Test Author")
        #expect(commit.authorEmail == "test@example.com")
        #expect(commit.shortSHA.count == 7)
        #expect(abs(commit.date.timeIntervalSinceNow) < 5)

        let shown = try fixture.git("show", "--stat", "--format=%s", "HEAD")
        #expect(shown.hasPrefix("Change line 2"))
        #expect(shown.contains("1 insertion(+), 1 deletion(-)"))

        let snapshot = try await repo.snapshot()
        #expect(snapshot.staged.isEmpty)
        #expect(snapshot.unstaged == [ChangedFile(path: "a.txt", status: .modified, side: .unstaged)])
        let remaining = try #require(try await repo.diff(path: "a.txt", side: .unstaged))
        #expect(remaining.hunks.count == 1)
        #expect(remaining.hunks[0].lines.contains { $0.text == "inserted after 18" })
    }

    @Test func historyIsNewestFirstAcrossBranches() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "1\n")
        try fixture.commitAll("First")
        try fixture.write("a.txt", "2\n")
        try fixture.commitAll("Second")
        try fixture.git("checkout", "-q", "-b", "feature")
        try fixture.write("a.txt", "3\n")
        try fixture.commitAll("Third on feature")

        let repo = try GitRepository(url: fixture.url)
        #expect(try await repo.history().map(\.commit.summary) == ["Third on feature", "Second", "First"])
        try await repo.switchBranch(named: "main")
        #expect(try await repo.history().map(\.commit.summary) == ["Third on feature", "Second", "First"])
    }

    @Test func commitDetailListsFilesWithCounts() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "one\n")
        try fixture.write("b.txt", "b\n")
        try fixture.commitAll("Initial")
        try fixture.write("a.txt", "one\ntwo\n")
        try fixture.remove("b.txt")
        try fixture.write("c.txt", "c\n")
        try fixture.commitAll("Second")

        let repo = try GitRepository(url: fixture.url)
        let head = try #require(try await repo.history().first).commit
        let detail = try await repo.commitDetail(sha: head.sha)

        #expect(detail.commit == head)
        #expect(detail.files.map(\.path) == ["a.txt", "b.txt", "c.txt"])
        #expect(detail.files.map(\.status) == [.modified, .deleted, .added])
        #expect(detail.files.map(\.additions) == [1, 0, 1])
        #expect(detail.files.map(\.deletions) == [0, 1, 0])
        #expect(detail.files[0].hunks[0].lines.map(\.text) == ["one", "two"])

        let root = try #require(try await repo.history().last).commit
        #expect(try await repo.commitDetail(sha: root.sha).files.map(\.path) == ["a.txt", "b.txt"])
    }

    @Test func commitSummariesCarryParentSHAs() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "1\n")
        try fixture.commitAll("First")
        try fixture.git("checkout", "-q", "-b", "feature")
        try fixture.write("b.txt", "b\n")
        try fixture.commitAll("Feature")
        try fixture.git("checkout", "-q", "main")
        try fixture.write("c.txt", "c\n")
        try fixture.commitAll("Main")
        try fixture.git("merge", "-q", "--no-ff", "-m", "Merge feature", "feature")

        let merge = try fixture.git("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        let parents = try fixture.git("rev-parse", "HEAD^1", "HEAD^2").split(separator: "\n").map(String.init)
        let root = try fixture.git("rev-list", "--max-parents=0", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)

        let repo = try GitRepository(url: fixture.url)
        #expect(try await repo.commitDetail(sha: merge).commit.parentSHAs == parents)
        #expect(try await repo.commitDetail(sha: root).commit.parentSHAs.isEmpty)
    }

    @Test func emptyRepositoryHasNoHistory() async throws {
        let fixture = try TestRepository()
        let repo = try GitRepository(url: fixture.url)
        #expect(try await repo.history().isEmpty)
        #expect(try await repo.snapshot().currentBranch == "main")
    }
}
