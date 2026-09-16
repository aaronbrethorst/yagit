import Foundation
import Testing
@testable import GitCore

private func c(_ sha: String, _ parents: String...) -> CommitSummary {
    CommitSummary(sha: sha, summary: sha, message: sha, authorName: "A", authorEmail: "a@example.com",
                  date: .distantPast, parentSHAs: parents)
}

private func s(_ from: Int, _ to: Int, _ color: Int) -> GraphSegment {
    GraphSegment(fromColumn: from, toColumn: to, colorIndex: color)
}

private func row(_ column: Int, _ color: Int, merge: Bool = false, _ upper: [GraphSegment], _ lower: [GraphSegment]) -> GraphRow {
    GraphRow(column: column, colorIndex: color, isMerge: merge, upper: upper, lower: lower)
}

@Suite struct GraphLayoutTests {
    @Test func linearHistoryIsOneStraightLane() {
        let rows = GraphLayout.rows(for: [c("A", "B"), c("B", "C"), c("C")], mainlineTip: "A")
        #expect(rows == [
            row(0, 0, [], [s(0, 0, 0)]),
            row(0, 0, [s(0, 0, 0)], [s(0, 0, 0)]),
            row(0, 0, [s(0, 0, 0)], []),
        ])
    }

    @Test func rowsAboveTheMainlineTipDrawNothingInColumnZero() {
        let rows = GraphLayout.rows(for: [c("F2", "F1"), c("F1", "M"), c("M", "R"), c("R")], mainlineTip: "M")
        #expect(rows == [
            row(1, 1, [], [s(1, 1, 1)]),
            row(1, 1, [s(1, 1, 1)], [s(1, 0, 1)]),
            row(0, 0, [s(0, 0, 0)], [s(0, 0, 0)]),
            row(0, 0, [s(0, 0, 0)], []),
        ])
    }

    @Test func unmergedTipCurvesIntoTheMainlineInItsOwnColor() {
        let rows = GraphLayout.rows(for: [c("T", "M"), c("M", "R"), c("R")], mainlineTip: "M")
        #expect(rows[0] == row(1, 1, [], [s(1, 0, 1)]))
        #expect(rows[1] == row(0, 0, [s(0, 0, 0)], [s(0, 0, 0)]))
    }

    @Test func mergeOpensALaneForItsSecondParent() {
        let rows = GraphLayout.rows(for: [c("M", "A", "S"), c("S", "A"), c("A")], mainlineTip: "M")
        #expect(rows == [
            row(0, 0, merge: true, [], [s(0, 0, 0), s(0, 1, 1)]),
            row(1, 1, [s(0, 0, 0), s(1, 1, 1)], [s(0, 0, 0), s(1, 0, 1)]),
            row(0, 0, [s(0, 0, 0)], []),
        ])
    }

    @Test func octopusMergeOpensOneLanePerExtraParent() {
        let rows = GraphLayout.rows(for: [c("M", "A", "S1", "S2"), c("S1", "A"), c("S2", "A"), c("A")], mainlineTip: "M")
        #expect(rows[0] == row(0, 0, merge: true, [], [s(0, 0, 0), s(0, 1, 1), s(0, 2, 2)]))
        #expect(rows[1].column == 1)
        #expect(rows[2].column == 2)
        #expect(rows[3] == row(0, 0, [s(0, 0, 0)], []))
    }

    @Test func mergeJoinsALaneAlreadyWaitingForItsSecondParent() {
        let rows = GraphLayout.rows(for: [c("X", "S"), c("M", "A", "S"), c("S", "A"), c("A")], mainlineTip: "M")
        #expect(rows[0] == row(1, 1, [], [s(1, 1, 1)]))
        #expect(rows[1] == row(0, 0, merge: true, [s(1, 1, 1)], [s(1, 1, 1), s(0, 0, 0), s(0, 1, 1)]))
        #expect(rows[2] == row(1, 1, [s(0, 0, 0), s(1, 1, 1)], [s(0, 0, 0), s(1, 0, 1)]))
    }

    @Test func mainlineAndSideLaneWaitingForTheSameParentBothCloseThere() {
        let rows = GraphLayout.rows(for: [c("X", "B"), c("M", "B"), c("B")], mainlineTip: "M")
        #expect(rows == [
            row(1, 1, [], [s(1, 1, 1)]),
            row(0, 0, [s(1, 1, 1)], [s(1, 1, 1), s(0, 0, 0)]),
            row(0, 0, [s(0, 0, 0), s(1, 0, 1)], []),
        ])
    }

    @Test func sideBranchFromAnOlderMainlineCommitKeepsItsLaneUntilItsParent() {
        let rows = GraphLayout.rows(for: [c("S", "M3"), c("M1", "M2"), c("M2", "M3"), c("M3")], mainlineTip: "M1")
        #expect(rows == [
            row(1, 1, [], [s(1, 1, 1)]),
            row(0, 0, [s(1, 1, 1)], [s(1, 1, 1), s(0, 0, 0)]),
            row(0, 0, [s(0, 0, 0), s(1, 1, 1)], [s(1, 1, 1), s(0, 0, 0)]),
            row(0, 0, [s(0, 0, 0), s(1, 0, 1)], []),
        ])
    }

    @Test func tipsSharingAParentShareALane() {
        let rows = GraphLayout.rows(for: [c("T1", "P"), c("T2", "P"), c("P")], mainlineTip: nil)
        #expect(rows == [
            row(0, 1, [], [s(0, 0, 1)]),
            row(1, 2, [s(0, 0, 1)], [s(0, 0, 1), s(1, 0, 2)]),
            row(0, 1, [s(0, 0, 1)], []),
        ])
    }

    @Test func freedColumnsAreReused() {
        let rows = GraphLayout.rows(for: [c("S1", "A"), c("M", "A"), c("A", "B"), c("S2", "B"), c("B")], mainlineTip: "M")
        #expect(rows[2].upper == [s(0, 0, 0), s(1, 0, 1)])
        #expect(rows[3].column == 1)
        #expect(rows[3].colorIndex == 2)
    }

    @Test func aParentBeyondTheListRunsOffTheBottom() {
        let rows = GraphLayout.rows(for: [c("S", "Z"), c("M")], mainlineTip: "M")
        #expect(rows == [
            row(1, 1, [], [s(1, 1, 1)]),
            row(0, 0, [s(1, 1, 1)], [s(1, 1, 1)]),
        ])
    }

    @Test(arguments: [nil, "missing"] as [String?])
    func withoutAMainlineColumnZeroIsOrdinary(tip: String?) {
        let rows = GraphLayout.rows(for: [c("T", "P"), c("P")], mainlineTip: tip)
        #expect(rows == [
            row(0, 1, [], [s(0, 0, 1)]),
            row(0, 1, [s(0, 0, 1)], []),
        ])
    }

    @Test func colorsAreHandedOutAsTipsAndLanesAppear() {
        let rows = GraphLayout.rows(for: [c("T1", "M"), c("T2", "M"), c("M", "A", "S"), c("S", "A"), c("A")], mainlineTip: "M")
        #expect(rows.map(\.colorIndex) == [1, 2, 0, 3, 0])
        #expect(rows[1].lower == [s(0, 0, 0), s(1, 0, 2)])
    }

    /// The history in the design mockup, newest first.
    @Test func mockupHistory() {
        let commits = [
            c("a1f4c2e", "2f9ae57"), c("2f9ae57", "d6d0bb6"), c("7d20b95", "d6d0bb6"), c("53d2e91", "0363da3"),
            c("d6d0bb6", "cfa7deb"), c("0363da3", "cfa7deb"), c("cfa7deb", "8a2ef0e", "1e5b1be"),
            c("1e5b1be", "9c8c58d"), c("9c8c58d", "8a2ef0e"), c("8a2ef0e", "1525650", "2223d74"),
            c("2223d74", "25b3fde"), c("25b3fde", "1525650"), c("1525650", "9e8ca99"), c("9e8ca99"),
        ]
        let rows = GraphLayout.rows(for: commits, mainlineTip: "2f9ae57")
        #expect(rows.map(\.column) == [1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 1, 0, 0])
        #expect(rows.map(\.colorIndex) == [1, 0, 2, 3, 0, 3, 0, 4, 4, 0, 5, 5, 0, 0])
        #expect(rows.map(\.isMerge) == [false, false, false, false, false, false, true, false, false, true, false, false, false, false])
        #expect(rows[5].lower == [s(0, 0, 0), s(1, 0, 3)])
    }
}
