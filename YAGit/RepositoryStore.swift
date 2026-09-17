import Foundation
import GitCore
import Observation

/// UI state for one repository window. Every intent goes through the `GitRepository` actor,
/// then the store re-reads a snapshot so the lists always reflect the real index.
@MainActor
@Observable
final class RepositoryStore {
    enum Mode: Hashable {
        case changes
        case history
    }

    /// The list the arrow keys act on. Mirrored into a `@FocusState` by `RepositoryContent`
    /// so clicking a row and tabbing between panes both land in the same place.
    enum Pane: Hashable {
        case sidebar
        case list
        case commitFiles
    }

    let url: URL
    let repository: GitRepository

    var snapshot: RepositorySnapshot?
    var mode: Mode = .changes
    var focusedPane: Pane = .list
    /// Whether the commit message editor has keyboard focus; `CommitBox` keeps this current.
    /// `focusedPane` can't answer this — it stays on `.list` while the message is being typed.
    var isEditingCommitMessage = false
    /// Bumped by `requestFocus` so a click can reclaim focus even when `focusedPane` is unchanged,
    /// as after typing a commit message: the pane never left `.list`, but the focus did.
    private(set) var focusRequestCount = 0

    // Changes mode
    var selectedChangeID: ChangedFile.ID?
    var currentDiff: FileDiff?
    var commitMessage = ""

    // History mode
    var history: [HistoryEntry] = []
    /// Graph width in lanes, shared by every row so their text lines up. Capped at `maxGraphLanes`.
    private(set) var graphLaneCount = 0
    /// The walk hit `GitRepository.historyLimit`, so older commits aren't listed.
    private(set) var isHistoryTruncated = false
    static let maxGraphLanes = 8
    var selectedCommitSHA: String?
    var commitDetail: CommitDetail?
    var selectedCommitFile: String?

    // Chrome
    var statusText = ""
    var isFetching = false
    var isPresentingNewBranch = false
    /// A blocking failure (for example the folder is not a repository).
    var loadError: String?

    init(url: URL) throws {
        self.url = url
        repository = try GitRepository(url: url)
    }

    // MARK: - Derived state

    var staged: [ChangedFile] { snapshot?.staged ?? [] }
    var unstaged: [ChangedFile] { snapshot?.unstaged ?? [] }
    var currentBranch: String { snapshot?.currentBranch ?? "" }
    var branches: [BranchInfo] { snapshot?.branches ?? [] }

    /// Distinct paths with any change, for the sidebar badge.
    var changedFileCount: Int { Set((staged + unstaged).map(\.path)).count }

    var selectedChange: ChangedFile? {
        (staged + unstaged).first { $0.id == selectedChangeID }
    }

    var hasStagedChanges: Bool { !staged.isEmpty }

    var canCommit: Bool {
        hasStagedChanges && !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Gates the Changes ▸ Stage/Unstage File menu item. Its key equivalent is a bare Space, which
    /// AppKit hands to an enabled menu item before any text view sees it, so the item must be off
    /// whenever text is being typed. Any new text input must report its focus here too.
    var canToggleSelectedFile: Bool {
        mode == .changes && selectedChange != nil && !isEditingCommitMessage && !isPresentingNewBranch
    }

    var selectedCommit: CommitSummary? { history.first { $0.commit.sha == selectedCommitSHA }?.commit }

    var selectedCommitDiff: FileDiff? {
        commitDetail?.files.first { $0.path == selectedCommitFile }
    }

    func isOnBothSides(_ path: String) -> Bool {
        staged.contains { $0.path == path } && unstaged.contains { $0.path == path }
    }

    // MARK: - Loading

    func load() async {
        statusText = "Opened ‘\(url.lastPathComponent)’"
        await refresh()
        await reloadHistory()
        if selectedChangeID == nil { selectFallbackChange() }
        await reloadDiff()
    }

    /// Re-reads status and branches, keeps the selection valid, reloads the visible diff.
    func refresh() async {
        do {
            snapshot = try await repository.snapshot()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
            return
        }
        if selectedChange == nil { selectFallbackChange() }
        await reloadDiff()
    }

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

    private func reloadDiff() async {
        guard let change = selectedChange else {
            currentDiff = nil
            return
        }
        do {
            currentDiff = try await repository.diff(path: change.path, side: change.side)
        } catch {
            currentDiff = nil
            report("Couldn't read diff", error)
        }
    }

    private func selectFallbackChange() {
        selectedChangeID = unstaged.first?.id ?? staged.first?.id
    }

    // MARK: - Focus

    /// Moves keyboard focus to `pane`, re-asserting it even if the store already points there.
    func requestFocus(_ pane: Pane) {
        focusedPane = pane
        focusRequestCount += 1
    }

    /// The panes the Tab key visits, left to right, when the store orders the loop itself.
    ///
    /// AppKit's automatic key view loop puts the sidebar *after* the list column, so in History
    /// mode Tab jumped from the history list back into the sidebar. In Changes mode the commit
    /// message editor is part of the loop and isn't a pane, so AppKit keeps that one.
    var tabOrder: [Pane]? {
        mode == .history ? [.sidebar, .list, .commitFiles] : nil
    }

    /// Moves focus to the next (or previous) pane in `tabOrder`, wrapping at either end.
    /// Returns false when AppKit should handle the key instead.
    @discardableResult
    func focusAdjacentPane(reverse: Bool) -> Bool {
        guard let order = tabOrder, let index = order.firstIndex(of: focusedPane) else { return false }
        let step = reverse ? order.count - 1 : 1
        requestFocus(order[(index + step) % order.count])
        return true
    }

    // MARK: - Changes intents

    func select(change id: ChangedFile.ID?) {
        selectedChangeID = id
        Task { await reloadDiff() }
    }

    /// Row checkbox: stage or unstage every hunk of that file on that side.
    func toggle(file: ChangedFile, then completion: (() -> Void)? = nil) {
        run(file.side == .unstaged ? "stage \(file.fileName)" : "unstage \(file.fileName)",
            success: file.side == .unstaged ? "Staged \(file.path)" : "Unstaged \(file.path)",
            then: completion) {
            switch file.side {
            case .unstaged: try await self.repository.stage(path: file.path)
            case .staged: try await self.repository.unstage(path: file.path)
            }
        }
    }

    /// Header checkbox: stage or unstage everything on that side.
    func toggleAll(side: ChangeSide) {
        let files = side == .unstaged ? unstaged : staged
        run(side == .unstaged ? "stage all files" : "unstage all files",
            success: side == .unstaged ? "Staged \(files.count) files" : "Unstaged \(files.count) files") {
            for file in files {
                switch side {
                case .unstaged: try await self.repository.stage(path: file.path)
                case .staged: try await self.repository.unstage(path: file.path)
                }
            }
        }
    }

    /// Stage/Unstage File: like the row checkbox, but the selection follows the file to its new
    /// side so pressing Space again moves it straight back.
    func toggleSelectedFile() {
        guard let change = selectedChange else { return }
        let destination = ChangedFile(path: change.path, status: change.status,
                                      side: change.side == .unstaged ? .staged : .unstaged).id
        toggle(file: change) {
            if (self.staged + self.unstaged).contains(where: { $0.id == destination }) {
                self.select(change: destination)
            }
        }
    }

    func stageHunk(_ hunk: DiffHunk) {
        guard let change = selectedChange, let diff = currentDiff, change.side == .unstaged else { return }
        run("stage hunk", success: "Staged hunk \(hunk.index + 1) of \(change.fileName)") {
            try await self.repository.stageHunk(path: change.path, hunk: hunk, fileStatus: diff.status)
        }
    }

    func unstageHunk(_ hunk: DiffHunk) {
        guard let change = selectedChange, let diff = currentDiff, change.side == .staged else { return }
        run("unstage hunk", success: "Unstaged hunk \(hunk.index + 1) of \(change.fileName)") {
            try await self.repository.unstageHunk(path: change.path, hunk: hunk, fileStatus: diff.status)
        }
    }

    func clearMessage() {
        commitMessage = ""
    }

    func commit() {
        guard canCommit else { return }
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let commit = try await repository.commit(message: message)
                commitMessage = ""
                selectedChangeID = nil
                await refresh()
                await reloadHistory()
                statusText = "Committed \(commit.shortSHA) to \(currentBranch)"
            } catch {
                report("Couldn't commit", error)
            }
        }
    }

    // MARK: - History intents

    func selectCommit(sha: String?) {
        selectedCommitSHA = sha
        commitDetail = nil
        selectedCommitFile = nil
        guard let sha else { return }
        Task {
            do {
                let detail = try await repository.commitDetail(sha: sha)
                guard selectedCommitSHA == sha else { return }
                commitDetail = detail
                selectedCommitFile = detail.files.first?.path
            } catch {
                report("Couldn't read commit", error)
            }
        }
    }

    // MARK: - Branch intents

    func switchBranch(named name: String) {
        guard name != currentBranch else { return }
        Task {
            do {
                try await repository.switchBranch(named: name)
                await refresh()
                await reloadHistory()
                statusText = "Switched to branch ‘\(name)’"
            } catch {
                report("Couldn't switch to ‘\(name)’", error)
            }
        }
    }

    /// Creates and checks out a branch. Returns an error message to show in the sheet, or nil.
    func createBranch(named name: String) async -> String? {
        let name = name.trimmingCharacters(in: .whitespaces)
        do {
            try await repository.createBranch(named: name)
            await refresh()
            await reloadHistory()
            statusText = "Created branch ‘\(name)’"
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func fetch() {
        guard !isFetching else { return }
        isFetching = true
        statusText = "Fetching origin…"
        Task {
            defer { isFetching = false }
            do {
                let result = try await repository.fetch()
                await refresh()
                await reloadHistory()
                switch result {
                case .upToDate: statusText = "Fetched origin — already up to date"
                case .updated: statusText = "Fetched origin — remote branches updated"
                }
            } catch {
                report("Couldn't fetch origin", error)
            }
        }
    }

    // MARK: - Helpers

    private func run(_ verb: String, success: String, then completion: (() -> Void)? = nil,
                     _ operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation()
                await refresh()
                statusText = success
                completion?()
            } catch {
                report("Couldn't \(verb)", error)
                await refresh()
            }
        }
    }

    private func report(_ prefix: String, _ error: Error) {
        statusText = "\(prefix): \(error.localizedDescription)"
    }
}
