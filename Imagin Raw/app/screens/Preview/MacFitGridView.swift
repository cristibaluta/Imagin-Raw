//
//  MacFitGridView.swift
//  Imagin Raw
//
//  Reusable NSCollectionView that shows N images, each as a bare image.
//  Tries to fit all of them on screen (ReviewFitLayout); when they would become
//  too small it falls back to a regular scrolling grid.
//
#if os(macOS)
import SwiftUI
import AppKit

struct MacFitGridView: NSViewRepresentable {
    let photos: [PhotoItem]
    let cacheManager: PhotoCacheManager
    var spacing: CGFloat = 12
    var padding: CGFloat = 12
    /// When true, cells with a full resolution image in `fullResImages` (keyed by photo path)
    /// show it at 100%, panned in sync by moving the mouse over any cell.
    var isZoomed: Bool = false
    var fullResImages: [String: IRImage] = [:]
    /// Normalized pan position (0...1), driven externally (e.g. minimap).
    var panPosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
    var onPanChanged: ((CGPoint) -> Void)?
    var onViewportChanged: ((CGSize) -> Void)?

    func makeCoordinator() -> MacFitGridCoordinator {
        MacFitGridCoordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let coord = context.coordinator

        let layout = MacFitGridLayout()
        layout.spacing = spacing
        layout.padding = padding
        layout.aspects = photos.map(\.fitAspectRatio)

        let cv = NSCollectionView()
        cv.collectionViewLayout = layout
        cv.dataSource = coord
        cv.isSelectable = false
        cv.backgroundColors = [.clear]
        cv.register(MacFitImageCell.self, forItemWithIdentifier: MacFitImageCell.identifier)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.documentView = cv

        coord.photos = photos
        coord.cacheManager = cacheManager
        coord.collectionView = cv
        coord.layout = layout
        coord.observe(scrollView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coord = context.coordinator
        coord.cacheManager = cacheManager

        guard let cv = coord.collectionView, let layout = coord.layout else {
            return
        }
        let idsChanged = coord.photos.map(\.id) != photos.map(\.id)
        let metricsChanged = layout.spacing != spacing || layout.padding != padding
        let zoomChanged = coord.isZoomed != isZoomed || coord.fullResImages.count != fullResImages.count

        coord.photos = photos
        coord.isZoomed = isZoomed
        coord.fullResImages = fullResImages
        coord.onPositionChanged = onPanChanged
        coord.onViewportChanged = onViewportChanged
        coord.setPosition(panPosition)
        layout.spacing = spacing
        layout.padding = padding

        if idsChanged {
            layout.aspects = photos.map(\.fitAspectRatio)
            cv.reloadData()
            cv.scroll(.zero)
        } else {
            if metricsChanged {
                layout.invalidateLayout()
            }
            if zoomChanged {
                coord.refreshZoom()
            }
        }
        if isZoomed {
            coord.reportViewport()
        }
    }
}

#endif
