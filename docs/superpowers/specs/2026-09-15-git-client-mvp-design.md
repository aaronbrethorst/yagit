# YAGit MVP — Design

Date: 2026-09-15. Source of truth for behavior is the functional spec supplied with the task
(derived from the `Git Client.dc.html` prototype). This document records how that spec maps onto
the codebase. The prototype itself could not be imported from this session (the design MCP
needs an interactive `/design-login`), so visual details follow the written spec.

## 1. Architecture

Two layers, one repository handle:

```
YAGit (app, SwiftUI, macOS 27)
  └─ RepositoryStore  @MainActor @Observable   — UI state + intent → GitRepository
       └─ GitCore (local Swift package)
            └─ GitRepository  actor             — one libgit2 handle, all git operations
                 └─ libgit2 (SwiftPM, ibrahimcetin/libgit2 1.9.2)
```

**Why libgit2 directly instead of SwiftGitX.** The project already pulls SwiftGitX, but it
cannot do what the spec needs: it frees `git_diff` pointers immediately (so `git_apply` cannot
be used for hunk staging), collapses old/new line numbers into one field (the unified view
needs both gutters), has no ahead/behind, and hides the repository pointer, which forces a
second handle and stale-index hazards. `GitCore` wraps libgit2 itself in ~600 lines, is fully
testable with `swift test` against throwaway repositories, and keeps one handle. The SwiftGitX
package reference is left in the Xcode project untouched.

**Sandbox.** The app sandbox is turned off. A git client must read the user's real
`~/.gitconfig`, SSH keys, credential helpers and arbitrary repository paths; the sandboxed
container home breaks all of those. Hardened runtime stays on.

## 2. GitCore

### Models (all `Sendable` value types)

| Type | Fields |
| --- | --- |
| `ChangeSide` | `.staged`, `.unstaged` |
| `FileStatus` | `.modified`, `.added`, `.deleted` |
| `ChangedFile` | `path`, `status`, `side`; `id = "\(side):\(path)"` |
| `DiffLine` | `kind` (context/addition/deletion), `oldLineNumber?`, `newLineNumber?`, `text`, `missingTrailingNewline` |
| `DiffHunk` | `index`, `header`, `oldStart`, `oldLines`, `newStart`, `newLines`, `lines` |
| `FileDiff` | `path`, `status`, `isBinary`, `additions`, `deletions`, `hunks` |
| `BranchInfo` | `name`, `isCurrent`, `ahead: Int?` (nil = no upstream) |
| `CommitSummary` | `sha`, `shortSHA`, `summary`, `message`, `authorName`, `authorEmail`, `date` |
| `CommitDetail` | `commit`, `files: [FileDiff]` |
| `Author` | `name`, `email` |
| `RepositorySnapshot` | `currentBranch`, `branches`, `remoteBranches`, `staged`, `unstaged`, `author` |
| `FetchResult` | `.upToDate`, `.updated` |
| `GitError` | `code`, `message`, `operation` — wraps `git_error_last()` |

### `GitRepository` (actor)

```swift
init(url: URL) throws(GitError)                   // open only, never create
func snapshot() throws -> RepositorySnapshot
func diff(path: String, side: ChangeSide) throws -> FileDiff?
func stage(path:)   / unstage(path:)              // whole file, one side
func stageHunk(path:, hunk: DiffHunk) / unstageHunk(path:, hunk: DiffHunk)
func commit(message: String) throws -> CommitSummary
func history() throws -> [CommitSummary]          // current branch, newest first
func commitDetail(sha: String) throws -> CommitDetail
func switchBranch(named:) throws
func createBranch(named:) throws                  // from HEAD, then checks it out; refuses duplicates
func fetch() async throws -> FetchResult          // origin; compares remote ref OIDs before/after
```

### How staging works

- **Whole file, unstaged → staged:** `git_index_add_bypath` if the file exists in the working
  tree, else `git_index_remove_bypath`; then `git_index_write`.
- **Whole file, staged → unstaged:** `git_reset_default(HEAD, pathspec)`, i.e. `git reset -- path`.
- **Single hunk:** build a minimal unified patch from the `DiffHunk` the UI displayed
  (`diff --git`, `---`/`+++`, one `@@` header, its lines, `\ No newline at end of file` where
  needed), parse it with `git_diff_from_buffer`, apply with
  `git_apply(..., GIT_APPLY_LOCATION_INDEX)`. Unstaging emits the *reversed* hunk (swap
  +/− and the two ranges) and applies it the same way. Because the preimage (the index) is
  unchanged when one hunk is applied alone, the hunk's `oldStart` is exact and libgit2's
  strict line matching succeeds. Untracked, added-in-index and deleted files always have
  exactly one hunk, so their hunk operations delegate to the whole-file path.
- After any index mutation the store re-snapshots; a file with hunks on both sides appears
  in both lists, as the spec requires.

### Diffs

- Unstaged side: `git_diff_index_to_workdir` with `INCLUDE_UNTRACKED | SHOW_UNTRACKED_CONTENT`
  and a single-path pathspec.
- Staged side: `git_diff_tree_to_index(HEAD tree, index)`, same pathspec.
- Commit: `git_diff_tree_to_tree(parent tree or empty, commit tree)`.
- No rename detection (a rename shows as D + A). Binary deltas yield `isBinary` and no hunks.
- Line numbers are computed while walking each hunk from `oldStart`/`newStart` so both
  gutters are always filled.

### Ahead counts

For each local branch, upstream via `git_branch_upstream`, falling back to
`refs/remotes/origin/<name>`; then `git_graph_ahead_behind`. No upstream → `nil` and the UI
shows no badge and `· not on origin` in the status bar.

## 3. App

### `RepositoryStore` (`@MainActor @Observable`)

State: `snapshot`, `mode` (changes/history), `selectedChange: ChangedFile.ID?`,
`selectedCommitSHA`, `selectedCommitFile`, `currentDiff: FileDiff?`, `commitDetail`,
`history`, `commitMessage`, `statusText`, `isFetching`, `isPresentingNewBranch`.

Intents (each awaits the actor, then refreshes and writes the status bar; failures land in
`statusText` as `Couldn't <verb>: <message>`): `refresh`, `select(change:)`,
`toggleFile`, `toggleAll(side:)`, `stageHunk`/`unstageHunk`, `commit`, `clearMessage`,
`selectCommit`, `selectCommitFile`, `switchBranch`, `createBranch`, `fetch`.

Selection fallback after commit: first unstaged file, else first staged file, else nil.

### Windows and scenes

- `WindowGroup(for: URL.self)` — one window per repository. App launch opens the last
  repository from `UserDefaults` (plain path, no sandbox bookmark needed); if none or it fails
  to open, `File ▸ Open Repository…` (⌘O) shows an `NSOpenPanel` limited to directories.
- Commands: Open Repository… ⌘O, Fetch ⇧⌘R, New Branch… ⇧⌘N, Make Branch Active (no shortcut),
  Commit ⌘↩ (via the commit box's default action).
- Branch checkout is always explicit. Clicking a sidebar branch only selects it
  (`selectedBranchName`); "Make Branch Active" in the row's context menu or the Repository menu
  performs the checkout, so a stray click can't change the working tree. The toolbar branch pop-up
  is the one-click path. Remote rows are inert.

### Views

| View | Responsibility |
| --- | --- |
| `RepositoryWindow` | `NavigationSplitView` (sidebar 212 / content 326 / detail flexible), toolbar, bottom `StatusBar` via `safeAreaInset`, new-branch sheet. |
| `SidebarView` | Workspace / Branches / Remotes sections, 32pt rows, badges. Selection is a `SidebarView.Item` (mode or branch); branch rows carry a "Make Branch Active" context menu. |
| `ChangesList` | Staged + Unstaged sections with header checkboxes and counts, 42pt rows, `CommitBox` pinned at the bottom. |
| `CommitBox` | Author line, `Description` label, 4-row `TextEditor`, Cancel / Commit. |
| `HistoryList` | 44pt commit rows, header `n commits`. |
| `DiffPane` | Header (path, +/−, Unified/Split segmented control, Stage/Unstage File) + `DiffBody`. |
| `DiffBody` | Hunk header rows with optional Stage/Unstage Hunk button; unified or split renderer; 12pt monospaced, 19pt rows; green 14% / red 12% washes. |
| `CommitDetailPane` | Message (15 semibold), `sha · author · when`, file chips, read-only `DiffBody`. |
| `StatusBar` | 26pt; last action left; spinner + branch + ahead text right. |
| `NewBranchSheet` | Title, explanatory line, name field (`feature/name`), Cancel / Create Branch; Return creates, Escape cancels; disabled while blank. |

Diff view style (Unified/Split) is an `@AppStorage("diffViewStyle")` user preference.

## 4. Testing

- `GitCore` tests (Swift Testing, `swift test`): build throwaway repositories with the system
  `git` as an independent oracle, then assert on snapshots, diffs, hunk staging (stage one of
  two hunks → file in both lists; commit → only that hunk lands), unstage, whole-file stage
  and unstage of added/deleted files, commit metadata and ahead counts, branch create/switch
  (duplicate refused), history per branch.
- App: `xcodebuild build`; a small `RepositoryStore` test in `YAGitTests` covering the commit
  flow against a temp repo.

## 5. Out of scope

Everything in spec §7: push/pull, line-level staging, discard/stash/merge/rebase, tags,
submodules, blame, context expansion, amend.
