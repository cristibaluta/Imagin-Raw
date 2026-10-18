//
//  MacFitGridCoordinator.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 18/10/2026.
//

import AppKit

@MainActor
final class MacFitGridCoordinator: NSObject, NSCollectionViewDataSource {
    var photos: [PhotoItem] = []
    var cacheManager: PhotoCacheManager?
    weak var collectionView: NSCollectionView?
    weak var layout: MacFitGridLayout?
    // Accessed from the nonisolated deinit only to remove the observer
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    /// Re-layout whenever the visible area changes (window resize, split view drag...).
    func observe(_ scrollView: NSScrollView) {
        scrollView.contentView.postsFrameChangedNotifications = true
        observer = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
                                                          object: scrollView.contentView,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.layout?.invalidateLayout()
                self?.reportViewport()
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        1
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        photos.count
    }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: MacFitImageCell.identifier, for: indexPath)
        if let cell = item as? MacFitImageCell, let cacheManager, indexPath.item < photos.count {
            let photo = photos[indexPath.item]
            cell.configure(with: photo,
                           cacheManager: cacheManager,
                           zoomImage: zoomImage(for: photo),
                           mousePosition: mousePosition,
                           canRemove: photos.count > 1,
                           actions: MacFitCellActions(
                               onMouseMoved: { [weak self] position in
                                   self?.handleMouseMoved(position)
                               },
                               onHover: { [weak self] photo in
                                   self?.onHoverChanged?(photo)
                               },
                               onRating: { [weak self] photo, rating in
                                   self?.onRatingChanged?(photo, rating)
                               },
                               onApprove: { [weak self] photo in
                                   self?.onApprove?(photo)
                               },
                               onReject: { [weak self] photo in
                                   self?.onReject?(photo)
                               },
                               onRemove: { [weak self] photo in
                                   self?.onRemove?(photo)
                               }))
        }
        return item
    }

    // MARK: Hover actions

    var onHoverChanged: ((PhotoItem?) -> Void)?
    var onRatingChanged: ((PhotoItem, Int) -> Void)?
    var onApprove: ((PhotoItem) -> Void)?
    var onReject: ((PhotoItem) -> Void)?
    var onRemove: ((PhotoItem) -> Void)?

    /// Pushes updated metadata of the displayed photos to the visible cells.
    func refreshPhotos() {
        for cell in visibleCells {
            if let id = cell.currentPhoto?.id, let photo = photos.first(where: { $0.id == id }) {
                cell.update(photo: photo, canRemove: photos.count > 1)
            }
        }
    }

    // MARK: Synced zoom

    var isZoomed = false
    var fullResImages: [String: IRImage] = [:]
    private var mousePosition = CGPoint(x: 0.5, y: 0.5)

    private func zoomImage(for photo: PhotoItem) -> IRImage? {
        isZoomed ? fullResImages[photo.path] : nil
    }

    private var visibleCells: [MacFitImageCell] {
        (collectionView?.visibleItems() ?? []).compactMap { $0 as? MacFitImageCell }
    }

    func refreshZoom() {
        for cell in visibleCells {
            guard let photo = cell.currentPhoto else {
                continue
            }
            cell.setZoom(image: zoomImage(for: photo), position: mousePosition)
        }
        reportViewport()
    }

    var onPositionChanged: ((CGPoint) -> Void)?
    var isPanLocked = false
    var onViewportChanged: ((CGSize) -> Void)?

    /// Applies a position coming from outside (minimap).
    func setPosition(_ position: CGPoint) {
        guard position != mousePosition else {
            return
        }
        mousePosition = position
        visibleCells.forEach { $0.setMousePosition(position) }
    }

    /// Reports the visible fraction of the first photo's zoomed image.
    func reportViewport() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isZoomed, let first = self.photos.first,
                  let cell = self.visibleCells.first(where: { $0.currentPhoto?.id == first.id }) else {
                return
            }
            self.onViewportChanged?(cell.zoomVisibleFraction)
        }
    }

    private func handleMouseMoved(_ position: CGPoint) {
        guard isZoomed, !isPanLocked else {
            return
        }
        mousePosition = position
        onPositionChanged?(position)
        visibleCells.forEach { $0.setMousePosition(position) }
    }
}
