import GitCore
import SwiftUI

/// One commit in the History list: its slice of the lane graph, ref badges, summary and byline.
struct CommitRow: View {
    let entry: HistoryEntry
    let laneCount: Int

    private static let visibleBadgeLimit = 3

    var body: some View {
        let commit = entry.commit
        let laneColor = GraphPalette.color(for: entry.graph.colorIndex)
        let hidden = entry.refs.dropFirst(Self.visibleBadgeLimit)
        HStack(spacing: 8) {
            GraphColumn(row: entry.graph, laneCount: laneCount)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    // Badges take their width first; the summary truncates into what's left.
                    ForEach(entry.refs.prefix(Self.visibleBadgeLimit), id: \.self) { label in
                        RefBadge(label: label, laneColor: laneColor)
                            .layoutPriority(1)
                    }
                    if !hidden.isEmpty {
                        RefBadge(text: "+\(hidden.count)", style: .remote, laneColor: laneColor)
                            .help(hidden.map(\.name).joined(separator: ", "))
                            .layoutPriority(1)
                    }
                    Text(commit.summary)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
                // The date outranks the author, so a long name truncates before the time does.
                HStack(spacing: 0) {
                    Text("\(commit.shortSHA) · ")
                    Text(commit.authorName)
                    Text(" · \(CommitDate.string(for: commit.date))")
                        .layoutPriority(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 34)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(for: entry))
    }

    /// "summary, merge commit, on main, origin/main, author, date", naming every ref, including those hidden behind "+N".
    static func accessibilityLabel(for entry: HistoryEntry, now: Date = .now, calendar: Calendar = .current) -> String {
        var parts = [entry.commit.summary]
        if entry.graph.isMerge { parts.append(String(localized: "merge commit")) }
        if !entry.refs.isEmpty {
            parts.append(String(localized: "on \(entry.refs.map(\.name).joined(separator: ", "))"))
        }
        parts.append(entry.commit.authorName)
        parts.append(CommitDate.string(for: entry.commit.date, now: now, calendar: calendar))
        return parts.joined(separator: ", ")
    }
}
