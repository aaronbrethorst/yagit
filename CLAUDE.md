# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

YAGit is a native macOS-only Git client (SwiftUI, macOS 27, Xcode 27) that deliberately does
less. Read the Goals in `README.md` before proposing features: the bar is "nearly every Git user
needs it fifty times a day". Push/pull, discard, stash, merge, rebase, amend, tag operations,
submodules, blame, and line-level staging are intentionally absent.

## Commands

```sh
# App (Xcode project, scheme YAGit)
xcodebuild -project YAGit.xcodeproj -scheme YAGit build
xcodebuild -project YAGit.xcodeproj -scheme YAGit -destination 'platform=macOS' test
xcodebuild -project YAGit.xcodeproj -scheme YAGit -destination 'platform=macOS' test \
  -only-testing:YAGitTests/HistoryGraphTests            # one suite

# GitCore (standalone SwiftPM package; fastest loop for Git logic)
cd GitCore
swift build
swift test
swift test --filter StagingTests                        # one suite
swift test --filter StagingTests/stagingOneOfTwoHunksSplitsTheFileAcrossBothSides   # one test

# Manual perf probe on a real repository (skipped unless the env var is set)
YAGIT_TIMING_REPO=/path/to/repo swift test --filter HistoryTimingTests
```

Tests use Swift Testing (`@Suite`/`@Test`/`#expect`), except the placeholder UI test target
which is XCTest. Tests shell out to the system `git` binary as an independent oracle, so `git`
must be on `PATH`. The GitCore scheme also exists in the Xcode project if you prefer Xcode.

## Architecture

Two layers sharing one libgit2 handle:

```
YAGit (app)          RepositoryStore   @MainActor @Observable   UI state; every intent → actor → re-snapshot
GitCore (package)    GitRepository     actor                    one libgit2 repo pointer; all Git operations
                     libgit2           SwiftPM, ibrahimcetin/libgit2 pinned exactly at 1.9.2
```

**GitCore** (`GitCore/Sources/GitCore/`)
- `GitRepository.swift` holds the actor, the `repo` pointer, and shared helpers (`check`,
  `index()`, `headCommit()`, `withStrArray`). Each operation family is an extension file:
  `+Snapshot`, `+Staging`, `+Diff`, `+Commit`, `+History`, `+Branches`.
- `Models.swift` is entirely `Sendable` value types; the app never touches libgit2 types.
- `GraphLayout.swift` is pure (no libgit2): turns a topologically ordered `[CommitSummary]` into
  lane `GraphRow`s. Mainline (first-parent chain from `main`/`master`/`origin/main`/HEAD) is
  always column 0 and color 0. It is unit-tested directly in `GraphLayoutTests`.
- Hunk staging builds a minimal unified patch from the `DiffHunk` the UI showed and applies it
  with `git_apply` at `GIT_APPLY_LOCATION_INDEX`; unstaging applies the reversed hunk. This only
  works because the index is unchanged between diff and apply, so keep that invariant.
  Untracked/added/deleted files delegate hunk operations to the whole-file path.
- `index()` always re-reads from disk so external `git` invocations are seen.
- `history()` walks HEAD, all local branches, only `origin/main` + `origin/<current>`, and all
  tags, capped at `GitRepository.historyLimit`. Tags are display-only.
- libgit2 errors surface as `GitError` built from `git_error_last()`.

**App** (`YAGit/`)
- `YAGitApp.swift`: `WindowGroup(for: URL.self)`, one window per repository; `WelcomeView`
  reopens the last repository from `UserDefaults`. Menu commands (`RepositoryCommands`) reach the
  frontmost window's store through a `@FocusedValue`.
- `RepositoryStore.swift`: all mutations go through `run(_:success:then:_:)`, which awaits the
  actor, calls `refresh()` to re-snapshot, and writes a status-bar line. Never mutate cached lists
  locally; re-read from the actor so the UI reflects the real index.
- `Views/`: `RepositoryWindow` composes sidebar / list / diff panes. `PaneFocus.swift` explains
  the focus workaround: macOS `List` doesn't move first responder on click, so panes claim focus
  via a simultaneous tap gesture and `store.requestFocus(_:)`.
- The Stage/Unstage menu item's key equivalent is a bare Space. `canToggleSelectedFile` must be
  false whenever any text field has focus, or typing a space triggers staging. Any new text
  input must report its focus to the store (see `isEditingCommitMessage`).

**Build settings worth knowing**
- App Sandbox is off on purpose (real `~/.gitconfig`, SSH keys, credential helpers). Hardened
  runtime stays on.
- App target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency;
  GitCore is a Swift 6 package with explicit isolation.

## Tests

- `GitCore/Tests/GitCoreTests/TestRepository.swift` and `YAGitTests/TestRepository.swift` are
  near-identical copies of the throwaway-repo fixture (the GitCore one adds date-pinned commits).
  Change both when changing one.
- Pattern: build state with `fixture.git(...)`, act through `GitRepository`, then assert both on
  the Swift result and on `fixture.git("diff", "--cached", ...)` output as the oracle.

## Design docs

`docs/superpowers/specs/` holds the design documents (MVP, history graph) and
`docs/superpowers/plans/` the implementation plans. The specs record *why* choices were made
(for example why libgit2 is wrapped directly instead of using SwiftGitX) and are the source of
truth for intended behavior; update them when behavior changes.
