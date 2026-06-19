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
    var photos: [PhotoItem] = []
    var itemSize: CGFloat
    var cellHeight: CGFloat
    var selectedPhotos: Set<UUID> = []
    var delegate: ThumbCellDelegate
    var duplicateResult: DuplicateScanResult? = nil
    var onKeyDown: ((NSEvent) -> Bool)?
    var onReview: ((DuplicateGroup, Int) -> Void)?
    var photosById: [String: PhotoItem] = [:]
    var dateGroups: [(title: String, photos: [PhotoItem])] = []
    var sortOption: ThumbGridViewModel.SortOption = .name
    weak var collectionView: NSCollectionView?
    weak var scrollView: NSScrollView?
    var onVisibleSectionChanged: ((Int) -> Void)?
    var thumbsManager: PhotoCacheManager!
    var lastClickedIndexPath: IndexPath?

    private var isScrolling = false
    private var scrollEndTimer: Timer?
    private var scrollObserver: NSObjectProtocol?
    private var isDateGrouped: Bool {
        sortOption != .name && !dateGroups.isEmpty
    }
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

    private func photosForSection(_ section: Int) -> [PhotoItem] {
        if let result = duplicateResult {
            guard section < result.groups.count else {
                return []
            }
            return result.groups[section].photos.map {
                photosById[$0.path] ?? $0
            }
        } else if isDateGrouped {
            guard section < dateGroups.count else {
                return []
            }
            return dateGroups[section].photos
        }
        return section == 0 ? photos : []
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
            self.reportVisibleSection()
//            self.scrollEndTimer?.invalidate()
//            self.scrollEndTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
//                guard let self else {
//                    return
//                }
//                self.isScrolling = false
//                self.boostVisibleItems()
//            }
        }
    }

    private func reportVisibleSection() {
        guard let cv = collectionView, let sv = scrollView, isDateGrouped else {
            return
        }
        let topY = sv.contentView.bounds.minY
        let layout = cv.collectionViewLayout as? NSCollectionViewFlowLayout
        var activeSection = 0
        for section in 0..<dateGroups.count {
            let ip = IndexPath(item: 0, section: section)
            guard let attrs = layout?.layoutAttributesForSupplementaryView(
                ofKind: NSCollectionView.elementKindSectionHeader,
                at: ip) else {
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
        for indexPath in indexPaths {
            let sectionPhotos = photosForSection(indexPath.section)
            guard indexPath.item < sectionPhotos.count else {
                continue
            }
            let photo = sectionPhotos[indexPath.item]
            Task {
                _ = await thumbsManager.getImage(for: photo)
            }
        }
    }
}

extension MacThumbGridCoordinator: NSCollectionViewDataSource {

    func numberOfSections(in cv: NSCollectionView) -> Int {
        if duplicateResult != nil {
            return duplicateResult!.groups.count
        }
        if isDateGrouped {
            return dateGroups.count
        }
        return 1
    }

    func collectionView(_ cv: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        photosForSection(section).count
    }

    func collectionView(_ cv: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {

        let photo = photosForSection(indexPath.section)[indexPath.item]

        let item = cv.makeItem(withIdentifier: MacThumbCell.identifier, for: indexPath) as! MacThumbCell
        item.configure(with: photo,
                       colorScheme: colorScheme,
                       isSelected: selectedPhotos.contains(photo.id),
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
        // Duplicate group header
        if let result = duplicateResult, indexPath.section < result.groups.count {
            let header = cv.makeSupplementaryView(ofKind: kind,
                                                  withIdentifier: MacDuplicateSectionHeader.identifier,
                                                  for: indexPath) as! MacDuplicateSectionHeader
            header.configure(group: result.groups[indexPath.section],
                             index: indexPath.section,
                             onReview: onReview)
            return header
        }
        // Date group header
        if isDateGrouped, indexPath.section < dateGroups.count {
            let header = cv.makeSupplementaryView(ofKind: kind,
                                                  withIdentifier: MacDateSectionHeader.identifier,
                                                  for: indexPath) as! MacDateSectionHeader
            header.configure(title: dateGroups[indexPath.section].title)
            return header
        }
        return NSView()
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
