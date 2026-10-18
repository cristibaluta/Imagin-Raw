//
//  MacFitImageCell.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 18/10/2026.
//

import AppKit

final class MacFitImageCell: NSCollectionViewItem {

    static let identifier = NSUserInterfaceItemIdentifier("MacFitImageCell")

    private let container = MacFitCellView()
    private let fitImageView = NSImageView()
    private let zoomView = MacZoomImageView(frame: .zero)
    private var loadTask: Task<Void, Never>?
    private(set) var currentPhoto: PhotoItem?

    override func loadView() {
        fitImageView.imageScaling = .scaleProportionallyUpOrDown
        fitImageView.imageAlignment = .alignCenter
        if #available(macOS 14.0, *) {
            fitImageView.preferredImageDynamicRange = .high
        }
        for sub in [fitImageView, zoomView] {
            sub.frame = container.bounds
            sub.autoresizingMask = [.width, .height]
            container.addSubview(sub)
        }
        zoomView.isHidden = true
        view = container
    }

    func configure(with photo: PhotoItem,
                   cacheManager: PhotoCacheManager,
                   zoomImage: IRImage?,
                   mousePosition: CGPoint,
                   onMouseMoved: @escaping (CGPoint) -> Void) {
        _ = self.view
        container.onMouseMoved = onMouseMoved
        setZoom(image: zoomImage, position: mousePosition)

        guard currentPhoto?.id != photo.id else {
            return
        }
        loadTask?.cancel()
        currentPhoto = photo
        fitImageView.image = nil

        loadTask = Task { [weak self] in
            let image = await cacheManager.getImage(for: photo)
            guard !Task.isCancelled, let self, self.currentPhoto?.id == photo.id else {
                return
            }
            self.fitImageView.image = image
        }
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
        fitImageView.image = nil
        setZoom(image: nil, position: CGPoint(x: 0.5, y: 0.5))
    }
}
