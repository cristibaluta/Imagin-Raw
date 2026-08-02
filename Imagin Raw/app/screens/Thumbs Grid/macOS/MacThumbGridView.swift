//
//  MacThumbGridView.swift
//  Imagin Raw
//
//  NSCollectionView-based photo grid — full feature parity with ThumbCell.
//
#if os(macOS)
import SwiftUI
import AppKit

struct MacThumbGridView: NSViewRepresentable {
    let delegate: ThumbCellDelegate
    let photos: [PhotoItem]
    let selectedPhotos: [PhotoItem]
    let itemSize: CGFloat
    let cellHeight: CGFloat
    var duplicateResult: DuplicateScanResult? = nil
    var onReview: ((DuplicateGroup, Int) -> Void)? = nil
    var dateGroups: [(title: String, photos: [PhotoItem])] = []
    var sortOption: SortOption = .name
    var onKeyPress: ((NSEvent) -> Bool)?
    var thumbsManager: PhotoCacheManager
    var isSearchActive: Bool = false

    @Binding var scrollToPhotoId: UUID?
    @Binding var scrollToCenteredPhotoId: UUID?
    @Binding var visibleSectionIndex: Int
    @Environment(\.colorScheme) private var colorScheme: ColorScheme  // ✅ triggers updateNSView on change

    func makeCoordinator() -> MacThumbGridCoordinator {
        MacThumbGridCoordinator(itemSize: itemSize, cellHeight: cellHeight, delegate: delegate)
    }

    private var isDateGrouped: Bool {
        sortOption != .name && !dateGroups.isEmpty
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        context.coordinator.scrollView = scrollView
        buildCollectionView(in: scrollView, context: context)
        context.coordinator.observeScrollView(scrollView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coord = context.coordinator
        coord.colorScheme = colorScheme
        coord.onVisibleSectionChanged = { idx in
            DispatchQueue.main.async {
                self.visibleSectionIndex = idx
            }
        }

        let sortChanged       = coord.sortOption != sortOption
        let photosChanged     = coord.photos.map(\.id) != photos.map(\.id)
        let sizeChanged       = coord.itemSize != itemSize || coord.cellHeight != cellHeight
        let selectionChanged  = coord.selectedPhotos != selectedPhotos
        let dupChanged        = coord.duplicateResult?.groups.map(\.id) != duplicateResult?.groups.map(\.id)
        let dateGroupsChanged = coord.dateGroups.map({ $0.title }) != dateGroups.map({ $0.title })

        coord.photos = photos
        coord.selectedPhotos = selectedPhotos
        coord.itemSize = itemSize
        coord.cellHeight = cellHeight
        coord.delegate = delegate
        coord.duplicateResult = duplicateResult
        coord.onReview = onReview
        coord.dateGroups = dateGroups
        coord.sortOption = sortOption
        coord.photosById = Dictionary(uniqueKeysWithValues: photos.map { ($0.path, $0) })
        coord.onKeyDown = { event in
            self.onKeyPress?(event) ?? false
        }

        if sortChanged {
            buildCollectionView(in: scrollView, context: context)
        }
        guard let collectionView = coord.collectionView else {
            return
        }

        if photosChanged || sizeChanged || dupChanged || dateGroupsChanged || sortChanged {
            let headerHeight: CGFloat = (duplicateResult != nil || isDateGrouped) ? 32 : 0
            collectionView.collectionViewLayout = coord.makeLayout(itemSize: itemSize,
                                                                   cellHeight: cellHeight,
                                                                   headerHeight: headerHeight)
            collectionView.reloadData()
        } else {
            // TODO: Not sure how this works

            let latestMap  = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
            let oldPhotoMap = Dictionary(uniqueKeysWithValues: coord.photos.map { ($0.id, $0) })

            collectionView.visibleItems().forEach { item in
                guard let thumbItem = item as? MacThumbCell,
                      let url = thumbItem.currentPhoto?.url,
                      let photo = latestMap.values.first(where: { $0.url == url }) else {
                    return
                }
                let isSelected = selectedPhotos.contains(photo)
                if oldPhotoMap[photo.id] != photo {
                    thumbItem.configure(with: photo,
                                        colorScheme: colorScheme,
                                        isSelected: isSelected,
                                        itemSize: itemSize,
                                        delegate: delegate)
                } else if selectionChanged {
                    thumbItem.updateSelection(isSelected: isSelected)
                }
            }
        }

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
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.allowsImplicitAnimation = true
                    if isDateGrouped,
                       let headerAttrs = collectionView.collectionViewLayout?.layoutAttributesForSupplementaryView(
                           ofKind: NSCollectionView.elementKindSectionHeader,
                           at: IndexPath(item: 0, section: ip.section)),
                       let scrollView = collectionView.enclosingScrollView {
                        scrollView.contentView.animator().setBoundsOrigin(
                            NSPoint(x: 0, y: headerAttrs.frame.minY)
                        )
                    } else {
                        collectionView.animator().scrollToItems(at: [ip], scrollPosition: .centeredVertically)
                    }
                }
            }

            DispatchQueue.main.async {
                self.scrollToPhotoId = nil
            }
        }

        if let photoId = scrollToCenteredPhotoId {
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
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.allowsImplicitAnimation = true
                    collectionView.animator().scrollToItems(at: [ip], scrollPosition: .centeredVertically)
                }
            }

            DispatchQueue.main.async {
                self.scrollToCenteredPhotoId = nil
            }
        }
    }

    private func buildCollectionView(in scrollView: NSScrollView, context: Context) {
        let coord = context.coordinator
        let headerHeight: CGFloat = (duplicateResult != nil || isDateGrouped) ? 32 : 0

        let cv = MacKeyableCollectionView()
        cv.onKeyDown = { event in
            coord.onKeyDown?(event) ?? false
        }
        cv.collectionViewLayout = coord.makeLayout(itemSize: itemSize,
                                               cellHeight: cellHeight,
                                               headerHeight: headerHeight)
        cv.dataSource = coord
        cv.delegate = coord
        cv.prefetchDataSource = coord
        cv.registerForDraggedTypes([.URL])
        cv.setDraggingSourceOperationMask(.every, forLocal: false)
        cv.isSelectable = true
        cv.allowsMultipleSelection = true
        cv.backgroundColors = [NSColor.clear]

        cv.register(MacThumbCell.self, forItemWithIdentifier: MacThumbCell.identifier)
        cv.register(MacDuplicateSectionHeader.self,
                    forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                    withIdentifier: MacDuplicateSectionHeader.identifier)
        cv.register(MacDateSectionHeader.self,
                    forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                    withIdentifier: MacDateSectionHeader.identifier)

        coord.collectionView = cv

        scrollView.documentView = cv

        if !isSearchActive {
            DispatchQueue.main.async {
                cv.window?.makeFirstResponder(cv)
            }
        }
    }
}
#endif
