import GitCore
import SwiftUI

/// Renders a file diff hunk by hunk, unified or split. Shared by Changes and History.
struct DiffBody: View {
    struct HunkAction {
        let title: String
        let perform: (DiffHunk) -> Void
    }

    let diff: FileDiff
    let style: DiffViewStyle
    /// `nil` for read-only diffs (commits).
    let hunkAction: HunkAction?

    var body: some View {
        if diff.isBinary {
            ContentUnavailableView("Binary file", systemImage: "doc",
                                   description: Text("Binary changes can't be shown."))
        } else if diff.hunks.isEmpty {
            ContentUnavailableView("No text changes", systemImage: "doc.text",
                                   description: Text("This change has no lines to show."))
        } else {
            switch style {
            case .unified: UnifiedDiffView(diff: diff, hunkAction: hunkAction)
            case .split: SplitDiffView(diff: diff, hunkAction: hunkAction)
            }
        }
    }
}

enum DiffMetrics {
    static let font = Font.system(size: 12, design: .monospaced)
    static let rowHeight: CGFloat = 19
    static let gutterWidth: CGFloat = 48
    static let signWidth: CGFloat = 18
    /// Approximate advance of one glyph at 12pt monospaced, for horizontal scroll sizing.
    static let glyphWidth: CGFloat = 7.3

    static func wash(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .addition: Color.green.opacity(0.14)
        case .deletion: Color.red.opacity(0.12)
        case .context: .clear
        }
    }

    static func sign(for kind: DiffLine.Kind) -> String {
        switch kind {
        case .addition: "+"
        case .deletion: "−"
        case .context: " "
        }
    }
}

/// Identity of a diff row. Every hunk's rows share one LazyVStack, so a per-hunk offset alone
/// would repeat across hunks and SwiftUI would leave the later hunks' rows blank.
struct DiffRowID: Hashable {
    let hunk: Int
    let row: Int
}

struct HunkHeaderRow: View {
    let hunk: DiffHunk
    let action: DiffBody.HunkAction?

    var body: some View {
        HStack(spacing: 8) {
            Text(hunk.header)
                .font(DiffMetrics.font)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let action {
                Button(action.title) { action.perform(hunk) }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Color.accentColor.opacity(0.06))
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }
}

// MARK: - Unified

/// One row of the unified view.
struct UnifiedRow: Identifiable {
    let id: DiffRowID
    let line: DiffLine
}

func unifiedRows(for hunk: DiffHunk) -> [UnifiedRow] {
    hunk.lines.enumerated().map { UnifiedRow(id: DiffRowID(hunk: hunk.index, row: $0.offset), line: $0.element) }
}

private struct UnifiedDiffView: View {
    let diff: FileDiff
    let hunkAction: DiffBody.HunkAction?

    private var minWidth: CGFloat {
        let longest = diff.hunks.flatMap(\.lines).map(\.text.count).max() ?? 0
        return CGFloat(longest) * DiffMetrics.glyphWidth + DiffMetrics.gutterWidth * 2 + DiffMetrics.signWidth + 24
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(diff.hunks) { hunk in
                        Section {
                            ForEach(unifiedRows(for: hunk)) { row in
                                UnifiedLineRow(line: row.line)
                            }
                        } header: {
                            HunkHeaderRow(hunk: hunk, action: hunkAction)
                                .background(.background)
                        }
                    }
                }
                .frame(minWidth: max(minWidth, proxy.size.width), alignment: .leading)
            }
        }
    }
}

private struct UnifiedLineRow: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            Gutter(number: line.oldLineNumber)
            Gutter(number: line.newLineNumber)
            Text(DiffMetrics.sign(for: line.kind))
                .font(DiffMetrics.font)
                .foregroundStyle(.secondary)
                .frame(width: DiffMetrics.signWidth)
            Text(line.text)
                .font(DiffMetrics.font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if line.missingTrailingNewline {
                Text("  ⏎ No newline at end of file")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(height: DiffMetrics.rowHeight)
        .background(DiffMetrics.wash(for: line.kind))
    }
}

private struct Gutter: View {
    let number: Int?

    var body: some View {
        Text(number.map(String.init) ?? "")
            .font(DiffMetrics.font)
            .foregroundStyle(.tertiary)
            .frame(width: DiffMetrics.gutterWidth, alignment: .trailing)
            .padding(.trailing, 6)
    }
}

// MARK: - Split

/// One row of the split view: a left (old) cell and a right (new) cell, either may be empty.
struct SplitRow: Identifiable {
    let id: DiffRowID
    let left: DiffLine?
    let right: DiffLine?
}

func splitRows(for hunk: DiffHunk) -> [SplitRow] {
    var rows: [SplitRow] = []
    var deletions: [DiffLine] = []
    var additions: [DiffLine] = []

    func flush() {
        for i in 0..<max(deletions.count, additions.count) {
            rows.append(SplitRow(id: DiffRowID(hunk: hunk.index, row: rows.count),
                                 left: i < deletions.count ? deletions[i] : nil,
                                 right: i < additions.count ? additions[i] : nil))
        }
        deletions.removeAll()
        additions.removeAll()
    }

    for line in hunk.lines {
        switch line.kind {
        case .deletion: deletions.append(line)
        case .addition: additions.append(line)
        case .context:
            flush()
            rows.append(SplitRow(id: DiffRowID(hunk: hunk.index, row: rows.count), left: line, right: line))
        }
    }
    flush()
    return rows
}

private struct SplitDiffView: View {
    let diff: FileDiff
    let hunkAction: DiffBody.HunkAction?

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(diff.hunks) { hunk in
                    Section {
                        ForEach(splitRows(for: hunk)) { row in
                            HStack(alignment: .top, spacing: 0) {
                                SplitCell(line: row.left, number: row.left?.oldLineNumber, side: .deletion)
                                Divider()
                                SplitCell(line: row.right, number: row.right?.newLineNumber, side: .addition)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    } header: {
                        HunkHeaderRow(hunk: hunk, action: hunkAction)
                            .background(.background)
                    }
                }
            }
        }
    }
}

private struct SplitCell: View {
    let line: DiffLine?
    let number: Int?
    /// Which non-context kind this column shows, for the wash.
    let side: DiffLine.Kind

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Gutter(number: number)
            Text(line.map { DiffMetrics.sign(for: $0.kind) } ?? " ")
                .font(DiffMetrics.font)
                .foregroundStyle(.secondary)
                .frame(width: DiffMetrics.signWidth)
            Text(line?.text ?? "")
                .font(DiffMetrics.font)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(minHeight: DiffMetrics.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(wash)
    }

    private var wash: Color {
        guard let line else { return Color.secondary.opacity(0.05) }
        return DiffMetrics.wash(for: line.kind == .context ? .context : side)
    }
}
