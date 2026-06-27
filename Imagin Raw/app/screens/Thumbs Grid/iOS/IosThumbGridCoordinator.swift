//
//  Coordinator.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 25.06.2026.
//

#if os(iOS)
import UIKit
import Photos

class IosThumbGridCoordinator: NSObject {
    var photos: [PhotoItem] = []
    var itemSize: CGFloat
    var cellHeight: CGFloat
    var columnCount: Int
    var selectedPhotos: Set<UUID> = []
    var isSelectMode: Bool = false {
        didSet {
            if !isSelectMode {
                selectFromIndexPath = nil
            }
        }
    }
    var delegate: ThumbCellDelegate
    /// Called when a photo is tapped in select mode — toggles selection, never navigates.
    var onSelectToggle: ((PhotoItem) -> Void)?
    /// Called when a photo is tapped in normal mode — navigates to preview.
    var onNavigate: ((PhotoItem) -> Void)?
    /// Anchor set by "Select from here" — defines the start of a range selection.
    var selectFromIndexPath: IndexPath?
    /// Called when a range selection is committed — passes all photos in the range.
    var onSelectRange: (([PhotoItem]) -> Void)?
    var onStartSelectMode: ((PhotoItem) -> Void)?
    var onEndSelectMode: (() -> Void)?
    var duplicateResult: DuplicateScanResult? = nil
    var onReview: ((DuplicateGroup, Int) -> Void)?
    var photosById: [String: PhotoItem] = [:]
    var dateGroups: [(title: String, photos: [PhotoItem])] = []
    var sortOption: ThumbGridViewModel.SortOption = .name
    weak var collectionView: UICollectionView?
    weak var scrollView: UIScrollView?
    var onVisibleSectionChanged: ((Int) -> Void)?
    var thumbsManager: PhotoCacheManager!

    private let thumbnailSize = CGSize(width: 100, height: 100)
    private let cachingManager = PHCachingImageManager()
    let fetchResult = PHAsset.fetchAssets(with: .image, options: {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return options
    }())

    private var isScrolling = false
    private var isDateGrouped: Bool { sortOption != .name && !dateGroups.isEmpty }

    init(itemSize: CGFloat, cellHeight: CGFloat, columnCount: Int, delegate: ThumbCellDelegate) {
        self.itemSize = itemSize
        self.cellHeight = cellHeight
        self.columnCount = columnCount
        self.delegate = delegate
    }

    private func photosForSection(_ section: Int) -> [PhotoItem] {
        if let result = duplicateResult {
            guard section < result.groups.count else { return [] }
            return result.groups[section].photos.map { photosById[$0.path] ?? $0 }
        }
        if isDateGrouped {
            guard section < dateGroups.count else { return [] }
            return dateGroups[section].photos
        }
        return section == 0 ? photos : []
    }
}

// MARK: UICollectionViewDataSource

extension IosThumbGridCoordinator: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        if duplicateResult != nil { return duplicateResult!.groups.count }
        if isDateGrouped { return dateGroups.count }
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        photosForSection(section).count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: IosThumbCell.identifier,
                                                      for: indexPath) as! IosThumbCell
        let photo = photosForSection(indexPath.section)[indexPath.item]
        // During fast scroll use .low so queued items don't pile up at .high.
        // When scrolling stops, scrollViewDidEndDecelerating boosts visible cells.
        cell.configure(with: photo,
                       isSelected: selectedPhotos.contains(photo.id),
                       isSelectMode: isSelectMode,
                       itemSize: itemSize,
                       thumbsManager: thumbsManager,
                       delegate: delegate,
                       asset: photo.phAsset,
                       manager: cachingManager)
        cell.onSelectFromHere = { [weak self] in
            guard let self else {
                return
            }
            self.selectFromIndexPath = self.collectionView?.indexPath(for: cell)
            self.onStartSelectMode?(photo)
        }
        cell.onEndSelection = { [weak self] in
            self?.onEndSelectMode?()
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader else {
            return UICollectionReusableView()
        }
        // Duplicate header
        if let result = duplicateResult, indexPath.section < result.groups.count {
            let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: IosDuplicateSectionHeader.identifier,
                for: indexPath) as! IosDuplicateSectionHeader
            let group = result.groups[indexPath.section]
            let idx = indexPath.section
            header.configure(group: group, index: idx, onReview: { [weak self] in
                self?.onReview?(group, idx)
            })
            return header
        }
        // Date header
        if isDateGrouped, indexPath.section < dateGroups.count {
            let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: IosDateSectionHeader.identifier,
                for: indexPath) as! IosDateSectionHeader
            header.configure(title: dateGroups[indexPath.section].title)
            return header
        }
        return UICollectionReusableView()
    }
}

// MARK: UICollectionViewDelegateFlowLayout

extension IosThumbGridCoordinator: UICollectionViewDelegateFlowLayout {

    /// Fills the full collection view width with exactly 3 columns and 1 px gaps.
    /// Both grid modes share the same column count; height scales proportionally.
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let columns = CGFloat(columnCount)
        let totalGap = columns - 1
        let cellWidth = floor((collectionView.bounds.width - totalGap) / columns)
        return CGSize(width: cellWidth, height: (cellWidth * 4.0 / 3.0).rounded())
    }
}

// MARK: UICollectionViewDataSourcePrefetching

extension IosThumbGridCoordinator: UICollectionViewDataSourcePrefetching {

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
//        for ip in indexPaths {
//            let photo = photosForSection(ip.section)[ip.item]
//            Task {
//                await thumbsManager.getImage(for: photo)
//            }
//        }
        let assets = indexPaths.map { fetchResult.object(at: $0.item) }
        cachingManager.startCachingImages(
            for: assets,
            targetSize: thumbnailSize,
            contentMode: .aspectFill,
            options: nil
        )
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let assets = indexPaths.map { fetchResult.object(at: $0.item) }
        cachingManager.stopCachingImages(
            for: assets,
            targetSize: thumbnailSize,
            contentMode: .aspectFill,
            options: nil
        )
    }
}

// MARK: UICollectionViewDelegate

extension IosThumbGridCoordinator: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let photo = photosForSection(indexPath.section)[indexPath.item]
        if isSelectMode {
            onSelectToggle?(photo)
        } else {
            onNavigate?(photo)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard isSelectMode else {
            return
        }
        let photo = photosForSection(indexPath.section)[indexPath.item]
        onSelectToggle?(photo)
    }

    private func selectRangeFrom(_ from: IndexPath, to: IndexPath) {
        // Flatten all sections into a single ordered list with their index paths
        var allPaths: [IndexPath] = []
        let sectionCount = collectionView?.numberOfSections ?? 1
        for s in 0..<sectionCount {
            let count = collectionView?.numberOfItems(inSection: s) ?? 0
            for i in 0..<count {
                allPaths.append(IndexPath(item: i, section: s))
            }
        }

        guard let startFlat = allPaths.firstIndex(of: from),
              let endFlat = allPaths.firstIndex(of: to) else {
            return
        }

        let lo = min(startFlat, endFlat)
        let hi = max(startFlat, endFlat)
        let rangePhotos = allPaths[lo...hi].map { photosForSection($0.section)[$0.item] }
        onSelectRange?(rangePhotos)
        selectFromIndexPath = nil
    }
}

// MARK: UIScrollViewDelegate

extension IosThumbGridCoordinator: UIScrollViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let cv = collectionView, isDateGrouped else { return }
        let topY = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        let layout = cv.collectionViewLayout as? UICollectionViewFlowLayout
        var activeSection = 0
        for section in 0..<dateGroups.count {
            let ip = IndexPath(item: 0, section: section)
            guard let attrs = layout?.layoutAttributesForSupplementaryView(
                ofKind: UICollectionView.elementKindSectionHeader, at: ip) else { continue }
            if attrs.frame.minY <= topY + 1 {
                activeSection = section
            }
        }
        onVisibleSectionChanged?(activeSection)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isScrolling = true
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            isScrolling = false
            boostVisibleCells()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        isScrolling = false
        boostVisibleCells()
    }

    /// Re-request thumbnails for all currently visible cells at .high priority.
    private func boostVisibleCells() {
        guard let cv = collectionView else {
            return
        }
        // Cancel stale low-priority work so visible cells get the semaphore slots immediately
//        thumbsManager.cancelLowPriorityRequests()

//        for ip in cv.indexPathsForVisibleItems {
//            let photo = photosForSection(ip.section)[ip.item]
//            guard let cell = cv.cellForItem(at: ip) as? IosThumbCell,
//                  cell.thumbImage == nil else {
//                continue
//            }
//            thumbsManager.loadThumbnail(for: photo, priority: .high) { [weak cell] image in
//                guard let image else {
//                    return
//                }
//                cell?.setThumb(image)
//            }
//        }
    }
}

#endif
