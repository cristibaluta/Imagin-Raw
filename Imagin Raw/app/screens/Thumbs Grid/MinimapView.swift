//
//  MinimapView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 16.04.2026.
//

import SwiftUI

struct MinimapView: View {
    let groups: [(title: String, photos: [PhotoItem])]
    let onScrollTo: (UUID) -> Void
    /// Index of the section currently at the top of the scroll view.
    let visibleSectionIndex: Int

    @State private var hoveredIndex: Int? = nil

    private let width: CGFloat = 10
    private let spacing: CGFloat = 2
    private let minSquareHeight: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let availableHeight = geo.size.height
            let squareH = squareHeight(for: availableHeight)

            VStack(spacing: spacing) {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    let isActive = index == visibleSectionIndex

                    RoundedRectangle(cornerRadius: 2)
                        .fill(isActive
                              ? Color.accentColor
                              : Color.secondary.opacity(hoveredIndex == index ? 0.65 : 0.3))
                        .frame(width: width, height: squareH)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let first = group.photos.first {
                                onScrollTo(first.id)
                            }
                        }
#if os(macOS)
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.1)) {
                                hoveredIndex = hovering ? index : nil
                            }
                        }
                        .help(group.title)
#endif
                }
            }
            .frame(width: width, alignment: .center)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: width)
    }

    private func squareHeight(for availableHeight: CGFloat) -> CGFloat {
        guard !groups.isEmpty else { return minSquareHeight }
        let totalSpacing = spacing * CGFloat(groups.count - 1)
        let raw = (availableHeight - totalSpacing) / CGFloat(groups.count)
        return max(minSquareHeight, raw)
    }
}
