//
//  MacFitGridLayout.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 18/10/2026.
//

import AppKit

final class MacFitGridLayout: NSCollectionViewLayout {
    var aspects: [CGFloat] = [] {
        didSet { invalidateLayout() }
    }
    var spacing: CGFloat = 12
    var padding: CGFloat = 12
    /// Minimum cell width used by the scrolling fallback to decide the column count.
    var minColumnWidth: CGFloat = 320

    private var attributes: [NSCollectionViewLayoutAttributes] = []
    private var contentSize: NSSize = .zero

    override var collectionViewContentSize: NSSize {
        contentSize
    }

    override func prepare() {
        super.prepare()
        attributes = []
        guard let cv = collectionView else {
            contentSize = .zero
            return
        }
        let visible = cv.enclosingScrollView?.contentSize ?? cv.bounds.size
        guard visible.width > 0, visible.height > 0, !aspects.isEmpty else {
            contentSize = visible
            return
        }
        let available = NSSize(width: visible.width - padding * 2, height: visible.height - padding * 2)

        if let fitted = ReviewFitLayout.best(aspects: aspects, in: available, spacing: spacing) {
            layoutFitted(fitted, visible: visible, available: available)
        } else {
            layoutScrolling(visible: visible, available: available)
        }
    }

    /// Everything fits: rows centered in the visible area, no scrolling.
    private func layoutFitted(_ fitted: ReviewFitLayout, visible: NSSize, available: NSSize) {
        let totalH = fitted.rows.reduce(CGFloat(0)) { $0 + ($1.first?.size.height ?? 0) }
            + spacing * CGFloat(max(0, fitted.rows.count - 1))
        var y = padding + max(0, (available.height - totalH) / 2)

        for row in fitted.rows {
            let rowW = row.reduce(CGFloat(0)) { $0 + $1.size.width } + spacing * CGFloat(max(0, row.count - 1))
            var x = padding + max(0, (available.width - rowW) / 2)
            for item in row {
                add(item.index, frame: NSRect(x: x, y: y, width: item.size.width, height: item.size.height))
                x += item.size.width + spacing
            }
            y += (row.first?.size.height ?? 0) + spacing
        }
        contentSize = visible
    }

    /// Too many photos: uniform cells in fixed columns, vertical scroll.
    private func layoutScrolling(visible: NSSize, available: NSSize) {
        let cols = max(1, Int((available.width + spacing) / (minColumnWidth + spacing)))
        let cellW = (available.width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
        let cellH = cellW / 1.5

        for i in 0..<aspects.count {
            let row = i / cols
            let col = i % cols
            add(i, frame: NSRect(x: padding + CGFloat(col) * (cellW + spacing),
                                 y: padding + CGFloat(row) * (cellH + spacing),
                                 width: cellW,
                                 height: cellH))
        }
        let rows = (aspects.count + cols - 1) / cols
        let totalH = padding * 2 + CGFloat(rows) * cellH + CGFloat(max(0, rows - 1)) * spacing
        contentSize = NSSize(width: visible.width, height: max(totalH, visible.height))
    }

    private func add(_ index: Int, frame: NSRect) {
        let attrs = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: index, section: 0))
        attrs.frame = frame
        attributes.append(attrs)
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        attributes.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        attributes.first { $0.indexPath == indexPath }
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        newBounds.size != contentSize
    }
}
