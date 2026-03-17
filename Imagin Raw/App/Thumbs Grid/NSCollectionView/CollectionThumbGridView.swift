//
//  CollectionThumbGridView.swift
//  Imagin Raw
//
//  NSCollectionView-based photo grid — full feature parity with ThumbCell.
//

import SwiftUI
import AppKit

// MARK: - Callbacks bundle (passed from ThumbGridView into the collection)

struct ThumbCellCallbacks {
    let onTap: (PhotoItem, NSEvent.ModifierFlags) -> Void
    let onDoubleClick: (PhotoItem) -> Void
    let onRatingChanged: (PhotoItem, Int) -> Void
    let onMoveToTrash: (PhotoItem) -> Void
    let onCopyTo: (PhotoItem) -> Void
    let onRenameTo: (PhotoItem) -> Void
    let onMoveAllMarkedToTrash: (PhotoItem) -> (count: Int, action: () -> Void)?
}

// MARK: - KeyableCollectionView

private final class KeyableCollectionView: NSCollectionView {
    var onKeyDown: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true {
            super.keyDown(with: event)
        }
    }
}

// MARK: - SwiftUI Wrapper

struct CollectionThumbGridView: NSViewRepresentable {
    let photos: [PhotoItem]
    let itemSize: CGFloat
    let cellHeight: CGFloat
    let selectedPhotos: Set<UUID>
    let callbacks: ThumbCellCallbacks
    @Binding var scrollToPhotoId: UUID?
    var onKeyPress: ((NSEvent) -> Bool)?

    func makeCoordinator() -> Coordinator {
        Coordinator(itemSize: itemSize, cellHeight: cellHeight, callbacks: callbacks)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let cv = KeyableCollectionView()
        cv.onKeyDown = { event in context.coordinator.onKeyDown?(event) ?? false }
        cv.collectionViewLayout = context.coordinator.makeLayout(itemSize: itemSize, cellHeight: cellHeight)
        cv.dataSource = context.coordinator
        cv.delegate = context.coordinator
        cv.isSelectable = true
        cv.allowsMultipleSelection = true
//        cv.backgroundColors = [NSColor(red: 30/255, green: 30/255, blue: 30/255, alpha: 1)]
        cv.register(ThumbCollectionItem.self, forItemWithIdentifier: ThumbCollectionItem.identifier)

        context.coordinator.collectionView = cv
        scrollView.documentView = cv

        // Make collection view first responder so it receives key events
        DispatchQueue.main.async { cv.window?.makeFirstResponder(cv) }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let c = context.coordinator
        let cv = c.collectionView

        let photosChanged = c.photos.map(\.id) != photos.map(\.id)
        let sizeChanged = c.itemSize != itemSize || c.cellHeight != cellHeight
        let selectionChanged = c.selectedPhotos != selectedPhotos

        c.photos = photos
        c.itemSize = itemSize
        c.cellHeight = cellHeight
        c.selectedPhotos = selectedPhotos
        c.callbacks = callbacks
        c.onKeyDown = { event in self.onKeyPress?(event) ?? false }

        if sizeChanged {
            cv?.collectionViewLayout = c.makeLayout(itemSize: itemSize, cellHeight: cellHeight)
        }
        if photosChanged || sizeChanged {
            cv?.reloadData()
        } else if selectionChanged {
            cv?.visibleItems().forEach { item in
                guard let thumbItem = item as? ThumbCollectionItem,
                      let path = thumbItem.currentPath,
                      let photo = c.photos.first(where: { $0.path == path }) else { return }
                thumbItem.updateSelection(isSelected: selectedPhotos.contains(photo.id))
            }
        }

        // Scroll to requested photo
        if let photoId = scrollToPhotoId,
           let index = photos.firstIndex(where: { $0.id == photoId }) {
            NSAnimationContext.current.allowsImplicitAnimation = true
            cv?.animator().scrollToItems(at: [IndexPath(item: index, section: 0)],
                                         scrollPosition: .centeredVertically)
            DispatchQueue.main.async { self.scrollToPhotoId = nil }
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var photos: [PhotoItem] = []
        var itemSize: CGFloat
        var cellHeight: CGFloat
        var selectedPhotos: Set<UUID> = []
        var callbacks: ThumbCellCallbacks
        var onKeyDown: ((NSEvent) -> Bool)?
        weak var collectionView: NSCollectionView?

        init(itemSize: CGFloat, cellHeight: CGFloat, callbacks: ThumbCellCallbacks) {
            self.itemSize = itemSize
            self.cellHeight = cellHeight
            self.callbacks = callbacks
        }

        func makeLayout(itemSize: CGFloat, cellHeight: CGFloat) -> NSCollectionViewFlowLayout {
            let layout = NSCollectionViewFlowLayout()
            layout.itemSize = NSSize(width: itemSize, height: cellHeight)
            layout.minimumInteritemSpacing = 0
            layout.minimumLineSpacing = 8
            layout.sectionInset = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
            return layout
        }

        func collectionView(_ cv: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            photos.count
        }

        func collectionView(_ cv: NSCollectionView,
                            itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = cv.makeItem(withIdentifier: ThumbCollectionItem.identifier,
                                   for: indexPath) as! ThumbCollectionItem
            let photo = photos[indexPath.item]
            item.configure(
                with: photo,
                isSelected: selectedPhotos.contains(photo.id),
                itemSize: itemSize,
                callbacks: callbacks
            )
            return item
        }

        // Selection is handled manually via click in ThumbCollectionItem
    }
}
