//
//  ReviewView.swift
//  Imagin Raw
//
//  Full-screen review view for a single duplicate group.
//  Shows all photos side-by-side with name, rating, approve and delete actions.
//

import SwiftUI

struct ReviewView: View {
    @ObservedObject private var appState: AppState
    @ObservedObject private var viewModel: ReviewViewModel

    @FocusState private var isFocused: Bool

    init(appState: AppState, viewModel: ReviewViewModel) {
        self.appState = appState
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button(action: {
                    appState.reviewGroup = nil
                }) {
                    Label("Close", systemImage: "xmark")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 8) {
                    Button(action: viewModel.navigateLeft) {
                        Image(systemName: "chevron.left")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(viewModel.groupIndex > 0 ? .primary : .secondary.opacity(0.3))
                    .disabled(viewModel.groupIndex <= 0)

                    Text("\(viewModel.groupIndex + 1)/\(viewModel.totalGroups)")
                        .font(.callout)
                        .foregroundColor(.secondary)

                    Button(action: viewModel.navigateRight) {
                        Image(systemName: "chevron.right")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(viewModel.groupIndex < viewModel.totalGroups - 1 ? .primary : .secondary.opacity(0.3))
                    .disabled(viewModel.groupIndex >= viewModel.totalGroups - 1)
                }

                Spacer()

                Button(action: viewModel.toggleZoom) {
                    Label(viewModel.isZoomed ? "Fit" : "Zoom 100%",
                          systemImage: viewModel.isZoomed ? "arrow.down.right.and.arrow.up.left" : "plus.magnifyingglass")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundColor(viewModel.isZoomed ? .accentColor : .secondary)
            }
            .padding(.horizontal, 16)
            .background(Color(IRColor.windowBackgroundColor))

            // Photo grid
            GeometryReader { geo in
                photoGrid(in: geo)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(IRColor.windowBackgroundColor))
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(characters: CharacterSet(charactersIn: "zZ")) { _ in
            viewModel.toggleZoom()
            return .handled
        }
        .onKeyPress(.escape) {
            Task {
                appState.reviewGroup = nil
            }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: " ")) { _ in
            Task {
                appState.reviewGroup = nil
            }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "12345")) { press in
            guard let photo = viewModel.hoveredPhoto,
                  let rating = Int(String(press.characters)) else {
                return .ignored
            }
            Task {
                viewModel.handleRating(rating, for: photo)
            }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "aA")) { _ in
            guard let photo = viewModel.hoveredPhoto else {
                return .ignored
            }
            viewModel.handleApprove(for: photo)
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "xX")) { _ in
            guard let photo = viewModel.hoveredPhoto else {
                return .ignored
            }
            viewModel.handleToggleDelete(for: photo)
            return .handled
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
        .onTapGesture {
            isFocused = true
        }
        #if os(macOS)
        .background(KeyEventInterceptor(onLeft: viewModel.navigateLeft,
                                        onRight: viewModel.navigateRight))
        #endif
    }

    // MARK: - Grid

    @ViewBuilder
    private func photoGrid(in geo: GeometryProxy) -> some View {
        let pad: CGFloat = 12
        let spacing: CGFloat = 12
        let available = CGSize(width: geo.size.width - pad * 2, height: geo.size.height - pad * 2)

        if let fitted = ReviewFitLayout.best(aspects: viewModel.photos.map { aspectRatio(of: $0) },
                                             in: available,
                                             spacing: spacing) {
            // Everything fits on screen without scrolling
            VStack(spacing: spacing) {
                ForEach(Array(fitted.rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: spacing) {
                        ForEach(row, id: \.index) { item in
                            photoCard(for: viewModel.photos[item.index])
                                .frame(width: item.size.width, height: item.size.height)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(pad)
        } else {
            scrollingGrid(in: geo, pad: pad, spacing: spacing)
        }
    }

    private func aspectRatio(of photo: PhotoItem) -> CGFloat {
        if let w = photo.exif?.width, let h = photo.exif?.height, w > 0, h > 0 {
            return CGFloat(w) / CGFloat(h)
        }
        return 3.0 / 2.0
    }

    /// Fallback used when there are too many photos to fit legibly: fixed-width columns + vertical scroll.
    @ViewBuilder
    private func scrollingGrid(in geo: GeometryProxy, pad: CGFloat, spacing: CGFloat) -> some View {
        let cols = viewModel.nrOfColumns
        let cardW = (geo.size.width - pad * 2 - spacing * CGFloat(cols - 1)) / CGFloat(cols)
        let columns = Array(repeating: GridItem(.fixed(cardW), spacing: spacing), count: cols)

        ScrollView {
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(viewModel.photos) { photo in
                    photoCard(for: photo)
                        .frame(width: cardW)
                }
            }
        }
        .padding(pad)
    }

    @ViewBuilder
    private func photoCard(for photo: PhotoItem) -> some View {
        ReviewPhotoCard(photo: photo,
                        previewsCacheManager: viewModel.previewsManager,
                        isZoomed: viewModel.isZoomed,
                        fullResImage: viewModel.fullResImages[photo.path],
                        isFullResLoading: viewModel.fullResLoading.contains(photo.path),
                        syncedMousePosition: $viewModel.syncedMousePosition,
                        hoveredPhotoId: $viewModel.hoveredPhotoId,
                        onRatingChanged: { rating in viewModel.handleRating(rating, for: photo) },
                        onApprove: { viewModel.handleApprove(for: photo) },
                        onMarkForDeletion: { viewModel.handleToggleDelete(for: photo) })
    }
}

// MARK: - Fit layout

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
