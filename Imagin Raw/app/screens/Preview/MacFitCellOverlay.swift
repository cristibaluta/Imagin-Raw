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

    private let bar = NSView()
    private let filenameLabel = NSTextField(labelWithString: "")
    private let starView = MacStarRatingView()
    private let approveButton = NSButton()
    private let rejectButton = NSButton()
    private let barHeight: CGFloat = 52

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
        bar.frame = CGRect(x: 0, y: bounds.height - barHeight, width: bounds.width, height: barHeight)

        let w = bar.bounds.width
        filenameLabel.sizeToFit()
        let labelW = min(filenameLabel.frame.width + 8, w - 8)
        filenameLabel.frame = CGRect(x: (w - labelW) / 2, y: 5, width: labelW, height: 16)

        let rowY: CGFloat = 26
        let buttonSize: CGFloat = 20
        let starW: CGFloat = 5 * starView.starSize + 4 * 2 + 4
        let total = buttonSize + 10 + starW + 10 + buttonSize
        var x = (w - total) / 2
        approveButton.frame = CGRect(x: x, y: rowY, width: buttonSize, height: buttonSize)
        x += buttonSize + 10
        starView.frame = CGRect(x: x, y: rowY, width: starW, height: buttonSize)
        x += starW + 10
        rejectButton.frame = CGRect(x: x, y: rowY, width: buttonSize, height: buttonSize)
    }

    /// Only the bar's controls take clicks; everything else passes through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return (hit === self || hit === bar) ? nil : hit
    }
}
