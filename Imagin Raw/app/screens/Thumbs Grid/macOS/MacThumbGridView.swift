//
//  MacThumbGridView.swift
//  Imagin Raw
//
//  NSCollectionView-based photo grid — full feature parity with ThumbCell.
//
import SwiftUI
#if os(macOS)
import AppKit

private final class MacKeyableCollectionView: NSCollectionView {
    var onKeyDown: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool {
        true
    }
    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true { super.keyDown(with: event) }
    }
    // NSCollectionView handles Cmd+A via performKeyEquivalent (before keyDown),
    // which would update its internal selection model but bypass our viewModel.
    // Intercept it here and route through our handler instead.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyDown?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct MacThumbGridView: NSViewRepresentable {
    let delegate: ThumbCellDelegate
    let photos: [PhotoItem]
    let itemSize: CGFloat
    let cellHeight: CGFloat
    let selectedPhotos: Set<UUID>
    var duplicateResult: DuplicateScanResult? = nil
    var onReview: ((DuplicateGroup, Int) -> Void)? = nil
    var dateGroups: [(title: String, photos: [PhotoItem])] = []
    var sortOption: ThumbGridViewModel.SortOption = .name
    var onKeyPress: ((NSEvent) -> Bool)?
    var thumbsManager: ThumbsManager
    var isSearchActive: Bool = false

    @Binding var scrollToPhotoId: UUID?
    @Binding var scrollToCenteredPhotoId: UUID?
    @Binding var visibleSectionIndex: Int

    func makeCoordinator() -> MacThumbGridCoordinator {
        MacThumbGridCoordinator(itemSize: itemSize, cellHeight: cellHeight, delegate: delegate)
    }

    private var isDateGrouped: Bool { sortOption != .name && !dateGroups.isEmpty }

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

    private func buildCollectionView(in scrollView: NSScrollView, context: Context) {
        let c = context.coordinator
        let headerHeight: CGFloat = (duplicateResult != nil || isDateGrouped) ? 32 : 0

        let cv = MacKeyableCollectionView()
        cv.onKeyDown = { event in
            c.onKeyDown?(event) ?? false
        }
        cv.collectionViewLayout = c.makeLayout(itemSize: itemSize,
                                               cellHeight: cellHeight,
                                               headerHeight: headerHeight)
        cv.dataSource = c
        cv.delegate = c
        cv.prefetchDataSource = c
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
        c.collectionView = cv

        scrollView.documentView = cv

        if !isSearchActive {
            DispatchQueue.main.async {
                cv.window?.makeFirstResponder(cv)
            }
        }
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let c = context.coordinator
        c.onVisibleSectionChanged = { idx in
            DispatchQueue.main.async {
                self.visibleSectionIndex = idx
            }
        }

        let isDupNow  = duplicateResult != nil
        let wasDup    = c.duplicateResult != nil
        let isDateNow = isDateGrouped
        let wasDate   = c.sortOption != .name && !c.dateGroups.isEmpty
        let modeChanged = isDupNow != wasDup || isDateNow != wasDate

        let photosChanged    = c.photos.map(\.id) != photos.map(\.id)
        let sizeChanged      = c.itemSize != itemSize || c.cellHeight != cellHeight
        let selectionChanged = c.selectedPhotos != selectedPhotos
        let dupChanged       = c.duplicateResult?.groups.map(\.id) != duplicateResult?.groups.map(\.id)
        let dateGroupsChanged = c.dateGroups.map({ $0.title }) != dateGroups.map({ $0.title })

        let latestMap  = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        let oldPhotoMap = Dictionary(uniqueKeysWithValues: c.photos.map { ($0.id, $0) })

        c.photos = photos
        c.itemSize = itemSize
        c.cellHeight = cellHeight
        c.selectedPhotos = selectedPhotos
        c.delegate = delegate
        c.duplicateResult = duplicateResult
        c.onReview = onReview
        c.dateGroups = dateGroups
        c.sortOption = sortOption
        c.photosById = Dictionary(uniqueKeysWithValues: photos.map { ($0.path, $0) })
        c.onKeyDown = { event in self.onKeyPress?(event) ?? false }
        c.thumbsManager = thumbsManager

        if modeChanged {
            buildCollectionView(in: scrollView, context: context)
            return
        }

        let cv = c.collectionView

        if photosChanged || sizeChanged || dupChanged || dateGroupsChanged {
            if sizeChanged {
                let headerHeight: CGFloat = (duplicateResult != nil || isDateGrouped) ? 32 : 0
                cv?.collectionViewLayout = c.makeLayout(itemSize: itemSize,
                                                        cellHeight: cellHeight,
                                                        headerHeight: headerHeight)
            }
            cv?.reloadData()
            return
        } else {
            let theme: NSAppearance.Name = (NSApp.keyWindow ?? NSApp.mainWindow)?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) ??
                .aqua
            cv?.visibleItems().forEach { item in
                guard let thumbItem = item as? MacThumbCell,
                      let path = thumbItem.currentPath,
                      let photo = latestMap.values.first(where: { $0.path == path }) else { return }
                let isSelected = selectedPhotos.contains(photo.id)
                if oldPhotoMap[photo.id] != photo {
                    thumbItem.configure(with: photo,
                                        theme: theme,
                                        isSelected: isSelected,
                                        itemSize: itemSize,
                                        thumbsManager: thumbsManager,
                                        priority: .high,
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
                       let headerAttrs = cv?.collectionViewLayout?.layoutAttributesForSupplementaryView(
                           ofKind: NSCollectionView.elementKindSectionHeader,
                           at: IndexPath(item: 0, section: ip.section)),
                       let scrollView = cv?.enclosingScrollView {
                        scrollView.contentView.animator().setBoundsOrigin(
                            NSPoint(x: 0, y: headerAttrs.frame.minY)
                        )
                    } else {
                        cv?.animator().scrollToItems(at: [ip], scrollPosition: .centeredVertically)
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
                    cv?.animator().scrollToItems(at: [ip], scrollPosition: .centeredVertically)
                }
            }
            DispatchQueue.main.async {
                self.scrollToCenteredPhotoId = nil
            }
        }
    }
}
#endif
