import Foundation

/// Lays commits out in lanes, one `GraphRow` per commit in list order, so each row can draw its own slice.
///
/// The mainline, the first-parent chain from `mainlineTip`, always sits in column 0. Every other
/// lane is an edge travelling down a column toward the parent it is waiting for; lanes waiting for
/// the same parent meet at that parent's dot. Color 0 is reserved for the mainline; other lanes get
/// 1, 2, 3, … in the order they appear.
public enum GraphLayout {
    private struct Lane {
        let target: String
        let colorIndex: Int
    }

    public static func rows(for commits: [CommitSummary], mainlineTip: String?) -> [GraphRow] {
        let bySHA = Dictionary(commits.map { ($0.sha, $0) }, uniquingKeysWith: { first, _ in first })
        var mainline = Set<String>()
        var cursor = mainlineTip
        while let sha = cursor, let commit = bySHA[sha], mainline.insert(sha).inserted {
            cursor = commit.parentSHAs.first
        }
        let hasMainline = !mainline.isEmpty
        // Column 0 belongs to the mainline whenever there is one.
        let firstFree = hasMainline ? 1 : 0

        var slots: [Lane?] = []
        var nextColor = 1

        func takeColor() -> Int {
            defer { nextColor += 1 }
            return nextColor
        }

        func freeColumn() -> Int {
            if let index = slots.indices.first(where: { $0 >= firstFree && slots[$0] == nil }) { return index }
            while slots.count < firstFree { slots.append(nil) }
            slots.append(nil)
            return slots.count - 1
        }

        var rows: [GraphRow] = []
        rows.reserveCapacity(commits.count)
        for commit in commits {
            let isMainline = mainline.contains(commit.sha)

            // Column and color.
            let column: Int
            let color: Int
            if isMainline {
                if slots.isEmpty { slots.append(nil) }
                column = 0
                color = 0
            } else if let index = slots.firstIndex(where: { $0?.target == commit.sha }) {
                column = index
                color = slots[index]!.colorIndex
            } else {
                column = freeColumn()
                color = takeColor()
            }

            // Upper half: lanes waiting for this commit end at its dot; the rest pass straight through.
            var upper: [GraphSegment] = []
            for (index, lane) in slots.enumerated() {
                guard let lane else { continue }
                if lane.target == commit.sha {
                    upper.append(GraphSegment(fromColumn: index, toColumn: column, colorIndex: lane.colorIndex))
                    slots[index] = nil
                } else {
                    upper.append(GraphSegment(fromColumn: index, toColumn: index, colorIndex: lane.colorIndex))
                }
            }

            // Lower half: open lanes pass straight through, then one edge per parent.
            var lower = slots.enumerated().compactMap { index, lane in
                lane.map { GraphSegment(fromColumn: index, toColumn: index, colorIndex: $0.colorIndex) }
            }
            for (i, parent) in commit.parentSHAs.enumerated() {
                if isMainline && i == 0 {
                    slots[0] = Lane(target: parent, colorIndex: 0)
                    lower.append(GraphSegment(fromColumn: 0, toColumn: 0, colorIndex: 0))
                } else if hasMainline, parent == mainlineTip, slots[0] == nil {
                    // The first edge to reach the mainline starts its lane.
                    slots[0] = Lane(target: parent, colorIndex: 0)
                    lower.append(GraphSegment(fromColumn: column, toColumn: 0, colorIndex: i == 0 ? color : 0))
                } else if let index = slots.firstIndex(where: { $0?.target == parent }) {
                    // A branch's own line keeps its color until it joins; a merge's extra parent takes the lane's.
                    lower.append(GraphSegment(fromColumn: column, toColumn: index,
                                              colorIndex: i == 0 ? color : slots[index]!.colorIndex))
                } else if i == 0 {
                    slots[column] = Lane(target: parent, colorIndex: color)
                    lower.append(GraphSegment(fromColumn: column, toColumn: column, colorIndex: color))
                } else {
                    let index = freeColumn()
                    let laneColor = takeColor()
                    slots[index] = Lane(target: parent, colorIndex: laneColor)
                    lower.append(GraphSegment(fromColumn: column, toColumn: index, colorIndex: laneColor))
                }
            }

            while slots.last.map({ $0 == nil }) == true { slots.removeLast() }
            rows.append(GraphRow(column: column, colorIndex: color, isMerge: commit.parentSHAs.count > 1,
                                 upper: upper, lower: lower))
        }
        return rows
    }
}
