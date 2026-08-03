//
//  MacThumbGridCoordinator.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 05/06/2026.
//
#if os(macOS)
import AppKit
import SwiftUI

@MainActor
class MacThumbGridCoordinator: NSObject {
    // Photos grouped by date or duplicates
    var photos: [(title: String, photos: [PhotoItem])] = []
    var selectedPhotos: [PhotoItem] = []
    var itemSize: CGFloat
    var cellHeight: CGFloat
    var delegate: ThumbCellDelegate
    var isDuplicateMode: Bool = false
    var onKeyDown: ((NSEvent) -> Bool)?
    var onReview: ((Int) -> Void)?

    weak var collectionView: NSCollectionView?
    weak var scrollView: NSScrollView?

    var onVisibleSectionChanged: ((Int) -> Void)?
    var lastClickedIndexPath: IndexPath?

    private var isScrolling = false
    private var scrollEndTimer: Timer?
    nonisolated(unsafe) private var scrollObserver: NSObjectProtocol?

    var colorScheme: ColorScheme = .light {
        didSet {
            guard oldValue != colorScheme else { return }
            collectionView?.reloadData()
        }
    }

    init(itemSize: CGFloat, cellHeight: CGFloat, delegate: ThumbCellDelegate) {
        self.itemSize = itemSize
        self.cellHeight = cellHeight
        self.delegate = delegate
    }

    deinit {
        if let obs = scrollObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    func makeLayout(itemSize: CGFloat, cellHeight: CGFloat, headerHeight: CGFloat = 0) -> NSCollectionViewFlowLayout {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: itemSize, height: cellHeight)
        layout.minimumInteritemSpacing = 3
        layout.minimumLineSpacing = 6
        layout.sectionInset = NSEdgeInsets(top: 6, left: 3, bottom: 6, right: 3)
        if headerHeight > 0 {
            layout.headerReferenceSize = NSSize(width: 0, height: headerHeight)
        }
        return layout
    }

    private func reloadDiffs() {
        // 1. Snapshot the old state
//        let oldItems = self.prevSelectedPhotos
//
//        // 2. Create the new state in a temporary array
//        var newItems = self.selectedPhotos
//
//        var itemsToReload = Set<IndexPath>()
//        for (index, (oldItem, newItem)) in zip(oldItems, newItems).enumerated() {
//            if oldItem != newItem { // This checks the Equatable conformance (isSelected changed)
//                itemsToReload.insert(IndexPath(item: index, section: 0))
//            }
//        }

        // 3. Calculate the difference between old and new states
//        let diff = newItems.difference(from: oldItems)
//
//        // 4. Extract the indices that actually changed
//        var itemsToReload = Set<IndexPath>()
//        for change in diff {
//            switch change {
//            case .insert(let offset, _, _), .remove(let offset, _, _):
//                itemsToReload.insert(IndexPath(item: offset, section: 0))
//            }
//        }
//
//        // 6. Only reload the items that toggled state
//        if !itemsToReload.isEmpty {
//            collectionView!.reloadItems(at: itemsToReload)
//        }
    }

    private func photosForSection(_ section: Int) -> [PhotoItem] {
        guard section < photos.count else {
            return []
        }
        return photos[section].photos
    }

    /// Call once after the scroll view is created to start observing scroll events.
    func observeScrollView(_ sv: NSScrollView) {
        sv.contentView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                                                object: sv.contentView,
                                                                queue: .main) { [weak self] _ in
            guard let self else {
                return
            }
//            self.isScrolling = true
            Task {
                await self.reportVisibleSection()
            }
        }
    }

    private func reportVisibleSection() {
        guard let cv = collectionView, let sv = scrollView else {
            return
        }
        let topY = sv.contentView.bounds.minY
        let layout = cv.collectionViewLayout as? NSCollectionViewFlowLayout
        var activeSection = 0
        for section in 0..<photos.count {
            let ip = IndexPath(item: 0, section: section)
            guard let attrs = layout?.layoutAttributesForSupplementaryView(ofKind: NSCollectionView.elementKindSectionHeader, at: ip) else {
                continue
            }
            if attrs.frame.minY <= topY + 1 {
                activeSection = section
            }
        }
        onVisibleSectionChanged?(activeSection)
    }
}

extension MacThumbGridCoordinator: NSCollectionViewPrefetching {

    func collectionView(_ collectionView: NSCollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let items = indexPaths.map { photos[$0.section].photos[$0.item] }
        delegate.startCachingImages(for: items)
    }

    func collectionView(_ collectionView: NSCollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let items = indexPaths.map { photos[$0.section].photos[$0.item] }
        delegate.stopCachingImages(for: items)
    }
}

extension MacThumbGridCoordinator: NSCollectionViewDataSource {

    func numberOfSections(in cv: NSCollectionView) -> Int {
        return photos.count
    }

    func collectionView(_ cv: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        photosForSection(section).count
    }

    func collectionView(_ cv: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {

        guard let item = cv.makeItem(withIdentifier: MacThumbCell.identifier, for: indexPath) as? MacThumbCell else {
            return NSCollectionViewItem()
        }

        let photo = photosForSection(indexPath.section)[indexPath.item]
        let isSelected = selectedPhotos.contains(photo)
//        print(">>>>>>>. itemForRepresentedObjectAt: \(indexPath) isSelected: \(isSelected)")
        item.configure(with: photo,
                       colorScheme: colorScheme,
                       isSelected: isSelected,
                       itemSize: itemSize,
                       delegate: delegate)
        return item
    }

    func collectionView(_ cv: NSCollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> NSView {

        guard kind == NSCollectionView.elementKindSectionHeader else {
            return NSView()
        }
        guard indexPath.section < photos.count else {
            return NSView()
        }
        let groupTitle = photos[indexPath.section].title
        if isDuplicateMode {
            // Duplicate group header
            let header = cv.makeSupplementaryView(ofKind: kind,
                                                  withIdentifier: MacDuplicateSectionHeader.identifier,
                                                  for: indexPath) as! MacDuplicateSectionHeader
            header.configure(title: groupTitle,
                             index: indexPath.section,
                             onReview: onReview)
            return header
        } else {
            // Date group header
            let header = cv.makeSupplementaryView(ofKind: kind,
                                                  withIdentifier: MacDateSectionHeader.identifier,
                                                  for: indexPath) as! MacDateSectionHeader
            header.configure(title: groupTitle)
            return header
        }
    }
}

extension MacThumbGridCoordinator: NSCollectionViewDelegate {

    func collectionView(_ collectionView: NSCollectionView,
                        shouldSelectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> {

        // 1. Get the current active mouse/keyboard event modifier keys
        let currentEvent = NSApp.currentEvent
        let isShiftPressed = currentEvent?.modifierFlags.contains(.shift) ?? false

        // 2. If Shift is held down and we have a starting point anchor
        if isShiftPressed, let startPath = lastClickedIndexPath, let endPath = indexPaths.first {

            // Handle single-section ranges (assumes items are in section 0)
            if startPath.section == endPath.section {
                let startItem = startPath.item
                let endItem = endPath.item

                let minItem = min(startItem, endItem)
                let maxItem = max(startItem, endItem)

                // Construct a set containing EVERY index path in between the two clicks
                var rangeIndexPaths = Set<IndexPath>()
                for itemIndex in minItem...maxItem {
                    rangeIndexPaths.insert(IndexPath(item: itemIndex, section: startPath.section))
                }

                // Manually select everything inside the range
                collectionView.selectItems(at: rangeIndexPaths, scrollPosition: [])

                // Return an empty set so AppKit doesn't override what we just did
                return []
            }
        }

        // 3. If it's a normal click (or Cmd+Click), treat the current item as the new anchor
        if let singlePath = indexPaths.first {
            lastClickedIndexPath = singlePath
        }

        return indexPaths
    }

    func collectionView(_ collectionView: NSCollectionView,
                        canDragItemsAt indexPaths: Set<IndexPath>,
                        with event: NSEvent) -> Bool {
        return true
    }

    func collectionView(_ collectionView: NSCollectionView,
                        pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        let photo = photosForSection(indexPath.section)[indexPath.item]
        return photo.url as NSPasteboardWriting
    }

    func collectionView(_ collectionView: NSCollectionView,
                        draggingSession session: NSDraggingSession,
                        willBeginAt screenPoint: NSPoint,
                        forItemsAt indexPaths: Set<IndexPath>) {
        RCLog("start dragging \(indexPaths)")
    }

    func collectionView(_ collectionView: NSCollectionView,
                        draggingSession session: NSDraggingSession,
                        endedAt screenPoint: NSPoint,
                        dragOperation operation: NSDragOperation) {
        RCLog("ended dragging \(screenPoint) \(operation)")

        if operation == .delete {
            // Handle scenario where item was dragged to the Trash
        } else if operation == .move {
            // File was moved to another app, update your local UI if needed
        }
    }
}
#endif
