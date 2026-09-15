import GitCore
import SwiftUI

/// "Create a new branch?" — name field, Cancel / Create Branch.
struct NewBranchSheet: View {
    @Bindable var store: RepositoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var failure: String?
    @State private var isCreating = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create a new branch?")
                .font(.system(size: 15, weight: .semibold))
            Text("The new branch starts at the tip of ‘\(store.currentBranch)’.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            TextField("feature/name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)
            if let failure {
                Text(failure)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create Branch", action: create)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedName.isEmpty || isCreating)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func create() {
        guard !trimmedName.isEmpty, !isCreating else { return }
        isCreating = true
        Task {
            failure = await store.createBranch(named: trimmedName)
            isCreating = false
            if failure == nil { dismiss() }
        }
    }
}
