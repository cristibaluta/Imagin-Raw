//
//  IosThumbGridView.swift
//  Imagin Raw
//
//  UICollectionView-based photo grid for iOS — mirrors CollectionThumbGridView (macOS).
//

#if os(iOS)
import UIKit
import SwiftUI

struct IosThumbGridView: UIViewRepresentable {
    let delegate: ThumbCellDelegate
    let photos: [PhotoItem]
    let itemSize: CGFloat
    let cellHeight: CGFloat
    let columnCount: Int
    let selectedPhotos: Set<UUID>
    let isSelectMode: Bool
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
    var thumbsManager: PhotoCacheManager
    var isLoadingMetadata: Bool = false
    var onStartSelectMode: ((PhotoItem) -> Void)? = nil
    var onEndSelectMode: (() -> Void)? = nil

    private var isDateGrouped: Bool {
        sortOption != .name && !dateGroups.isEmpty
    }

    func makeCoordinator() -> IosThumbGridCoordinator {
        return IosThumbGridCoordinator(itemSize: itemSize,
                                       cellHeight: cellHeight,
                                       columnCount: columnCount,
                                       delegate: delegate)
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
        c.thumbsManager = thumbsManager

        let isDupNow    = duplicateResult != nil
        let wasDup      = c.duplicateResult != nil
        let isDateNow   = isDateGrouped
        let wasDate     = c.sortOption != .name && !c.dateGroups.isEmpty
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
        c.delegate        = delegate
        c.duplicateResult = duplicateResult
        c.onReview        = onReview
        c.dateGroups      = dateGroups
        c.sortOption      = sortOption
        c.photosById      = Dictionary(uniqueKeysWithValues: photos.map { ($0.path, $0) })
        c.collectionView?.allowsMultipleSelection = isSelectMode
        c.onSelectToggle  = onSelectToggle
        c.onNavigate      = onNavigate
        c.onSelectRange   = onSelectRange
        c.onStartSelectMode = onStartSelectMode
        c.onEndSelectMode = onEndSelectMode

        if modeChanged {
            buildCollectionView(in: scrollView, context: context)
            return
        }

        let cv = c.collectionView

        if photosChanged || sizeChanged || dupChanged || dateGroupsChanged {
            // While metadata is still loading, dates/labels on photos change frequently.
            // Calling reloadData() resets the scroll position every time, making the
            // grid unusable. Only do a full reload once metadata has finished loading.
            if isLoadingMetadata && !sizeChanged && !modeChanged {
                cv?.indexPathsForVisibleItems.forEach { ip in
                    guard let cell = cv?.cellForItem(at: ip) as? IosThumbCell,
                          let path = cell.currentPath,
                          let photo = latestMap.values.first(where: { $0.path == path }) else {
                        return
                    }
                    let isSelected = selectedPhotos.contains(photo.id)
//                    cell.configure(with: photo,
//                                   isSelected: isSelected,
//                                   isSelectMode: isSelectMode,
//                                   itemSize: itemSize,
//                                   thumbsManager: thumbsManager,
//                                   delegate: delegate,
//                                   asset: photo.phAsset,
//                                   manager: cachingManager)
                }
            } else {
                if sizeChanged {
                    let hasHeaders = duplicateResult != nil || isDateGrouped
                    if let layout = cv?.collectionViewLayout as? UICollectionViewFlowLayout {
                        layout.headerReferenceSize = hasHeaders ? CGSize(width: 0, height: 32) : .zero
                    }
                    cv?.collectionViewLayout.invalidateLayout()
                }
                cv?.reloadData()
            }
        } else {
            cv?.indexPathsForVisibleItems.forEach { ip in
                guard let cell = cv?.cellForItem(at: ip) as? IosThumbCell,
                      let path = cell.currentPath,
                      let photo = latestMap.values.first(where: { $0.path == path }) else { return }
                let isSelected = selectedPhotos.contains(photo.id)
                if oldPhotoMap[photo.id] != photo {
//                    cell.configure(with: photo,
//                                   isSelected: isSelected,
//                                   isSelectMode: isSelectMode,
//                                   itemSize: itemSize,
//                                   thumbsManager: thumbsManager,
//                                   delegate: delegate,
//                                   asset: photo.phAsset,
//                                   manager: cachingManager)
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
}
#endif
