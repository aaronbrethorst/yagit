# YAGit MVP — Implementation Plan

Companion to `docs/superpowers/specs/2026-09-15-git-client-mvp-design.md`.
Build commands (Xcode is not the selected developer dir on this machine):

```sh
export DEVELOPER_DIR=/Applications/Xcode-27.0.0.app/Contents/Developer
(cd GitCore && swift test)                                   # core, fast
xcodebuild -project YAGit.xcodeproj -scheme YAGit build      # app
```

Each task is TDD: failing test → minimal code → green → commit.

## Task 1 — GitCore scaffolding
- [x] `GitCore/Package.swift` depending on `libgit2` 1.9.2; smoke test that links libgit2.
- [ ] `TestRepository` helper in tests: creates a temp dir, runs system `git` for fixtures
      (`init`, `config user.*`, `add`, `commit`, `branch`, bare remote for `origin`).

## Task 2 — Models + open + snapshot
- [ ] Models file. `GitError` from `git_error_last()`.
- [ ] `GitRepository.init(url:)`, `snapshot()`: current branch, local branches with ahead
      counts, `origin/*` remote branches, staged/unstaged `ChangedFile`s, author.
- Tests: clean repo → empty lists; modified/added/deleted in worktree → unstaged with the
  right status letters; `git add` → staged; both-sides file appears twice.

## Task 3 — Diffs
- [ ] `diff(path:side:)` producing hunks with both gutters; `+`/`−` totals; binary flag;
      untracked file content as one hunk of additions.
- Tests: two-hunk modification → 2 hunks, line numbers match `git diff` header ranges;
  untracked file → one hunk, all additions.

## Task 4 — Staging
- [ ] `stage(path:)`, `unstage(path:)` whole-file.
- [ ] `stageHunk`, `unstageHunk` via constructed patch + `git_apply` to index.
- Tests: stage hunk 1 of 2 → file appears in both lists, staged diff has 1 hunk, unstaged
  has 1; unstage it → back to start; stage/unstage added and deleted files; no-newline EOF.

## Task 5 — Commit + history
- [ ] `commit(message:)` from index tree with configured author, updates HEAD;
      `history()` via revwalk; `commitDetail(sha:)`.
- Tests: partial-hunk commit contains only the staged hunk (verify with `git show`); message,
  author, short SHA; history order newest first; detail files with +/−.

## Task 6 — Branches + fetch
- [ ] `switchBranch`, `createBranch` (duplicate → `GitError`), `fetch()` with
      before/after OID comparison.
- Tests: create → current, history copied; switch resets; duplicate refused; ahead count
  after committing on a branch that tracks a bare origin; fetch reports up-to-date/updated.

## Task 7 — Xcode wiring
- [ ] Add local package reference + product dependency in `project.pbxproj`; sandbox off;
      remove SwiftData `Item`.
- [ ] `RepositoryStore` + `RepositoryWindow` skeleton that opens a repo and shows the sidebar.
- Verify: `xcodebuild build`, launch, window appears.

## Task 8 — Changes mode UI
- [ ] `ChangesList`, `CommitBox`, `DiffPane`, `DiffBody` (unified + split), staging actions,
      status bar messages.

## Task 9 — History mode UI
- [ ] `HistoryList`, `CommitDetailPane` with file chips.

## Task 10 — Branching + fetch UI
- [ ] Toolbar branch menu, `NewBranchSheet`, fetch with spinner, commands.

## Task 11 — Verification
- [ ] `swift test` green; `xcodebuild build` clean; launch against this repo and exercise
      stage-hunk → commit → history; screenshots.
