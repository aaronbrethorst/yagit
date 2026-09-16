# YAGit

**Yet Another Git client, for macOS only.**

YAGit is a native macOS Git client that deliberately does less. Most graphical Git clients grow by
accretion until every menu is a kitchen sink, and the handful of things you do fifty times a day
end up buried under features you touch once a year. YAGit takes the opposite bet: pick the small
set of operations that nearly every Git user needs, and make each of them fast, obvious, and
unmistakably Mac.

Think of it as SourceTree with a rabid, macOS-only focus.

## Goals

- **Serve the common case extremely well.** Review your changes, stage what you mean to stage
  (whole files or individual hunks), write a commit, browse history, and switch branches. Those
  are the workflows YAGit optimizes for, and they should never feel slower than the command line.
- **Be a real Mac app.** SwiftUI, native windows and menus, standard keyboard shortcuts, full
  keyboard navigation between panes, and the platform's conventions everywhere. No web views, no
  cross-platform toolkit, no "close enough" UI.
- **Prefer subtraction.** Every feature has to earn its place by being useful to a broad audience
  of Git users. If something is rarely used, is better done in a terminal, or would complicate the
  main workflows, it stays out.
- **Stay honest about what's on disk.** YAGit talks to libgit2 directly with a single repository
  handle. What you see is the actual state of the working tree and index, not a cached
  approximation.
- **Respect your existing setup.** The app runs without the App Sandbox so it can use your real
  `~/.gitconfig`, SSH keys, and credential helpers, and open any repository path you like.

## What it does today

- One window per repository, with the last repository reopened on launch.
- Sidebar with workspace, local branches (with ahead-of-upstream badges), and remote branches.
- Changes view listing staged and unstaged files, with per-file and select-all toggles.
- Unified and split diff views with both old and new line numbers.
- Stage and unstage by whole file or by individual hunk.
- Commit box with author, message, and ⌘↩ to commit.
- History view for the current branch, with per-commit file lists and read-only diffs.
- Create and switch branches, and fetch from `origin`.

## What it intentionally leaves out (for now)

Push and pull, line-level staging, discard, stash, merge, rebase, tags, submodules, blame, amend,
and context expansion in diffs. Some of these will arrive once they can be done well. Others will
never arrive, because the terminal already does them better.

## Requirements

- macOS 27 or later
- Xcode 27 or later to build from source

## Building

Clone the repository and open `YAGit.xcodeproj` in Xcode, then build and run the `YAGit` scheme.
Or from the command line:

```sh
xcodebuild -project YAGit.xcodeproj -scheme YAGit build
```

## Project layout

```
YAGit/       SwiftUI app: windows, views, and the RepositoryStore that drives them
GitCore/     Local Swift package wrapping libgit2; all Git operations live here
YAGitTests/  App-level tests
docs/        Design notes and implementation plans
```

`GitCore` is a standalone package and can be built and tested on its own:

```sh
cd GitCore
swift test
```

Its tests create throwaway repositories with the system `git` binary as an independent oracle, so
you'll need `git` on your `PATH`.

## Contributing

Bug reports and pull requests are welcome. Before proposing a feature, please read the goals above.
The most useful contributions are the ones that make the existing workflows sharper, not the ones
that add new ones.

## License

Copyright © 2026 Aaron Brethorst.

YAGit is free software: you can redistribute it and/or modify it under the terms of the
[GNU Affero General Public License](LICENSE) as published by the Free Software Foundation,
either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
Affero General Public License for more details.
