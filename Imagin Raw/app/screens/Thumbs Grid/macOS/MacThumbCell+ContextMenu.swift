//
//  MacThumbCell+ContextMenu.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 05/06/2026.
//

#if os(macOS)
import AppKit

extension MacThumbCell {

    func makeContextMenu(for photo: PhotoItem) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }

    func populateMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let photo = currentPhoto else {
            return
        }

        // Review — resolves selected photos at action time
        let selectedCount = delegate?.selectedPhotosCount() ?? 0
        let reviewCount = max(selectedCount, 1)
        let review = NSMenuItem(title: "Review Photos\(reviewCount >= 2 ? " (\(reviewCount))" : "")",
                                action: reviewCount >= 2 ? #selector(handleReview) : nil,
                                keyEquivalent: " ")
        review.keyEquivalentModifierMask = []
        review.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)
        menu.addItem(review)
        menu.addItem(.separator())

        let isRaw = photo.isRawFile
        let url = URL(fileURLWithPath: photo.path)
        let supportsMetadata = isRaw || JpegMetadataWriter.isSupported(url)

        // Rate submenu
        let rateItem = NSMenuItem(title: "Rate", action: nil, keyEquivalent: "")
//        rateItem.image = NSImage(systemSymbolName: "star", accessibilityDescription: nil)
        if !supportsMetadata { rateItem.isEnabled = false }
        let rateMenu = NSMenu()
        for i in 0...5 {
            let title = i == 0 ? "No Rating" : String(repeating: "★", count: i)
            let item = NSMenuItem(title: title, action: #selector(handleSetRating(_:)), keyEquivalent: i > 0 ? "\(i)" : "")
            item.keyEquivalentModifierMask = []
            item.tag = i
            if currentRating(for: photo) == i {
                item.state = .on
            }
            rateMenu.addItem(item)
        }
        rateItem.submenu = rateMenu
        menu.addItem(rateItem)

        // Label submenu
        let labelItem = NSMenuItem(title: "Label", action: nil, keyEquivalent: "")
//        labelItem.image = NSImage(systemSymbolName: "tag", accessibilityDescription: nil)
        if !supportsMetadata { labelItem.isEnabled = false }
        let labelMenu = NSMenu()
        let labels: [(name: String, key: String)] = [
            ("Select", "6"), ("Second", "7"), ("Approved", "8"), ("Review", "9"), ("To Do", "0")
        ]
        let currentLabel = photo.xmp?.label ?? ""
        for (name, key) in labels {
            let item = NSMenuItem(title: name, action: #selector(handleSetLabel(_:)), keyEquivalent: key)
            item.keyEquivalentModifierMask = []
            item.representedObject = name
            if currentLabel == name { item.state = .on }
            let colorDot = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
                NSColor(PhotoLabel.color(for: name)).setFill()
                NSBezierPath(ovalIn: rect).fill()
                return true
            }
            item.image = colorDot
            labelMenu.addItem(item)
        }
        let removeItem = NSMenuItem(title: "No Label", action: #selector(handleRemoveLabel), keyEquivalent: "-")
        removeItem.keyEquivalentModifierMask = []
        if currentLabel.isEmpty { removeItem.state = .on }
        labelMenu.addItem(.separator())
        labelMenu.addItem(removeItem)
        labelItem.submenu = labelMenu
        menu.addItem(labelItem)

        // Approve
        let approveItem = NSMenuItem(title: "Approve", action: supportsMetadata ? #selector(handleApprove) : nil, keyEquivalent: "a")
        approveItem.keyEquivalentModifierMask = []
        approveItem.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        if !supportsMetadata {
            approveItem.isEnabled = false
        }
        menu.addItem(approveItem)

        // Reject
        let rejectItem = NSMenuItem(title: "Reject", action: supportsMetadata ? #selector(handleReject) : nil, keyEquivalent: "x")
        rejectItem.keyEquivalentModifierMask = []
        rejectItem.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        if !supportsMetadata { rejectItem.isEnabled = false }
        menu.addItem(rejectItem)

        menu.addItem(.separator())
        let finder = NSMenuItem(title: "Show in Finder", action: #selector(handleShowInFinder), keyEquivalent: "")
//        finder.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        menu.addItem(finder)

        // Open with submenu
        if let apps = delegate?.discoveredPhotoApps(), !apps.isEmpty {
            let openWithItem = NSMenuItem(title: "Open with", action: nil, keyEquivalent: "")
//            openWithItem.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil)
            let openWithMenu = NSMenu()
            for app in apps {
                let appItem = NSMenuItem(title: app.displayName, action: #selector(handleOpenWithApp(_:)), keyEquivalent: "")
                appItem.representedObject = app
                appItem.image = NSWorkspace.shared.icon(forFile: app.url.path)
                appItem.image?.size = NSSize(width: 16, height: 16)
                openWithMenu.addItem(appItem)
            }
            openWithItem.submenu = openWithMenu
            menu.addItem(openWithItem)
        }

        let copy = NSMenuItem(title: "Copy to...", action: #selector(handleCopyTo), keyEquivalent: "")
//        copy.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        menu.addItem(copy)
        let rename = NSMenuItem(title: "Batch Rename...", action: #selector(handleRenameTo), keyEquivalent: "")
//        rename.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
        menu.addItem(rename)

        menu.addItem(.separator())

        let trash = NSMenuItem(title: "Move to Trash", action: #selector(handleMoveToTrash), keyEquivalent: String(Unicode.Scalar(NSBackspaceCharacter)!))
        trash.keyEquivalentModifierMask = [.command]
        trash.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(trash)
        if photo.toDelete, let count = delegate?.markedForDeletionCount(), count > 0 {
            let all = NSMenuItem(title: "Move to Trash all Rejected Photos (\(count))",
                                 action: #selector(handleMoveAllToTrash), keyEquivalent: "")
            all.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            menu.addItem(all)
        }
    }

    @objc private func handleReview() {
        guard let p = currentPhoto else {
            return
        }
        delegate?.onReviewSelected(photo: p)
    }

    @objc private func handleShowInFinder() {
        guard let path = currentPath else {
            return
        }
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    @objc private func handleOpenWithApp(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? PhotoApp,
              let photo = currentPhoto else {
            return
        }
        delegate?.onOpenWith(photo: photo, app: app)
    }

    @objc private func handleCopyTo() {
        guard let p = currentPhoto else {
            return
        }
        delegate?.onCopyTo(photo: p)
    }

    @objc private func handleRenameTo() {
        guard let p = currentPhoto else {
            return
        }
        delegate?.onRenameTo(photo: p)
    }

    @objc private func handleMoveToTrash() {
        guard let p = currentPhoto else {
            return
        }
        delegate?.onMoveToTrash(photo: p)
    }

    @objc private func handleMoveAllToTrash() {
        guard let p = currentPhoto else {
            return
        }
        delegate?.onMoveAllMarkedToTrash(photo: p)
    }

    @objc private func handleSetRating(_ sender: NSMenuItem) {
        guard let p = currentPhoto else {
            return
        }
        delegate?.onRatingChanged(photo: p, rating: sender.tag)
    }

    @objc private func handleSetLabel(_ sender: NSMenuItem) {
        guard let p = currentPhoto, let label = sender.representedObject as? String else {
            return
        }
        delegate?.onLabelChanged(photo: p, label: label)
    }

    @objc private func handleRemoveLabel() {
        guard let p = currentPhoto else {
            return
        }
        delegate?.onLabelChanged(photo: p, label: nil)
    }

    @objc private func handleApprove() {
        guard let p = currentPhoto else {
            return
        }
        delegate?.onApprove(photo: p)
    }

    @objc private func handleReject() {
        guard let p = currentPhoto else {
            return
        }
        delegate?.onReject(photo: p)
    }
}
#endif
