import Foundation
import Testing
@testable import GitCore

@Suite struct HistoryTests {
    private func minute(_ n: Int) -> Date { Date(timeIntervalSince1970: 1_780_000_000 + Double(n) * 60) }
    private func sha(_ fixture: TestRepository, _ rev: String) throws -> String {
        try fixture.git("rev-parse", rev).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test func includesCommitsOnlyReachableFromAnotherBranch() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "1\n")
        try fixture.commitAll("First", date: minute(0))
        try fixture.git("checkout", "-q", "-b", "side")
        try fixture.write("a.txt", "2\n")
        try fixture.commitAll("On side", date: minute(1))
        try fixture.git("checkout", "-q", "main")

        let history = try await GitRepository(url: fixture.url).history()
        #expect(history.map(\.commit.summary) == ["On side", "First"])
        #expect(history[0].refs == [RefLabel(name: "side", kind: .localBranch(isCurrent: false))])
        #expect(history[1].refs == [RefLabel(name: "main", kind: .localBranch(isCurrent: true))])
    }

    @Test func includesCommitsOnlyReachableFromTags() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "1\n")
        try fixture.commitAll("First", date: minute(0))
        try fixture.git("checkout", "-q", "-b", "light")
        try fixture.write("a.txt", "2\n")
        try fixture.commitAll("Lightweight", date: minute(1))
        try fixture.git("tag", "v1")
        try fixture.git("checkout", "-q", "-b", "annotated", "main")
        try fixture.write("a.txt", "3\n")
        try fixture.commitAll("Annotated", date: minute(2))
        try fixture.git("tag", "-a", "v2", "-m", "Release 2")
        try fixture.git("checkout", "-q", "main")
        try fixture.git("branch", "-D", "light", "annotated")

        let history = try await GitRepository(url: fixture.url).history()
        #expect(history.map(\.commit.summary) == ["Annotated", "Lightweight", "First"])
        #expect(history[0].refs == [RefLabel(name: "v2", kind: .tag)])
        #expect(history[1].refs == [RefLabel(name: "v1", kind: .tag)])
    }

    @Test func skipsTagsThatDoNotPointAtCommits() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "1\n")
        try fixture.commitAll("First", date: minute(0))
        try fixture.git("tag", "tree-tag", "HEAD^{tree}")

        let history = try await GitRepository(url: fixture.url).history()
        #expect(history.map(\.commit.summary) == ["First"])
        #expect(history[0].refs == [RefLabel(name: "main", kind: .localBranch(isCurrent: true))])
    }

    @Test func includesOriginMainButNotOtherRemoteBranches() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "1\n")
        try fixture.commitAll("First", date: minute(0))
        try fixture.addOrigin()
        try fixture.git("checkout", "-q", "-b", "elsewhere")
        try fixture.write("a.txt", "2\n")
        try fixture.commitAll("Only on origin/elsewhere", date: minute(1))
        try fixture.git("push", "-q", "origin", "elsewhere")  // untagged, so no tag drags it in
        try fixture.git("checkout", "-q", "main")
        try fixture.git("branch", "-D", "elsewhere")
        try fixture.commitOnOrigin("Remote work")

        let repo = try GitRepository(url: fixture.url)
        _ = try await repo.fetch()
        let history = try await repo.history()
        let summaries = history.map(\.commit.summary)
        #expect(summaries.contains("Remote work"))
        #expect(!summaries.contains("Only on origin/elsewhere"))
        let remote = try #require(history.first { $0.commit.summary == "Remote work" })
        #expect(remote.refs == [RefLabel(name: "origin/main", kind: .remoteBranch)])
    }

    @Test func mergeEntriesCarryBothParents() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "1\n")
        try fixture.commitAll("First", date: minute(0))
        try fixture.git("checkout", "-q", "-b", "feature")
        try fixture.write("b.txt", "b\n")
        try fixture.commitAll("Feature", date: minute(1))
        try fixture.git("checkout", "-q", "main")
        try fixture.write("c.txt", "c\n")
        try fixture.commitAll("Main", date: minute(2))
        try fixture.git(date: minute(3), "merge", "-q", "--no-ff", "-m", "Merge feature", "feature")

        let history = try await GitRepository(url: fixture.url).history()
        let merge = try #require(history.first)
        let parents = [try sha(fixture, "HEAD^1"), try sha(fixture, "HEAD^2")]
        #expect(merge.commit.summary == "Merge feature")
        #expect(merge.commit.parentSHAs == parents)
        #expect(merge.graph.isMerge)
        #expect(merge.graph.column == 0)
    }

    @Test func labelsAreOrderedCurrentLocalRemoteTag() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "1\n")
        try fixture.commitAll("First", date: minute(0))
        try fixture.addOrigin()
        try fixture.git("branch", "zeta")
        try fixture.git("branch", "alpha")
        try fixture.git("tag", "v2.10")
        try fixture.git("tag", "v2.9")

        let history = try await GitRepository(url: fixture.url).history()
        #expect(history[0].refs == [
            RefLabel(name: "main", kind: .localBranch(isCurrent: true)),
            RefLabel(name: "alpha", kind: .localBranch(isCurrent: false)),
            RefLabel(name: "zeta", kind: .localBranch(isCurrent: false)),
            RefLabel(name: "origin/main", kind: .remoteBranch),
            RefLabel(name: "v2.9", kind: .tag),
            RefLabel(name: "v2.10", kind: .tag),
        ])
    }

    @Test func detachedHeadCommitAppearsLabelledHead() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "1\n")
        try fixture.commitAll("First", date: minute(0))
        try fixture.git("checkout", "-q", "--detach")
        try fixture.write("a.txt", "2\n")
        try fixture.commitAll("Detached work", date: minute(1))

        let history = try await GitRepository(url: fixture.url).history()
        #expect(history.map(\.commit.summary) == ["Detached work", "First"])
        #expect(history[0].refs == [RefLabel(name: "HEAD", kind: .head)])
        #expect(history[1].refs == [RefLabel(name: "main", kind: .localBranch(isCurrent: false))])
    }

    @Test func unbornHeadStillShowsOtherBranches() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "1\n")
        try fixture.commitAll("First", date: minute(0))
        try fixture.git("checkout", "-q", "--orphan", "fresh")

        let history = try await GitRepository(url: fixture.url).history()
        #expect(history.map(\.commit.summary) == ["First"])
    }

    /// Each case makes `candidate` the highest-precedence mainline ref that exists and points every
    /// lower-precedence ref (including HEAD) at a different commit, which must not land in column 0.
    @Test(arguments: ["main", "master", "origin/main", "HEAD"])
    func mainlineTipFallsBackInOrder(candidate: String) async throws {
        let fixture = try TestRepository()
        try fixture.write("base.txt", "base\n")
        try fixture.commitAll("Base", date: minute(0))
        try fixture.git("checkout", "-q", "-b", "other")
        try fixture.write("b.txt", "b\n")
        try fixture.commitAll("Other", date: minute(2))
        try fixture.git("checkout", "-q", "-b", "candidate", "main")
        try fixture.write("a.txt", "a\n")
        try fixture.commitAll("Candidate", date: minute(1))
        let candidateSHA = try sha(fixture, "HEAD")
        let otherSHA = try sha(fixture, "other")
        try fixture.git("checkout", "-q", "other")
        try fixture.git("branch", "-D", "main", "candidate")

        switch candidate {
        case "main":
            try fixture.git("branch", "main", candidateSHA)
            try fixture.git("branch", "master", otherSHA)
            try fixture.git("update-ref", "refs/remotes/origin/main", otherSHA)
        case "master":
            try fixture.git("branch", "master", candidateSHA)
            try fixture.git("update-ref", "refs/remotes/origin/main", otherSHA)
        case "origin/main":
            try fixture.git("update-ref", "refs/remotes/origin/main", candidateSHA)
        default:
            try fixture.git("checkout", "-q", "--detach", candidateSHA)
        }

        let history = try await GitRepository(url: fixture.url).history()
        #expect(try #require(history.first { $0.commit.sha == candidateSHA }).graph.column == 0)
        #expect(try #require(history.first { $0.commit.sha == otherSHA }).graph.column != 0)
    }

    @Test func walkStopsAtLimit() async throws {
        let fixture = try TestRepository()
        for (index, name) in ["First", "Second", "Third"].enumerated() {
            try fixture.write("a.txt", "\(index)\n")
            try fixture.commitAll(name, date: minute(index))
        }
        let history = try await GitRepository(url: fixture.url).history(limit: 2)
        #expect(history.map(\.commit.summary) == ["Third", "Second"])
    }
}
