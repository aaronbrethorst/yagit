import GitCore
import SwiftUI

/// The files touched by the selected commit, listed between History and the diff.
struct CommitFilesList: View {
    @Bindable var store: RepositoryStore
    var focus: FocusState<RepositoryStore.Pane?>.Binding

    var body: some View {
        List(selection: selection) {
            Section {
                ForEach(store.commitDetail?.files ?? []) { file in
                    CommitFileRow(file: file)
                        .tag(file.path)
                }
            } header: {
                HStack(spacing: 8) {
                    Text("Files")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let files = store.commitDetail?.files {
                        Text(files.count == 1 ? "1 file" : "\(files.count) files")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                .textCase(nil)
                .padding(.vertical, 2)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .overlay {
            if store.selectedCommitSHA == nil {
                EmptyView()
            } else if store.commitDetail == nil {
                ProgressView().controlSize(.small)
            } else if store.commitDetail?.files.isEmpty == true {
                Text("No file changes")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .paneFocus(focus, .commitFiles)
        .claimsPaneFocus(store, .commitFiles)
    }

    private var selection: Binding<String?> {
        Binding(get: { store.selectedCommitFile }, set: {
            store.requestFocus(.commitFiles)
            store.selectedCommitFile = $0
        })
    }
}

/// Status letter, file name, directory, and the file's +/− counts.
private struct CommitFileRow: View {
    let file: FileDiff

    var body: some View {
        HStack(spacing: 8) {
            StatusLetter(status: file.status)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.fileName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.directory.isEmpty ? "—" : file.directory)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text("+\(file.additions)").foregroundStyle(.green)
                Text("−\(file.deletions)").foregroundStyle(.red)
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
        }
        .frame(height: 38)
        .padding(.vertical, 2)
        .help(file.path)
    }
}
