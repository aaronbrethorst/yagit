import GitCore
import SwiftUI

/// Author line, description field, Cancel / Commit.
struct CommitBox: View {
    @Bindable var store: RepositoryStore
    @FocusState private var isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let author = store.snapshot?.author {
                Text("\(author.name) · \(author.email)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Set user.name and user.email in your git config to commit.")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            Text("Description")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextEditor(text: $store.commitMessage)
                .font(.system(size: 13))
                .frame(height: 4 * 17 + 8)
                .padding(4)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                .focused($isEditing)
            HStack(spacing: 8) {
                Button { store.clearMessage() } label: {
                    Text("Cancel").frame(maxWidth: .infinity)
                }
                .disabled(store.commitMessage.isEmpty)
                Button { store.commit() } label: {
                    Text("Commit").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.canCommit)
            }
            .controlSize(.regular)
        }
        .padding(12)
        .background(.bar)
    }
}
