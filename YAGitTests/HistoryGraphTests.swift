import Foundation
import GitCore
import SwiftUI
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

/// A Gregorian calendar in UTC with the given locale, so results don't depend on the test machine.
func utcCalendar(_ locale: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: locale)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    utcCalendar("en_US").date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

/// ICU puts a narrow no-break space before AM/PM; compare with a plain space.
func plainSpaces(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{202F}", with: " ")
}

@MainActor
struct CommitDateTests {
    static let now = utcDate(2026, 9, 16, 12, 0)

    @Test(arguments: [
        (utcDate(2026, 9, 16, 8, 14), "en_US", "Today at 8:14 AM"),
        (utcDate(2026, 9, 15, 17, 48), "en_US", "Yesterday at 5:48 PM"),
        (utcDate(2026, 9, 14, 11, 2), "en_US", "Sep 14 at 11:02 AM"),
        (utcDate(2025, 9, 14, 11, 2), "en_US", "Sep 14, 2025 at 11:02 AM"),
        (utcDate(2027, 1, 2, 9, 0), "en_US", "Jan 2, 2027 at 9:00 AM"),
        (utcDate(2026, 9, 15, 17, 48), "en_GB", "Yesterday at 17:48"),
    ])
    func formats(date: Date, locale: String, expected: String) {
        let text = CommitDate.string(for: date, now: Self.now, calendar: utcCalendar(locale))
        #expect(plainSpaces(text) == expected)
    }
}

@MainActor
struct GraphPaletteTests {
    @Test func mainlineIsBlue() {
        #expect(GraphPalette.color(for: 0) == .blue)
    }

    @Test(arguments: 1...6)
    func laneColorsAreNeverBlue(index: Int) {
        #expect(GraphPalette.color(for: index) != .blue)
    }

    @Test func laneColorsAreDistinctAndWrap() {
        #expect(Set((1...6).map(GraphPalette.color(for:))).count == 6)
        #expect(GraphPalette.color(for: 7) == GraphPalette.color(for: 1))
        #expect(GraphPalette.color(for: 13) == GraphPalette.color(for: 1))
    }

    @Test func columnWidthFitsEveryLane() {
        #expect(GraphColumn.width(laneCount: 1) == 18)
        #expect(GraphColumn.width(laneCount: 8) == 88)
    }
}

@MainActor
struct CommitRowTests {
    private func entry(isMerge: Bool, refs: [RefLabel]) -> HistoryEntry {
        let commit = CommitSummary(sha: "cfa7deb0000", summary: "Merge pull request #418", message: "Merge pull request #418",
                                   authorName: "Aaron Brethorst", authorEmail: "aaron@example.com",
                                   date: utcDate(2026, 9, 16, 8, 14), parentSHAs: isMerge ? ["a", "b"] : ["a"])
        return HistoryEntry(commit: commit, refs: refs,
                            graph: GraphRow(column: 0, colorIndex: 0, isMerge: isMerge, upper: [], lower: []))
    }

    @Test func accessibilityLabelNamesMergeAndEveryRef() {
        let refs = [
            RefLabel(name: "main", kind: .localBranch(isCurrent: true)),
            RefLabel(name: "origin/main", kind: .remoteBranch),
            RefLabel(name: "v2.7.1", kind: .tag),
            RefLabel(name: "v2.7.1-rc1", kind: .tag),
        ]
        let label = CommitRow.accessibilityLabel(for: entry(isMerge: true, refs: refs),
                                                 now: CommitDateTests.now, calendar: utcCalendar("en_US"))
        #expect(plainSpaces(label) ==
                "Merge pull request #418, merge commit, on main, origin/main, v2.7.1, v2.7.1-rc1, Aaron Brethorst, Today at 8:14 AM")
    }

    @Test func accessibilityLabelOmitsEmptyParts() {
        let label = CommitRow.accessibilityLabel(for: entry(isMerge: false, refs: []),
                                                 now: CommitDateTests.now, calendar: utcCalendar("en_US"))
        #expect(plainSpaces(label) == "Merge pull request #418, Aaron Brethorst, Today at 8:14 AM")
    }
}
