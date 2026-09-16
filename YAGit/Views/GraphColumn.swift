import GitCore
import SwiftUI

/// Draws one row's slice of the lane graph. Rows sit edge to edge, so each row's segments meet the
/// next row's at the shared boundary.
struct GraphColumn: View {
    let row: GraphRow
    let laneCount: Int
    @Environment(\.backgroundProminence) private var prominence

    static let laneSpacing: CGFloat = 10

    static func width(laneCount: Int) -> CGFloat { 8 + laneSpacing * CGFloat(laneCount) }

    var body: some View {
        let selected = prominence == .increased
        let row = self.row
        let laneCount = self.laneCount
        let laneSpacing = Self.laneSpacing
        Canvas { context, size in
            func x(_ column: Int) -> CGFloat { 9 + laneSpacing * CGFloat(column) }
            let midY = size.height / 2

            func draw(_ segment: GraphSegment, from top: CGFloat, to bottom: CGFloat) {
                // Lanes past the cap are skipped rather than widening the column.
                guard segment.fromColumn < laneCount, segment.toColumn < laneCount else { return }
                let start = CGPoint(x: x(segment.fromColumn), y: top)
                let end = CGPoint(x: x(segment.toColumn), y: bottom)
                var path = Path()
                path.move(to: start)
                if start.x == end.x {
                    path.addLine(to: end)
                } else {
                    // Vertical tangents at both ends make an S-curve that meets straight lanes cleanly.
                    let middle = (top + bottom) / 2
                    path.addCurve(to: end, control1: CGPoint(x: start.x, y: middle), control2: CGPoint(x: end.x, y: middle))
                }
                let color = selected ? Color.white.opacity(0.7) : GraphPalette.color(for: segment.colorIndex)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }

            for segment in row.upper { draw(segment, from: 0, to: midY) }
            for segment in row.lower { draw(segment, from: midY, to: size.height) }

            guard row.column < laneCount else { return }
            let center = CGPoint(x: x(row.column), y: midY)
            let dotColor = selected ? Color.white : GraphPalette.color(for: row.colorIndex)
            let dot = Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
            if row.isMerge {
                // Punch through the lines so whatever is behind the row (plain, accent, or gray
                // selection) shows inside the ring.
                context.blendMode = .clear
                context.fill(dot, with: .color(.black))
                context.blendMode = .normal
                let ring = Path(ellipseIn: CGRect(x: center.x - 3.25, y: center.y - 3.25, width: 6.5, height: 6.5))
                context.stroke(ring, with: .color(dotColor), lineWidth: 1.5)
            } else {
                context.fill(dot, with: .color(dotColor))
            }
        }
        .frame(width: Self.width(laneCount: laneCount))
        .accessibilityHidden(true)
    }
}
