# History Graph — Design

Date: 2026-09-16. Adds a commit graph, ref badges, and an all-branches walk to the History list,
following the mockup supplied in the brainstorming session (History pane with colored lanes,
`feature/trip-planner` / `main` / `origin/main` / `v2.8.1` badges, hollow merge dots). The mockup
screenshot is @2x; all point values below are halved from its pixels.

## 1. Scope

In:

- History walks HEAD, every local branch, the sidebar's remote branches, and every tag — so it
  also includes any history reachable only from a tag (fetch auto-follows tags, so a tagged
  branch that exists only on origin shows up through its tag).
- A lane graph drawn per row: straight lanes, S-curves for lane changes, filled commit dots,
  hollow merge dots, a fixed mainline in column 0, rotating lane colors.
- Ref badges before the summary: HEAD (when detached), local branches, remote branches, tags.
- Row layout: badges + summary on line one, `sha · author · date` on line two, 34pt rows.
- Calendar-style dates ("Today at 08:14") in the list and in `CommitDetailPane`.
- History reloads after a fetch; the selected commit survives reloads and branch switches.

Out:

- A toggle between all branches and current branch.
- Pushing every `origin/*` branch into the walk (only those the sidebar shows).
- Interacting with badges or lanes (click to check out, hover highlighting of a lane).
- Creating, deleting, or pushing tags. Tags are display-only; the MVP's "tags out of scope"
  still holds for tag operations.
- Widening or horizontally scrolling graphs past 8 lanes.

## 2. GitCore

### Models (`Models.swift`)

| Type | Change |
| --- | --- |
| `CommitSummary` | adds `parentSHAs: [String]` (libgit2 parent order; first parent first) |
| `RefLabel` | new: `name: String`, `kind: Kind`; `Kind` is `.head`, `.localBranch(isCurrent: Bool)`, `.remoteBranch`, `.tag` |
| `GraphSegment` | new: `fromColumn: Int`, `toColumn: Int`, `colorIndex: Int` |
| `GraphRow` | new: `column: Int`, `colorIndex: Int`, `isMerge: Bool`, `upper: [GraphSegment]`, `lower: [GraphSegment]` |
| `HistoryEntry` | new, `Identifiable` by `commit.sha`: `commit: CommitSummary`, `refs: [RefLabel]`, `graph: GraphRow` |

All new types are `Sendable, Hashable`. `RefLabel.name` is the short name (`main`,
`origin/main`, `v2.8.1`, `HEAD`).

`parentSHAs` is filled in `CommitSummary.init(commit:)` (`GitRepository+Commit.swift`) from
`git_commit_parentcount` / `git_commit_parent_id`, so `commit()`, `commitDetail()`, and
`history()` all return the same value for the same commit.

### `history(limit: Int = GitRepository.historyLimit) throws -> [HistoryEntry]`

`public static let historyLimit = 2000`. Replaces the HEAD-only walk.

1. Revwalk with `GIT_SORT_TOPOLOGICAL | GIT_SORT_TIME` (unchanged), pushing:
   - `git_revwalk_push_head`, unless HEAD is unborn (covers detached HEAD),
   - every local branch (`refs/heads/*`),
   - `refs/remotes/origin/main` and `refs/remotes/origin/<current>` when they exist — the same
     set `remoteBranches(current:)` returns for the sidebar,
   - `git_revwalk_push_glob(walk, "refs/tags")`, which peels annotated tags and silently skips
     tags that don't peel to a commit.

   Only `origin/main` and `origin/<current>` are walked, so a commit that exists only on
   `origin/<other branch>` leaves history (and its selection clears) when you switch away from
   that branch.

   If nothing was pushed (unborn HEAD and no refs), return `[]`. An unborn HEAD with other
   branches (orphan checkout) still shows those branches.
2. Collect up to `limit` commits.
3. Build `[sha: [RefLabel]]` from the same refs. Tags are listed with
   `git_reference_iterator_glob_new(repo, "refs/tags/*")` and peeled with
   `git_reference_peel(..., GIT_OBJECT_COMMIT)`; `GIT_EPEEL`, `GIT_EINVALIDSPEC`, and
   `GIT_ENOTFOUND` skip that tag, any other error throws. A detached HEAD adds `.head` to its
   commit. Order within one commit: `.head`, current branch, other local branches, remote
   branches, tags; each group sorted with `localizedStandardCompare` (so `v2.10` follows `v2.9`).
4. Resolve the mainline tip: `refs/heads/main`, else `refs/heads/master`, else
   `refs/remotes/origin/main`, else HEAD (nil when unborn).
5. Run `GraphLayout.rows(for:mainlineTip:)` and zip commits, labels, and rows into entries.

`forEachBranch` and `remoteBranches(current:)` in `GitRepository+Snapshot.swift` become
`internal` so `history()` can reuse them.

### `GraphLayout` (`GraphLayout.swift`)

A pure `enum GraphLayout` with
`static func rows(for commits: [CommitSummary], mainlineTip: String?) -> [GraphRow]`. It does not
touch libgit2 and is tested with hand-built commit lists.

**Mainline.** Follow `parentSHAs.first` from `mainlineTip` through the commits present in the
list; the SHAs visited form the mainline set. Mainline commits always occupy column 0, and no
other commit ever does. If `mainlineTip` is nil or not in the list, the mainline set is empty and
column 0 is an ordinary column. "Free column" below means the leftmost nil slot at index ≥ 1
when the mainline set is non-empty (≥ 0 otherwise), appending a slot if none is nil.

**State.** `slots: [Lane?]`, where `Lane` is `(target: String, colorIndex: Int)`. Each non-nil
slot is an edge travelling down that column toward its target commit; several slots may share
a target. All slots start nil — nothing is drawn in column 0 above the first edge that reaches
it. A color counter starts at 1; `nextColor()` returns it and advances it. Color indices are
unbounded; the app maps them onto its palette (§3), and 0 is only ever the mainline.

**Per commit C, in list order:**

1. *Column and color.*
   - C is mainline → column 0, color 0.
   - Else if any slot targets C → the leftmost such slot; that slot's color.
   - Else (a tip with no child in the list) → a free column; `nextColor()`.
2. *Upper half.* Every slot targeting C: segment `slot → column` in that slot's color, then the
   slot becomes nil. Every other non-nil slot: straight segment `slot → slot` in its color.
3. *Lower half.* Every non-nil slot left after step 2: straight segment `slot → slot`. Then for
   each parent P of C, in order (index i), apply the first rule that matches:
   1. C is mainline and i == 0 → slot 0 becomes `(P, 0)`; segment `0 → 0`, color 0.
   2. The mainline set is non-empty, P is `mainlineTip`, and slot 0 is nil → slot 0 becomes
      `(P, 0)`; segment `column → 0`.
   3. A slot already targets P → segment `column → thatSlot` (leftmost such slot).
   4. i == 0 → slot `column` becomes `(P, C's color)`; segment `column → column`.
   5. Otherwise → a free column becomes `(P, nextColor())`; segment `column → thatColumn`.

   Segment color for rules 2 and 3: C's color when i == 0 (a branch's own line stays its color
   until it joins), otherwise the joined slot's color. Rule 5 uses the new lane's color.
4. *Pack.* Visit the non-nil slots in ascending index order. For each slot `k`, find the leftmost
   nil slot `j` with `firstFree ≤ j < k`, where `firstFree` is 1 when the mainline set is
   non-empty and 0 otherwise. If there is one, move the lane from `k` to `j`, set slot `k` to nil,
   and rewrite every lower-half segment with `toColumn == k` to end at `j` (the straight
   pass-through `k → k` and any edge from C's dot that ended at `k`). Lanes keep their relative
   order, so packing never makes two lanes cross. C's dot and the tops of its segments don't move.
5. *Trim.* Drop trailing nil slots.
6. Emit `GraphRow(column, colorIndex, isMerge: parentSHAs.count > 1, upper, lower)`.

A parent that never appears (beyond `limit`, or a shallow-clone boundary) keeps its slot to the
end, so its lane runs straight off the bottom of the last row. A root commit emits no lower-half
segments from its dot.

**Visual rules this produces** (matching the mockup):

- Nothing is drawn in column 0 above the mainline tip unless an edge joins it there.
- An unmerged branch whose parent is the next mainline commit curves into column 0 directly
  below its dot, in the branch's color; the lane continues blue into the parent's dot.
- A merge commit's second parent opens a new column with a curve directly below the merge dot.
- A side branch cut from an older mainline commit stays in its own column past the mainline
  commits in between, then curves into its parent's dot in the parent's upper half, so
  intervening mainline commits never look like its ancestors.
- Two branches off the same parent share a lane from the second branch's dot down.
- An octopus merge opens one new lane per extra parent that no slot already targets.
- When a lane closes, the lanes to its right curve left to fill the gap in the lower half of
  that row, as `git log --graph` collapses lanes. A side lane never takes column 0 while there
  is a mainline, and lanes never cross.

The mockup places `fix/arrival-sort` in column 3 and `release/2.9` in column 2; this algorithm
packs them into column 1. Otherwise it reproduces the mockup's lanes.

Layout depends on walk order, and `GIT_SORT_TIME` breaks ties by committer time, so commits with
equal timestamps can come out in either order. Tests that depend on order pin commit dates.

## 3. App

### `RepositoryStore`

- `history: [HistoryEntry]`.
- `selectedCommit` becomes `history.first { $0.commit.sha == selectedCommitSHA }?.commit`.
- `graphLaneCount: Int` (stored) = `min(8, 1 + max over rows of column and every segment's
  from/to)`, or 0 for an empty history; set in `reloadHistory()`.
- `isHistoryTruncated: Bool` (stored) = `history.count == GitRepository.historyLimit`.
- `fetch()` calls `reloadHistory()` after `refresh()`, on both `.upToDate` and `.updated`
  (`.upToDate` only compares branch refs; new tags would not count).
- **Selection across reloads.** After every `reloadHistory()`: if `selectedCommitSHA` is still in
  `history`, keep it and its `commitDetail` / `selectedCommitFile`; otherwise clear all three.
  `switchBranch` and `createBranch` no longer clear the commit selection themselves.

### `HistoryList`

- `ForEach(store.history)` tags each row with `entry.commit.sha`; rows receive the entry and
  `store.graphLaneCount`, not the store.
- Header: "History" left; right (11pt, tertiary): "All branches · N", or "All branches · N+" when
  `isHistoryTruncated`.
- Empty state description: "Commits on any branch will appear here."
- Rows: `.listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))` and
  `.listRowSeparator(.hidden)`. With zero vertical insets an `.inset` List lays rows out exactly
  34pt apart with no intercell spacing, so row canvases meet edge to edge (confirmed by probe).
  Don't use `listRowSpacing`; it isn't available on macOS.

### `CommitRow` (34pt tall)

```
[GraphColumn][8pt][ badges… summary                      ]
                  [ sha · author · date                  ]
```

- Line 1: up to 3 `RefBadge`s, 4pt apart, then `summary` (13pt medium, `lineLimit(1)`, tail
  truncation). Badges have `.layoutPriority(1)` and a 140pt max width with middle truncation;
  the summary keeps default priority, so it shrinks first and a badge only truncates when the
  row can't fit it at all. More than 3 refs → a fourth neutral badge `+N` with `.help` listing
  the hidden names.
- Line 2: `shortSHA · authorName · CommitDate.string(for: date)` (11pt, `.secondary`, one line).
  Full author name, not a derived first name. `.secondary` adapts to selection on its own.
- Accessibility: `.accessibilityElement(children: .ignore)` with `.accessibilityLabel`
  "summary, merge commit (when isMerge), on <every ref name, including hidden ones>, author,
  date". `GraphColumn` is `.accessibilityHidden(true)`.

### `GraphColumn`

A `Canvas` of width `8 + 10 × laneCount`, full row height. Canvas clips to its frame, so all
drawing stays inside it.

- Column c's x center: `9 + 10c`; dot y center: `height / 2`.
- Segment path: upper from `(x(from), 0)` to `(x(to), midY)`; lower from `(x(from), midY)` to
  `(x(to), height)`. Equal columns → a straight line. Different columns → a cubic Bézier whose
  two control points sit at the half's vertical midpoint, one at the start x and one at the end
  x, so tangents are vertical at both ends.
- Stroke 1.5pt, round caps. Lines first, then the dot.
- Dot: filled 8pt circle. Merge dot: set `context.blendMode = .clear` and fill the 8pt circle
  (punching a transparent hole through the lines, so whatever is behind the row shows through,
  selected or not), restore `.normal`, then stroke a 6.5pt-diameter ring at 1.5pt (outer edge
  8pt). No background color is assumed.
- Overflow: segments with either end at column ≥ `laneCount` and dots at column ≥ `laneCount`
  are skipped. Such commits show no dot. Packing (§2) keeps lanes left, so this only happens
  past 8 concurrent lanes.

### Lane palette (`GraphPalette`)

`[.blue, .purple, .teal, .orange, .green, .pink, .brown]`. `GraphPalette.color(for: index)`
returns `.blue` for 0 and `palette[1 + (index - 1) % 6]` otherwise, so the mainline's blue is
never reused. System colors, so light and dark appearance adapt.

### `RefBadge`

Rounded rectangle, corner radius 4, height 16, horizontal padding 5, 11pt semibold text,
`lineLimit(1)`. Backgrounds use the shape form, e.g.
`.background(.indigo.opacity(0.15), in: .rect(cornerRadius: 4))`, to avoid SDK 27
content-builder ambiguity.

| Kind | Normal | Selected (prominence `.increased`) |
| --- | --- | --- |
| HEAD (detached) / current local branch | fill = lane color, text white | fill white, text = lane color |
| Other local branch | 1pt stroke in lane color; text = lane color mixed 35% toward `.primary` (`Color.mix(with:by:)`) for contrast | 1pt white stroke, white text |
| Remote branch | 1pt `.tertiary` stroke, `.secondary` text | same styles (they adapt) |
| Tag | fill indigo 15%, text indigo mixed 35% toward `.primary` | fill white 25%, white text |
| `+N` overflow | as remote | as remote |

"Lane color" is the row's dot color (`GraphPalette.color(for: graph.colorIndex)`), and a branch
tip's own line leaves its dot in that color, so badge and line always match.

### Selected rows

`GraphColumn` and `RefBadge` read `@Environment(\.backgroundProminence)`.

- `.increased` (selected row in the focused list, accent background): dots and ring white, lines
  white at 70% opacity, badges per the table.
- `.standard` (unselected, or selected while another pane has focus — gray background): normal
  colors. The merge dot's cleared center already shows the gray.

### `CommitDate`

`enum CommitDate { static func string(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String }`

Every format style is built from the calendar, never the process defaults:
`Date.FormatStyle(date:time:locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone)`.

- `calendar.isDate(date, inSameDayAs: now)` → "Today at <time>".
- `calendar.isDate(date, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: now)!)` →
  "Yesterday at <time>".
- Same `.year` component as `now` → "<abbreviated month> <day> at <time>" (e.g. "Sep 14 at 11:02").
- Any other year, past or future (clock skew) → "<abbreviated month> <day>, <year> at <time>".
- `<time>` uses `time: .shortened`, following the locale's 12/24-hour setting. Month/day use
  `.month(.abbreviated).day()` (plus `.year()`), so field order follows the locale.
  "Today at %@", "Yesterday at %@", and "%1$@ at %2$@" are localizable strings.
- `CommitDetailPane` uses it instead of `.relative(presentation: .named)`.

## 4. Testing

### Fixtures

Both `TestRepository` copies (GitCore and YAGitTests) gain `commitAll(_ message: String, date: Date)`,
which sets `GIT_AUTHOR_DATE` and `GIT_COMMITTER_DATE`; `run` gains an `environment` parameter.
Any test that depends on commit order uses dated commits one minute apart.

### GitCore (`swift test`, system `git` as oracle)

Existing tests whose meaning changes, rewritten as all-branches tests:

- `BranchTests.commitsOnANewBranchDoNotAppearOnTheParent` → the feature commit now appears after
  switching back to the parent; assert membership and that it is not labelled with the parent.
- `CommitTests.historyIsNewestFirstAndPerBranch` → newest first across both branches.
- Type updates: `BranchTests` lines 19 and 53, `CommitTests.commitDetailListsFilesWithCounts`
  (`detail.commit == head` holds because both fill `parentSHAs`).

`HistoryTests`:

- A commit reachable only from a second local branch appears.
- A commit reachable only from a lightweight tag appears; same for an annotated tag, whose label
  lands on the commit, not the tag object.
- A tag pointing at a tree is skipped without an error.
- A commit reachable only from `origin/main` appears (bare remote + fetch); a commit on an
  untagged `origin/x` branch does not.
- Merge commit `parentSHAs` equal `git rev-parse <sha>^1 <sha>^2`.
- Labels: the current branch is `.localBranch(isCurrent: true)`; order within a commit is head,
  current, local, remote, tag.
- Detached HEAD at a commit no branch reaches: the commit appears, labelled `.head`.
- Unborn HEAD with another branch that has commits: that branch's commits appear.
- Mainline tip fallback: `main` → `master` → `origin/main` → HEAD, each checked by which commit
  lands in column 0.
- The walk stops at `limit`.

`GraphLayoutTests` (hand-built `CommitSummary` lists, no repository), `@Test(arguments:)` where
cases share a shape:

- Linear history: every row column 0; straight segments; first row has no upper segment; root
  has no lower segment from its dot.
- Rows above the mainline tip draw nothing in column 0.
- Unmerged tip above the mainline tip: tip in column 1, color 1; its only lower segment is `1 → 0`
  in color 1; the mainline tip's upper segment is `0 → 0` in color 0.
- Merge: `isMerge`; lower segments `0 → 0` and `0 → 1`; the second-parent chain sits in column 1.
- Octopus merge: one new lane per extra parent.
- Merge whose second parent is already targeted: joins that slot, in that slot's color.
- Mainline commit whose first parent is already targeted by a side lane: both slots close at the
  parent.
- Side branch cut from a mainline commit three rows down: straight `k → k` through intermediate
  rows, upper `k → 0` at the parent in the side lane's color.
- Two tips sharing a parent: the second tip's lower segment curves into the first's slot.
- Column reuse: after a lane closes, the next new tip takes the freed column.
- Packing: a lane right of a closed lane curves left into the freed column in that row's lower
  half; it never packs into an empty column 0 while there is a mainline; without a mainline it
  does.
- Parent absent from the list: its slot still appears in the last row's lower half.
- `mainlineTip` nil, or not in the list: column 0 is used by ordinary tips.
- Colors: mainline always 0; indices 1, 2, 3, … are handed out in the order new tips appear and
  new parent lanes open; a lane continuing in its column keeps its color.
- The mockup history (as a fixture list): expected column per row.

### App (`YAGitTests`)

- Accessor updates: `PaneFocusTests` lines 38 and 56, and every `history[0].sha`,
  `history.first?.summary`, and `history.map(\.summary)` in `YAGitTests.swift`, move to
  `.commit`.
- `createBranchSwitchAndFetch`: call `fixture.commitOnOrigin("Remote work")` before
  `store.fetch()`; after settling, expect "Remote work" in `store.history` (covers
  fetch-reloads-history).
- Selection across reloads: select a commit, switch branch → still selected with its detail;
  delete the only branch reaching the selected commit with `git branch -D` and refresh history →
  selection, detail, and file are cleared.
- `graphLaneCount`: 0 for empty history; capped at 8 for a fixture with 10 concurrent tips.
- `CommitDateTests`: `@Test(arguments:)` over (date, now, locale identifier, expected) with an
  explicit `calendar.timeZone` of UTC — today, yesterday, same year, earlier year, next year in
  `en_US`; 24-hour time in `en_GB`.
- `GraphPaletteTests`: `@Test(arguments:)` over (index, expected) — 0 is blue; 1…6 are distinct and
  non-blue; 7 equals 1.
- Offscreen render (existing `NSWindow` + `cacheDisplay` harness) of `HistoryList` against a
  scripted, date-pinned fixture reproducing the mockup history: `main` with two merged PRs,
  unmerged `feature/trip-planner` (current), `fix/arrival-sort`, `release/2.9`, tags `v2.7.0`,
  `v2.7.1`, `v2.8.1`, and `origin/main`.
  - Renders: light; dark; a row selected with the window key and `store.requestFocus(.list)`
    (`.increased`); the same row selected with focus in the commit-files pane (`.standard`).
    PNGs to `$TMPDIR/yagit-screens` for visual comparison with the mockup.
  - Assertion: sample the pixel column at lane 0's x through the mainline rows and require no
    background-colored pixels across each row boundary.

### Manual

- Time `history()` on a large real repository (for example OBAKit with its tags) and record it in
  the plan's verification notes.

## 5. Risks

- **Walk cost.** With any sort mode, libgit2 visits every commit reachable from every pushed ref
  before `git_revwalk_next` returns the first one (`revwalk.c`: sorting sets `limited`, then
  `limit_list` and `sort_in_topological_order` run over the whole set). `limit` only bounds
  `CommitSummary` construction. Pushing all branches and tags adds to that up-front cost; it runs
  on the `GitRepository` actor, off the main thread. The manual timing check above decides
  whether this needs follow-up.
- **Wide graphs.** Packing (§2) keeps open lanes in the leftmost free columns, so skipping only
  happens past 8 concurrent lanes. There, overflow lanes and their dots are skipped rather than
  widening the pane.
- **Walk-order ties.** Equal committer timestamps can reorder commits, which changes the layout
  between reloads in rare cases. Accepted; tests pin dates.
