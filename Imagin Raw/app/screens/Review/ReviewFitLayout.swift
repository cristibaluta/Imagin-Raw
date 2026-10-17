//
//  ReviewFitLayout.swift
//  Imagin Raw
//
//  Shared "fit everything on screen" row packing, used by ReviewView and MacFitGridView.
//

import CoreGraphics

/// Packs photos (in order) into rows so that everything is visible without scrolling.
/// Tries every way of splitting the sequence into consecutive rows and keeps the one
/// with the largest total image area. Returns nil when the photos would be too small
/// (caller should fall back to a scrolling layout).
struct ReviewFitLayout {
    struct Item {
        let index: Int
        let size: CGSize
    }

    let rows: [[Item]]

    /// Above this many photos we don't try to fit (2^(n-1) partitions, and tiny cells anyway).
    static let maxPhotos = 9
    /// Smallest allowed short side of a cell before falling back to scrolling.
    static let minCellSide: CGFloat = 200

    static func best(aspects: [CGFloat], in size: CGSize, spacing: CGFloat) -> ReviewFitLayout? {
        let n = aspects.count
        guard n > 0, n <= maxPhotos, size.width > 0, size.height > 0 else {
            return nil
        }

        var bestScore: CGFloat = -1
        var bestRows: [[Item]] = []

        for mask in 0..<(1 << (n - 1)) {
            // Bit i set = start a new row after photo i
            var groups: [[Int]] = [[]]
            for i in 0..<n {
                groups[groups.count - 1].append(i)
                if i < n - 1, mask & (1 << i) != 0 {
                    groups.append([])
                }
            }

            let availH = size.height - spacing * CGFloat(groups.count - 1)
            guard availH > 0 else {
                continue
            }

            // Natural row heights when each row spans the full width
            var heights: [CGFloat] = []
            var widths: [CGFloat] = []
            for g in groups {
                let w = size.width - spacing * CGFloat(g.count - 1)
                let sumAspect = g.reduce(0) { $0 + aspects[$1] }
                guard w > 0, sumAspect > 0 else {
                    heights.append(0); widths.append(0)
                    continue
                }
                heights.append(w / sumAspect)
                widths.append(w)
            }
            let totalH = heights.reduce(0, +)
            guard totalH > 0 else {
                continue
            }
            let scale = min(1, availH / totalH)

            var area: CGFloat = 0
            var rows: [[Item]] = []
            for (r, g) in groups.enumerated() {
                let h = heights[r] * scale
                var row: [Item] = []
                for i in g {
                    let item = Item(index: i, size: CGSize(width: aspects[i] * h, height: h))
                    area += item.size.width * item.size.height
                    row.append(item)
                }
                rows.append(row)
            }

            if area > bestScore {
                bestScore = area
                bestRows = rows
            }
        }

        let minSide = bestRows.flatMap { $0 }.map { min($0.size.width, $0.size.height) }.min() ?? 0
        guard !bestRows.isEmpty, minSide >= minCellSide else {
            return nil
        }
        return ReviewFitLayout(rows: bestRows)
    }
}

extension PhotoItem {
    /// Width / height from EXIF, defaulting to 3:2.
    var fitAspectRatio: CGFloat {
        if let w = exif?.width, let h = exif?.height, w > 0, h > 0 {
            return CGFloat(w) / CGFloat(h)
        }
        return 3.0 / 2.0
    }
}
