import Foundation
import GitCore
import Testing
@testable import YAGit

private func commit(_ sha: String, _ parents: String...) -> CommitSummary {
    CommitSummary(sha: sha, summary: sha, message: sha, authorName: "A", authorEmail: "a@example.com",
                  date: .distantPast, parentSHAs: parents)
}

@MainActor
struct GraphLaneCountTests {
    @Test func emptyHistoryHasNoLanes() {
        #expect(RepositoryStore.laneCount(for: []) == 0)
    }

    @Test func laneCountCoversTheWidestRow() {
        let commits = [commit("M", "A", "S"), commit("S", "A"), commit("A")]
        let rows = GraphLayout.rows(for: commits, mainlineTip: "M")
        let entries = zip(commits, rows).map { HistoryEntry(commit: $0, refs: [], graph: $1) }
        #expect(RepositoryStore.laneCount(for: entries) == 2)
    }

    @Test func laneCountIsCappedAtEight() {
        let tips = (0..<10).map { commit("t\($0)", "p\($0)") }
        let parents = (0..<10).map { commit("p\($0)") }
        let rows = GraphLayout.rows(for: tips + parents, mainlineTip: nil)
        let entries = zip(tips + parents, rows).map { HistoryEntry(commit: $0, refs: [], graph: $1) }
        #expect(rows.map(\.column).max() == 9)
        #expect(RepositoryStore.laneCount(for: entries) == 8)
    }
}
