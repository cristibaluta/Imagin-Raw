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
    let photos: [(title: String, photos: [PhotoItem])]
    let selectedPhotos: [PhotoItem]
    let itemSize: CGFloat
    let cellHeight: CGFloat
    let isDuplicateMode: Bool
    let onReview: ((Int) -> Void)?
    let onKeyPress: ((NSEvent) -> Bool)?
    let thumbsManager: PhotoCacheManager
    let isSearchActive: Bool

    @Binding var scrollToPhotoId: UUID?
    @Binding var scrollToCenteredPhotoId: UUID?
    @Binding var visibleSectionIndex: Int
    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    func makeCoordinator() -> MacThumbGridCoordinator {
        MacThumbGridCoordinator(itemSize: itemSize, cellHeight: cellHeight, delegate: delegate)
    }

    func makeNSView(context: Context) -> NSScrollView {
        print(">>>>>>> make NSView photos.count \(photos.count)")
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
        print(">>>>>>> update NSView photos.count \(photos.count)")
        let coord = context.coordinator
        coord.colorScheme = colorScheme
        coord.onVisibleSectionChanged = { idx in
            DispatchQueue.main.async {
                self.visibleSectionIndex = idx
            }
        }

        let photosChanged     = photoIDs(from: coord.photos) != photoIDs(from: photos)
        let sizeChanged       = coord.itemSize != itemSize || coord.cellHeight != cellHeight
        let selectedPhotosChanged = coord.selectedPhotos != selectedPhotos

        coord.delegate = delegate
        coord.photos = photos
        coord.selectedPhotos = selectedPhotos
        coord.itemSize = itemSize
        coord.cellHeight = cellHeight
        coord.isDuplicateMode = isDuplicateMode
        coord.onReview = onReview
        coord.onKeyDown = { event in
            self.onKeyPress?(event) ?? false
        }

        guard let collectionView = coord.collectionView else {
            return
        }
        if sizeChanged {
            buildCollectionView(in: scrollView, context: context)
        }
        if photosChanged {
            collectionView.reloadData()
        }
        if selectedPhotosChanged {
//            let latestMap  = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
//            let oldPhotoMap = Dictionary(uniqueKeysWithValues: coord.photos.map { ($0.id, $0) })

            collectionView.visibleItems().forEach { item in
                guard let thumbItem = item as? MacThumbCell,
                      let url = thumbItem.currentPhoto?.url,
                      let photo = self.photos.flatMap(\.photos).first(where: { $0.url == url }) else {
                    return
                }
                let isSelected = selectedPhotos.contains(photo)
                print(">>>>>>>> refreshing cell \(url.lastPathComponent) isSelected: \(isSelected) state: \(photo.state)")
                // TODO: update only the cells that updated
                thumbItem.configure(with: photo,
                                    colorScheme: colorScheme,
                                    isSelected: isSelected,
                                    itemSize: itemSize,
                                    delegate: delegate)
                thumbItem.updateSelection(isSelected: isSelected)
            }
        }

//        if photosChanged || sizeChanged || dupChanged || dateGroupsChanged || sortChanged {
//            let headerHeight: CGFloat = (duplicateResult != nil || isDateGrouped) ? 32 : 0
//            collectionView.collectionViewLayout = coord.makeLayout(itemSize: itemSize,
//                                                                   cellHeight: cellHeight,
//                                                                   headerHeight: headerHeight)
//            collectionView.reloadData()
//        }

        if let scrollToPhotoId {
            var targetIndexPath: IndexPath?

            outer: for (s, group) in photos.enumerated() {
                for (i, photo) in group.photos.enumerated() {
                    if photo.id == scrollToPhotoId {
                        targetIndexPath = IndexPath(item: i, section: s)
                        break outer
                    }
                }
            }

            if let targetIndexPath {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.allowsImplicitAnimation = true
                    if let headerAttrs = collectionView.collectionViewLayout?.layoutAttributesForSupplementaryView(
                           ofKind: NSCollectionView.elementKindSectionHeader,
                           at: IndexPath(item: 0, section: targetIndexPath.section)),
                       let scrollView = collectionView.enclosingScrollView {
                        scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: headerAttrs.frame.minY))
                    } else {
                        collectionView.animator().scrollToItems(at: [targetIndexPath], scrollPosition: .centeredVertically)
                    }
                }
            }

            DispatchQueue.main.async {
                self.scrollToPhotoId = nil
            }
        }

        if let photoId = scrollToCenteredPhotoId {
            var targetIndexPath: IndexPath?

            outer: for (s, group) in photos.enumerated() {
                for (i, photo) in group.photos.enumerated() {
                    if photo.id == photoId {
                        targetIndexPath = IndexPath(item: i, section: s)
                        break outer
                    }
                }
            }

            if let targetIndexPath {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.allowsImplicitAnimation = true
                    collectionView.animator().scrollToItems(at: [targetIndexPath], scrollPosition: .centeredVertically)
                }
            }

            DispatchQueue.main.async {
                self.scrollToCenteredPhotoId = nil
            }
        }
    }

    private func buildCollectionView(in scrollView: NSScrollView, context: Context) {
        let coord = context.coordinator
        let headerHeight: CGFloat = 32

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

    private func photoIDs(from groups: [(title: String, photos: [PhotoItem])]) -> [PhotoItem.ID] {
        groups.flatMap(\.photos).map(\.id)
    }
}
#endif
