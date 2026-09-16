import GitCore
import SwiftUI

/// Workspace / Branches / Remotes. Workspace rows drive the list column; branch rows check out.
struct SidebarView: View {
    @Bindable var store: RepositoryStore
    var focus: FocusState<RepositoryStore.Pane?>.Binding

    var body: some View {
        List(selection: modeSelection) {
            Section("Workspace") {
                Label("Changes", systemImage: "pencil.line")
                    .badge(store.changedFileCount)
                    .tag(RepositoryStore.Mode.changes)
                    .frame(height: 24)
                Label("History", systemImage: "clock")
                    .tag(RepositoryStore.Mode.history)
                    .frame(height: 24)
            }
            Section("Branches") {
                ForEach(store.branches) { branch in
                    BranchRow(branch: branch)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.focusedPane = .sidebar
                            store.switchBranch(named: branch.name)
                        }
                        .selectionDisabled()
                }
            }
            Section("Remotes") {
                ForEach(store.snapshot?.remoteBranches ?? [], id: \.self) { name in
                    Label(name, systemImage: "cloud")
                        .frame(height: 24)
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                }
            }
        }
        .listStyle(.sidebar)
        .paneFocus(focus, .sidebar)
        .claimsPaneFocus(store, .sidebar)
    }

    private var modeSelection: Binding<RepositoryStore.Mode?> {
        Binding(
            get: { store.mode },
            set: {
                guard let mode = $0 else { return }
                store.mode = mode
                store.focusedPane = .sidebar
            }
        )
    }
}

private struct BranchRow: View {
    let branch: BranchInfo

    var body: some View {
        Label {
            Text(branch.name)
                .fontWeight(branch.isCurrent ? .semibold : .regular)
        } icon: {
            Image(systemName: branch.isCurrent ? "checkmark.circle.fill" : "arrow.triangle.branch")
                .foregroundStyle(branch.isCurrent ? Color.accentColor : Color.secondary)
        }
        .badge(branch.ahead ?? 0)
        .frame(height: 24)
        .listRowBackground(
            branch.isCurrent
                ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.15))
                : nil
        )
        .help(branch.isCurrent ? "Current branch" : "Check out \(branch.name)")
    }
}
