import GitCore
import SwiftUI

/// One row per commit on the current branch.
struct HistoryList: View {
    @Bindable var store: RepositoryStore

    var body: some View {
        List(selection: selection) {
            Section {
                ForEach(store.history) { commit in
                    CommitRow(commit: commit)
                        .tag(commit.sha)
                }
            } header: {
                Text("\(store.history.count) commits")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .overlay {
            if store.history.isEmpty {
                ContentUnavailableView("No commits yet", systemImage: "clock",
                                       description: Text("Commits on this branch will appear here."))
            }
        }
        .navigationSplitViewColumnWidth(min: 280, ideal: 326, max: 480)
    }

    private var selection: Binding<String?> {
        Binding(get: { store.selectedCommitSHA }, set: { store.selectCommit(sha: $0) })
    }
}

private struct CommitRow: View {
    let commit: CommitSummary

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.summary)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text("\(commit.authorName) · \(commit.date, format: .relative(presentation: .named))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(commit.shortSHA)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(height: 40)
        .padding(.vertical, 2)
    }
}
