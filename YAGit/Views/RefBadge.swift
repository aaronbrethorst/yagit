import GitCore
import SwiftUI

/// A branch, remote, or tag name drawn as a small rounded badge before a commit's summary.
struct RefBadge: View {
    enum Style {
        /// Detached HEAD or the current branch.
        case filled
        /// Another local branch.
        case outlined
        /// A remote branch, or the "+N" overflow badge.
        case remote
        case tag
    }

    let text: String
    let style: Style
    /// The commit's lane color, so a branch badge matches the line leaving its tip.
    let laneColor: Color
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        let selected = prominence == .increased
        let shape = RoundedRectangle(cornerRadius: 4)
        CappedWidth(maxWidth: 130) {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 5)
        .frame(height: 16)
        .foregroundStyle(foreground(selected: selected))
        .background(fill(selected: selected), in: shape)
        .overlay {
            if let stroke = stroke(selected: selected) {
                shape.strokeBorder(stroke, lineWidth: 1)
            }
        }
    }

    private func foreground(selected: Bool) -> AnyShapeStyle {
        switch (style, selected) {
        case (.filled, false): AnyShapeStyle(Color.white)
        case (.filled, true): AnyShapeStyle(laneColor)
        // Mixing toward the primary color keeps light-appearance contrast readable for orange, teal and pink.
        case (.outlined, false): AnyShapeStyle(laneColor.mix(with: .primary, by: 0.35))
        case (.tag, false): AnyShapeStyle(Color.indigo.mix(with: .primary, by: 0.35))
        case (.outlined, true), (.tag, true): AnyShapeStyle(Color.white)
        case (.remote, _): AnyShapeStyle(HierarchicalShapeStyle.secondary)
        }
    }

    private func fill(selected: Bool) -> Color {
        switch (style, selected) {
        case (.filled, false): laneColor
        case (.filled, true): .white
        case (.tag, false): .indigo.opacity(0.15)
        case (.tag, true): .white.opacity(0.25)
        case (.outlined, _), (.remote, _): .clear
        }
    }

    private func stroke(selected: Bool) -> AnyShapeStyle? {
        switch (style, selected) {
        case (.outlined, false): AnyShapeStyle(laneColor)
        case (.outlined, true): AnyShapeStyle(Color.white)
        case (.remote, _): AnyShapeStyle(HierarchicalShapeStyle.tertiary)
        case (.filled, _), (.tag, _): nil
        }
    }
}

extension RefBadge {
    init(label: RefLabel, laneColor: Color) {
        let style: Style = switch label.kind {
        case .head, .localBranch(isCurrent: true): .filled
        case .localBranch: .outlined
        case .remoteBranch: .remote
        case .tag: .tag
        }
        self.init(text: label.name, style: style, laneColor: laneColor)
    }
}

/// Sizes its content to its natural width, but never wider than `maxWidth`.
///
/// `.frame(maxWidth:)` would grow to fill a larger proposal, so a short badge inside a wide row would
/// stretch. This layout proposes `min(proposal, maxWidth)` and reports what the content actually uses.
struct CappedWidth: Layout {
    var maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(capped(proposal)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }

    private func capped(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: min(proposal.width ?? .infinity, maxWidth), height: proposal.height)
    }
}
