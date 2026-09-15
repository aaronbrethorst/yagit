import Foundation
import Testing
@testable import GitCore

@Suite struct BranchTests {
    @Test func createBranchStartsAtHeadAndChecksItOut() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "1\n")
        try fixture.commitAll("First")
        try fixture.write("a.txt", "2\n")  // uncommitted change carries over

        let repo = try GitRepository(url: fixture.url)
        try await repo.createBranch(named: "feature/trip-planner")

        let snapshot = try await repo.snapshot()
        #expect(snapshot.currentBranch == "feature/trip-planner")
        #expect(snapshot.branches.map(\.name) == ["feature/trip-planner", "main"])
        #expect(snapshot.unstaged.map(\.path) == ["a.txt"])
        #expect(try await repo.history().map(\.summary) == ["First"])
        #expect(try fixture.git("rev-parse", "--abbrev-ref", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines) == "feature/trip-planner")
    }

    @Test func duplicateBranchNameIsRefused() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "1\n")
        try fixture.commitAll("First")

        let repo = try GitRepository(url: fixture.url)
        let error = await #expect(throws: GitError.self) { try await repo.createBranch(named: "main") }
        #expect(error?.message.contains("already exists") == true)
        #expect(try await repo.snapshot().currentBranch == "main")
    }

    @Test func invalidBranchNameIsRefused() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "1\n")
        try fixture.commitAll("First")

        let repo = try GitRepository(url: fixture.url)
        await #expect(throws: GitError.self) { try await repo.createBranch(named: "bad name") }
    }

    @Test func commitsOnANewBranchDoNotAppearOnTheParent() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "1\n")
        try fixture.commitAll("First")

        let repo = try GitRepository(url: fixture.url)
        try await repo.createBranch(named: "feature")
        try fixture.write("a.txt", "2\n")
        try await repo.stage(path: "a.txt")
        try await repo.commit(message: "On feature")
        #expect(try await repo.history().map(\.summary) == ["On feature", "First"])

        try await repo.switchBranch(named: "main")
        #expect(try await repo.history().map(\.summary) == ["First"])
        #expect(try fixture.read("a.txt") == "1\n")
    }

    @Test func fetchReportsUpToDateThenUpdated() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "1\n")
        try fixture.commitAll("First")
        try fixture.addOrigin()

        let repo = try GitRepository(url: fixture.url)
        #expect(try await repo.fetch() == .upToDate)

        try fixture.commitOnOrigin("Remote work")
        #expect(try await repo.fetch() == .updated)
        #expect(try await repo.fetch() == .upToDate)
        #expect(try await repo.snapshot().branches.first?.ahead == 0)
    }

    @Test func fetchWithoutOriginFails() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "1\n")
        try fixture.commitAll("First")
        let repo = try GitRepository(url: fixture.url)
        await #expect(throws: GitError.self) { try await repo.fetch() }
    }
}
