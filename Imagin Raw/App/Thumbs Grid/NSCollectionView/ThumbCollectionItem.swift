//
//  ThumbCollectionItem.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 17.03.2026.
//
import Foundation
#if os(macOS)
import AppKit

private final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let superRect = super.drawingRect(forBounds: rect)
        let size = cellSize(forBounds: rect)
        let dy = (superRect.height - size.height) / 2
        return NSRect(x: superRect.minX, y: superRect.minY + dy,
                      width: superRect.width, height: size.height)
    }
}

final class ThumbCollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ThumbCollectionItem")

    // Views
    private let thumbView           = NSImageView()
    private let filenameLabel       = NSTextField(labelWithString: "")
    private let trashContainer      = NSView()       // shadow lives here
    private let trashOverlay        = NSImageView()  // icon inside container
    private let selectionBorder     = NSView()
    private let badgeStack          = NSStackView()
    private let acrBadgeContainer   = NSView()
    private let acrBadge            = NSImageView()
    private let jpgBadgeContainer   = NSView()
    private let jpgBadge            = NSTextField(labelWithString: "+JPG")
    private var starView: AppKitStarRatingView?

    // State
    private(set) var currentPath: String?
    private var currentPhoto: PhotoItem?
    private var loadTask: DispatchWorkItem?
    private var callbacks: ThumbCellCallbacks?
    private var itemSize: CGFloat = 100
    private var currentImageSize: CGSize = .zero

    // MARK: loadView

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        self.view = root

        thumbView.imageScaling = .scaleProportionallyUpOrDown
        thumbView.imageAlignment = .alignCenter
        thumbView.wantsLayer = true

        selectionBorder.wantsLayer = true

        let config = NSImage.SymbolConfiguration(pointSize: CGFloat.zero, weight: .bold)
        trashOverlay.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        trashOverlay.contentTintColor = .orange
        trashOverlay.imageScaling = .scaleProportionallyUpOrDown

        // trashContainer holds the shadow; trashOverlay is inside it
        trashContainer.wantsLayer = true
        trashContainer.layer?.masksToBounds = false
        trashContainer.isHidden = true
        trashContainer.addSubview(trashOverlay)

        // ACR badge
        acrBadge.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        acrBadge.contentTintColor = .white
        acrBadge.imageScaling = .scaleProportionallyUpOrDown
        acrBadge.wantsLayer = true
        acrBadge.setContentHuggingPriority(.required, for: .horizontal)

        acrBadgeContainer.wantsLayer = true
        acrBadgeContainer.addSubview(acrBadge)
        acrBadge.translatesAutoresizingMaskIntoConstraints = false
        let padding: CGFloat = 2.0
        NSLayoutConstraint.activate([
            acrBadge.topAnchor.constraint(equalTo: acrBadgeContainer.topAnchor, constant: padding+2),
            acrBadge.bottomAnchor.constraint(equalTo: acrBadgeContainer.bottomAnchor, constant: -padding-2),
            acrBadge.leadingAnchor.constraint(equalTo: acrBadgeContainer.leadingAnchor, constant: padding),
            acrBadge.trailingAnchor.constraint(equalTo: acrBadgeContainer.trailingAnchor, constant: -padding)
        ])

        // JPG badge
        jpgBadge.font = NSFont.boldSystemFont(ofSize: 8)
        jpgBadge.textColor = .white
        jpgBadge.alignment = .center
        jpgBadge.isBordered = false
        jpgBadge.drawsBackground = false
        jpgBadge.wantsLayer = true
        jpgBadge.setContentHuggingPriority(.required, for: .horizontal)

        jpgBadgeContainer.wantsLayer = true
        jpgBadgeContainer.addSubview(jpgBadge)
        jpgBadge.translatesAutoresizingMaskIntoConstraints = false
        let paddingJpg: CGFloat = 2
        NSLayoutConstraint.activate([
            jpgBadge.topAnchor.constraint(equalTo: jpgBadgeContainer.topAnchor, constant: paddingJpg),
            jpgBadge.bottomAnchor.constraint(equalTo: jpgBadgeContainer.bottomAnchor, constant: -paddingJpg),
            jpgBadge.leadingAnchor.constraint(equalTo: jpgBadgeContainer.leadingAnchor, constant: paddingJpg),
            jpgBadge.trailingAnchor.constraint(equalTo: jpgBadgeContainer.trailingAnchor, constant: -paddingJpg)
        ])

        // Badge stack
        badgeStack.orientation = .horizontal
        badgeStack.spacing = 6
        badgeStack.alignment = .centerY
        badgeStack.distribution = .fill
        badgeStack.addArrangedSubview(acrBadgeContainer)
        badgeStack.addArrangedSubview(jpgBadgeContainer)
        badgeStack.isHidden = true

        let labelCell = VerticallyCenteredTextFieldCell()
        labelCell.font = NSFont.systemFont(ofSize: 11)
        labelCell.textColor = .labelColor
        labelCell.lineBreakMode = .byTruncatingMiddle
        labelCell.alignment = .center
        filenameLabel.cell = labelCell
        filenameLabel.wantsLayer = true

        for sub in [thumbView, selectionBorder, trashContainer, badgeStack, filenameLabel] as [NSView] {
            root.addSubview(sub)
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        configureLayers()
        layoutSubviews()
    }

    private func configureLayers() {
        view.layer?.backgroundColor = NSColor(white: 0.15, alpha: 1).cgColor
        selectionBorder.layer?.borderColor = NSColor.systemBlue.cgColor
        selectionBorder.layer?.borderWidth = selectionBorder.isHidden ? 0 : 2

        if let layer = trashContainer.layer {
            layer.masksToBounds = false
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.6
            layer.shadowRadius = 3.0
            layer.shadowOffset = CGSize(width: 0, height: 0)
        }

        if let layer = acrBadgeContainer.layer {
            layer.masksToBounds = false
            layer.cornerRadius = 3
            layer.backgroundColor = NSColor.gray.cgColor
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.5
            layer.shadowRadius = 2.0
            layer.shadowOffset = CGSize(width: 0, height: 0)
        }

        if let layer = jpgBadgeContainer.layer {
            layer.cornerRadius = 3
            layer.masksToBounds = false
            layer.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.8).cgColor
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.5
            layer.shadowRadius = 2.0
            layer.shadowOffset = CGSize(width: 0, height: 0)
        }

        filenameLabel.layer?.cornerRadius = 4
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

        let imgPad: CGFloat = 2
        thumbView.frame = CGRect(x: imgPad, y: thumbY, width: w - imgPad * 2, height: size - imgPad)

        let imageRect = actualImageRect(in: thumbView.frame)
        selectionBorder.frame = view.bounds
        let iconSize: CGFloat = 24
        trashContainer.frame = CGRect(x: imageRect.midX - iconSize/2,
                                      y: imageRect.midY - iconSize/2,
                                      width: iconSize,
                                      height: iconSize)
        trashOverlay.frame = trashContainer.bounds

        // Badge stack — top-right of image rect
        let stackSize = badgeStack.fittingSize
        let stackW = stackSize.width > 0 ? stackSize.width : 44
        let stackH: CGFloat = 16 + 8
        badgeStack.frame = CGRect(
            x: w - stackW - 4,
            y: h - stackH,
            width: stackW,
            height: stackH
        )

        let pad: CGFloat = 2
        let maxLabelW = w - pad * 2
        filenameLabel.sizeToFit()
        let labelW = min(filenameLabel.frame.width, maxLabelW)
        let labelX = (w - labelW) / 2
        filenameLabel.frame = CGRect(x: labelX, y: labelY + 1, width: labelW, height: labelH)

        // Star view
        if photo.isRawFile {
            if starView == nil {
                let sv = AppKitStarRatingView()
                sv.onRatingChanged = { [weak self] r in
                    guard let self, let p = self.currentPhoto else { return }
                    self.callbacks?.onRatingChanged(p, r)
                }
                view.addSubview(sv)
                starView = sv
            }
            let rating = currentRating(for: photo)
            starView?.rating = rating
            starView?.frame = CGRect(x: 0, y: labelY - starH - 2, width: w, height: starH)
            starView?.isHidden = rating == 0
        } else {
            starView?.isHidden = true
        }
    }

    private func actualImageRect(in frame: CGRect) -> CGRect {
        guard let image = thumbView.image else { return frame }
        // Use pixel size from the best representation for accurate scaling
        let pixelSize: CGSize
        if let rep = image.bestRepresentation(for: frame, context: nil, hints: nil) {
            pixelSize = CGSize(width: rep.pixelsWide > 0 ? CGFloat(rep.pixelsWide) : image.size.width,
                               height: rep.pixelsHigh > 0 ? CGFloat(rep.pixelsHigh) : image.size.height)
        } else {
            pixelSize = image.size
        }
        // NSImageView scales proportionally — mirror its exact calculation
        let viewScale = view.window?.backingScaleFactor ?? 1.0
        let displayW = pixelSize.width / viewScale
        let displayH = pixelSize.height / viewScale
        let scale = min(frame.width / displayW, frame.height / displayH)
        let drawW = (displayW * scale).rounded()
        let drawH = (displayH * scale).rounded()
        let x = (frame.minX + (frame.width - drawW) / 2).rounded()
        let y = (frame.minY + (frame.height - drawH) / 2).rounded()
        return CGRect(x: x, y: y, width: drawW, height: drawH)
    }

    private func setupTrackingArea() {
        view.trackingAreas.forEach { view.removeTrackingArea($0) }
        let ta = NSTrackingArea(rect: view.bounds,
                                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                owner: self, userInfo: nil)
        view.addTrackingArea(ta)
    }

    // MARK: Configure

    var thumbImage: IRImage? { thumbView.image }

    func setThumb(_ image: IRImage) {
        thumbView.image = image
        currentImageSize = image.size
        layoutSubviews()
    }

    func configure(with photo: PhotoItem,
                   isSelected: Bool,
                   itemSize: CGFloat,
                   priority: ThumbnailRequest.Priority = .high,
                   callbacks: ThumbCellCallbacks) {
        self.callbacks = callbacks
        self.itemSize = itemSize

        let pathChanged = currentPath != photo.path
        currentPath = photo.path
        currentPhoto = photo

        if pathChanged {
            loadTask?.cancel()
            loadTask = nil
            thumbView.image = nil
            currentImageSize = .zero

            if let cached = ThumbsManager.shared.getCachedThumbnail(for: photo) {
                thumbView.image = cached
                currentImageSize = cached.size
                layoutSubviews()
            } else {
                let path = photo.path
                let work = DispatchWorkItem { [weak self] in
                    ThumbsManager.shared.loadThumbnail(for: photo, priority: priority) { image in
                        DispatchQueue.main.async {
                            guard self?.currentPath == path else {
                                return
                            }
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
        trashContainer.isHidden = !photo.toDelete

        let showACR = photo.hasACR
        let showJPG = photo.isRawFile && photo.hasJPG
        acrBadgeContainer.isHidden = !showACR
        jpgBadgeContainer.isHidden = !showJPG
        badgeStack.isHidden = !showACR && !showJPG

        filenameLabel.stringValue = URL(fileURLWithPath: photo.path).lastPathComponent
        applyLabelStyle(for: photo)
        starView?.rating = currentRating(for: photo)
        view.menu = makeContextMenu(for: photo)

        if view.trackingAreas.isEmpty { setupTrackingArea() }
        if view.bounds.width > 0 { layoutSubviews() }
    }

    func updateSelection(isSelected: Bool) {
        selectionBorder.isHidden = !isSelected
        selectionBorder.layer?.borderWidth = isSelected ? 2 : 0
    }

    // MARK: Context menu

    private func makeContextMenu(for photo: PhotoItem) -> NSMenu {
        let menu = NSMenu()

        // Review — resolves selected photos at action time
        let review = NSMenuItem(title: "Review Photos", action: #selector(menuReview), keyEquivalent: "")
        review.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)
        menu.addItem(review)
        menu.addItem(.separator())

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

    @objc private func menuReview() {
        guard let p = currentPhoto else { return }
        callbacks?.onReviewSelected(p)
    }

    @objc private func menuShowInFinder() {
        guard let path = currentPath else { return }
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
    @objc private func menuCopyTo() { guard let p = currentPhoto else { return }; callbacks?.onCopyTo(p) }
    @objc private func menuRenameTo() { guard let p = currentPhoto else { return }; callbacks?.onRenameTo(p) }
    @objc private func menuMoveToTrash() { guard let p = currentPhoto else { return }; callbacks?.onMoveToTrash(p) }
    @objc private func menuMoveAllToTrash() { guard let p = currentPhoto else { return }; callbacks?.onMoveAllMarkedToTrash(p)?.action() }

    // MARK: Helpers

    private func currentRating(for photo: PhotoItem) -> Int {
        if let r = photo.xmp?.rating, r > 0 { return r }
        return photo.inCameraRating ?? 0
    }

    private func applyLabelStyle(for photo: PhotoItem) {
        if photo.toDelete {
            filenameLabel.layer?.backgroundColor = NSColor.orange.cgColor
            filenameLabel.textColor = .black;
            return
        }
        guard let label = photo.xmp?.label, !label.isEmpty else {
            filenameLabel.layer?.backgroundColor = NSColor.clear.cgColor
            filenameLabel.textColor = .labelColor;
            return
        }
        switch label {
        case "Select":   filenameLabel.layer?.backgroundColor = NSColor.systemRed.cgColor;    filenameLabel.textColor = .white
        case "Second":   filenameLabel.layer?.backgroundColor = NSColor.systemYellow.cgColor; filenameLabel.textColor = .black
        case "Approved": filenameLabel.layer?.backgroundColor = NSColor(red: 133/255, green: 199/255, blue: 102/255, alpha: 1).cgColor; filenameLabel.textColor = .black
        case "Review":   filenameLabel.layer?.backgroundColor = NSColor.systemBlue.cgColor;   filenameLabel.textColor = .white
        case "To Do":    filenameLabel.layer?.backgroundColor = NSColor.systemPurple.cgColor; filenameLabel.textColor = .white
        default:         filenameLabel.layer?.backgroundColor = NSColor.clear.cgColor;         filenameLabel.textColor = .labelColor
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
        trashContainer.isHidden = true
        badgeStack.isHidden = true
        acrBadgeContainer.isHidden = true
        jpgBadgeContainer.isHidden = true
        starView?.removeFromSuperview()
        starView = nil
        view.menu = nil
    }
}

extension ThumbCollectionItem {
    override func mouseEntered(with event: NSEvent) {
        starView?.isHidden = !(currentPhoto?.isRawFile ?? false)
    }

    override func mouseExited(with event: NSEvent) {
        let rating = currentPhoto.map {
            currentRating(for: $0)
        } ?? 0
        if rating == 0 {
            starView?.isHidden = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard let photo = currentPhoto else {
            return
        }
        if event.clickCount == 1 {
            callbacks?.onTap(photo, event.modifierFlags)
        } else if event.clickCount == 2 {
            callbacks?.onDoubleClick(photo)
        }
    }
}
#endif
