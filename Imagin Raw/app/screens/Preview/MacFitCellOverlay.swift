//
//  MacFitCellOverlay.swift
//  Imagin Raw
//
//  Hover overlay of a MacFitImageCell: file name (tinted by label), rating stars,
//  approve and reject buttons.
//

import AppKit

final class MacFitCellOverlay: NSView {

    var onRatingChanged: ((Int) -> Void)?
    var onApprove: (() -> Void)?
    var onReject: (() -> Void)?
    var onRemove: (() -> Void)?
    /// The remove button is shown only when more than one photo is displayed.
    var canRemove = true {
        didSet {
            if oldValue != canRemove {
                removeBar.isHidden = !canRemove
                needsLayout = true
            }
        }
    }

    private let bar = NSView()
    private let removeBar = NSView()
    private let removeButton = NSButton()
    private let filenameLabel = NSTextField(labelWithString: "")
    private let starView = MacStarRatingView()
    private let approveButton = NSButton()
    private let rejectButton = NSButton()

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        addSubview(bar)

        filenameLabel.font = NSFont.systemFont(ofSize: 11)
        filenameLabel.alignment = .center
        filenameLabel.lineBreakMode = .byTruncatingMiddle
        filenameLabel.textColor = .white
        filenameLabel.wantsLayer = true
        filenameLabel.layer?.cornerRadius = 4
        bar.addSubview(filenameLabel)

        starView.colorScheme = .dark
        starView.onRatingChanged = { [weak self] rating in
            self?.onRatingChanged?(rating)
        }
        bar.addSubview(starView)

        configure(button: approveButton, symbol: "checkmark.circle.fill", action: #selector(approveTapped))
        configure(button: rejectButton, symbol: "xmark.circle.fill", action: #selector(rejectTapped))
        approveButton.toolTip = "Approve (A)"
        rejectButton.toolTip = "Reject (X)"
        bar.addSubview(approveButton)
        bar.addSubview(rejectButton)

        removeBar.wantsLayer = true
        removeBar.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        addSubview(removeBar)
        configure(button: removeButton, symbol: "xmark", action: #selector(removeTapped))
        removeButton.contentTintColor = .white
        removeButton.toolTip = "Remove from preview"
        removeBar.addSubview(removeButton)
    }

    @objc private func removeTapped() {
        onRemove?()
    }

    private func configure(button: NSButton, symbol: String, action: Selector) {
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyUpOrDown
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.target = self
        button.action = action
    }

    @objc private func approveTapped() {
        onApprove?()
    }

    @objc private func rejectTapped() {
        onReject?()
    }

    func configure(with photo: PhotoItem) {
        filenameLabel.stringValue = photo.url.lastPathComponent
        if let label = PhotoLabel(rawValue: photo.xmp?.label ?? photo.state.rawValue) {
            filenameLabel.layer?.backgroundColor = label.nsCGColor
            filenameLabel.textColor = label.nsTextColor
        } else {
            filenameLabel.layer?.backgroundColor = NSColor.clear.cgColor
            filenameLabel.textColor = .white
        }

        let supportsRating = photo.isRaw || JpegMetadataWriter.isSupported(photo.url)
        starView.isHidden = !supportsRating
        starView.rating = photo.effectiveRating

        let isApproved = photo.xmp?.label == PhotoLabel.approved.rawValue
        approveButton.contentTintColor = isApproved ? PhotoLabel.approved.nsColor : .white
        rejectButton.contentTintColor = photo.state == .rejected ? PhotoLabel.rejected.nsColor : .white
    }

    override func layout() {
        super.layout()

        let pillH: CGFloat = 28
        let bottomPadding: CGFloat = 8
        let hPad: CGFloat = 10
        let gap: CGFloat = 8
        let buttonSize: CGFloat = 18
        let starW: CGFloat = 5 * starView.starSize + 4 * 2 + 4
        let showStars = !starView.isHidden

        var fixedW = hPad * 2 + gap * 2 + buttonSize * 2
        if showStars {
            fixedW += starW + gap
        }
        filenameLabel.sizeToFit()
        let maxLabelW = max(0, bounds.width - 16 - fixedW)
        let labelW = min(filenameLabel.frame.width + 8, maxLabelW)
        let pillW = fixedW + labelW
        let removeGap: CGFloat = 6
        let removeW: CGFloat = canRemove ? pillH + removeGap : 0
        let groupX = (bounds.width - pillW - removeW) / 2
        let pillY = bounds.height - pillH - bottomPadding

        bar.frame = CGRect(x: groupX, y: pillY, width: pillW, height: pillH)
        bar.layer?.cornerRadius = pillH / 2

        removeBar.frame = CGRect(x: groupX + pillW + removeGap, y: pillY, width: pillH, height: pillH)
        removeBar.layer?.cornerRadius = pillH / 2
        removeButton.frame = CGRect(x: (pillH - 14) / 2, y: (pillH - 14) / 2, width: 14, height: 14)

        var x = hPad
        filenameLabel.frame = CGRect(x: x, y: (pillH - 16) / 2, width: labelW, height: 16)
        x += labelW + gap
        if showStars {
            starView.frame = CGRect(x: x, y: (pillH - buttonSize) / 2, width: starW, height: buttonSize)
            x += starW + gap
        }
        approveButton.frame = CGRect(x: x, y: (pillH - buttonSize) / 2, width: buttonSize, height: buttonSize)
        x += buttonSize + gap
        rejectButton.frame = CGRect(x: x, y: (pillH - buttonSize) / 2, width: buttonSize, height: buttonSize)
    }


    /// Only the bar's controls take clicks; everything else passes through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return (hit === self || hit === bar || hit === removeBar) ? nil : hit
    }
}
