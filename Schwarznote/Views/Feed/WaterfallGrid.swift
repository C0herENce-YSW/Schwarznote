//
//  WaterfallGrid.swift
//  Schwarznote
//

import SwiftUI

/// Masonry layout like the web explore page: each item goes into the currently
/// shortest column, so cards of different heights pack tightly.
struct WaterfallGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let columns: Int
    let spacing: CGFloat
    /// Estimated height relative to column width, used only for column assignment.
    let relativeHeight: (Item) -> CGFloat
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(Array(distribute().enumerated()), id: \.offset) { _, column in
                LazyVStack(spacing: spacing) {
                    ForEach(column) { item in
                        content(item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func distribute() -> [[Item]] {
        var result = Array(repeating: [Item](), count: columns)
        var heights = Array(repeating: CGFloat.zero, count: columns)
        for item in items {
            let target = heights.indices.min { heights[$0] < heights[$1] }!
            result[target].append(item)
            heights[target] += relativeHeight(item)
        }
        return result
    }
}
