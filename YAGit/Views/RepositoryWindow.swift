import GitCore
import SwiftUI

/// The single window for one repository: sidebar, list column, detail pane, status bar.
struct RepositoryWindow: View {
    let url: URL
    @State private var store: RepositoryStore?
    @State private var openFailure: String?

    var body: some View {
        Group {
            if let store {
                RepositoryContent(store: store)
            } else if let openFailure {
                ContentUnavailableView("Couldn't open repository", systemImage: "exclamationmark.triangle",
                                       description: Text(openFailure))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(url.lastPathComponent)
        .navigationDocument(url)
        .task {
            do {
                let store = try RepositoryStore(url: url)
                self.store = store
                await store.load()
            } catch {
                openFailure = error.localizedDescription
            }
        }
    }
}

struct RepositoryContent: View {
    @Bindable var store: RepositoryStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @FocusState private var focusedPane: RepositoryStore.Pane?

    var body: some View {
        VStack(spacing: 0) {
            splitView
            StatusBar(store: store)
        }
        .sheet(isPresented: $store.isPresentingNewBranch) { NewBranchSheet(store: store) }
        .focusedSceneValue(\.repositoryStore, store)
        .frame(minWidth: 900, minHeight: 480)
        // Keep the store and the real first responder in step in both directions: clicks and
        // programmatic moves push into @FocusState, Tab pushes back out.
        .onAppear { focusedPane = store.focusedPane }
        .onChange(of: store.focusedPane) { _, pane in
            if focusedPane != pane { focusedPane = pane }
        }
        .onChange(of: store.focusRequestCount) {
            focusedPane = store.focusedPane
        }
        .onChange(of: focusedPane) { _, pane in
            if let pane, store.focusedPane != pane { store.focusedPane = pane }
        }
        // Switching modes rebuilds the content column and retires the commit-files column, so
        // focus can be left on a view that no longer exists. Re-assert it once the new lists are
        // in the tree — the sidebar survives the switch, so focus there is left alone.
        //
        // A focus request whose target list is not in the window yet is dropped, not queued, and
        // the incoming list's table lands a few frames after the outgoing one is torn down. So ask
        // repeatedly until the focus state confirms the move, instead of once after a yield.
        .task(id: store.mode) {
            if store.mode == .changes, store.focusedPane == .commitFiles { store.focusedPane = .list }
            guard store.focusedPane != .sidebar else { return }
            let pane = store.focusedPane
            focusedPane = nil
            // The read lags the request until SwiftUI's next update; wait for the release to land
            // so the confirmation below can't be satisfied by the stale pre-switch value.
            for _ in 0..<20 where focusedPane != nil {
                try? await Task.sleep(for: .milliseconds(30))
                if Task.isCancelled { return }
            }
            for _ in 0..<20 {
                focusedPane = pane
                try? await Task.sleep(for: .milliseconds(30))
                if Task.isCancelled || focusedPane == pane { return }
            }
        }
    }

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(store: store, focus: $focusedPane)
                .navigationSplitViewColumnWidth(min: 180, ideal: 212, max: 320)
        } content: {
            switch store.mode {
            case .changes: ChangesList(store: store, focus: $focusedPane)
            case .history: HistoryList(store: store, focus: $focusedPane)
            }
        } detail: {
            switch store.mode {
            case .changes:
                DiffPane(store: store)
            case .history:
                // Files get their own column so a large commit lists cleanly instead of wrapping into chips.
                // HSplitView lays its children out at their ideal height, not its own, so a child with a
                // finite ideal height (the binary-file placeholder) would collapse the whole split.
                HSplitView {
                    CommitFilesList(store: store, focus: $focusedPane)
                        .frame(minWidth: 180, idealWidth: 216, maxWidth: 360, maxHeight: .infinity)
                    CommitDetailPane(store: store)
                        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar { RepositoryToolbar(store: store) }
    }
}

/// Branch pop-up, Fetch, New Branch.
struct RepositoryToolbar: ToolbarContent {
    @Bindable var store: RepositoryStore

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Menu {
                Section("Branches") {
                    ForEach(store.branches) { branch in
                        Button {
                            store.switchBranch(named: branch.name)
                        } label: {
                            if branch.isCurrent {
                                Label(branch.name, systemImage: "checkmark")
                            } else {
                                Text(branch.name)
                            }
                        }
                    }
                }
                Divider()
                Button("New Branch…") { store.isPresentingNewBranch = true }
            } label: {
                Label(store.currentBranch, systemImage: "arrow.triangle.branch")
                    .labelStyle(.titleAndIcon)
            }
            .help("Switch branch")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                store.fetch()
            } label: {
                Label("Fetch", systemImage: "arrow.clockwise")
            }
            .help("Fetch origin")
            .disabled(store.isFetching)
            Button {
                store.isPresentingNewBranch = true
            } label: {
                Label("New Branch", systemImage: "plus")
            }
            .help("New Branch…")
        }
    }
}
