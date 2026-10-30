import SwiftUI

/// 简单的流式换行布局:子视图从左到右排列,放不下就换行。
struct FlowWrap: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGFloat]] = [[]]
        var rowWidths: [CGFloat] = [0]
        var currentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let added = size.width + (rows[rows.count - 1].isEmpty ? 0 : spacing)
            if currentWidth + added > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                rowWidths.append(0)
                currentWidth = 0
            }
            let widthAdd = size.width + (rows[rows.count - 1].isEmpty ? 0 : spacing)
            rows[rows.count - 1].append(size.height)
            currentWidth += widthAdd
            rowWidths[rowWidths.count - 1] = currentWidth
        }

        let totalHeight = rows.reduce(CGFloat(0)) { partial, row in
            partial + (row.max() ?? 0) + spacing
        } - spacing
        return CGSize(width: maxWidth == .infinity ? (rowWidths.max() ?? 0) : maxWidth,
                      height: max(0, totalHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
