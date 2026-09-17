import GitCore
import SwiftUI

/// Workspace / Branches / Remotes. Workspace rows drive the list column. Branch rows only select;
/// checking out is an explicit "Make Branch Active" from the row's context menu or the Repository
/// menu, so a stray click can't change what's on disk.
struct SidebarView: View {
    @Bindable var store: RepositoryStore
    var focus: FocusState<RepositoryStore.Pane?>.Binding

    /// One selectable thing in the sidebar. Remote rows aren't selectable.
    enum Item: Hashable {
        case mode(RepositoryStore.Mode)
        case branch(String)
    }

    var body: some View {
        List(selection: selection) {
            Section("Workspace") {
                Label("Changes", systemImage: "pencil.line")
                    .badge(store.changedFileCount)
                    .tag(Item.mode(.changes))
                    .frame(height: 24)
                Label("History", systemImage: "clock")
                    .tag(Item.mode(.history))
                    .frame(height: 24)
            }
            Section("Branches") {
                ForEach(store.branches) { branch in
                    BranchRow(branch: branch)
                        .tag(Item.branch(branch.name))
                        .contextMenu {
                            Button("Make Branch Active") {
                                store.selectedBranchName = branch.name
                                store.makeSelectedBranchActive()
                            }
                            .disabled(branch.isCurrent)
                        }
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

    /// A branch selection leaves `store.mode` alone so the content column keeps showing what it
    /// was; a mode selection clears the branch highlight.
    private var selection: Binding<Item?> {
        Binding(
            get: { store.selectedBranchName.map(Item.branch) ?? .mode(store.mode) },
            set: {
                switch $0 {
                case .mode(let mode):
                    store.mode = mode
                    store.selectedBranchName = nil
                case .branch(let name):
                    store.selectedBranchName = name
                case nil:
                    return
                }
                store.requestFocus(.sidebar)
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
        .help(branch.isCurrent ? "Current branch" : "Control-click to make \(branch.name) active")
    }
}
