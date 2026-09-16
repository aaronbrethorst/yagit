# History Graph — Design

Date: 2026-09-16. Adds a commit graph, ref badges, and an all-branches walk to the History list,
following the mockup supplied in the brainstorming session (History pane with colored lanes,
`feature/trip-planner` / `main` / `origin/main` / `v2.8.1` badges, hollow merge dots). The mockup
screenshot is @2x; all point values below are halved from its pixels.

## 1. Scope

In:

- History walks every local branch, the sidebar's remote branches, all tags, and HEAD.
- A lane graph drawn per row: straight lanes, S-curves for lane changes, filled commit dots,
  hollow merge dots, a fixed mainline in column 0, rotating lane colors.
- Ref badges before the summary: local branches, remote branches, tags.
- Row layout: badges + summary on line one, `sha · author · date` on line two, 34pt rows.
- Calendar-style dates ("Today at 08:14") in the list and in `CommitDetailPane`.
- History reloads after a fetch.

Out:

- A toggle between all branches and current branch.
- Walking every `origin/*` branch (only those the sidebar shows).
- Interacting with badges or lanes (click to check out, hover highlighting of a lane).
- Creating, deleting, or pushing tags. Tags are display-only; the MVP's "tags out of scope"
  still holds for tag operations.
- Horizontal scrolling of wide graphs.

## 2. GitCore

### Models (`Models.swift`)

| Type | Change |
| --- | --- |
| `CommitSummary` | adds `parentSHAs: [String]` (libgit2 parent order; first parent first) |
| `RefLabel` | new: `name: String`, `kind: Kind`; `Kind` is `.localBranch(isCurrent: Bool)`, `.remoteBranch`, `.tag` |
| `GraphSegment` | new: `fromColumn: Int`, `toColumn: Int`, `colorIndex: Int` |
| `GraphRow` | new: `column: Int`, `colorIndex: Int`, `isMerge: Bool`, `upper: [GraphSegment]`, `lower: [GraphSegment]` |
| `HistoryEntry` | new, `Identifiable` by `commit.sha`: `commit: CommitSummary`, `refs: [RefLabel]`, `graph: GraphRow` |

All new types are `Sendable, Hashable`. `RefLabel.name` is the short name (`main`,
`origin/main`, `v2.8.1`).

### `history(limit: Int = 2000) throws -> [HistoryEntry]`

Replaces the HEAD-only walk.

1. Return `[]` when HEAD is unborn (unchanged).
2. Revwalk with `GIT_SORT_TOPOLOGICAL | GIT_SORT_TIME` (unchanged), pushing:
   - `git_revwalk_push_head` (covers detached HEAD),
   - every local branch (`refs/heads/*`),
   - `refs/remotes/origin/main` and `refs/remotes/origin/<current>` when they exist — the same
     set `remoteBranches(current:)` returns for the sidebar,
   - every tag (`refs/tags/*`), peeled to a commit with `git_reference_peel(..., GIT_OBJECT_COMMIT)`.
     Tags that don't peel to a commit (tags of trees or blobs) are skipped, not errors.
3. Collect up to `limit` commits; each `CommitSummary` fills `parentSHAs` from
   `git_commit_parentcount` / `git_commit_parent_id`.
4. Build `[sha: [RefLabel]]` from the same refs pushed in step 2. Within one commit, order labels:
   current branch, other local branches (name-sorted, `localizedStandardCompare`), remote
   branches (name-sorted), tags (name-sorted, `localizedStandardCompare` so `v2.10` follows `v2.9`).
5. Resolve the mainline tip: `refs/heads/main`, else `refs/heads/master`, else
   `refs/remotes/origin/main`, else HEAD.
6. Run `GraphLayout.rows(for:mainlineTip:)` and zip commits, labels, and rows into entries.

Ref pushing reuses the existing `forEachBranch` iterator for local branches; tags use
`git_reference_iterator_glob_new(repo, "refs/tags/*")`.

### `GraphLayout` (`GraphLayout.swift`)

A pure `enum GraphLayout` with
`static func rows(for commits: [CommitSummary], mainlineTip: String?) -> [GraphRow]`. It does not
touch libgit2 and is tested with hand-built commit lists.

**Mainline.** Follow `parentSHAs.first` from `mainlineTip` through the commits present in the
list; the SHAs visited form the mainline set. Mainline commits always occupy column 0, and no
other commit ever does. If `mainlineTip` is nil or not in the list, the mainline set is empty and
column 0 is an ordinary column.

**State.** `lanes: [Lane?]`, where `Lane` is `(target: String, colorIndex: Int)`. Each non-nil
slot is an edge travelling down that column toward its target commit. Several slots may share a
target. When the mainline set is non-empty, slot 0 starts as `(mainlineTip, 0)`. A color counter
starts at 1.

**Per commit C at row r:**

1. *Column and color.*
   - C is mainline → column 0, color 0.
   - Else if any slot targets C → the leftmost such slot; its color.
   - Else (a tip with no child in the list) → the leftmost nil slot at index ≥ 1 (or ≥ 0 when
     there is no mainline), appending if none; color = next palette color (see step 3).
2. *Upper half.* For every slot targeting C: a segment `slot → column` in that slot's color,
   then the slot becomes nil. For every other non-nil slot: a straight segment `slot → slot`.
3. *Lower half.* For each non-nil slot that step 2 left alone: a straight segment `slot → slot`.
   Then for each parent P of C, in order (index i):
   - C is mainline and i == 0 → slot 0 becomes `(P, 0)`; segment `0 → 0`.
   - Else if a slot already targets P → segment `column → thatSlot` in that slot's color. The
     leftmost such slot wins.
   - Else if i == 0 and slot `column` is nil (and `column != 0` or there is no mainline) →
     slot `column` becomes `(P, C's color)`; segment `column → column`.
   - Else → the leftmost nil slot at index ≥ 1 (≥ 0 without a mainline) becomes
     `(P, nextColor())`; segment `column → slot`.
   `nextColor()` returns the counter and advances it. Color indices are unbounded here; the app
   maps them onto its palette (§3), keeping 0 for the mainline.
   Segments are appended in slot order for straight lanes, then parent order.
4. *Trim.* Drop trailing nil slots.
5. Emit `GraphRow(column, colorIndex, isMerge: parentSHAs.count > 1, upper, lower)`.

A parent that never appears (beyond `limit`, or a shallow clone boundary) keeps its slot to the
end, so its lane runs straight off the bottom of the last row. A root commit emits no
lower-half segments from its dot.

**Visual rules this produces** (matching the mockup):

- An unmerged branch whose parent is the next mainline commit curves into column 0 directly
  below its dot.
- A merge commit's second parent opens a new column with a curve directly below the merge dot.
- A side branch cut from an older mainline commit stays in its own column past the mainline
  commits in between, then curves into its parent's dot in the parent's upper half, so
  intervening mainline commits never look like its ancestors.
- Two branches off the same parent share a lane from the second branch's dot down.

The mockup places `fix/arrival-sort` in column 3 and `release/2.9` in column 2; this algorithm
packs them into column 1. Otherwise it reproduces the mockup's lanes.

## 3. App

### `RepositoryStore`

- `history: [HistoryEntry]`.
- `selectedCommit` becomes `history.first { $0.commit.sha == selectedCommitSHA }?.commit`.
- `fetch()` calls `reloadHistory()` after `refresh()`, on both `.upToDate` and `.updated`.
- New stored `graphLaneCount: Int` = `min(8, 1 + max over rows of column and every segment's
  from/to)`, set in `reloadHistory()` so it isn't recomputed per render.

### `HistoryList`

- `ForEach(store.history)` tags each row with `entry.commit.sha`.
- Header: "History" left; "All branches · N" right (11pt, tertiary).
- Empty state unchanged except description: "Commits on any branch will appear here."
- Rows: `.listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))` so graph
  segments meet across row boundaries.

### `CommitRow` (34pt tall)

```
[GraphColumn][8pt][ badges… summary                      ]
                  [ sha · author · date                  ]
```

- Line 1: up to 3 `RefBadge`s, 4pt apart, then `summary` (13pt medium, one line, truncating
  tail). Badges use `.fixedSize()` so only the summary truncates. More than 3 refs → a fourth
  neutral badge `+N` with `.help` listing the hidden names.
- Line 2: `shortSHA · authorName · CommitDate(date)` (11pt, secondary, one line). Full author
  name, not a derived first name.
- Accessibility: the row combines to one element labelled
  "summary, on ref, ref, …, author, date"; `GraphColumn` is `.accessibilityHidden(true)`.

### `GraphColumn`

A `Canvas` of width `8 + 10 × laneCount`, full row height.

- Column c's x center: `9 + 10c`; dot y center: `height / 2`.
- Segment path: from `(x(from), top)` to `(x(to), midY)` for upper, `(x(from), midY)` to
  `(x(to), bottom)` for lower. Equal columns → a straight line. Different columns → a cubic
  Bézier with control points at the vertical midpoint of the half, at the start and end x, so
  tangents are vertical at both ends.
- Stroke 1.5pt, round caps.
- Dot: 8pt circle. Merge dots are an 8pt ring with a 1.5pt stroke, filled with the list background
  (`Color(nsColor: .controlBackgroundColor)` normally; the selection color when selected).
  Lines are drawn first, dot last.
- Columns ≥ `laneCount` are not drawn (clip at the 8-lane cap).
- To prevent hairline gaps between rows, lines extend 1pt above the top and below the bottom
  edge; if the offscreen render still shows gaps, the canvas gets `.padding(.vertical, -2)` and
  draws into the overhang.

### Lane palette (`GraphPalette`)

`[.blue, .purple, .teal, .orange, .green, .pink, .brown]`. `GraphPalette.color(for: index)`
returns `.blue` for 0 and `palette[1 + (index - 1) % 6]` otherwise, so the mainline's blue is
never reused. System colors, so light and dark appearance adapt.

### `RefBadge`

Rounded rectangle, corner radius 4, height 16, horizontal padding 5, 11pt semibold text, one line.

| Kind | Normal | Selected (prominence `.increased`) |
| --- | --- | --- |
| Current local branch | fill = lane color, text white | fill white, text accent color |
| Other local branch | 1pt stroke + text in lane color | 1pt white stroke, white text |
| Remote branch | 1pt `.tertiary` stroke, `.secondary` text | 1pt white 70% stroke, white 70% text |
| Tag | fill indigo 15%, text indigo | fill white 25%, white text |
| `+N` overflow | 1pt `.tertiary` stroke, `.secondary` text | as remote |

"Lane color" is the row's dot color, so a branch badge always matches its tip's lane.

### Selected rows

`GraphColumn`, `RefBadge`, and line-2 text read `@Environment(\.backgroundProminence)`. When
`.increased`: dots white, lines white at 70% opacity, merge ring filled with the accent color,
badges per the table above. Otherwise normal colors.

### `CommitDate`

`enum CommitDate { static func string(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String }`

- Same day as `now` → "Today at <time>".
- Previous day → "Yesterday at <time>".
- Same year → "<abbreviated month> <day> at <time>" (e.g. "Sep 14 at 11:02").
- Earlier year → "<abbreviated month> <day>, <year> at <time>".
- `<time>` is `date.formatted(date: .omitted, time: .shortened)`, which follows the locale's 12/24-
  hour setting. Month/day use `Date.FormatStyle` with `.month(.abbreviated).day()` (plus
  `.year()`), so field order follows the locale; "Today"/"Yesterday"/"at" are localizable strings.
- `CommitDetailPane` uses it instead of `.relative(presentation: .named)`.

## 4. Testing

### GitCore (`swift test`, system `git` as oracle)

`HistoryTests` (extends the existing history coverage in `CommitTests`):

- A commit reachable only from a second local branch appears.
- A commit reachable only from a lightweight tag appears; same for an annotated tag.
- A commit reachable only from `origin/main` appears (fixture: bare remote + fetch); a commit on
  some other `origin/x` branch does not.
- Merge commit `parentSHAs` equal `git rev-parse <sha>^1 <sha>^2`.
- Labels: the current branch is `.localBranch(isCurrent: true)`; label order within a commit is
  current, local, remote, tag; an annotated tag labels the commit, not the tag object.
- Detached HEAD at a commit no branch reaches: the commit appears.
- The walk still stops at `limit`.

`GraphLayoutTests` (hand-built `CommitSummary` lists, no repository):

- Linear history: every row column 0; straight upper/lower segments; first row has no upper
  segment; root has no lower segment from its dot.
- Unmerged tip above the mainline tip: tip in column 1 with a new color; lower segment `1 → 0`.
- Merge: `isMerge`; lower segments `0 → 0` and `0 → 1`; the second-parent chain sits in column 1.
- Side branch cut from a mainline commit three rows down: straight `k → k` through intermediate
  rows, upper `k → 0` at the parent.
- Two tips sharing a parent: second tip's lower segment curves into the first's slot.
- Column reuse: after a lane closes, the next new tip takes the freed column.
- Parent absent from the list: lane still present in the last row's lower half.
- `mainlineTip` nil: column 0 is used by ordinary tips.
- Colors: mainline always 0; new lanes get 1, 2, 3, … in the order they open; a lane that
  continues in its column keeps its color.

### App (`YAGitTests`)

- Update `history[0].sha` / `.summary` accesses to `history[0].commit…`.
- `createBranchSwitchAndFetch`: after switching to `main`, history contains the commits of
  `main` and of the other branches; assert on membership and on the first mainline entry rather
  than the exact list.
- `CommitDateTests` with a fixed `now` and a `calendar` whose locale is set explicitly: today,
  yesterday, same year, earlier year in `en_US`; 24-hour time in `en_GB`.
- `GraphPaletteTests`: index 0 is blue; indices 1…6 map to distinct non-blue colors; 7 maps
  back to index 1's color.
- Offscreen render (existing `NSWindow` + `cacheDisplay` harness) of `HistoryList` against a
  scripted fixture mirroring the mockup: `main` with two merged PRs, unmerged
  `feature/trip-planner` (current), `fix/arrival-sort`, `release/2.9`, tags `v2.7.0`, `v2.7.1`,
  `v2.8.1`, and `origin/main`. Render light, dark, and with a row selected; PNGs to
  `$TMPDIR/yagit-screens` for visual comparison against the mockup. Check lane continuity
  between rows specifically.

## 5. Risks

- **Row gaps.** macOS `List` may inset row content vertically even with zero row insets, breaking
  lane continuity. Mitigation in `GraphColumn` above; verified by the offscreen render.
- **Wide graphs.** Repositories with many concurrent branches exceed 8 lanes; lanes past the cap
  are clipped rather than widening the pane.
- **Walk cost.** Pushing all tags on a repository with thousands of tags adds ref iteration
  time; the walk is still bounded by `limit`, and runs on the `GitRepository` actor.
