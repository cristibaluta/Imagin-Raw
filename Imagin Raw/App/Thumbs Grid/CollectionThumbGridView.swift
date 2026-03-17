//
//  CollectionThumbGridView.swift
//  Imagin Raw
//
//  NSCollectionView-based photo grid — full feature parity with ThumbCell.
//

import SwiftUI
import AppKit

// MARK: - Callbacks bundle (passed from ThumbGridView into the collection)

struct ThumbCellCallbacks {
    let onTap: (PhotoItem, NSEvent.ModifierFlags) -> Void
    let onDoubleClick: (PhotoItem) -> Void
    let onRatingChanged: (PhotoItem, Int) -> Void
    let onMoveToTrash: (PhotoItem) -> Void
    let onCopyTo: (PhotoItem) -> Void
    let onRenameTo: (PhotoItem) -> Void
    let onMoveAllMarkedToTrash: (PhotoItem) -> (count: Int, action: () -> Void)?
}

// MARK: - KeyableCollectionView

private final class KeyableCollectionView: NSCollectionView {
    var onKeyDown: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true {
            super.keyDown(with: event)
        }
    }
}

// MARK: - SwiftUI Wrapper

struct CollectionThumbGridView: NSViewRepresentable {
    let photos: [PhotoItem]
    let itemSize: CGFloat
    let cellHeight: CGFloat
    let selectedPhotos: Set<UUID>
    let callbacks: ThumbCellCallbacks
    @Binding var scrollToPhotoId: UUID?
    var onKeyPress: ((NSEvent) -> Bool)?

    func makeCoordinator() -> Coordinator {
        Coordinator(itemSize: itemSize, cellHeight: cellHeight, callbacks: callbacks)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .legacy
        scrollView.backgroundColor = NSColor(red: 30/255, green: 30/255, blue: 30/255, alpha: 1)

        let cv = KeyableCollectionView()
        cv.onKeyDown = { event in context.coordinator.onKeyDown?(event) ?? false }
        cv.collectionViewLayout = context.coordinator.makeLayout(itemSize: itemSize, cellHeight: cellHeight)
        cv.dataSource = context.coordinator
        cv.delegate = context.coordinator
        cv.isSelectable = true
        cv.allowsMultipleSelection = true
        cv.backgroundColors = [NSColor(red: 30/255, green: 30/255, blue: 30/255, alpha: 1)]
        cv.register(ThumbCollectionItem.self, forItemWithIdentifier: ThumbCollectionItem.identifier)

        context.coordinator.collectionView = cv
        scrollView.documentView = cv

        // Make collection view first responder so it receives key events
        DispatchQueue.main.async { cv.window?.makeFirstResponder(cv) }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let c = context.coordinator
        let cv = c.collectionView

        let photosChanged = c.photos.map(\.id) != photos.map(\.id)
        let sizeChanged = c.itemSize != itemSize || c.cellHeight != cellHeight
        let selectionChanged = c.selectedPhotos != selectedPhotos

        c.photos = photos
        c.itemSize = itemSize
        c.cellHeight = cellHeight
        c.selectedPhotos = selectedPhotos
        c.callbacks = callbacks
        c.onKeyDown = { event in self.onKeyPress?(event) ?? false }

        if sizeChanged {
            cv?.collectionViewLayout = c.makeLayout(itemSize: itemSize, cellHeight: cellHeight)
        }
        if photosChanged || sizeChanged {
            cv?.reloadData()
        } else if selectionChanged {
            cv?.visibleItems().forEach { item in
                guard let thumbItem = item as? ThumbCollectionItem,
                      let path = thumbItem.currentPath,
                      let photo = c.photos.first(where: { $0.path == path }) else { return }
                thumbItem.updateSelection(isSelected: selectedPhotos.contains(photo.id))
            }
        }

        // Scroll to requested photo
        if let photoId = scrollToPhotoId,
           let index = photos.firstIndex(where: { $0.id == photoId }) {
            cv?.scrollToItems(at: [IndexPath(item: index, section: 0)],
                              scrollPosition: .centeredVertically)
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
        var onKeyDown: ((NSEvent) -> Bool)?
        weak var collectionView: NSCollectionView?

        init(itemSize: CGFloat, cellHeight: CGFloat, callbacks: ThumbCellCallbacks) {
            self.itemSize = itemSize
            self.cellHeight = cellHeight
            self.callbacks = callbacks
        }

        func makeLayout(itemSize: CGFloat, cellHeight: CGFloat) -> NSCollectionViewFlowLayout {
            let layout = NSCollectionViewFlowLayout()
            layout.itemSize = NSSize(width: itemSize, height: cellHeight)
            layout.minimumInteritemSpacing = 0
            layout.minimumLineSpacing = 8
            layout.sectionInset = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
            return layout
        }

        func collectionView(_ cv: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            photos.count
        }

        func collectionView(_ cv: NSCollectionView,
                            itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = cv.makeItem(withIdentifier: ThumbCollectionItem.identifier,
                                   for: indexPath) as! ThumbCollectionItem
            let photo = photos[indexPath.item]
            item.configure(
                with: photo,
                isSelected: selectedPhotos.contains(photo.id),
                itemSize: itemSize,
                callbacks: callbacks
            )
            return item
        }

        // Selection is handled manually via click in ThumbCollectionItem
    }
}

// MARK: - Pure AppKit Star Rating View

final class AppKitStarRatingView: NSView {
    var rating: Int = 0 { didSet { if oldValue != rating { needsDisplay = true } } }
    var maxRating: Int = 5
    var starSize: CGFloat = 10
    var onRatingChanged: ((Int) -> Void)?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard maxRating > 0 else { return }
        let spacing: CGFloat = 2
        let total = CGFloat(maxRating) * starSize + CGFloat(maxRating - 1) * spacing
        var x = (bounds.width - total) / 2
        let y = (bounds.height - starSize) / 2

        for i in 1...maxRating {
            let filled = i <= rating
            let color: NSColor = filled ? .systemYellow : NSColor.white.withAlphaComponent(0.3)
            color.setFill()
            let path = starPath(in: CGRect(x: x, y: y, width: starSize, height: starSize))
            path.fill()
            x += starSize + spacing
        }
    }

    private func starPath(in rect: CGRect) -> NSBezierPath {
        let cx = rect.midX, cy = rect.midY
        let r = rect.width / 2, ri = r * 0.4
        let path = NSBezierPath()
        for i in 0..<5 {
            let outer = CGFloat(i) * .pi * 2 / 5 - .pi / 2
            let inner = outer + .pi / 5
            let op = CGPoint(x: cx + r * cos(outer), y: cy + r * sin(outer))
            let ip = CGPoint(x: cx + ri * cos(inner), y: cy + ri * sin(inner))
            if i == 0 { path.move(to: op) } else { path.line(to: op) }
            path.line(to: ip)
        }
        path.close()
        return path
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let spacing: CGFloat = 2
        let total = CGFloat(maxRating) * starSize + CGFloat(maxRating - 1) * spacing
        let startX = (bounds.width - total) / 2
        for i in 1...maxRating {
            let x = startX + CGFloat(i - 1) * (starSize + spacing)
            if loc.x >= x && loc.x <= x + starSize {
                let newRating = (rating == i) ? 0 : i
                rating = newRating
                onRatingChanged?(newRating)
                return
            }
        }
    }
}

final class ThumbCollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ThumbCollectionItem")

    // Views
    private let thumbView       = NSImageView()
    private let filenameLabel   = NSTextField(labelWithString: "")
    private let trashOverlay    = NSImageView()
    private let selectionBorder = NSView()
    private let acrBadge        = NSImageView()
    private let jpgBadge        = NSTextField(labelWithString: "+JPG")
    private var starView: AppKitStarRatingView?

    // State
    private(set) var currentPath: String?
    private var currentPhoto: PhotoItem?
    private var loadTask: DispatchWorkItem?
    private var clickCount = 0
    private var clickTimer: Timer?
    private var callbacks: ThumbCellCallbacks?
    private var itemSize: CGFloat = 100

    // MARK: loadView

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        self.view = root

        // Thumb
        thumbView.imageScaling = .scaleProportionallyUpOrDown
        thumbView.imageAlignment = .alignCenter
        thumbView.wantsLayer = true
        thumbView.layer?.backgroundColor = NSColor(red: 41/255, green: 41/255, blue: 41/255, alpha: 1).cgColor

        // Selection border (inside thumb)
        selectionBorder.wantsLayer = true
        selectionBorder.layer?.borderColor = NSColor.systemBlue.cgColor
        selectionBorder.layer?.borderWidth = 0
        selectionBorder.isHidden = true

        // Trash overlay
        trashOverlay.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        trashOverlay.contentTintColor = .systemRed
        trashOverlay.imageScaling = .scaleProportionallyUpOrDown
        trashOverlay.isHidden = true

        // ACR badge
        acrBadge.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        acrBadge.contentTintColor = .white
        acrBadge.imageScaling = .scaleProportionallyUpOrDown
        acrBadge.wantsLayer = true
        acrBadge.layer?.backgroundColor = NSColor.systemGray.withAlphaComponent(0.8).cgColor
        acrBadge.layer?.cornerRadius = 3
        acrBadge.isHidden = true

        // JPG badge
        jpgBadge.font = NSFont.boldSystemFont(ofSize: 8)
        jpgBadge.textColor = .white
        jpgBadge.alignment = .center
        jpgBadge.wantsLayer = true
        jpgBadge.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.8).cgColor
        jpgBadge.layer?.cornerRadius = 3
        jpgBadge.isHidden = true

        // Filename
        filenameLabel.font = NSFont.systemFont(ofSize: 11)
        filenameLabel.textColor = .labelColor
        filenameLabel.lineBreakMode = .byTruncatingMiddle
        filenameLabel.alignment = .center
        filenameLabel.wantsLayer = true
        filenameLabel.layer?.cornerRadius = 4

        for sub in [thumbView, selectionBorder, trashOverlay, acrBadge, jpgBadge, filenameLabel] as [NSView] {
            root.addSubview(sub)
        }

        // Click gesture
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        click.numberOfClicksRequired = 1
        root.addGestureRecognizer(click)

        // Hover tracking added in viewDidLayout when size is known
    }

    // MARK: Layout

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutSubviews()
    }

    private func layoutSubviews() {
        guard let photo = currentPhoto else { return }
        let w = view.bounds.width
        let h = view.bounds.height
        let size = itemSize
        let thumbY = h - size               // thumb sits at top
        let labelH: CGFloat = 16
        let starH: CGFloat = photo.isRawFile ? 14 : 0
        let labelY = thumbY - labelH - 2

        thumbView.frame = CGRect(x: 0, y: thumbY, width: w, height: size)
        selectionBorder.frame = thumbView.frame
        trashOverlay.frame = CGRect(x: w/2 - 12, y: thumbY + size/2 - 12, width: 24, height: 24)
        acrBadge.frame = CGRect(x: w - 46, y: thumbY + size - 22, width: 18, height: 18)
        jpgBadge.frame = CGRect(x: w - 26, y: thumbY + size - 22, width: 24, height: 14)
        filenameLabel.frame = CGRect(x: 0, y: labelY, width: w, height: labelH)

        // Star view
        if photo.isRawFile {
            if starView == nil {
                let sv = AppKitStarRatingView()
                sv.maxRating = 5
                sv.starSize = 10
                sv.onRatingChanged = { [weak self] r in
                    guard let self, let p = self.currentPhoto else { return }
                    self.callbacks?.onRatingChanged(p, r)
                }
                view.addSubview(sv)
                starView = sv
            }
            starView?.rating = currentRating(for: photo)
            starView?.frame = CGRect(x: 0, y: labelY - starH - 2, width: w, height: starH)
            starView?.isHidden = false
        } else {
            starView?.isHidden = true
        }
    }

    private func setupTrackingArea() {
        view.trackingAreas.forEach { view.removeTrackingArea($0) }
        let ta = NSTrackingArea(rect: view.bounds,
                                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                owner: self, userInfo: nil)
        view.addTrackingArea(ta)
    }

    // MARK: Configure

    func configure(with photo: PhotoItem,
                   isSelected: Bool,
                   itemSize: CGFloat,
                   callbacks: ThumbCellCallbacks) {
        self.callbacks = callbacks
        self.itemSize = itemSize

        let pathChanged = currentPath != photo.path
        currentPath = photo.path
        currentPhoto = photo

        // Thumbnail
        if pathChanged {
            loadTask?.cancel()
            loadTask = nil
            thumbView.image = nil

            if let cached = ThumbsManager.shared.getCachedThumbnail(for: photo.path) {
                thumbView.image = cached
            } else {
                let path = photo.path
                let work = DispatchWorkItem { [weak self] in
                    ThumbsManager.shared.loadThumbnail(for: path, priority: .medium) { image in
                        DispatchQueue.main.async {
                            guard self?.currentPath == path else { return }
                            self?.thumbView.image = image
                        }
                    }
                }
                loadTask = work
                DispatchQueue.global(qos: .userInitiated).async(execute: work)
            }
        }

        updateSelection(isSelected: isSelected)

        // Trash
        trashOverlay.isHidden = !photo.toDelete

        // Badges
        acrBadge.isHidden = !photo.hasACR
        jpgBadge.isHidden = !(photo.isRawFile && photo.hasJPG)

        // Filename + label color
        filenameLabel.stringValue = URL(fileURLWithPath: photo.path).lastPathComponent
        applyLabelStyle(for: photo)

        // Update star rating — layoutSubviews will position and update it
        starView?.rating = currentRating(for: photo)

        // Context menu
        view.menu = makeContextMenu(for: photo)

        // Setup tracking area once per cell reuse
        if view.trackingAreas.isEmpty { setupTrackingArea() }

        // Manually lay out since configure may be called outside of a layout pass
        if view.bounds.width > 0 { layoutSubviews() }
    }

    func updateSelection(isSelected: Bool) {
        selectionBorder.isHidden = !isSelected
        selectionBorder.layer?.borderWidth = isSelected ? 2 : 0
    }

    // MARK: Click handling

    @objc private func handleClick(_ recognizer: NSClickGestureRecognizer) {
        guard let photo = currentPhoto else { return }
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []

        clickCount += 1
        if clickCount == 1 {
            callbacks?.onTap(photo, modifiers)
            clickTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                self?.clickCount = 0
            }
        } else if clickCount == 2 {
            clickTimer?.invalidate()
            clickCount = 0
            callbacks?.onDoubleClick(photo)
        }
    }

    // MARK: Hover (show/hide stars on hover)

    override func mouseEntered(with event: NSEvent) {
        starView?.isHidden = !(currentPhoto?.isRawFile ?? false)
    }

    override func mouseExited(with event: NSEvent) {
        let rating = currentPhoto.map { currentRating(for: $0) } ?? 0
        if rating == 0 { starView?.isHidden = true }
    }

    // MARK: Context menu

    private func makeContextMenu(for photo: PhotoItem) -> NSMenu {
        let menu = NSMenu()

        let finder = NSMenuItem(title: "Show in Finder", action: #selector(menuShowInFinder), keyEquivalent: "")
        finder.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        menu.addItem(finder)

        let copy = NSMenuItem(title: "Copy to...", action: #selector(menuCopyTo), keyEquivalent: "")
        copy.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        menu.addItem(copy)

        let rename = NSMenuItem(title: "Rename...", action: #selector(menuRenameTo), keyEquivalent: "")
        rename.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
        menu.addItem(rename)

        menu.addItem(.separator())

        let trash = NSMenuItem(title: "Move to Trash", action: #selector(menuMoveToTrash), keyEquivalent: "")
        trash.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(trash)

        if photo.toDelete, let info = callbacks?.onMoveAllMarkedToTrash(photo) {
            let all = NSMenuItem(title: "Move to Trash all Rejected Photos (\(info.count))",
                                 action: #selector(menuMoveAllToTrash), keyEquivalent: "")
            all.image = NSImage(systemSymbolName: "trash.fill", accessibilityDescription: nil)
            menu.addItem(all)
        }

        return menu
    }

    @objc private func menuShowInFinder() {
        guard let path = currentPath else { return }
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
    @objc private func menuCopyTo() {
        guard let photo = currentPhoto else { return }
        callbacks?.onCopyTo(photo)
    }
    @objc private func menuRenameTo() {
        guard let photo = currentPhoto else { return }
        callbacks?.onRenameTo(photo)
    }
    @objc private func menuMoveToTrash() {
        guard let photo = currentPhoto else { return }
        callbacks?.onMoveToTrash(photo)
    }
    @objc private func menuMoveAllToTrash() {
        guard let photo = currentPhoto else { return }
        callbacks?.onMoveAllMarkedToTrash(photo)?.action()
    }

    // MARK: Helpers

    private func currentRating(for photo: PhotoItem) -> Int {
        if let r = photo.xmp?.rating, r > 0 { return r }
        return photo.inCameraRating ?? 0
    }

    private func applyLabelStyle(for photo: PhotoItem) {
        if photo.toDelete {
            filenameLabel.layer?.backgroundColor = NSColor.systemRed.cgColor
            filenameLabel.textColor = .black
            return
        }
        guard let label = photo.xmp?.label, !label.isEmpty else {
            filenameLabel.layer?.backgroundColor = NSColor.clear.cgColor
            filenameLabel.textColor = .labelColor
            return
        }
        switch label {
        case "Select":
            filenameLabel.layer?.backgroundColor = NSColor.systemRed.cgColor
            filenameLabel.textColor = .white
        case "Second":
            filenameLabel.layer?.backgroundColor = NSColor.systemYellow.cgColor
            filenameLabel.textColor = .black
        case "Approved":
            filenameLabel.layer?.backgroundColor = NSColor(red: 133/255, green: 199/255, blue: 102/255, alpha: 1).cgColor
            filenameLabel.textColor = .black
        case "Review":
            filenameLabel.layer?.backgroundColor = NSColor.systemBlue.cgColor
            filenameLabel.textColor = .white
        case "To Do":
            filenameLabel.layer?.backgroundColor = NSColor.systemPurple.cgColor
            filenameLabel.textColor = .white
        default:
            filenameLabel.layer?.backgroundColor = NSColor.clear.cgColor
            filenameLabel.textColor = .labelColor
        }
    }

    // MARK: Reuse

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
        currentPath = nil
        currentPhoto = nil
        thumbView.image = nil
        selectionBorder.layer?.borderWidth = 0
        selectionBorder.isHidden = true
        trashOverlay.isHidden = true
        acrBadge.isHidden = true
        jpgBadge.isHidden = true
        starView?.removeFromSuperview()
        starView = nil
        view.menu = nil
    }
}
