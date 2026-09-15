import GitCore
import SwiftUI

enum DiffViewStyle: String, CaseIterable, Identifiable {
    case unified = "Unified"
    case split = "Split"
    var id: String { rawValue }
}

/// Detail pane in Changes mode: header with counts and controls, then the diff body.
struct DiffPane: View {
    @Bindable var store: RepositoryStore
    @AppStorage("diffViewStyle") private var style: DiffViewStyle = .unified

    var body: some View {
        if let change = store.selectedChange, let diff = store.currentDiff {
            VStack(spacing: 0) {
                DiffHeader(path: diff.path, additions: diff.additions, deletions: diff.deletions, style: $style) {
                    Button(change.side == .unstaged ? "Stage File" : "Unstage File") {
                        store.toggleSelectedFile()
                    }
                }
                Divider()
                DiffBody(diff: diff, style: style, hunkAction: hunkAction(for: change))
            }
        } else {
            ContentUnavailableView {
                Text("Select a file to see its changes.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func hunkAction(for change: ChangedFile) -> DiffBody.HunkAction? {
        switch change.side {
        case .unstaged: DiffBody.HunkAction(title: "Stage Hunk") { store.stageHunk($0) }
        case .staged: DiffBody.HunkAction(title: "Unstage Hunk") { store.unstageHunk($0) }
        }
    }
}

/// Path, +/− counts, Unified/Split control, and a trailing action slot.
struct DiffHeader<Trailing: View>: View {
    let path: String
    let additions: Int
    let deletions: Int
    @Binding var style: DiffViewStyle
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Text(path)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.head)
            DiffCounts(additions: additions, deletions: deletions)
            Spacer()
            Picker("View", selection: $style) {
                ForEach(DiffViewStyle.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            trailing
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct DiffCounts: View {
    let additions: Int
    let deletions: Int

    var body: some View {
        HStack(spacing: 6) {
            Text("+\(additions)").foregroundStyle(.green)
            Text("−\(deletions)").foregroundStyle(.red)
        }
        .font(.system(size: 11, weight: .medium).monospacedDigit())
    }
}
