//
//  MacThumbGridCoordinator.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 05/06/2026.
//
#if os(macOS)
import AppKit

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
    var thumbsManager: ThumbsManager!

    private var isScrolling = false
    private var scrollEndTimer: Timer?
    private var scrollObserver: NSObjectProtocol?
    private var isDateGrouped: Bool {
        sortOption != .name && !dateGroups.isEmpty
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
            return result.groups[section].photos.map { photosById[$0.path] ?? $0 }
        }
        if isDateGrouped {
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
            self.isScrolling = true
            self.reportVisibleSection()
            self.scrollEndTimer?.invalidate()
            self.scrollEndTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
                guard let self else {
                    return
                }
                self.isScrolling = false
                self.boostVisibleItems()
            }
        }
    }

    private func reportVisibleSection() {
        guard let cv = collectionView, let sv = scrollView, isDateGrouped else { return }
        let topY = sv.contentView.bounds.minY
        let layout = cv.collectionViewLayout as? NSCollectionViewFlowLayout
        var activeSection = 0
        for section in 0..<dateGroups.count {
            let ip = IndexPath(item: 0, section: section)
            guard let attrs = layout?.layoutAttributesForSupplementaryView(
                ofKind: NSCollectionView.elementKindSectionHeader, at: ip) else { continue }
            if attrs.frame.minY <= topY + 1 { activeSection = section }
        }
        onVisibleSectionChanged?(activeSection)
    }

    private func boostVisibleItems() {
        guard let cv = collectionView else {
            return
        }
        // Flush all stale low-priority work so .high requests get the semaphore slots
        thumbsManager.cancelLowPriorityRequests()

        for indexPath in cv.indexPathsForVisibleItems() {
            guard let item = cv.item(at: indexPath) as? MacThumbCell,
                  item.thumbImage == nil else {
                continue
            }
            let photo = photosForSection(indexPath.section)[indexPath.item]
            thumbsManager.loadThumbnail(for: photo, priority: .high) { [weak item] image in
                guard let image else {
                    return
                }
                DispatchQueue.main.async {
                    item?.setThumb(image)
                }
            }
        }
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
            guard thumbsManager.getCachedThumbnail(for: photo) == nil else {
                continue
            }
            thumbsManager.loadThumbnail(for: photo, priority: .low) { _ in }
        }
    }

    func collectionView(_ collectionView: NSCollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        // Low-priority requests are naturally superseded when a .high request
        // arrives for the same key, so no explicit cancellation is needed.
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

        let item = cv.makeItem(withIdentifier: MacThumbCell.identifier,
                               for: indexPath) as! MacThumbCell

        let photo = photosForSection(indexPath.section)[indexPath.item]
        let priority: ThumbnailRequest.Priority = isScrolling ? .low : .high
        item.configure(with: photo,
                       theme: nil,
                       isSelected: selectedPhotos.contains(photo.id),
                       itemSize: itemSize,
                       thumbsManager: thumbsManager,
                       priority: priority,
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

}
#endif
