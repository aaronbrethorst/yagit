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

    var body: some View {
        VStack(spacing: 0) {
            splitView
            StatusBar(store: store)
        }
        .sheet(isPresented: $store.isPresentingNewBranch) { NewBranchSheet(store: store) }
        .focusedSceneValue(\.repositoryStore, store)
        .frame(minWidth: 900, minHeight: 480)
    }

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 180, ideal: 212, max: 320)
        } content: {
            switch store.mode {
            case .changes: ChangesList(store: store)
            case .history: HistoryList(store: store)
            }
        } detail: {
            switch store.mode {
            case .changes:
                DiffPane(store: store)
            case .history:
                // Files get their own column so a large commit lists cleanly instead of wrapping into chips.
                HSplitView {
                    CommitFilesList(store: store)
                        .frame(minWidth: 180, idealWidth: 216, maxWidth: 360)
                    CommitDetailPane(store: store)
                        .frame(minWidth: 320, maxWidth: .infinity)
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
