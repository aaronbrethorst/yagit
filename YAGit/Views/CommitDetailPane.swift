import GitCore
import SwiftUI

/// Detail pane in History mode: commit heading, file chips, read-only diff.
struct CommitDetailPane: View {
    @Bindable var store: RepositoryStore
    @AppStorage("diffViewStyle") private var style: DiffViewStyle = .unified

    var body: some View {
        if let commit = store.selectedCommit {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(commit.summary)
                        .font(.system(size: 15, weight: .semibold))
                    Text("\(commit.shortSHA) · \(commit.authorName) · \(commit.date, format: .relative(presentation: .named))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if let files = store.commitDetail?.files {
                        // Scrolls once the chips pass a few rows, so a large commit can't crowd out the diff.
                        // Measured at its ideal height: FlowLayout's height depends on its width, and the
                        // zero-width minimum probe would otherwise demand one row per file from the window.
                        ScrollView(.vertical) {
                            FlowLayout(spacing: 6) {
                                ForEach(files) { file in
                                    FileChip(file: file, isSelected: file.path == store.selectedCommitFile) {
                                        store.selectedCommitFile = file.path
                                    }
                                }
                            }
                            .padding(1)  // keeps the selected chip's outline clear of the scroll clip
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .frame(maxHeight: 96)
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ProgressView().controlSize(.small)
                    }
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

private struct FileChip: View {
    let file: FileDiff
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(file.fileName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                DiffCounts(additions: file.additions, deletions: file.deletions)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08),
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(isSelected ? Color.accentColor : .clear))
        }
        .buttonStyle(.plain)
        .help(file.path)
    }
}

/// Wraps its children onto as many rows as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(in: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(in: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: .unspecified)
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
        var y: CGFloat = 0
    }

    private func arrange(in width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        var y: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            var row = rows.removeLast()
            if !row.indices.isEmpty, row.width + spacing + size.width > width {
                y += row.height + spacing
                rows.append(row)
                row = Row(y: y)
            }
            row.indices.append(index)
            row.width += (row.indices.count > 1 ? spacing : 0) + size.width
            row.height = max(row.height, size.height)
            row.y = y
            rows.append(row)
        }
        return rows
    }
}
