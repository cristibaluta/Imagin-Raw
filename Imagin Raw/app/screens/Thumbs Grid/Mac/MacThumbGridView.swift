//
//  MacThumbGridView.swift
//  Imagin Raw
//
//  NSCollectionView-based photo grid — full feature parity with ThumbCell.
//

import SwiftUI

// MARK: - Callbacks bundle (shared iOS + macOS)

struct ThumbCellCallbacks {
    let onTap: (PhotoItem, NSEvent.ModifierFlags) -> Void
    let onDoubleClick: (PhotoItem) -> Void
    let onRatingChanged: (PhotoItem, Int) -> Void
    let onMoveToTrash: (PhotoItem) -> Void
    let onCopyTo: (PhotoItem) -> Void
    let onRenameTo: (PhotoItem) -> Void
    let onMoveAllMarkedToTrash: (PhotoItem) -> (count: Int, action: () -> Void)?
    let onReviewSelected: (PhotoItem) -> Void
}

#if os(macOS)
import AppKit

// MARK: - Section Header

final class MacDuplicateSectionHeader: NSView, NSCollectionViewElement {
    static let identifier = NSUserInterfaceItemIdentifier("DuplicateSectionHeader")

    private let label      = NSTextField(labelWithString: "")
    private let pill       = NSView()
    private let actionBtn  = NSButton()
    private var groupIndex = 0
    private var group: DuplicateGroup?
    var onReview: ((DuplicateGroup, Int) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)

        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        pill.layer?.cornerRadius = 4
        addSubview(pill)

        label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        label.textColor = .white
        pill.addSubview(label)

        actionBtn.bezelStyle = .rounded
        actionBtn.title = "Review"
        actionBtn.font = NSFont.systemFont(ofSize: 10)
        actionBtn.isBordered = false
        actionBtn.wantsLayer = true
        actionBtn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        actionBtn.layer?.cornerRadius = 3
        actionBtn.contentTintColor = .white
        actionBtn.target = self
        actionBtn.action = #selector(actionTapped)
        addSubview(actionBtn)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(group: DuplicateGroup, index: Int, onReview: ((DuplicateGroup, Int) -> Void)?) {
        self.group = group
        self.groupIndex = index
        self.onReview = onReview
        let pct = max(0, min(100, Int(((1.0 - Double(group.distance)) * 100).rounded())))
        label.stringValue = "Group \(index + 1)  ·  \(pct)% similarity"
        label.sizeToFit()
        needsLayout = true
    }

    @objc private func actionTapped() {
        guard let group else { return }
        onReview?(group, groupIndex)
    }

    override func layout() {
        super.layout()
        let h: CGFloat = 20
        let hPad: CGFloat = 8
        let vPad: CGFloat = (bounds.height - h) / 2

        let pillW = label.frame.width + hPad * 2
        pill.frame = CGRect(x: 12, y: vPad, width: pillW, height: h)
        label.frame = CGRect(x: hPad, y: (h - label.frame.height) / 2,
                             width: label.frame.width, height: label.frame.height)

        let btnW: CGFloat = 50
        let btnH: CGFloat = 18
        actionBtn.frame = CGRect(x: pill.frame.maxX + 8,
                                 y: (bounds.height - btnH) / 2,
                                 width: btnW, height: btnH)

        pill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        pill.layer?.cornerRadius = 4
        actionBtn.layer?.backgroundColor = NSColor.systemBlue.cgColor
        actionBtn.layer?.cornerRadius = 3
    }
}

// MARK: - Date Section Header

final class MacDateSectionHeader: NSView, NSCollectionViewElement {
    static let identifier = NSUserInterfaceItemIdentifier("DateSectionHeader")

    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String) {
        label.stringValue = title
        label.sizeToFit()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        label.frame = CGRect(x: 8, y: (bounds.height - label.frame.height) / 2,
                             width: bounds.width - 16, height: label.frame.height)
    }
}

// MARK: - MacKeyableCollectionView

private final class MacKeyableCollectionView: NSCollectionView {
    var onKeyDown: ((NSEvent) -> Bool)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true { super.keyDown(with: event) }
    }
    // NSCollectionView handles Cmd+A via performKeyEquivalent (before keyDown),
    // which would update its internal selection model but bypass our viewModel.
    // Intercept it here and route through our handler instead.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyDown?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - SwiftUI Wrapper

struct MacThumbGridView: NSViewRepresentable {
    let photos: [PhotoItem]
    let itemSize: CGFloat
    let cellHeight: CGFloat
    let selectedPhotos: Set<UUID>
    let callbacks: ThumbCellCallbacks
    var duplicateResult: DuplicateScanResult? = nil
    var onReview: ((DuplicateGroup, Int) -> Void)? = nil
    var dateGroups: [(title: String, photos: [PhotoItem])] = []
    var sortOption: ThumbGridViewModel.SortOption = .name
    @Binding var scrollToPhotoId: UUID?
    @Binding var visibleSectionIndex: Int
    var onKeyPress: ((NSEvent) -> Bool)?

    func makeCoordinator() -> Coordinator {
        Coordinator(itemSize: itemSize, cellHeight: cellHeight, callbacks: callbacks)
    }

    private var isDateGrouped: Bool { sortOption == .dateCreated && !dateGroups.isEmpty }

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
        cv.onKeyDown = { event in c.onKeyDown?(event) ?? false }
        cv.collectionViewLayout = c.makeLayout(itemSize: itemSize, cellHeight: cellHeight,
                                               headerHeight: headerHeight)
        cv.dataSource = c
        cv.delegate = c
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
        DispatchQueue.main.async { cv.window?.makeFirstResponder(cv) }
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let c = context.coordinator
        c.onVisibleSectionChanged = { idx in
            DispatchQueue.main.async { self.visibleSectionIndex = idx }
        }

        let isDupNow  = duplicateResult != nil
        let wasDup    = c.duplicateResult != nil
        let isDateNow = isDateGrouped
        let wasDate   = c.sortOption == .dateCreated && !c.dateGroups.isEmpty
        let modeChanged = isDupNow != wasDup || isDateNow != wasDate

        let photosChanged    = c.photos.map(\.id) != photos.map(\.id)
        let contentChanged   = !photosChanged && c.photos != photos
        let sizeChanged      = c.itemSize != itemSize || c.cellHeight != cellHeight
        let selectionChanged = c.selectedPhotos != selectedPhotos
        let dupChanged       = c.duplicateResult?.groups.map(\.id) != duplicateResult?.groups.map(\.id)
        let dateGroupsChanged = c.dateGroups.map({ $0.title }) != dateGroups.map({ $0.title })

        let latestMap  = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        let oldPhotoMap = Dictionary(uniqueKeysWithValues: c.photos.map { ($0.id, $0) })

        // Update coordinator state FIRST
        c.photos = photos
        c.itemSize = itemSize
        c.cellHeight = cellHeight
        c.selectedPhotos = selectedPhotos
        c.callbacks = callbacks
        c.duplicateResult = duplicateResult
        c.onReview = onReview
        c.dateGroups = dateGroups
        c.sortOption = sortOption
        c.photosById = Dictionary(uniqueKeysWithValues: photos.map { ($0.path, $0) })
        c.onKeyDown = { event in self.onKeyPress?(event) ?? false }

        if modeChanged {
            // Recreate the entire collection view to avoid NSCollectionViewData
            // layout/section count inconsistency crashes when switching modes
            buildCollectionView(in: scrollView, context: context)
            return
        }

        let cv = c.collectionView

        if photosChanged || sizeChanged || dupChanged || dateGroupsChanged {
            if sizeChanged {
                let headerHeight: CGFloat = (duplicateResult != nil || isDateGrouped) ? 32 : 0
                cv?.collectionViewLayout = c.makeLayout(itemSize: itemSize, cellHeight: cellHeight,
                                                        headerHeight: headerHeight)
            }
            cv?.reloadData()
        } else {
            cv?.visibleItems().forEach { item in
                guard let thumbItem = item as? MacThumbCell,
                      let path = thumbItem.currentPath,
                      let photo = latestMap.values.first(where: { $0.path == path }) else { return }
                let isSelected = selectedPhotos.contains(photo.id)
                if oldPhotoMap[photo.id] != photo {
                    thumbItem.configure(with: photo, isSelected: isSelected,
                                        itemSize: itemSize, priority: .high, callbacks: callbacks)
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
        var onReview: ((DuplicateGroup, Int) -> Void)?
        var photosById: [String: PhotoItem] = [:]
        var dateGroups: [(title: String, photos: [PhotoItem])] = []
        var sortOption: ThumbGridViewModel.SortOption = .name
        weak var collectionView: NSCollectionView?
        weak var scrollView: NSScrollView?
        var onVisibleSectionChanged: ((Int) -> Void)?

        private var isScrolling = false
        private var scrollEndTimer: Timer?
        private var scrollObserver: NSObjectProtocol?
        private var isDateGrouped: Bool { sortOption == .dateCreated && !dateGroups.isEmpty }

        deinit {
            if let obs = scrollObserver {
                NotificationCenter.default.removeObserver(obs)
            }
        }

        /// Call once after the scroll view is created to start observing scroll events.
        func observeScrollView(_ sv: NSScrollView) {
            sv.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: sv.contentView,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.isScrolling = true
                self.reportVisibleSection()
                self.scrollEndTimer?.invalidate()
                self.scrollEndTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
                    guard let self else { return }
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
            ThumbsManager.shared.cancelLowPriorityRequests()

            for indexPath in cv.indexPathsForVisibleItems() {
                guard let item = cv.item(at: indexPath) as? MacThumbCell,
                      item.thumbImage == nil else {
                    continue
                }
                let photo = photosForSection(indexPath.section)[indexPath.item]
                ThumbsManager.shared.loadThumbnail(for: photo, priority: .high) { [weak item] image in
                    guard let image else {
                        return
                    }
                    DispatchQueue.main.async {
                        item?.setThumb(image)
                    }
                }
            }
        }

        init(itemSize: CGFloat, cellHeight: CGFloat, callbacks: ThumbCellCallbacks) {
            self.itemSize = itemSize
            self.cellHeight = cellHeight
            self.callbacks = callbacks
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
                guard section < result.groups.count else { return [] }
                return result.groups[section].photos.map { photosById[$0.path] ?? $0 }
            }
            if isDateGrouped {
                guard section < dateGroups.count else { return [] }
                return dateGroups[section].photos
            }
            return section == 0 ? photos : []
        }

        // MARK: NSCollectionViewDataSource

        func numberOfSections(in cv: NSCollectionView) -> Int {
            if duplicateResult != nil { return duplicateResult!.groups.count }
            if isDateGrouped { return dateGroups.count }
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
                           isSelected: selectedPhotos.contains(photo.id),
                           itemSize: itemSize,
                           priority: priority,
                           callbacks: callbacks)
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
                let header = cv.makeSupplementaryView(
                    ofKind: kind,
                    withIdentifier: MacDuplicateSectionHeader.identifier,
                    for: indexPath) as! MacDuplicateSectionHeader
                header.configure(group: result.groups[indexPath.section], index: indexPath.section, onReview: onReview)
                return header
            }
            // Date group header
            if isDateGrouped, indexPath.section < dateGroups.count {
                let header = cv.makeSupplementaryView(
                    ofKind: kind,
                    withIdentifier: MacDateSectionHeader.identifier,
                    for: indexPath) as! MacDateSectionHeader
                header.configure(title: dateGroups[indexPath.section].title)
                return header
            }
            return NSView()
        }
    }
}
#endif
