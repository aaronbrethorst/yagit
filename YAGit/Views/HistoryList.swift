import GitCore
import SwiftUI

/// One row per commit on any branch, with the lane graph drawn down the leading edge.
struct HistoryList: View {
    @Bindable var store: RepositoryStore
    var focus: FocusState<RepositoryStore.Pane?>.Binding
    @State private var width: CGFloat = 0

    var body: some View {
        // A narrow column gives up outer lanes rather than the summary; every row uses the same count.
        let laneCount = GraphColumn.laneCount(fitting: width, of: store.graphLaneCount)
        List(selection: selection) {
            Section {
                ForEach(store.history) { entry in
                    CommitRow(entry: entry, laneCount: laneCount)
                        .tag(entry.commit.sha)
                        // Zero vertical insets put rows exactly edge to edge, so lanes meet between rows.
                        // The table already keeps 8pt leading and 9pt trailing; more only starves the summary.
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }
            } header: {
                HStack(spacing: 8) {
                    Text("History")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("All branches · \(store.history.count)\(store.isHistoryTruncated ? "+" : "")")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .textCase(nil)
                .padding(.vertical, 2)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .overlay {
            if store.history.isEmpty {
                ContentUnavailableView("No commits yet", systemImage: "clock",
                                       description: Text("Commits on any branch will appear here."))
            }
        }
        .navigationSplitViewColumnWidth(min: 280, ideal: 326, max: 480)
        .paneFocus(focus, .list)
        .claimsPaneFocus(store, .list)
    }

    private var selection: Binding<String?> {
        Binding(get: { store.selectedCommitSHA }, set: {
            store.requestFocus(.list)
            store.selectCommit(sha: $0)
        })
    }
}
