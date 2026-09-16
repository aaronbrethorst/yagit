import GitCore
import SwiftUI

/// Detail pane in History mode: commit heading and the read-only diff of the selected file.
struct CommitDetailPane: View {
    @Bindable var store: RepositoryStore
    @AppStorage("diffViewStyle") private var style: DiffViewStyle = .unified

    var body: some View {
        if let commit = store.selectedCommit {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(commit.summary)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                    Text("\(commit.shortSHA) · \(commit.authorName) · \(CommitDate.string(for: commit.date))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
                Divider()
                if let diff = store.selectedCommitDiff {
                    DiffHeader(path: diff.path, additions: diff.additions, deletions: diff.deletions, style: $style) {
                        EmptyView()
                    }
                    Divider()
                    DiffBody(diff: diff, style: style, hunkAction: nil)
                } else if store.commitDetail?.files.isEmpty == true {
                    ContentUnavailableView("No file changes", systemImage: "doc",
                                           description: Text("This commit doesn't change any files."))
                } else {
                    Spacer()
                }
            }
        } else {
            ContentUnavailableView {
                Text("Select a commit to see what changed.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
