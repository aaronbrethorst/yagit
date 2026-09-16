# History Graph Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show every branch's history in the History list with a lane graph, ref badges, and calendar-style dates, matching the design mockup.

**Architecture:** `GitCore` walks all branches and tags and runs a pure `GraphLayout` that turns the commit list into one `GraphRow` per commit (dot column, color, and the line pieces in the row's upper and lower halves). The app's `CommitRow` draws its row's slice with a `Canvas` inside the native `List`, so selection, keyboard navigation, and pane focus keep working.

**Tech Stack:** Swift 6, SwiftUI (macOS 27), libgit2 1.9.2 via the local `GitCore` package, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-16-history-graph-design.md`

## Global Constraints

- Every `swift`/`xcodebuild` command needs `export DEVELOPER_DIR=/Applications/Xcode-27.0.0.app/Contents/Developer` first.
- GitCore tests: `cd GitCore && swift test --filter <Suite>`. App tests: `xcodebuild -project YAGit.xcodeproj -scheme YAGit -derivedDataPath "$TMPDIR/yagit-derived-data" -only-testing:YAGitTests/<Suite> test 2>&1 | tail -40`. Always pass `-derivedDataPath`: the user may be running YAGit from Xcode, and sharing DerivedData breaks code signing.
- The Xcode project uses synchronized folders: new `.swift` files under `YAGit/` or `YAGitTests/` are picked up automatically. Don't edit `project.pbxproj`.
- The working tree had uncommitted user edits to `YAGit/Views/ChangesList.swift` and `YAGitTests/PaneFocusTests.swift` when this plan was written. Before Task 1, run `git status`. If they're still there, ask the user whether to commit them first. Always commit with explicit paths (`git commit -- <paths>`), never `git add -A`.
- Commit messages follow the repo style: present tense, third person ("Adds …", "Keeps …").
- History limit: `GitRepository.historyLimit = 2000`.
- Rows are 34pt tall; lanes 10pt apart; lane x center `9 + 10c`; graph width `8 + 10 × laneCount`; lane cap 8; dots 8pt; strokes 1.5pt.
- Palette: `[.blue, .purple, .teal, .orange, .green, .pink, .brown]`, index 0 (blue) only for the mainline.
- Copy: header "All branches · N" (or "All branches · N+" when truncated); empty-state description "Commits on any branch will appear here."; dates "Today at <time>", "Yesterday at <time>", "<Mon d> at <time>", "<Mon d, yyyy> at <time>"; accessibility "merge commit", "on <refs>".
- The app target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (Swift 5 language mode); the test target does not. Mark every new test suite that touches app types `@MainActor`.
- The offscreen-render harness can't drive clicks. Selection and focus are set through the store (`selectCommit`, `requestFocus`, `focusedPane`).

---

## File Map

GitCore:
- Modify `GitCore/Sources/GitCore/Models.swift`: `CommitSummary.parentSHAs`, `GraphSegment`, `GraphRow`, `RefLabel`, `HistoryEntry`.
- Create `GitCore/Sources/GitCore/GraphLayout.swift`: pure lane layout.
- Create `GitCore/Sources/GitCore/GitRepository+History.swift`: all-branches `history()`, ref labels, mainline tip. The old `history()` is removed from `GitRepository+Commit.swift`.
- Modify `GitCore/Sources/GitCore/GitRepository+Commit.swift`: `CommitSummary.init(commit:)` fills `parentSHAs`; remove `history()`.
- Modify `GitCore/Sources/GitCore/GitRepository+Snapshot.swift`: `forEachBranch`, `remoteBranches(current:)` become internal.
- Tests: create `GraphLayoutTests.swift`, `HistoryTests.swift`, `HistoryTimingTests.swift`; modify `CommitTests.swift`, `BranchTests.swift`, `TestRepository.swift`.

App:
- Modify `YAGit/RepositoryStore.swift`: `history: [HistoryEntry]`, `graphLaneCount`, `isHistoryTruncated`, selection across reloads, fetch reloads history.
- Create `YAGit/CommitDate.swift`.
- Create `YAGit/Views/GraphPalette.swift` and `YAGit/Views/GraphColumn.swift`.
- Create `YAGit/Views/RefBadge.swift` (includes `CappedWidth`) and `YAGit/Views/CommitRow.swift`.
- Modify `YAGit/Views/HistoryList.swift` and `YAGit/Views/CommitDetailPane.swift`.
- Tests: create `YAGitTests/HistoryGraphTests.swift` (unit) and `YAGitTests/HistoryGraphRenderTests.swift`; modify `YAGitTests/YAGitTests.swift`, `YAGitTests/PaneFocusTests.swift`, `YAGitTests/TestRepository.swift`.

---

### Task 1: Parent SHAs on `CommitSummary`

**Files:**
- Modify: `GitCore/Sources/GitCore/Models.swift` (`CommitSummary`)
- Modify: `GitCore/Sources/GitCore/GitRepository+Commit.swift` (`extension CommitSummary { init(commit:) }`)
- Test: `GitCore/Tests/GitCoreTests/CommitTests.swift`

**Interfaces:**
- Produces: `CommitSummary.parentSHAs: [String]` (libgit2 order, first parent first) and
  `CommitSummary.init(sha:summary:message:authorName:authorEmail:date:parentSHAs: [String] = [])`.

- [ ] **Step 1: Write the failing test.** Add it to `CommitTests` after `commitDetailListsFilesWithCounts`:

```swift
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
```

- [ ] **Step 2: Run it and confirm it fails to compile.**

Run: `cd GitCore && swift test --filter CommitTests`
Expected: compile error `value of type 'CommitSummary' has no member 'parentSHAs'`.

- [ ] **Step 3: Implement.** In `Models.swift`, replace the `CommitSummary` stored properties and init with:

```swift
public struct CommitSummary: Sendable, Hashable, Identifiable {
    public let sha: String
    public let summary: String
    public let message: String
    public let authorName: String
    public let authorEmail: String
    public let date: Date
    /// Parent commits in libgit2 order: the first parent first, empty for a root commit.
    public let parentSHAs: [String]

    public init(sha: String, summary: String, message: String, authorName: String, authorEmail: String, date: Date,
                parentSHAs: [String] = []) {
        self.sha = sha
        self.summary = summary
        self.message = message
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.date = date
        self.parentSHAs = parentSHAs
    }
```

(Keep `id` and `shortSHA` as they are.) In `GitRepository+Commit.swift`, replace `CommitSummary.init(commit:)` with:

```swift
extension CommitSummary {
    init(commit: OpaquePointer) {
        let author = git_commit_author(commit)!.pointee
        self.init(
            sha: String(oid: git_commit_id(commit)!.pointee),
            summary: String(cString: git_commit_summary(commit)),
            message: String(cString: git_commit_message(commit)),
            authorName: String(cString: author.name),
            authorEmail: String(cString: author.email),
            date: Date(timeIntervalSince1970: TimeInterval(git_commit_time(commit))),
            parentSHAs: (0..<git_commit_parentcount(commit)).map { String(oid: git_commit_parent_id(commit, $0)!.pointee) })
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass.**

Run: `cd GitCore && swift test`
Expected: all GitCore tests pass (`commitDetailListsFilesWithCounts` still passes, because both sides fill `parentSHAs`).

- [ ] **Step 5: Commit.**

```bash
git commit -m "Adds parent SHAs to commit summaries" -- GitCore/Sources/GitCore/Models.swift GitCore/Sources/GitCore/GitRepository+Commit.swift GitCore/Tests/GitCoreTests/CommitTests.swift
```

---

### Task 2: `GraphLayout`

**Files:**
- Modify: `GitCore/Sources/GitCore/Models.swift` (append `GraphSegment`, `GraphRow`)
- Create: `GitCore/Sources/GitCore/GraphLayout.swift`
- Test: `GitCore/Tests/GitCoreTests/GraphLayoutTests.swift`

**Interfaces:**
- Consumes: `CommitSummary.parentSHAs` (Task 1).
- Produces:
  - `public struct GraphSegment: Sendable, Hashable { fromColumn: Int, toColumn: Int, colorIndex: Int }` with memberwise public init.
  - `public struct GraphRow: Sendable, Hashable { column: Int, colorIndex: Int, isMerge: Bool, upper: [GraphSegment], lower: [GraphSegment] }` with memberwise public init.
  - `public enum GraphLayout { public static func rows(for commits: [CommitSummary], mainlineTip: String?) -> [GraphRow] }`.

- [ ] **Step 1: Write the failing tests.** Create `GitCore/Tests/GitCoreTests/GraphLayoutTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests and confirm they fail to compile.**

Run: `cd GitCore && swift test --filter GraphLayoutTests`
Expected: compile errors `cannot find 'GraphLayout' in scope` / `cannot find type 'GraphSegment'`.

- [ ] **Step 3: Add the models.** Append to `Models.swift` after `CommitDetail`:

```swift
/// A piece of lane line within half a row: from a column at one edge of the half to a column at the
/// other. Equal columns draw a straight line; different columns draw a curve.
public struct GraphSegment: Sendable, Hashable {
    public let fromColumn: Int
    public let toColumn: Int
    public let colorIndex: Int

    public init(fromColumn: Int, toColumn: Int, colorIndex: Int) {
        self.fromColumn = fromColumn
        self.toColumn = toColumn
        self.colorIndex = colorIndex
    }
}

/// One commit's slice of the lane graph. `upper` runs from the row's top edge to the dot's center,
/// `lower` from the dot's center to the bottom edge.
public struct GraphRow: Sendable, Hashable {
    public let column: Int
    public let colorIndex: Int
    public let isMerge: Bool
    public let upper: [GraphSegment]
    public let lower: [GraphSegment]

    public init(column: Int, colorIndex: Int, isMerge: Bool, upper: [GraphSegment], lower: [GraphSegment]) {
        self.column = column
        self.colorIndex = colorIndex
        self.isMerge = isMerge
        self.upper = upper
        self.lower = lower
    }
}
```

- [ ] **Step 4: Implement the layout.** Create `GitCore/Sources/GitCore/GraphLayout.swift`:

```swift
import Foundation

/// Lays commits out in lanes, one `GraphRow` per commit in list order, so each row can draw its own slice.
///
/// The mainline, the first-parent chain from `mainlineTip`, always sits in column 0. Every other
/// lane is an edge travelling down a column toward the parent it is waiting for; lanes waiting for
/// the same parent meet at that parent's dot. Color 0 is reserved for the mainline; other lanes get
/// 1, 2, 3, … in the order they appear.
public enum GraphLayout {
    private struct Lane {
        let target: String
        let colorIndex: Int
    }

    public static func rows(for commits: [CommitSummary], mainlineTip: String?) -> [GraphRow] {
        let bySHA = Dictionary(commits.map { ($0.sha, $0) }, uniquingKeysWith: { first, _ in first })
        var mainline = Set<String>()
        var cursor = mainlineTip
        while let sha = cursor, let commit = bySHA[sha], mainline.insert(sha).inserted {
            cursor = commit.parentSHAs.first
        }
        let hasMainline = !mainline.isEmpty
        // Column 0 belongs to the mainline whenever there is one.
        let firstFree = hasMainline ? 1 : 0

        var slots: [Lane?] = []
        var nextColor = 1

        func takeColor() -> Int {
            defer { nextColor += 1 }
            return nextColor
        }

        func freeColumn() -> Int {
            if let index = slots.indices.first(where: { $0 >= firstFree && slots[$0] == nil }) { return index }
            while slots.count < firstFree { slots.append(nil) }
            slots.append(nil)
            return slots.count - 1
        }

        var rows: [GraphRow] = []
        rows.reserveCapacity(commits.count)
        for commit in commits {
            let isMainline = mainline.contains(commit.sha)

            // Column and color.
            let column: Int
            let color: Int
            if isMainline {
                if slots.isEmpty { slots.append(nil) }
                column = 0
                color = 0
            } else if let index = slots.firstIndex(where: { $0?.target == commit.sha }) {
                column = index
                color = slots[index]!.colorIndex
            } else {
                column = freeColumn()
                color = takeColor()
            }

            // Upper half: lanes waiting for this commit end at its dot; the rest pass straight through.
            var upper: [GraphSegment] = []
            for (index, lane) in slots.enumerated() {
                guard let lane else { continue }
                if lane.target == commit.sha {
                    upper.append(GraphSegment(fromColumn: index, toColumn: column, colorIndex: lane.colorIndex))
                    slots[index] = nil
                } else {
                    upper.append(GraphSegment(fromColumn: index, toColumn: index, colorIndex: lane.colorIndex))
                }
            }

            // Lower half: open lanes pass straight through, then one edge per parent.
            var lower = slots.enumerated().compactMap { index, lane in
                lane.map { GraphSegment(fromColumn: index, toColumn: index, colorIndex: $0.colorIndex) }
            }
            for (i, parent) in commit.parentSHAs.enumerated() {
                if isMainline && i == 0 {
                    slots[0] = Lane(target: parent, colorIndex: 0)
                    lower.append(GraphSegment(fromColumn: 0, toColumn: 0, colorIndex: 0))
                } else if hasMainline, parent == mainlineTip, slots[0] == nil {
                    // The first edge to reach the mainline starts its lane.
                    slots[0] = Lane(target: parent, colorIndex: 0)
                    lower.append(GraphSegment(fromColumn: column, toColumn: 0, colorIndex: i == 0 ? color : 0))
                } else if let index = slots.firstIndex(where: { $0?.target == parent }) {
                    // A branch's own line keeps its color until it joins; a merge's extra parent takes the lane's.
                    lower.append(GraphSegment(fromColumn: column, toColumn: index,
                                              colorIndex: i == 0 ? color : slots[index]!.colorIndex))
                } else if i == 0 {
                    slots[column] = Lane(target: parent, colorIndex: color)
                    lower.append(GraphSegment(fromColumn: column, toColumn: column, colorIndex: color))
                } else {
                    let index = freeColumn()
                    let laneColor = takeColor()
                    slots[index] = Lane(target: parent, colorIndex: laneColor)
                    lower.append(GraphSegment(fromColumn: column, toColumn: index, colorIndex: laneColor))
                }
            }

            while slots.last.map({ $0 == nil }) == true { slots.removeLast() }
            rows.append(GraphRow(column: column, colorIndex: color, isMerge: commit.parentSHAs.count > 1,
                                 upper: upper, lower: lower))
        }
        return rows
    }
}
```

- [ ] **Step 5: Run the tests and confirm they pass.**

Run: `cd GitCore && swift test --filter GraphLayoutTests`
Expected: all 14 tests pass (15 test cases, counting both arguments of the parameterized test). If one fails, trace the rule order in spec §2 by hand for that input. Fix the implementation, not the expectation, unless the trace shows the expectation contradicts the spec.

- [ ] **Step 6: Commit.**

```bash
git add GitCore/Sources/GitCore/GraphLayout.swift GitCore/Tests/GitCoreTests/GraphLayoutTests.swift
git commit -m "Adds the commit graph lane layout" -- GitCore/Sources/GitCore/Models.swift GitCore/Sources/GitCore/GraphLayout.swift GitCore/Tests/GitCoreTests/GraphLayoutTests.swift
```

---

### Task 3: All-branches `history()` with ref labels

**Files:**
- Modify: `GitCore/Sources/GitCore/Models.swift` (append `RefLabel`, `HistoryEntry`)
- Create: `GitCore/Sources/GitCore/GitRepository+History.swift`
- Modify: `GitCore/Sources/GitCore/GitRepository+Commit.swift` (delete `history(limit:)`)
- Modify: `GitCore/Sources/GitCore/GitRepository+Snapshot.swift:50,58` (drop `private` on `remoteBranches(current:)` and `forEachBranch`)
- Modify: `GitCore/Tests/GitCoreTests/TestRepository.swift`, `CommitTests.swift`, `BranchTests.swift`
- Create: `GitCore/Tests/GitCoreTests/HistoryTests.swift`
- Modify (to keep the app compiling): `YAGit/RepositoryStore.swift`, `YAGit/Views/HistoryList.swift`, `YAGitTests/YAGitTests.swift`, `YAGitTests/PaneFocusTests.swift`

**Interfaces:**
- Consumes: `GraphLayout.rows(for:mainlineTip:)`, `GraphRow` (Task 2).
- Produces:
  - `public struct RefLabel: Sendable, Hashable { name: String; kind: Kind }` with `public enum Kind: Sendable, Hashable { case head, localBranch(isCurrent: Bool), remoteBranch, tag }` and `public init(name:kind:)`.
  - `public struct HistoryEntry: Sendable, Hashable, Identifiable { commit: CommitSummary; refs: [RefLabel]; graph: GraphRow; id: String /* commit.sha */ }` with `public init(commit:refs:graph:)`.
  - `GitRepository.historyLimit: Int` (static, 2000) and `func history(limit: Int = GitRepository.historyLimit) throws -> [HistoryEntry]`.
  - `RepositoryStore.history: [HistoryEntry]`.
  - GitCore `TestRepository.commitAll(_:date:)` and `git(date:_:)`.

- [ ] **Step 1: Add the dated-commit fixture helpers.** In `GitCore/Tests/GitCoreTests/TestRepository.swift`, add after `commitAll(_:)`:

```swift
    /// Commits with author and committer dates pinned, so walk order doesn't depend on timing.
    func commitAll(_ message: String, date: Date) throws {
        try git("add", "-A")
        try git(date: date, "commit", "-q", "-m", message)
    }
```

Add after `git(_:)`:

```swift
    /// Runs git with author and committer dates pinned (for commits and merges in order-sensitive tests).
    @discardableResult
    func git(date: Date, _ arguments: String...) throws -> String {
        let stamp = "\(Int(date.timeIntervalSince1970)) +0000"
        return try run("/usr/bin/git", arguments, in: url,
                       extraEnvironment: ["GIT_AUTHOR_DATE": stamp, "GIT_COMMITTER_DATE": stamp])
    }
```

Change `run`'s signature and environment setup to:

```swift
    private func run(_ executable: String, _ arguments: [String], in directory: URL,
                     extraEnvironment: [String: String] = [:]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        environment["HOME"] = directory.deletingLastPathComponent().path
        environment.merge(extraEnvironment) { _, new in new }
        process.environment = environment
```

(the rest of `run` is unchanged).

- [ ] **Step 2: Write the failing tests.** Create `GitCore/Tests/GitCoreTests/HistoryTests.swift`:

```swift
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
```

- [ ] **Step 3: Update the existing GitCore tests for all-branches history.**

In `BranchTests.swift`:
- `createBranchStartsAtHeadAndChecksItOut`: `repo.history().map(\.summary)` → `repo.history().map(\.commit.summary)`.
- Replace `commitsOnANewBranchDoNotAppearOnTheParent` entirely with:

```swift
    @Test func commitsOnANewBranchStayInHistoryAfterSwitchingBack() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "1\n")
        try fixture.commitAll("First")

        let repo = try GitRepository(url: fixture.url)
        try await repo.createBranch(named: "feature")
        try fixture.write("a.txt", "2\n")
        try await repo.stage(path: "a.txt")
        try await repo.commit(message: "On feature")
        #expect(try await repo.history().map(\.commit.summary) == ["On feature", "First"])

        try await repo.switchBranch(named: "main")
        let history = try await repo.history()
        #expect(history.map(\.commit.summary) == ["On feature", "First"])
        #expect(history[0].refs == [RefLabel(name: "feature", kind: .localBranch(isCurrent: false))])
        #expect(history[1].refs == [RefLabel(name: "main", kind: .localBranch(isCurrent: true))])
        #expect(try fixture.read("a.txt") == "1\n")
    }
```

In `CommitTests.swift`:
- Rename `historyIsNewestFirstAndPerBranch` to `historyIsNewestFirstAcrossBranches`, and replace its two expectations with:

```swift
        #expect(try await repo.history().map(\.commit.summary) == ["Third on feature", "Second", "First"])
        try await repo.switchBranch(named: "main")
        #expect(try await repo.history().map(\.commit.summary) == ["Third on feature", "Second", "First"])
```

- `commitDetailListsFilesWithCounts`: `let head = try #require(try await repo.history().first)` → `let head = try #require(try await repo.history().first).commit`, and `let root = try #require(try await repo.history().last)` → `let root = try #require(try await repo.history().last).commit`.

- [ ] **Step 4: Run the tests and confirm they fail to compile.**

Run: `cd GitCore && swift test --filter HistoryTests`
Expected: compile errors about `RefLabel` and `commit` on `CommitSummary`.

- [ ] **Step 5: Add the models.** Append to `Models.swift`:

```swift
/// A ref shown as a badge on the commit it points to.
public struct RefLabel: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// HEAD, only when detached.
        case head
        case localBranch(isCurrent: Bool)
        case remoteBranch
        case tag
    }

    /// Short name: `main`, `origin/main`, `v2.8.1`, `HEAD`.
    public let name: String
    public let kind: Kind

    public init(name: String, kind: Kind) {
        self.name = name
        self.kind = kind
    }

    /// Badge order within one commit: detached HEAD, current branch, other local branches, remotes, tags.
    static func displayOrder(_ lhs: RefLabel, _ rhs: RefLabel) -> Bool {
        lhs.rank != rhs.rank ? lhs.rank < rhs.rank : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private var rank: Int {
        switch kind {
        case .head: 0
        case .localBranch(isCurrent: true): 1
        case .localBranch: 2
        case .remoteBranch: 3
        case .tag: 4
        }
    }
}

/// One row of the History list.
public struct HistoryEntry: Sendable, Hashable, Identifiable {
    public let commit: CommitSummary
    public let refs: [RefLabel]
    public let graph: GraphRow

    public init(commit: CommitSummary, refs: [RefLabel], graph: GraphRow) {
        self.commit = commit
        self.refs = refs
        self.graph = graph
    }

    public var id: String { commit.sha }
}
```

- [ ] **Step 6: Implement the walk.** Delete `history(limit:)` (and its doc comment) from `GitRepository+Commit.swift`. In `GitRepository+Snapshot.swift`, change `private func remoteBranches(current:` → `func remoteBranches(current:` and `private func forEachBranch(` → `func forEachBranch(`. Create `GitCore/Sources/GitCore/GitRepository+History.swift`:

```swift
import Foundation
import libgit2

extension GitRepository {
    public static let historyLimit = 2000

    /// Commits reachable from HEAD, every local branch, the sidebar's remote branches, and every tag,
    /// newest first, each with its ref badges and its slice of the lane graph.
    ///
    /// Any sorted walk visits every reachable commit before returning the first one; `limit` only
    /// bounds how many summaries are built.
    public func history(limit: Int = GitRepository.historyLimit) throws -> [HistoryEntry] {
        let refs = try historyRefs()

        var walker: OpaquePointer?
        try check(git_revwalk_new(&walker, repo), "log")
        defer { git_revwalk_free(walker) }
        git_revwalk_sorting(walker, GIT_SORT_TOPOLOGICAL.rawValue | GIT_SORT_TIME.rawValue)
        if git_repository_head_unborn(repo) == 0 {
            try check(git_revwalk_push_head(walker), "log")
        }
        for sha in refs.tips {
            var oid = git_oid()
            try check(git_oid_fromstr(&oid, sha), "log")
            try check(git_revwalk_push(walker, &oid), "log")
        }
        // Peels annotated tags and skips tags of trees or blobs.
        try check(git_revwalk_push_glob(walker, "refs/tags"), "log")

        var commits: [CommitSummary] = []
        var oid = git_oid()
        while commits.count < limit, git_revwalk_next(&oid, walker) == 0 {
            commits.append(try commitSummary(oid: oid))
        }
        let rows = GraphLayout.rows(for: commits, mainlineTip: mainlineTip())
        return zip(commits, rows).map { commit, row in
            HistoryEntry(commit: commit, refs: refs.labels[commit.sha] ?? [], graph: row)
        }
    }

    /// Branch tips to start the walk from, and every ref's badge keyed by the commit it points to.
    private func historyRefs() throws -> (tips: Set<String>, labels: [String: [RefLabel]]) {
        let current = try currentBranchName()
        let detached = git_repository_head_detached(repo) == 1
        var tips = Set<String>()
        var labels: [String: [RefLabel]] = [:]

        if detached, let head = try headCommit() {
            defer { git_commit_free(head) }
            labels[String(oid: git_commit_id(head)!.pointee), default: []].append(RefLabel(name: "HEAD", kind: .head))
        }

        try forEachBranch(type: GIT_BRANCH_LOCAL) { reference, name in
            guard let sha = try peeledCommitSHA(reference) else { return }
            tips.insert(sha)
            labels[sha, default: []].append(RefLabel(name: name, kind: .localBranch(isCurrent: !detached && name == current)))
        }

        for name in try remoteBranches(current: current) {
            var reference: OpaquePointer?
            guard git_reference_lookup(&reference, repo, "refs/remotes/\(name)") == 0 else { continue }
            defer { git_reference_free(reference) }
            guard let sha = try peeledCommitSHA(reference!) else { continue }
            tips.insert(sha)
            labels[sha, default: []].append(RefLabel(name: name, kind: .remoteBranch))
        }

        var iterator: OpaquePointer?
        try check(git_reference_iterator_glob_new(&iterator, repo, "refs/tags/*"), "log")
        defer { git_reference_iterator_free(iterator) }
        while true {
            var reference: OpaquePointer?
            let status = git_reference_next(&reference, iterator)
            if status == GIT_ITEROVER.rawValue { break }
            try check(status, "log")
            defer { git_reference_free(reference) }
            guard let sha = try peeledCommitSHA(reference!) else { continue }
            labels[sha, default: []].append(RefLabel(name: String(cString: git_reference_shorthand(reference)), kind: .tag))
        }

        return (tips, labels.mapValues { $0.sorted(by: RefLabel.displayOrder) })
    }

    /// The trunk drawn in column 0: `main`, else `master`, else `origin/main`, else HEAD.
    private func mainlineTip() -> String? {
        for name in ["refs/heads/main", "refs/heads/master", "refs/remotes/origin/main", "HEAD"] {
            var reference: OpaquePointer?
            guard git_reference_lookup(&reference, repo, name) == 0 else { continue }
            defer { git_reference_free(reference) }
            if let sha = try? peeledCommitSHA(reference!) { return sha }
        }
        return nil
    }

    /// The commit a reference ultimately points to, or `nil` when it doesn't lead to a commit
    /// (a tag of a tree or blob, or an unborn HEAD). Other failures throw.
    private func peeledCommitSHA(_ reference: OpaquePointer) throws -> String? {
        var object: OpaquePointer?
        let status = git_reference_peel(&object, reference, GIT_OBJECT_COMMIT)
        if [GIT_EPEEL.rawValue, GIT_EINVALIDSPEC.rawValue, GIT_ENOTFOUND.rawValue].contains(status) { return nil }
        try check(status, "log")
        defer { git_object_free(object) }
        return String(oid: git_object_id(object)!.pointee)
    }
}
```

- [ ] **Step 7: Run all GitCore tests and confirm they pass.**

Run: `cd GitCore && swift test`
Expected: every suite passes, including `HistoryTests` (13 test cases), `GraphLayoutTests`, and the rewritten branch and commit tests.

- [ ] **Step 8: Keep the app compiling.** In `YAGit/RepositoryStore.swift`:
- `var history: [CommitSummary] = []` → `var history: [HistoryEntry] = []`
- `var selectedCommit: CommitSummary? { history.first { $0.sha == selectedCommitSHA } }` →
  `var selectedCommit: CommitSummary? { history.first { $0.commit.sha == selectedCommitSHA }?.commit }`

In `YAGit/Views/HistoryList.swift`, replace the `ForEach` with:

```swift
                ForEach(store.history) { entry in
                    CommitRow(commit: entry.commit)
                        .tag(entry.commit.sha)
                }
```

In the app tests, update the accessors (the files may contain the user's own edits, so change only these expressions):

```bash
sed -i '' -e 's/history\[0\]\.sha/history[0].commit.sha/g' \
          -e 's/history\.map(\\\.summary)/history.map(\\.commit.summary)/g' \
          -e 's/history\.first?\.summary/history.first?.commit.summary/g' \
          YAGitTests/YAGitTests.swift YAGitTests/PaneFocusTests.swift
grep -n "history" YAGitTests/YAGitTests.swift YAGitTests/PaneFocusTests.swift
```

Expected grep: every `history` access goes through `.commit`.

- [ ] **Step 9: Build the app and run the store tests.**

Run: `xcodebuild -project YAGit.xcodeproj -scheme YAGit -derivedDataPath "$TMPDIR/yagit-derived-data" -only-testing:YAGitTests/RepositoryStoreTests -only-testing:YAGitTests/PaneFocusTests test 2>&1 | tail -40`
Expected: `** TEST SUCCEEDED **`. In the `makeFixture` repositories every branch points at the same linear commits, so the existing list expectations still hold.

- [ ] **Step 10: Commit.**

```bash
git add GitCore/Sources/GitCore/GitRepository+History.swift GitCore/Tests/GitCoreTests/HistoryTests.swift
git commit -m "Walks every branch and tag for history, with ref labels and graph rows" -- \
  GitCore/Sources/GitCore/Models.swift GitCore/Sources/GitCore/GitRepository+History.swift \
  GitCore/Sources/GitCore/GitRepository+Commit.swift GitCore/Sources/GitCore/GitRepository+Snapshot.swift \
  GitCore/Tests/GitCoreTests/HistoryTests.swift GitCore/Tests/GitCoreTests/TestRepository.swift \
  GitCore/Tests/GitCoreTests/CommitTests.swift GitCore/Tests/GitCoreTests/BranchTests.swift \
  YAGit/RepositoryStore.swift YAGit/Views/HistoryList.swift YAGitTests/YAGitTests.swift YAGitTests/PaneFocusTests.swift
```

If `YAGitTests/PaneFocusTests.swift` still has the user's unrelated uncommitted edits (see Global Constraints), don't sweep them into this commit: stage only the accessor hunks with `git add -p`, or ask the user.

---

### Task 4: Store: lane count, truncation, selection across reloads, fetch reload

**Files:**
- Modify: `YAGit/RepositoryStore.swift`
- Modify: `YAGitTests/YAGitTests.swift` (`createBranchSwitchAndFetch`, new selection test)
- Create: `YAGitTests/HistoryGraphTests.swift`

**Interfaces:**
- Consumes: `HistoryEntry`, `GraphLayout`, `GitRepository.historyLimit` (Task 3).
- Produces:
  - `RepositoryStore.graphLaneCount: Int` (`private(set)`)
  - `RepositoryStore.isHistoryTruncated: Bool` (`private(set)`)
  - `RepositoryStore.maxGraphLanes = 8` (static)
  - `static func RepositoryStore.laneCount(for: [HistoryEntry]) -> Int` (MainActor-isolated like the rest of the store; test suites calling it are `@MainActor`)

- [ ] **Step 1: Write the failing tests.** Create `YAGitTests/HistoryGraphTests.swift`:

```swift
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
```

In `YAGitTests/YAGitTests.swift`, change the end of `createBranchSwitchAndFetch` from:

```swift
        store.fetch()
        #expect(store.isFetching)
        #expect(store.statusText == "Fetching origin…")
        try await settle()
        #expect(store.isFetching == false)
        #expect(store.statusText == "Fetched origin — already up to date")
```

to:

```swift
        try fixture.commitOnOrigin("Remote work")
        store.fetch()
        #expect(store.isFetching)
        #expect(store.statusText == "Fetching origin…")
        try await settle()
        #expect(store.isFetching == false)
        #expect(store.statusText == "Fetched origin — remote branches updated")
        #expect(store.history.map(\.commit.summary).contains("Remote work"))
```

Add this test to `RepositoryStoreTests`, after `createBranchSwitchAndFetch`:

```swift
    @Test func commitSelectionSurvivesABranchSwitchAndClearsWhenItsCommitDisappears() async throws {
        let fixture = try makeFixture()
        let spike = try fixture.git("commit-tree", "HEAD^{tree}", "-p", "HEAD", "-m", "Spike")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try fixture.git("branch", "spike", spike)
        let store = try RepositoryStore(url: fixture.url)
        await store.load()
        #expect(store.history.map(\.commit.summary).contains("Spike"))

        store.mode = .history
        store.selectCommit(sha: spike)
        try await settle()
        #expect(store.commitDetail?.commit.sha == spike)

        store.switchBranch(named: "main")
        try await settle()
        #expect(store.currentBranch == "main")
        #expect(store.selectedCommitSHA == spike)
        #expect(store.commitDetail?.commit.sha == spike)

        try fixture.git("branch", "-D", "spike")
        await store.load()
        #expect(!store.history.contains { $0.commit.sha == spike })
        #expect(store.selectedCommitSHA == nil)
        #expect(store.commitDetail == nil)
        #expect(store.selectedCommitFile == nil)
    }
```

- [ ] **Step 2: Run the tests and confirm they fail.**

Run: `xcodebuild -project YAGit.xcodeproj -scheme YAGit -derivedDataPath "$TMPDIR/yagit-derived-data" -only-testing:YAGitTests/GraphLaneCountTests -only-testing:YAGitTests/RepositoryStoreTests test 2>&1 | tail -40`
Expected: a compile error (`type 'RepositoryStore' has no member 'laneCount'`). Once Step 3's `laneCount` exists but before the rest is done, the selection and fetch tests fail on their expectations.

- [ ] **Step 3: Implement.** In `RepositoryStore.swift`:

Under `// History mode`, after `var history: [HistoryEntry] = []`, add:

```swift
    /// Graph width in lanes, shared by every row so their text lines up. Capped at `maxGraphLanes`.
    private(set) var graphLaneCount = 0
    /// The walk hit `GitRepository.historyLimit`, so older commits aren't listed.
    private(set) var isHistoryTruncated = false
    static let maxGraphLanes = 8
```

Replace `reloadHistory()` with:

```swift
    private func reloadHistory() async {
        do {
            history = try await repository.history()
        } catch {
            report("Couldn't read history", error)
            return
        }
        graphLaneCount = Self.laneCount(for: history)
        isHistoryTruncated = history.count == GitRepository.historyLimit
        // Keep the selected commit through reloads; drop it only when it's no longer reachable.
        if let sha = selectedCommitSHA, !history.contains(where: { $0.commit.sha == sha }) {
            selectedCommitSHA = nil
            commitDetail = nil
            selectedCommitFile = nil
        }
    }

    static func laneCount(for history: [HistoryEntry]) -> Int {
        let widest = history.map { entry in
            (entry.graph.upper + entry.graph.lower).reduce(entry.graph.column) { max($0, $1.fromColumn, $1.toColumn) }
        }.max()
        return widest.map { min(maxGraphLanes, $0 + 1) } ?? 0
    }
```

In `switchBranch(named:)`, delete these two lines:

```swift
                selectedCommitSHA = nil
                commitDetail = nil
```

Delete the same two lines in `createBranch(named:)`.

In `fetch()`, change `await refresh()` to:

```swift
                await refresh()
                await reloadHistory()
```

- [ ] **Step 4: Run the tests and confirm they pass.**

Run: `xcodebuild -project YAGit.xcodeproj -scheme YAGit -derivedDataPath "$TMPDIR/yagit-derived-data" -only-testing:YAGitTests/GraphLaneCountTests -only-testing:YAGitTests/RepositoryStoreTests -only-testing:YAGitTests/PaneFocusTests test 2>&1 | tail -40`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit.**

```bash
git add YAGitTests/HistoryGraphTests.swift
git commit -m "Keeps the selected commit across history reloads and reloads history after a fetch" -- \
  YAGit/RepositoryStore.swift YAGitTests/YAGitTests.swift YAGitTests/HistoryGraphTests.swift
```

---

### Task 5: `CommitDate`

**Files:**
- Create: `YAGit/CommitDate.swift`
- Modify: `YAGit/Views/CommitDetailPane.swift` (byline), `YAGit/Views/HistoryList.swift` (the private `CommitRow` byline)
- Test: `YAGitTests/HistoryGraphTests.swift` (append)

**Interfaces:**
- Produces: `enum CommitDate { static func string(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String }`

- [ ] **Step 1: Write the failing tests.** Append to `YAGitTests/HistoryGraphTests.swift`:

```swift
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
```

- [ ] **Step 2: Run them and confirm they fail.**

Run: `xcodebuild -project YAGit.xcodeproj -scheme YAGit -derivedDataPath "$TMPDIR/yagit-derived-data" -only-testing:YAGitTests/CommitDateTests test 2>&1 | tail -40`
Expected: compile error `cannot find 'CommitDate' in scope`.

- [ ] **Step 3: Implement.** Create `YAGit/CommitDate.swift`:

```swift
import Foundation

/// Commit timestamps relative to the calendar day: "Today at 08:14", "Yesterday at 17:48",
/// "Sep 14 at 11:02", and the year added when it differs from now's.
///
/// Every style is built from `calendar` (its locale and time zone), never the process defaults,
/// so the day boundaries and the printed time always agree.
enum CommitDate {
    static func string(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let locale = calendar.locale ?? .current
        let base = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale,
                                                   calendar: calendar, timeZone: calendar.timeZone))
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "Today at \(time)", locale: locale)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday at \(time)", locale: locale)
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let day = date.formatted(sameYear ? base.month(.abbreviated).day() : base.month(.abbreviated).day().year())
        return String(localized: "\(day) at \(time)", locale: locale)
    }
}
```

In `CommitDetailPane.swift`, replace

```swift
                    Text("\(commit.shortSHA) · \(commit.authorName) · \(commit.date, format: .relative(presentation: .named))")
```

with

```swift
                    Text("\(commit.shortSHA) · \(commit.authorName) · \(CommitDate.string(for: commit.date))")
```

In `HistoryList.swift`'s private `CommitRow`, replace

```swift
                Text("\(commit.authorName) · \(commit.date, format: .relative(presentation: .named))")
```

with

```swift
                Text("\(commit.authorName) · \(CommitDate.string(for: commit.date))")
```

- [ ] **Step 4: Run the tests and confirm they pass.**

Run the Step 2 command.
Expected: `** TEST SUCCEEDED **`. If a case differs only in ICU's rendering (the abbreviation or spacing), print the actual string, confirm the right branch (today, yesterday, same year, other year) ran, and fix the expectation. If the wrong branch ran, fix `CommitDate`.

- [ ] **Step 5: Commit.**

```bash
git add YAGit/CommitDate.swift
git commit -m "Shows commit dates relative to the calendar day" -- YAGit/CommitDate.swift YAGit/Views/CommitDetailPane.swift YAGit/Views/HistoryList.swift YAGitTests/HistoryGraphTests.swift
```

---

### Task 6: `GraphPalette` and `GraphColumn`

**Files:**
- Create: `YAGit/Views/GraphPalette.swift`
- Create: `YAGit/Views/GraphColumn.swift`
- Test: `YAGitTests/HistoryGraphTests.swift` (append)

**Interfaces:**
- Consumes: `GraphRow`, `GraphSegment` (Task 2).
- Produces:
  - `enum GraphPalette { static let colors: [Color]; static func color(for index: Int) -> Color }`
  - `struct GraphColumn: View { init(row: GraphRow, laneCount: Int); static func width(laneCount: Int) -> CGFloat }`

- [ ] **Step 1: Write the failing tests.** Append to `YAGitTests/HistoryGraphTests.swift` (add `import SwiftUI` at the top of the file):

```swift
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
```

- [ ] **Step 2: Run them and confirm they fail.**

Run: `xcodebuild -project YAGit.xcodeproj -scheme YAGit -derivedDataPath "$TMPDIR/yagit-derived-data" -only-testing:YAGitTests/GraphPaletteTests test 2>&1 | tail -40`
Expected: compile error `cannot find 'GraphPalette' in scope`.

- [ ] **Step 3: Implement.** Create `YAGit/Views/GraphPalette.swift`:

```swift
import SwiftUI

/// Lane colors. Blue is the mainline only; other lanes rotate through the rest.
enum GraphPalette {
    static let colors: [Color] = [.blue, .purple, .teal, .orange, .green, .pink, .brown]

    static func color(for index: Int) -> Color {
        index == 0 ? colors[0] : colors[1 + (index - 1) % (colors.count - 1)]
    }
}
```

Create `YAGit/Views/GraphColumn.swift`:

```swift
import GitCore
import SwiftUI

/// Draws one row's slice of the lane graph. Rows sit edge to edge, so each row's segments meet the
/// next row's at the shared boundary.
struct GraphColumn: View {
    let row: GraphRow
    let laneCount: Int
    @Environment(\.backgroundProminence) private var prominence

    static let laneSpacing: CGFloat = 10

    static func width(laneCount: Int) -> CGFloat { 8 + laneSpacing * CGFloat(laneCount) }

    var body: some View {
        let selected = prominence == .increased
        let row = row
        let laneCount = laneCount
        Canvas { context, size in
            func x(_ column: Int) -> CGFloat { 9 + Self.laneSpacing * CGFloat(column) }
            let midY = size.height / 2

            func draw(_ segment: GraphSegment, from top: CGFloat, to bottom: CGFloat) {
                // Lanes past the cap are skipped rather than widening the column.
                guard segment.fromColumn < laneCount, segment.toColumn < laneCount else { return }
                let start = CGPoint(x: x(segment.fromColumn), y: top)
                let end = CGPoint(x: x(segment.toColumn), y: bottom)
                var path = Path()
                path.move(to: start)
                if start.x == end.x {
                    path.addLine(to: end)
                } else {
                    // Vertical tangents at both ends make an S-curve that meets straight lanes cleanly.
                    let middle = (top + bottom) / 2
                    path.addCurve(to: end, control1: CGPoint(x: start.x, y: middle), control2: CGPoint(x: end.x, y: middle))
                }
                let color = selected ? Color.white.opacity(0.7) : GraphPalette.color(for: segment.colorIndex)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }

            for segment in row.upper { draw(segment, from: 0, to: midY) }
            for segment in row.lower { draw(segment, from: midY, to: size.height) }

            guard row.column < laneCount else { return }
            let center = CGPoint(x: x(row.column), y: midY)
            let dotColor = selected ? Color.white : GraphPalette.color(for: row.colorIndex)
            let dot = Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
            if row.isMerge {
                // Punch through the lines so whatever is behind the row (plain, accent, or gray
                // selection) shows inside the ring.
                context.blendMode = .clear
                context.fill(dot, with: .color(.black))
                context.blendMode = .normal
                let ring = Path(ellipseIn: CGRect(x: center.x - 3.25, y: center.y - 3.25, width: 6.5, height: 6.5))
                context.stroke(ring, with: .color(dotColor), lineWidth: 1.5)
            } else {
                context.fill(dot, with: .color(dotColor))
            }
        }
        .frame(width: Self.width(laneCount: laneCount))
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass.**

Run the Step 2 command.
Expected: `** TEST SUCCEEDED **`. (Drawing is verified by the render test in Task 8.)

- [ ] **Step 5: Commit.**

```bash
git add YAGit/Views/GraphPalette.swift YAGit/Views/GraphColumn.swift
git commit -m "Adds the lane palette and per-row graph drawing" -- YAGit/Views/GraphPalette.swift YAGit/Views/GraphColumn.swift YAGitTests/HistoryGraphTests.swift
```

---

### Task 7: `RefBadge`, `CommitRow`, and the History list

**Files:**
- Create: `YAGit/Views/RefBadge.swift`
- Create: `YAGit/Views/CommitRow.swift`
- Modify: `YAGit/Views/HistoryList.swift` (delete the private `CommitRow`; new rows, header, empty state)
- Test: `YAGitTests/HistoryGraphTests.swift` (append)

**Interfaces:**
- Consumes: `HistoryEntry`, `RefLabel` (Task 3); `RepositoryStore.graphLaneCount`, `isHistoryTruncated` (Task 4); `CommitDate` (Task 5); `GraphColumn`, `GraphPalette` (Task 6).
- Produces:
  - `struct RefBadge: View { enum Style { filled, outlined, remote, tag }; init(text:style:laneColor:); init(label: RefLabel, laneColor: Color) }`
  - `struct CappedWidth: Layout { init(maxWidth: CGFloat) }`
  - `struct CommitRow: View { init(entry: HistoryEntry, laneCount: Int); static func accessibilityLabel(for: HistoryEntry, now: Date = .now, calendar: Calendar = .current) -> String }`

- [ ] **Step 1: Write the failing tests.** Append to `YAGitTests/HistoryGraphTests.swift`:

```swift
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
```

- [ ] **Step 2: Run them and confirm they fail.**

Run: `xcodebuild -project YAGit.xcodeproj -scheme YAGit -derivedDataPath "$TMPDIR/yagit-derived-data" -only-testing:YAGitTests/CommitRowTests test 2>&1 | tail -40`
Expected: compile error. `CommitRow` is still `private` in `HistoryList.swift` and has no `accessibilityLabel(for:)`.

- [ ] **Step 3: Implement the badge.** Create `YAGit/Views/RefBadge.swift`:

```swift
import GitCore
import SwiftUI

/// A branch, remote, or tag name drawn as a small rounded badge before a commit's summary.
struct RefBadge: View {
    enum Style {
        /// Detached HEAD or the current branch.
        case filled
        /// Another local branch.
        case outlined
        /// A remote branch, or the "+N" overflow badge.
        case remote
        case tag
    }

    let text: String
    let style: Style
    /// The commit's lane color, so a branch badge matches the line leaving its tip.
    let laneColor: Color
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        let selected = prominence == .increased
        let shape = RoundedRectangle(cornerRadius: 4)
        CappedWidth(maxWidth: 130) {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 5)
        .frame(height: 16)
        .foregroundStyle(foreground(selected: selected))
        .background(fill(selected: selected), in: shape)
        .overlay {
            if let stroke = stroke(selected: selected) {
                shape.strokeBorder(stroke, lineWidth: 1)
            }
        }
    }

    private func foreground(selected: Bool) -> AnyShapeStyle {
        switch (style, selected) {
        case (.filled, false): AnyShapeStyle(Color.white)
        case (.filled, true): AnyShapeStyle(laneColor)
        // Mixing toward the primary color keeps light-appearance contrast readable for orange, teal and pink.
        case (.outlined, false): AnyShapeStyle(laneColor.mix(with: .primary, by: 0.35))
        case (.tag, false): AnyShapeStyle(Color.indigo.mix(with: .primary, by: 0.35))
        case (.outlined, true), (.tag, true): AnyShapeStyle(Color.white)
        case (.remote, _): AnyShapeStyle(HierarchicalShapeStyle.secondary)
        }
    }

    private func fill(selected: Bool) -> Color {
        switch (style, selected) {
        case (.filled, false): laneColor
        case (.filled, true): .white
        case (.tag, false): .indigo.opacity(0.15)
        case (.tag, true): .white.opacity(0.25)
        case (.outlined, _), (.remote, _): .clear
        }
    }

    private func stroke(selected: Bool) -> AnyShapeStyle? {
        switch (style, selected) {
        case (.outlined, false): AnyShapeStyle(laneColor)
        case (.outlined, true): AnyShapeStyle(Color.white)
        case (.remote, _): AnyShapeStyle(HierarchicalShapeStyle.tertiary)
        case (.filled, _), (.tag, _): nil
        }
    }
}

extension RefBadge {
    init(label: RefLabel, laneColor: Color) {
        let style: Style = switch label.kind {
        case .head, .localBranch(isCurrent: true): .filled
        case .localBranch: .outlined
        case .remoteBranch: .remote
        case .tag: .tag
        }
        self.init(text: label.name, style: style, laneColor: laneColor)
    }
}

/// Sizes its content to its natural width, but never wider than `maxWidth`.
///
/// `.frame(maxWidth:)` would grow to fill a larger proposal, so a short badge inside a wide row would
/// stretch. This layout proposes `min(proposal, maxWidth)` and reports what the content actually uses.
struct CappedWidth: Layout {
    var maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(capped(proposal)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }

    private func capped(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: min(proposal.width ?? .infinity, maxWidth), height: proposal.height)
    }
}
```

- [ ] **Step 4: Implement the row.** Create `YAGit/Views/CommitRow.swift`:

```swift
import GitCore
import SwiftUI

/// One commit in the History list: its slice of the lane graph, ref badges, summary and byline.
struct CommitRow: View {
    let entry: HistoryEntry
    let laneCount: Int

    private static let visibleBadgeLimit = 3

    var body: some View {
        let commit = entry.commit
        let laneColor = GraphPalette.color(for: entry.graph.colorIndex)
        let hidden = entry.refs.dropFirst(Self.visibleBadgeLimit)
        HStack(spacing: 8) {
            GraphColumn(row: entry.graph, laneCount: laneCount)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    // Badges take their width first; the summary truncates into what's left.
                    ForEach(entry.refs.prefix(Self.visibleBadgeLimit), id: \.self) { label in
                        RefBadge(label: label, laneColor: laneColor)
                            .layoutPriority(1)
                    }
                    if !hidden.isEmpty {
                        RefBadge(text: "+\(hidden.count)", style: .remote, laneColor: laneColor)
                            .help(hidden.map(\.name).joined(separator: ", "))
                            .layoutPriority(1)
                    }
                    Text(commit.summary)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
                Text("\(commit.shortSHA) · \(commit.authorName) · \(CommitDate.string(for: commit.date))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 34)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(for: entry))
    }

    /// "summary, merge commit, on main, origin/main, author, date", naming every ref, including those hidden behind "+N".
    static func accessibilityLabel(for entry: HistoryEntry, now: Date = .now, calendar: Calendar = .current) -> String {
        var parts = [entry.commit.summary]
        if entry.graph.isMerge { parts.append(String(localized: "merge commit")) }
        if !entry.refs.isEmpty {
            parts.append(String(localized: "on \(entry.refs.map(\.name).joined(separator: ", "))"))
        }
        parts.append(entry.commit.authorName)
        parts.append(CommitDate.string(for: entry.commit.date, now: now, calendar: calendar))
        return parts.joined(separator: ", ")
    }
}
```

- [ ] **Step 5: Wire up the list.** Replace `YAGit/Views/HistoryList.swift` with:

```swift
import GitCore
import SwiftUI

/// One row per commit on any branch, with the lane graph drawn down the leading edge.
struct HistoryList: View {
    @Bindable var store: RepositoryStore
    var focus: FocusState<RepositoryStore.Pane?>.Binding

    var body: some View {
        List(selection: selection) {
            Section {
                ForEach(store.history) { entry in
                    CommitRow(entry: entry, laneCount: store.graphLaneCount)
                        .tag(entry.commit.sha)
                        // Zero vertical insets put rows exactly edge to edge, so lanes meet between rows.
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                        .listRowSeparator(.hidden)
                }
            } header: {
                HStack(spacing: 8) {
                    Text("History")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("All branches · \(store.history.count)\(store.isHistoryTruncated ? "+" : "")")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .textCase(nil)
                .padding(.vertical, 2)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .overlay {
            if store.history.isEmpty {
                ContentUnavailableView("No commits yet", systemImage: "clock",
                                       description: Text("Commits on any branch will appear here."))
            }
        }
        .navigationSplitViewColumnWidth(min: 280, ideal: 326, max: 480)
        .paneFocus(focus, .list)
        .claimsPaneFocus(store, .list)
    }

    private var selection: Binding<String?> {
        Binding(get: { store.selectedCommitSHA }, set: {
            store.requestFocus(.list)
            store.selectCommit(sha: $0)
        })
    }
}
```

- [ ] **Step 6: Run the tests and confirm they pass.**

Run: `xcodebuild -project YAGit.xcodeproj -scheme YAGit -derivedDataPath "$TMPDIR/yagit-derived-data" -only-testing:YAGitTests test 2>&1 | tail -40`
Expected: `** TEST SUCCEEDED **` for the whole app suite, including `CommitRowTests`, the store tests, and the existing screenshot tests.

- [ ] **Step 7: Commit.**

```bash
git add YAGit/Views/RefBadge.swift YAGit/Views/CommitRow.swift
git commit -m "Adds ref badges and the lane graph to history rows" -- YAGit/Views/RefBadge.swift YAGit/Views/CommitRow.swift YAGit/Views/HistoryList.swift YAGitTests/HistoryGraphTests.swift
```

---

### Task 8: Mockup render, lane-continuity check, and timing

**Files:**
- Modify: `YAGitTests/TestRepository.swift` (dated git helper)
- Create: `YAGitTests/HistoryGraphRenderTests.swift`
- Create: `GitCore/Tests/GitCoreTests/HistoryTimingTests.swift`

**Interfaces:**
- Consumes: everything above. `RepositoryContent(store:)` from `YAGit/Views/RepositoryWindow.swift`.
- Produces: PNGs in `$TMPDIR/yagit-screens/history-graph-*.png`; a timing line printed by `swift test`.

- [ ] **Step 1: Add the dated git helper to the app's fixture.** In `YAGitTests/TestRepository.swift`, apply the same change as Task 3 Step 1: the `git(date:_:)` method and the `extraEnvironment` parameter on `run`. The `commitAll(_:date:)` helper isn't needed here.

- [ ] **Step 2: Write the render test.** Create `YAGitTests/HistoryGraphRenderTests.swift`:

```swift
import AppKit
import Foundation
import GitCore
import SwiftUI
import Testing
@testable import YAGit

/// The design mockup's history, newest first.
private let mockupSummaries = [
    "Cache trip details between launches",
    "Update Norwegian localization",
    "Sort arrivals by scheduled time",
    "Fix stale arrival predictions",
    "Raise the minimum deployment target to iOS 17",
    "Cut the 2.9 release branch",
    "Merge pull request #418 from feature/trip-planner",
    "Add the TripCache actor",
    "Sketch the trip planner panel",
    "Merge pull request #412 from fix/bookmarks",
    "Add a regression test for empty bookmarks",
    "Guard the bookmarks reload against a nil session",
    "Extract OBAKitCore into its own package",
    "Initial 2.7 release",
]

/// Rebuilds the mockup's repository with one-minute-apart dates, so the walk order is fixed.
@MainActor
private func makeMockupFixture() throws -> TestRepository {
    let fixture = try TestRepository()
    try fixture.git("config", "user.name", "Aaron Brethorst")
    try fixture.git("config", "user.email", "aaron@onebusaway.org")
    var minute = 0
    func nextDate() -> Date {
        defer { minute += 1 }
        return Date(timeIntervalSince1970: 1_788_000_000 + Double(minute) * 60)
    }
    func commit(_ message: String) throws {
        try fixture.git(date: nextDate(), "commit", "-q", "--allow-empty", "-m", message)
    }
    func merge(_ branch: String, _ message: String) throws {
        try fixture.git(date: nextDate(), "merge", "-q", "--no-ff", "-m", message, branch)
        try fixture.git("branch", "-D", branch)
    }

    try commit("Initial 2.7 release")
    try fixture.git("tag", "v2.7.0")
    try commit("Extract OBAKitCore into its own package")
    try fixture.git("checkout", "-q", "-b", "fix/bookmarks")
    try commit("Guard the bookmarks reload against a nil session")
    try commit("Add a regression test for empty bookmarks")
    try fixture.git("checkout", "-q", "main")
    try merge("fix/bookmarks", "Merge pull request #412 from fix/bookmarks")
    try fixture.git("tag", "v2.7.1")
    try fixture.git("checkout", "-q", "-b", "feature/trip-planner-panel")
    try commit("Sketch the trip planner panel")
    try commit("Add the TripCache actor")
    try fixture.git("checkout", "-q", "main")
    try merge("feature/trip-planner-panel", "Merge pull request #418 from feature/trip-planner")
    try fixture.git("checkout", "-q", "-b", "release/2.9")
    try commit("Cut the 2.9 release branch")
    try fixture.git("checkout", "-q", "main")
    try commit("Raise the minimum deployment target to iOS 17")
    try fixture.git("checkout", "-q", "release/2.9")
    try commit("Fix stale arrival predictions")
    try fixture.git("tag", "v2.8.1")
    try fixture.git("checkout", "-q", "-b", "fix/arrival-sort", "main")
    try commit("Sort arrivals by scheduled time")
    try fixture.git("checkout", "-q", "main")
    try commit("Update Norwegian localization")
    try fixture.git("update-ref", "refs/remotes/origin/main", "HEAD")
    try fixture.git("checkout", "-q", "-b", "feature/trip-planner")
    try commit("Cache trip details between launches")
    // Not in the mockup: four refs on the root commit exercise the "+N" overflow badge.
    try fixture.git("branch", "archive/2.7", "v2.7.0")
    try fixture.git("tag", "v2.7.0-rc1", "v2.7.0")
    try fixture.git("tag", "v2.7.0-rc2", "v2.7.0")
    return fixture
}

@MainActor
@Suite(.serialized)
struct HistoryGraphRenderTests {
    private let listWidth = 326

    @Test(arguments: [false, true])
    func mainlineLaneIsContinuousAcrossRows(dark: Bool) async throws {
        let fixture = try makeMockupFixture()
        let store = try RepositoryStore(url: fixture.url)
        await store.load()
        #expect(store.history.map(\.commit.summary) == mockupSummaries)
        #expect(store.history.map(\.graph.column) == [1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 1, 0, 0])
        #expect(store.history.last?.refs.count == 4)
        store.mode = .history

        let window = makeWindow(store, dark: dark)
        try await settle(window)
        let (view, rep) = try snapshot(window, named: dark ? "history-graph-dark" : "history-graph-light")

        let table = try #require(view.descendants(of: NSTableView.self).first { Int($0.frame.width) == listWidth })
        let rows = (0..<table.numberOfRows).map { table.rect(ofRow: $0) }.filter { abs($0.height - 34) < 0.5 }
        try #require(rows.count == 14, "commit rows: \(rows)")
        func sample(_ x: CGFloat, _ y: CGFloat) -> NSColor? {
            color(in: rep, of: view, at: table.convert(NSPoint(x: x, y: y), to: view))
        }

        // Row 1 is `main`, a mainline commit: its dot is the first run of ink from the row's leading edge.
        let ink = stride(from: rows[1].minX, to: rows[1].maxX, by: 0.5).filter { isLaneInk(sample($0, rows[1].midY)) }
        let first = try #require(ink.first)
        let laneX = (first + ink.prefix { $0 - first <= 9 }.last!) / 2

        // Lane 0 must have ink on both sides of every boundary from row 1 down to the root.
        for index in 1..<13 {
            for y in [rows[index].maxY - 1, rows[index + 1].minY + 1] {
                let pixel = sample(laneX, y)
                #expect(isLaneInk(pixel), "lane 0 broken below row \(index) at y=\(y): \(String(describing: pixel))")
            }
        }
        window.close()
    }

    @Test func selectedMergeRowRendersFocusedAndUnfocused() async throws {
        let fixture = try makeMockupFixture()
        let store = try RepositoryStore(url: fixture.url)
        await store.load()
        store.mode = .history
        let window = makeWindow(store, dark: false)
        try await settle(window)

        let merge = store.history[6].commit.sha
        store.selectCommit(sha: merge)
        store.requestFocus(.list)
        try await settle(window)
        _ = try snapshot(window, named: "history-graph-selected-focused")

        store.focusedPane = .commitFiles
        try await settle(window)
        #expect(store.selectedCommitSHA == merge)
        _ = try snapshot(window, named: "history-graph-selected-unfocused")
        window.close()
    }

    // MARK: - Helpers

    private func makeWindow(_ store: RepositoryStore, dark: Bool) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = NSHostingView(rootView: RepositoryContent(store: store))
        window.makeKeyAndOrderFront(nil)
        return window
    }

    /// Other suites run in parallel and order their own windows front; reclaim key status every pass
    /// so selection renders with focused prominence.
    private func settle(_ window: NSWindow) async throws {
        for _ in 0..<8 {
            if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
            try await Task.sleep(for: .milliseconds(120))
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private func snapshot(_ window: NSWindow, named name: String) throws -> (NSView, NSBitmapImageRep) {
        let view = window.contentView!.superview!
        view.layoutSubtreeIfNeeded()
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("yagit-screens", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try #require(rep.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("\(name).png"))
        return (view, rep)
    }

    private func color(in rep: NSBitmapImageRep, of view: NSView, at point: NSPoint) -> NSColor? {
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        let y = view.isFlipped ? point.y : view.bounds.height - point.y
        return rep.colorAt(x: Int(point.x * scale), y: Int(y * scale))
    }

    /// Lane colors are saturated; list backgrounds (white, near-black, gray) are not.
    private func isLaneInk(_ color: NSColor?) -> Bool {
        guard let color = color?.usingColorSpace(.sRGB) else { return false }
        return color.saturationComponent > 0.35 && color.brightnessComponent > 0.3
    }
}

private extension NSView {
    func descendants<T: NSView>(of type: T.Type) -> [T] {
        subviews.flatMap { (($0 as? T).map { [$0] } ?? []) + $0.descendants(of: type) }
    }
}
```

- [ ] **Step 3: Run the render tests.**

Run: `xcodebuild -project YAGit.xcodeproj -scheme YAGit -derivedDataPath "$TMPDIR/yagit-derived-data" -only-testing:YAGitTests/HistoryGraphRenderTests test 2>&1 | tail -40`
Expected: `** TEST SUCCEEDED **`. PNGs land in `$(getconf DARWIN_USER_TEMP_DIR)yagit-screens/` (the test process's `NSTemporaryDirectory()`).

If the continuity check fails, open the PNG before touching anything. Look at whether the gap is real (the rows aren't 34pt apart, or the canvas isn't full height) or a sampling error (wrong `laneX`, or the header row counted as a commit row). Fix the cause. Don't loosen `isLaneInk` just to get a pass.

- [ ] **Step 4: Review the renders against the mockup.** Read each PNG with the Read tool (`history-graph-light.png`, `history-graph-dark.png`, `history-graph-selected-focused.png`, `history-graph-selected-unfocused.png`) and check:
  - Column 0 is a straight blue line from `main` down to the root. Nothing is drawn in column 0 above `main`'s dot except the purple curve from `feature/trip-planner`.
  - The `feature/trip-planner` badge is filled purple; `main` is outlined blue; `origin/main` is grey-outlined; `v2.8.1` and `v2.7.1` are indigo.
  - The two merge dots are hollow rings with the background visible inside, including the gray unfocused selection.
  - The root row shows 3 badges and a `+1` badge; the summary truncates rather than overlapping.
  - Selected and focused: the graph and badges are white on the accent background. Selected but unfocused: normal colors on gray.
  - Dark mode: lanes and badges stay legible.
  - Separators are hidden and the byline reads `sha · Aaron Brethorst · <date>`.

  Fix any visual mismatch in the view code, re-run Step 3, and re-check. Record anything left open in the Verification notes below.

- [ ] **Step 5: Add the timing probe.** Create `GitCore/Tests/GitCoreTests/HistoryTimingTests.swift`:

```swift
import Foundation
import Testing
@testable import GitCore

/// Manual probe: `YAGIT_TIMING_REPO=/path/to/repo swift test --filter HistoryTimingTests`.
@Suite struct HistoryTimingTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["YAGIT_TIMING_REPO"] != nil))
    func historyOnARealRepository() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["YAGIT_TIMING_REPO"])
        let repo = try GitRepository(url: URL(fileURLWithPath: path))
        var entries: [HistoryEntry] = []
        let elapsed = try await ContinuousClock().measure { entries = try await repo.history() }
        let lanes = (entries.map(\.graph.column).max() ?? -1) + 1
        print("history() on \(path): \(entries.count) entries, \(lanes) lanes, \(elapsed)")
    }
}
```

- [ ] **Step 6: Time two real repositories.**

Run:
```bash
cd GitCore
YAGIT_TIMING_REPO=$HOME/repos/onebusaway/app-modules swift test --filter HistoryTimingTests 2>&1 | grep "history()"
YAGIT_TIMING_REPO=$HOME/repos/onebusaway/ios swift test --filter HistoryTimingTests 2>&1 | grep "history()"
```
Expected: one `history() on …` line each; `app-modules` has about 5,000 commits and 200 tags. Record the numbers below. If either run takes more than 1 second, report it to the user as a possible follow-up; don't optimize it in this plan.

- [ ] **Step 7: Run everything.**

Run:
```bash
(cd GitCore && swift test)
xcodebuild -project YAGit.xcodeproj -scheme YAGit -derivedDataPath "$TMPDIR/yagit-derived-data" -only-testing:YAGitTests test 2>&1 | tail -40
```
Expected: GitCore tests all pass (the timing test is skipped without the env var); `** TEST SUCCEEDED **` for the app.

- [ ] **Step 8: Commit.**

```bash
git add YAGitTests/HistoryGraphRenderTests.swift GitCore/Tests/GitCoreTests/HistoryTimingTests.swift
git commit -m "Adds a mockup render test for the history graph and a history timing probe" -- \
  YAGitTests/HistoryGraphRenderTests.swift YAGitTests/TestRepository.swift GitCore/Tests/GitCoreTests/HistoryTimingTests.swift
```

---

## Verification notes

Fill in during Task 8:

- `app-modules` timing: _
- `ios` timing: _
- Visual differences from the mockup that remain, and why: _
