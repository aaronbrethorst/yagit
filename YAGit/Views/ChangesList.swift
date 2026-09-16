import GitCore
import SwiftUI

/// Split stage: Staged files above Unstaged files, commit box pinned to the bottom.
struct ChangesList: View {
    @Bindable var store: RepositoryStore
    var focus: FocusState<RepositoryStore.Pane?>.Binding

    var body: some View {
        VStack(spacing: 0) {
            if store.staged.isEmpty && store.unstaged.isEmpty {
                ContentUnavailableView("No changes", systemImage: "checkmark.circle",
                                       description: Text("The working tree is clean."))
                    .frame(maxHeight: .infinity)
            } else {
                List(selection: selection) {
                    Section {
                        ForEach(store.staged) { file in
                            FileRow(file: file, checkbox: store.isOnBothSides(file.path) ? .mixed : .on) {
                                store.toggle(file: file)
                            }
                            .tag(file.id)
                        }
                    } header: {
                        SectionHeader(title: "Staged files", count: store.staged.count,
                                      checkbox: stagedHeaderState) { store.toggleAll(side: .staged) }
                    }
                    Section {
                        ForEach(store.unstaged) { file in
                            FileRow(file: file, checkbox: .off) {
                                store.toggle(file: file)
                            }
                            .tag(file.id)
                        }
                    } header: {
                        SectionHeader(title: "Unstaged files", count: store.unstaged.count,
                                      checkbox: unstagedHeaderState) { store.toggleAll(side: .unstaged) }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .paneFocus(focus, .list)
                .claimsPaneFocus(store, .list)
            }
            Divider()
            CommitBox(store: store)
        }
        .navigationSplitViewColumnWidth(min: 280, ideal: 326, max: 480)
    }

    private var selection: Binding<ChangedFile.ID?> {
        Binding(get: { store.selectedChangeID }, set: {
            store.focusedPane = .list
            store.select(change: $0)
        })
    }

    private var stagedHeaderState: CheckboxState {
        if store.staged.isEmpty { return .off }
        return store.unstaged.isEmpty ? .on : .mixed
    }

    private var unstagedHeaderState: CheckboxState {
        if store.unstaged.isEmpty { return .off }
        return store.staged.isEmpty ? .off : .mixed
    }
}

private struct SectionHeader: View {
    let title: String
    let count: Int
    let checkbox: CheckboxState
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Checkbox(state: checkbox, action: action)
                .disabled(count == 0)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .textCase(nil)
        .padding(.vertical, 2)
    }
}

/// Checkbox, file name, left-truncated directory, status letter.
private struct FileRow: View {
    let file: ChangedFile
    let checkbox: CheckboxState
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Checkbox(state: checkbox, action: toggle)
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
            StatusLetter(status: file.status)
        }
        .frame(height: 38)
        .padding(.vertical, 2)
    }
}

struct StatusLetter: View {
    let status: FileStatus

    var body: some View {
        Text(status.rawValue)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: 16)
    }

    private var color: Color {
        switch status {
        case .modified: .secondary
        case .added: .green
        case .deleted: .red
        }
    }
}

enum CheckboxState {
    case off, on, mixed
}

/// A three-state checkbox drawn with symbols so the mixed state is available.
struct Checkbox: View {
    let state: CheckboxState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(state == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state == .off ? "Stage" : "Unstage")
    }

    private var symbol: String {
        switch state {
        case .off: "square"
        case .on: "checkmark.square.fill"
        case .mixed: "minus.square.fill"
        }
    }
}
