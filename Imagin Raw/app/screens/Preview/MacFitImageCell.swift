//
//  MacFitImageCell.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 18/10/2026.
//

import AppKit

struct MacFitCellActions {
    var onMouseMoved: (CGPoint) -> Void
    var onHover: (PhotoItem?) -> Void
    var onRating: (PhotoItem, Int) -> Void
    var onApprove: (PhotoItem) -> Void
    var onReject: (PhotoItem) -> Void
}

final class MacFitImageCell: NSCollectionViewItem {

    static let identifier = NSUserInterfaceItemIdentifier("MacFitImageCell")

    private let container = MacFitCellView()
    private let fitImageView = NSImageView()
    private let zoomView = MacZoomImageView(frame: .zero)
    private let overlay = MacFitCellOverlay()
    private var loadTask: Task<Void, Never>?
    private(set) var currentPhoto: PhotoItem?

    override func loadView() {
        fitImageView.imageScaling = .scaleProportionallyUpOrDown
        fitImageView.imageAlignment = .alignCenter
        if #available(macOS 14.0, *) {
            fitImageView.preferredImageDynamicRange = .high
        }
        for sub in [fitImageView, zoomView, overlay] {
            sub.frame = container.bounds
            sub.autoresizingMask = [.width, .height]
            container.addSubview(sub)
        }
        zoomView.isHidden = true
        overlay.isHidden = true
        view = container
    }

    func configure(with photo: PhotoItem,
                   cacheManager: PhotoCacheManager,
                   zoomImage: IRImage?,
                   mousePosition: CGPoint,
                   actions: MacFitCellActions) {
        _ = self.view
        container.onMouseMoved = actions.onMouseMoved
        container.onHover = { [weak self] inside in
            guard let self else {
                return
            }
            self.overlay.isHidden = !inside
            actions.onHover(inside ? self.currentPhoto : nil)
        }
        overlay.onRatingChanged = { [weak self] rating in
            if let photo = self?.currentPhoto {
                actions.onRating(photo, rating)
            }
        }
        overlay.onApprove = { [weak self] in
            if let photo = self?.currentPhoto {
                actions.onApprove(photo)
            }
        }
        overlay.onReject = { [weak self] in
            if let photo = self?.currentPhoto {
                actions.onReject(photo)
            }
        }
        setZoom(image: zoomImage, position: mousePosition)

        let isSamePhoto = currentPhoto?.id == photo.id
        update(photo: photo)
        guard !isSamePhoto else {
            return
        }
        loadTask?.cancel()
        fitImageView.image = nil

        loadTask = Task { [weak self] in
            let image = await cacheManager.getImage(for: photo)
            guard !Task.isCancelled, let self, self.currentPhoto?.id == photo.id else {
                return
            }
            self.fitImageView.image = image
        }
    }

    /// Refreshes the overlay (rating, label, state) without reloading the image.
    func update(photo: PhotoItem) {
        currentPhoto = photo
        overlay.configure(with: photo)
        overlay.needsLayout = true
    }

    /// Shows the full resolution image panned by `position`, or the fitted preview when `image` is nil.
    func setZoom(image: IRImage?, position: CGPoint) {
        if zoomView.image !== image {
            zoomView.image = image
        }
        zoomView.position = position
        zoomView.isHidden = image == nil
        fitImageView.isHidden = image != nil
    }

    var zoomVisibleFraction: CGSize { zoomView.visibleFraction }

    func setMousePosition(_ position: CGPoint) {
        if !zoomView.isHidden {
            zoomView.position = position
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
        currentPhoto = nil
        overlay.isHidden = true
        fitImageView.image = nil
        setZoom(image: nil, position: CGPoint(x: 0.5, y: 0.5))
    }
}
