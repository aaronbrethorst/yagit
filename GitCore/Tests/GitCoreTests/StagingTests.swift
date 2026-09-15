import Foundation
import Testing
@testable import GitCore

@Suite struct StagingTests {
    @Test func stagingOneOfTwoHunksSplitsTheFileAcrossBothSides() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", twentyLines)
        try fixture.commitAll("Initial")
        try fixture.write("a.txt", editedTwentyLines())

        let repo = try GitRepository(url: fixture.url)
        let before = try #require(try await repo.diff(path: "a.txt", side: .unstaged))
        try await repo.stageHunk(path: "a.txt", hunk: before.hunks[0], fileStatus: before.status)

        let snapshot = try await repo.snapshot()
        #expect(snapshot.staged == [ChangedFile(path: "a.txt", status: .modified, side: .staged)])
        #expect(snapshot.unstaged == [ChangedFile(path: "a.txt", status: .modified, side: .unstaged)])

        let staged = try #require(try await repo.diff(path: "a.txt", side: .staged))
        let unstaged = try #require(try await repo.diff(path: "a.txt", side: .unstaged))
        #expect(staged.hunks.count == 1)
        #expect(staged.hunks[0].lines.contains { $0.text == "line 2 changed" })
        #expect(unstaged.hunks.count == 1)
        #expect(unstaged.hunks[0].lines.contains { $0.text == "inserted after 18" })

        // The oracle agrees.
        let cached = try fixture.git("diff", "--cached", "--stat")
        #expect(cached.contains("1 file changed, 1 insertion(+), 1 deletion(-)"))
        #expect(try fixture.read("a.txt") == editedTwentyLines())
    }

    @Test func unstagingAHunkReturnsItToTheWorkingTree() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", twentyLines)
        try fixture.commitAll("Initial")
        try fixture.write("a.txt", editedTwentyLines())
        try fixture.git("add", "a.txt")

        let repo = try GitRepository(url: fixture.url)
        let staged = try #require(try await repo.diff(path: "a.txt", side: .staged))
        #expect(staged.hunks.count == 2)
        try await repo.unstageHunk(path: "a.txt", hunk: staged.hunks[1], fileStatus: staged.status)

        let after = try #require(try await repo.diff(path: "a.txt", side: .staged))
        #expect(after.hunks.count == 1)
        #expect(after.hunks[0].lines.contains { $0.text == "line 2 changed" })
        let unstaged = try #require(try await repo.diff(path: "a.txt", side: .unstaged))
        #expect(unstaged.hunks.count == 1)
        #expect(unstaged.hunks[0].lines.contains { $0.text == "inserted after 18" })
        #expect(try fixture.read("a.txt") == editedTwentyLines())
    }

    @Test func hunkWithoutTrailingNewlineRoundTrips() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "one\ntwo\n")
        try fixture.commitAll("Initial")
        try fixture.write("a.txt", "one\ntwo")

        let repo = try GitRepository(url: fixture.url)
        let diff = try #require(try await repo.diff(path: "a.txt", side: .unstaged))
        try await repo.stageHunk(path: "a.txt", hunk: diff.hunks[0], fileStatus: .modified)
        #expect(try await repo.snapshot().unstaged.isEmpty)

        let staged = try #require(try await repo.diff(path: "a.txt", side: .staged))
        try await repo.unstageHunk(path: "a.txt", hunk: staged.hunks[0], fileStatus: .modified)
        #expect(try await repo.snapshot().staged.isEmpty)
        #expect(try await repo.snapshot().unstaged.count == 1)
    }

    @Test func wholeFileStageAndUnstageForAddedAndDeletedFiles() async throws {
        let fixture = try TestRepository()
        try fixture.write("gone.txt", "gone\n")
        try fixture.commitAll("Initial")
        try fixture.write("new.txt", "new\n")
        try fixture.remove("gone.txt")

        let repo = try GitRepository(url: fixture.url)
        try await repo.stage(path: "new.txt")
        try await repo.stage(path: "gone.txt")
        var snapshot = try await repo.snapshot()
        #expect(snapshot.unstaged.isEmpty)
        #expect(snapshot.staged == [
            ChangedFile(path: "gone.txt", status: .deleted, side: .staged),
            ChangedFile(path: "new.txt", status: .added, side: .staged),
        ])

        try await repo.unstage(path: "new.txt")
        try await repo.unstage(path: "gone.txt")
        snapshot = try await repo.snapshot()
        #expect(snapshot.staged.isEmpty)
        #expect(snapshot.unstaged == [
            ChangedFile(path: "gone.txt", status: .deleted, side: .unstaged),
            ChangedFile(path: "new.txt", status: .added, side: .unstaged),
        ])
    }

    @Test func hunkOperationsOnAddedFilesFallBackToWholeFile() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "a\n")
        try fixture.commitAll("Initial")
        try fixture.write("new.txt", "new\n")

        let repo = try GitRepository(url: fixture.url)
        let diff = try #require(try await repo.diff(path: "new.txt", side: .unstaged))
        try await repo.stageHunk(path: "new.txt", hunk: diff.hunks[0], fileStatus: diff.status)
        #expect(try await repo.snapshot().staged.map(\.path) == ["new.txt"])

        let staged = try #require(try await repo.diff(path: "new.txt", side: .staged))
        try await repo.unstageHunk(path: "new.txt", hunk: staged.hunks[0], fileStatus: staged.status)
        #expect(try await repo.snapshot().staged.isEmpty)
        #expect(try await repo.snapshot().unstaged.map(\.path) == ["new.txt"])
    }
}
