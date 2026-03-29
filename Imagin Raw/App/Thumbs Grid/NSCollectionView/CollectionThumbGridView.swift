//
//  CollectionThumbGridView.swift
//  Imagin Raw
//
//  NSCollectionView-based photo grid — full feature parity with ThumbCell.
//

import SwiftUI
import AppKit

// MARK: - Callbacks bundle

struct ThumbCellCallbacks {
    let onTap: (PhotoItem, NSEvent.ModifierFlags) -> Void
    let onDoubleClick: (PhotoItem) -> Void
    let onRatingChanged: (PhotoItem, Int) -> Void
    let onMoveToTrash: (PhotoItem) -> Void
    let onCopyTo: (PhotoItem) -> Void
    let onRenameTo: (PhotoItem) -> Void
    let onMoveAllMarkedToTrash: (PhotoItem) -> (count: Int, action: () -> Void)?
}

// MARK: - Section Header

final class DuplicateSectionHeaderView: NSView, NSCollectionViewElement {
    static let identifier = NSUserInterfaceItemIdentifier("DuplicateSectionHeader")

    private let label = NSTextField(labelWithString: "")
    private let pill  = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        pill.layer?.cornerRadius = 4
        addSubview(pill)

        label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        label.textColor = .white
        pill.addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(group: DuplicateGroup, index: Int) {
        let pct = max(0, min(100, Int(((1.0 - Double(group.distance)) * 100).rounded())))
        label.stringValue = "Group \(index + 1)  ·  \(pct)% similarity"
        label.sizeToFit()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h: CGFloat = 20
        let hPad: CGFloat = 8
        let vPad: CGFloat = (bounds.height - h) / 2
        let pillW = label.frame.width + hPad * 2
        pill.frame = CGRect(x: 12, y: vPad, width: pillW, height: h)
        label.frame = CGRect(x: hPad, y: (h - label.frame.height) / 2, width: label.frame.width, height: label.frame.height)
        // Re-apply layer props after layout (layer may be reset)
        pill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        pill.layer?.cornerRadius = 4
    }
}

// MARK: - KeyableCollectionView

private final class KeyableCollectionView: NSCollectionView {
    var onKeyDown: ((NSEvent) -> Bool)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true { super.keyDown(with: event) }
    }
}

// MARK: - SwiftUI Wrapper

struct CollectionThumbGridView: NSViewRepresentable {
    let photos: [PhotoItem]
    let itemSize: CGFloat
    let cellHeight: CGFloat
    let selectedPhotos: Set<UUID>
    let callbacks: ThumbCellCallbacks
    var duplicateResult: DuplicateScanResult? = nil
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
        cv.backgroundColors = [NSColor.clear]
        cv.register(ThumbCollectionItem.self, forItemWithIdentifier: ThumbCollectionItem.identifier)
        cv.register(DuplicateSectionHeaderView.self,
                    forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                    withIdentifier: DuplicateSectionHeaderView.identifier)

        context.coordinator.collectionView = cv
        scrollView.documentView = cv
        DispatchQueue.main.async { cv.window?.makeFirstResponder(cv) }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let c = context.coordinator
        let cv = c.collectionView

        let photosChanged    = c.photos.map(\.id) != photos.map(\.id)
        let contentChanged   = !photosChanged && c.photos != photos
        let sizeChanged      = c.itemSize != itemSize || c.cellHeight != cellHeight
        let selectionChanged = c.selectedPhotos != selectedPhotos
        let dupChanged       = c.duplicateResult?.groups.map(\.id) != duplicateResult?.groups.map(\.id)

        // Build a lookup of latest PhotoItem state by id
        let latestMap = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        let oldPhotoMap = Dictionary(uniqueKeysWithValues: c.photos.map { ($0.id, $0) })

        c.photos = photos
        c.itemSize = itemSize
        c.cellHeight = cellHeight
        c.selectedPhotos = selectedPhotos
        c.callbacks = callbacks
        c.duplicateResult = duplicateResult
        c.photosById = Dictionary(uniqueKeysWithValues: photos.map { ($0.path, $0) })
        c.onKeyDown = { event in self.onKeyPress?(event) ?? false }

        if sizeChanged || dupChanged {
            cv?.collectionViewLayout = c.makeLayout(itemSize: itemSize, cellHeight: cellHeight,
                                                    headerHeight: duplicateResult != nil ? 32 : 0)
        }

        if photosChanged || sizeChanged || dupChanged {
            cv?.reloadData()
        } else {
            // Patch visible cells with latest photo state
            cv?.visibleItems().forEach { item in
                guard let thumbItem = item as? ThumbCollectionItem,
                      let path = thumbItem.currentPath,
                      let photo = latestMap.values.first(where: { $0.path == path }) else { return }
                let isSelected = selectedPhotos.contains(photo.id)
                if oldPhotoMap[photo.id] != photo {
                    thumbItem.configure(with: photo, isSelected: isSelected,
                                        itemSize: itemSize, callbacks: callbacks)
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
            } else if let index = photos.firstIndex(where: { $0.id == photoId }) {
                targetIndexPath = IndexPath(item: index, section: 0)
            }
            if let ip = targetIndexPath {
                NSAnimationContext.current.allowsImplicitAnimation = true
                cv?.animator().scrollToItems(at: [ip], scrollPosition: .centeredVertically)
            }
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
        var duplicateResult: DuplicateScanResult? = nil
        var onKeyDown: ((NSEvent) -> Bool)?
        weak var collectionView: NSCollectionView?

        init(itemSize: CGFloat, cellHeight: CGFloat, callbacks: ThumbCellCallbacks) {
            self.itemSize = itemSize
            self.cellHeight = cellHeight
            self.callbacks = callbacks
        }

        func makeLayout(itemSize: CGFloat, cellHeight: CGFloat, headerHeight: CGFloat = 0) -> NSCollectionViewFlowLayout {
            let layout = NSCollectionViewFlowLayout()
            layout.itemSize = NSSize(width: itemSize, height: cellHeight)
            layout.minimumInteritemSpacing = 0
            layout.minimumLineSpacing = 8
            layout.sectionInset = NSEdgeInsets(top: 8, left: 12, bottom: 16, right: 12)
            if headerHeight > 0 {
                layout.headerReferenceSize = NSSize(width: 0, height: headerHeight)
            }
            return layout
        }

        // photosById is the live source of truth (filteredPhotos)
        var photosById: [String: PhotoItem] = [:]

        private func photosForSection(_ section: Int) -> [PhotoItem] {
            if let result = duplicateResult {
                guard section < result.groups.count else { return [] }
                // Return live versions of photos, falling back to scan snapshot
                return result.groups[section].photos.map { photosById[$0.path] ?? $0 }
            }
            return section == 0 ? photos : []
        }

        // MARK: NSCollectionViewDataSource

        func numberOfSections(in cv: NSCollectionView) -> Int {
            duplicateResult?.groups.count ?? 1
        }

        func collectionView(_ cv: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            photosForSection(section).count
        }

        func collectionView(_ cv: NSCollectionView,
                            itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = cv.makeItem(withIdentifier: ThumbCollectionItem.identifier,
                                   for: indexPath) as! ThumbCollectionItem
            let photo = photosForSection(indexPath.section)[indexPath.item]
            item.configure(with: photo,
                           isSelected: selectedPhotos.contains(photo.id),
                           itemSize: itemSize,
                           callbacks: callbacks)
            return item
        }

        func collectionView(_ cv: NSCollectionView,
                            viewForSupplementaryElementOfKind kind: String,
                            at indexPath: IndexPath) -> NSView {
            guard kind == NSCollectionView.elementKindSectionHeader,
                  let result = duplicateResult,
                  indexPath.section < result.groups.count else {
                return cv.makeSupplementaryView(ofKind: kind,
                                                withIdentifier: NSUserInterfaceItemIdentifier(""),
                                                for: indexPath)
            }
            let header = cv.makeSupplementaryView(
                ofKind: kind,
                withIdentifier: DuplicateSectionHeaderView.identifier,
                for: indexPath) as! DuplicateSectionHeaderView
            header.configure(group: result.groups[indexPath.section], index: indexPath.section)
            return header
        }
    }
}
