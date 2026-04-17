//
//  IosThumbGridView.swift
//  Imagin Raw
//
//  UICollectionView-based photo grid for iOS — mirrors CollectionThumbGridView (macOS).
//

import SwiftUI
#if os(iOS)
import UIKit

// MARK: - Section Header (Duplicate Groups)

final class IosDuplicateSectionHeader: UICollectionReusableView {
    static let identifier = "IosDuplicateSectionHeader"

    private let pill      = UIView()
    private let label     = UILabel()
    private let reviewBtn = UIButton(type: .system)
    private var onReview: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        pill.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        pill.layer.cornerRadius = 4
        addSubview(pill)
        label.font = UIFont.systemFont(ofSize: 10, weight: .medium)
        label.textColor = .white
        pill.addSubview(label)
        reviewBtn.setTitle("Review", for: .normal)
        reviewBtn.titleLabel?.font = UIFont.systemFont(ofSize: 10)
        reviewBtn.backgroundColor = UIColor.systemBlue
        reviewBtn.layer.cornerRadius = 3
        reviewBtn.setTitleColor(.white, for: .normal)
        reviewBtn.addTarget(self, action: #selector(reviewTapped), for: .touchUpInside)
        addSubview(reviewBtn)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(group: DuplicateGroup, index: Int, onReview: (() -> Void)?) {
        self.onReview = onReview
        let pct = max(0, min(100, Int(((1.0 - Double(group.distance)) * 100).rounded())))
        label.text = "Group \(index + 1)  ·  \(pct)% similarity"
        label.sizeToFit()
        setNeedsLayout()
    }

    @objc private func reviewTapped() { onReview?() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        let pillH: CGFloat = 20
        let hPad: CGFloat = 8
        let pillW = label.intrinsicContentSize.width + hPad * 2
        pill.frame = CGRect(x: 12, y: (h - pillH) / 2, width: pillW, height: pillH)
        label.frame = CGRect(x: hPad, y: (pillH - label.intrinsicContentSize.height) / 2,
                             width: label.intrinsicContentSize.width, height: label.intrinsicContentSize.height)
        let btnW: CGFloat = 60, btnH: CGFloat = 22
        reviewBtn.frame = CGRect(x: pill.frame.maxX + 8, y: (h - btnH) / 2, width: btnW, height: btnH)
    }
}

// MARK: - Section Header (Date Groups)

final class IosDateSectionHeader: UICollectionReusableView {
    static let identifier = "IosDateSectionHeader"

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabel
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String) {
        label.text = title
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = CGRect(x: 8, y: 0, width: bounds.width - 16, height: bounds.height)
    }
}

// MARK: - SwiftUI Wrapper

struct IosThumbGridView: UIViewRepresentable {
    let photos: [PhotoItem]
    let itemSize: CGFloat
    let cellHeight: CGFloat
    let columnCount: Int
    let selectedPhotos: Set<UUID>
    let isSelectMode: Bool
    let callbacks: ThumbCellCallbacks
    /// Tap in select mode — toggles selection, never navigates.
    let onSelectToggle: (PhotoItem) -> Void
    /// Tap in normal mode — navigates to preview.
    let onNavigate: (PhotoItem) -> Void
    /// Range selection committed by "Select to here" — receives all photos in the range.
    let onSelectRange: ([PhotoItem]) -> Void
    var duplicateResult: DuplicateScanResult? = nil
    var onReview: ((DuplicateGroup, Int) -> Void)? = nil
    var dateGroups: [(title: String, photos: [PhotoItem])] = []
    var sortOption: ThumbGridViewModel.SortOption = .name
    @Binding var scrollToPhotoId: UUID?
    @Binding var visibleSectionIndex: Int

    private var isDateGrouped: Bool { sortOption == .dateCreated && !dateGroups.isEmpty }

    func makeCoordinator() -> Coordinator {
        Coordinator(itemSize: itemSize, cellHeight: cellHeight, columnCount: columnCount, callbacks: callbacks)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .clear
        context.coordinator.scrollView = scrollView
        buildCollectionView(in: scrollView, context: context)
        return scrollView
    }

    private func buildCollectionView(in scrollView: UIScrollView, context: Context) {
        // Remove any existing collection view
        scrollView.subviews.forEach { $0.removeFromSuperview() }

        let c = context.coordinator
        let hasHeaders = duplicateResult != nil || isDateGrouped
        let layout = makeLayout(hasHeaders: hasHeaders)

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.allowsSelection = true
        cv.allowsMultipleSelection = true
        cv.dataSource = c
        cv.delegate = c
        cv.isPrefetchingEnabled = true
        cv.prefetchDataSource = c
        cv.register(IosThumbCell.self, forCellWithReuseIdentifier: IosThumbCell.identifier)
        cv.register(IosDuplicateSectionHeader.self,
                    forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                    withReuseIdentifier: IosDuplicateSectionHeader.identifier)
        cv.register(IosDateSectionHeader.self,
                    forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                    withReuseIdentifier: IosDateSectionHeader.identifier)
        cv.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        c.collectionView = cv
        scrollView.addSubview(cv)
        cv.frame = scrollView.bounds
    }

    /// 3 columns, 1 px gaps between cells, 0 side insets.
    /// Actual cell size is computed by the delegate's sizeForItemAt so it always
    /// fills the screen width exactly, regardless of device or orientation.
    private func makeLayout(hasHeaders: Bool) -> UICollectionViewFlowLayout {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 1
        layout.minimumLineSpacing = 1
        layout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 1, right: 0)
        if hasHeaders {
            layout.headerReferenceSize = CGSize(width: 0, height: 32)
        }
        return layout
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let c = context.coordinator
        c.onVisibleSectionChanged = { idx in
            DispatchQueue.main.async { self.visibleSectionIndex = idx }
        }

        let isDupNow    = duplicateResult != nil
        let wasDup      = c.duplicateResult != nil
        let isDateNow   = isDateGrouped
        let wasDate     = c.sortOption == .dateCreated && !c.dateGroups.isEmpty
        let modeChanged = isDupNow != wasDup || isDateNow != wasDate

        let photosChanged     = c.photos.map(\.id) != photos.map(\.id)
        let sizeChanged       = c.itemSize != itemSize || c.cellHeight != cellHeight || c.columnCount != columnCount
        let selectionChanged  = c.selectedPhotos != selectedPhotos
        let dupChanged        = c.duplicateResult?.groups.map(\.id) != duplicateResult?.groups.map(\.id)
        let dateGroupsChanged = c.dateGroups.map({ $0.title }) != dateGroups.map({ $0.title })

        let latestMap   = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        let oldPhotoMap = Dictionary(uniqueKeysWithValues: c.photos.map { ($0.id, $0) })

        c.photos          = photos
        c.itemSize        = itemSize
        c.cellHeight      = cellHeight
        c.columnCount     = columnCount
        c.selectedPhotos  = selectedPhotos
        c.isSelectMode    = isSelectMode
        c.callbacks       = callbacks
        c.duplicateResult = duplicateResult
        c.onReview        = onReview
        c.dateGroups      = dateGroups
        c.sortOption      = sortOption
        c.photosById      = Dictionary(uniqueKeysWithValues: photos.map { ($0.path, $0) })
        c.collectionView?.allowsMultipleSelection = isSelectMode
        c.onSelectToggle  = onSelectToggle
        c.onNavigate      = onNavigate
        c.onSelectRange   = onSelectRange

        if modeChanged {
            buildCollectionView(in: scrollView, context: context)
            return
        }

        let cv = c.collectionView

        if photosChanged || sizeChanged || dupChanged || dateGroupsChanged {
            if sizeChanged {
                let hasHeaders = duplicateResult != nil || isDateGrouped
                if let layout = cv?.collectionViewLayout as? UICollectionViewFlowLayout {
                    layout.headerReferenceSize = hasHeaders ? CGSize(width: 0, height: 32) : .zero
                }
                cv?.collectionViewLayout.invalidateLayout()
            }
            cv?.reloadData()
        } else {
            cv?.indexPathsForVisibleItems.forEach { ip in
                guard let cell = cv?.cellForItem(at: ip) as? IosThumbCell,
                      let path = cell.currentPath,
                      let photo = latestMap.values.first(where: { $0.path == path }) else { return }
                let isSelected = selectedPhotos.contains(photo.id)
                if oldPhotoMap[photo.id] != photo {
                    cell.configure(with: photo, isSelected: isSelected, isSelectMode: isSelectMode,
                                   itemSize: itemSize, callbacks: callbacks)
                } else if selectionChanged {
                    cell.updateSelection(isSelected: isSelected, isSelectMode: isSelectMode)
                }
            }
        }

        // Scroll to photo
        if let photoId = scrollToPhotoId {
            var targetIndexPath: IndexPath?
            if let result = duplicateResult {
                outer: for (s, group) in result.groups.enumerated() {
                    for (i, photo) in group.photos.enumerated() {
                        if photo.id == photoId {
                            targetIndexPath = IndexPath(item: i, section: s)
                            break outer
                        }
                    }
                }
            } else if isDateGrouped {
                outer: for (s, group) in dateGroups.enumerated() {
                    for (i, photo) in group.photos.enumerated() {
                        if photo.id == photoId {
                            targetIndexPath = IndexPath(item: i, section: s)
                            break outer
                        }
                    }
                }
            } else if let index = photos.firstIndex(where: { $0.id == photoId }) {
                targetIndexPath = IndexPath(item: index, section: 0)
            }
            if let ip = targetIndexPath {
                // When date-grouped, align the section header to the top of the scroll view
                if isDateGrouped,
                   let headerAttrs = cv?.layoutAttributesForSupplementaryElement(
                       ofKind: UICollectionView.elementKindSectionHeader,
                       at: IndexPath(item: 0, section: ip.section)),
                   let cv = cv {
                    let offsetY = max(0, headerAttrs.frame.minY - cv.adjustedContentInset.top)
                    cv.setContentOffset(CGPoint(x: 0, y: offsetY), animated: true)
                } else {
                    cv?.scrollToItem(at: ip, at: .centeredVertically, animated: true)
                }
            }
            DispatchQueue.main.async { self.scrollToPhotoId = nil }
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching {
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
        var callbacks: ThumbCellCallbacks
        /// Called when a photo is tapped in select mode — toggles selection, never navigates.
        var onSelectToggle: ((PhotoItem) -> Void)?
        /// Called when a photo is tapped in normal mode — navigates to preview.
        var onNavigate: ((PhotoItem) -> Void)?
        /// Anchor set by "Select from here" — defines the start of a range selection.
        var selectFromIndexPath: IndexPath?
        /// Called when a range selection is committed — passes all photos in the range.
        var onSelectRange: (([PhotoItem]) -> Void)?
        var duplicateResult: DuplicateScanResult? = nil
        var onReview: ((DuplicateGroup, Int) -> Void)?
        var photosById: [String: PhotoItem] = [:]
        var dateGroups: [(title: String, photos: [PhotoItem])] = []
        var sortOption: ThumbGridViewModel.SortOption = .name
        weak var collectionView: UICollectionView?
        weak var scrollView: UIScrollView?
        var onVisibleSectionChanged: ((Int) -> Void)?

        private var isScrolling = false
        private var isDateGrouped: Bool { sortOption == .dateCreated && !dateGroups.isEmpty }

        init(itemSize: CGFloat, cellHeight: CGFloat, columnCount: Int, callbacks: ThumbCellCallbacks) {
            self.itemSize = itemSize
            self.cellHeight = cellHeight
            self.columnCount = columnCount
            self.callbacks = callbacks
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

        // MARK: UICollectionViewDataSource

        func numberOfSections(in collectionView: UICollectionView) -> Int {
            if duplicateResult != nil { return duplicateResult!.groups.count }
            if isDateGrouped { return dateGroups.count }
            return 1
        }

        func collectionView(_ collectionView: UICollectionView,
                            numberOfItemsInSection section: Int) -> Int {
            photosForSection(section).count
        }

        func collectionView(_ collectionView: UICollectionView,
                            cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: IosThumbCell.identifier,
                for: indexPath) as! IosThumbCell
            let photo = photosForSection(indexPath.section)[indexPath.item]
            // During fast scroll use .low so queued items don't pile up at .high.
            // When scrolling stops, scrollViewDidEndDecelerating boosts visible cells.
            let priority: ThumbnailRequest.Priority = isScrolling ? .low : .high
            cell.configure(with: photo,
                           isSelected: selectedPhotos.contains(photo.id),
                           isSelectMode: isSelectMode,
                           itemSize: itemSize,
                           priority: priority,
                           callbacks: callbacks)
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

        // MARK: UIScrollViewDelegate

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
            ThumbsManager.current?.cancelLowPriorityRequests()

            for ip in cv.indexPathsForVisibleItems {
                let photo = photosForSection(ip.section)[ip.item]
                guard let cell = cv.cellForItem(at: ip) as? IosThumbCell,
                      cell.thumbImage == nil else {
                    continue
                }
                ThumbsManager.current?.loadThumbnail(for: photo, priority: .high) { [weak cell] image in
                    guard let image else {
                        return
                    }
                    cell?.setThumb(image)
                }
            }
        }

        // MARK: UICollectionViewDelegateFlowLayout

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

        // MARK: UICollectionViewDataSourcePrefetching

        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            for ip in indexPaths {
                let photo = photosForSection(ip.section)[ip.item]
                ThumbsManager.current?.loadThumbnail(for: photo, priority: .low) { _ in }
            }
        }

        func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            // ThumbsManager manages its own priority queue — no action needed
        }

        // MARK: UICollectionViewDelegate

        func collectionView(_ collectionView: UICollectionView,
                            didSelectItemAt indexPath: IndexPath) {
            let photo = photosForSection(indexPath.section)[indexPath.item]
            if isSelectMode {
                onSelectToggle?(photo)
            } else {
                onNavigate?(photo)
            }
        }

        func collectionView(_ collectionView: UICollectionView,
                            didDeselectItemAt indexPath: IndexPath) {
            guard isSelectMode else {
                return
            }
            let photo = photosForSection(indexPath.section)[indexPath.item]
            onSelectToggle?(photo)
        }

        // MARK: Context menu

        func collectionView(_ collectionView: UICollectionView,
                            contextMenuConfigurationForItemAt indexPath: IndexPath,
                            point: CGPoint) -> UIContextMenuConfiguration? {
            guard isSelectMode else {
                return nil
            }

            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                guard let self else {
                    return UIMenu(title: "", children: [])
                }

                var actions: [UIAction] = []

                let fromAction = UIAction(
                    title: "Select from here",
                    image: UIImage(systemName: "arrow.down.right.square")
                ) { [weak self] _ in
                    guard let self else { return }
                    self.selectFromIndexPath = indexPath
                    let photo = self.photosForSection(indexPath.section)[indexPath.item]
                    self.onSelectToggle?(photo)
                }
                actions.append(fromAction)

                if let fromIP = selectFromIndexPath, fromIP != indexPath {
                    let toAction = UIAction(
                        title: "Select to here",
                        image: UIImage(systemName: "arrow.down.left.square")
                    ) { [weak self] _ in
                        guard let self else { return }
                        self.selectRangeFrom(fromIP, to: indexPath)
                    }
                    actions.append(toAction)
                }

                return UIMenu(title: "", children: actions)
            }
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
}
#endif
