//
//  ThumbCollectionItem.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 17.03.2026.
//
import Foundation
import AppKit

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
    private var currentImageSize: CGSize = .zero // actual pixel size of loaded image

    // MARK: loadView

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        self.view = root

        // Thumb
        thumbView.imageScaling = .scaleProportionallyUpOrDown
        thumbView.imageAlignment = .alignCenter
        thumbView.wantsLayer = true

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
        let thumbY = h - size
        let labelH: CGFloat = 16
        let starH: CGFloat = photo.isRawFile ? 14 : 0
        let labelY = thumbY - labelH - 2

        thumbView.frame = CGRect(x: 0, y: thumbY, width: w, height: size)

        // Compute the actual drawn image rect within the thumb square
        let imageRect = actualImageRect(in: CGRect(x: 0, y: thumbY, width: w, height: size))
        selectionBorder.frame = imageRect

        trashOverlay.frame = CGRect(x: w/2 - 12, y: thumbY + size/2 - 12, width: 24, height: 24)
        acrBadge.frame = CGRect(x: imageRect.maxX - 22, y: imageRect.maxY - 22, width: 18, height: 18)
        jpgBadge.frame = CGRect(x: imageRect.maxX - 28, y: imageRect.maxY - 22, width: 28, height: 14)
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

    /// Returns the rect that NSImageView actually draws the image in (aspect-fit within the frame)
    private func actualImageRect(in frame: CGRect) -> CGRect {
        guard currentImageSize.width > 0, currentImageSize.height > 0 else {
            return frame // fallback: no image loaded yet
        }
        let imgW = currentImageSize.width
        let imgH = currentImageSize.height
        let scale = min(frame.width / imgW, frame.height / imgH)
        let drawW = imgW * scale
        let drawH = imgH * scale
        let drawX = frame.minX + (frame.width - drawW) / 2
        let drawY = frame.minY + (frame.height - drawH) / 2
        return CGRect(x: drawX, y: drawY, width: drawW, height: drawH)
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
                currentImageSize = cached.size
                layoutSubviews()
            } else {
                let path = photo.path
                let work = DispatchWorkItem { [weak self] in
                    ThumbsManager.shared.loadThumbnail(for: path, priority: .medium) { image in
                        DispatchQueue.main.async {
                            guard self?.currentPath == path else { return }
                            self?.thumbView.image = image
                            self?.currentImageSize = image?.size ?? .zero
                            self?.layoutSubviews()
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
        currentImageSize = .zero
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
