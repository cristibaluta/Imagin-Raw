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

        bar.frame = CGRect(x: (bounds.width - pillW) / 2,
                           y: bounds.height - pillH - bottomPadding,
                           width: pillW,
                           height: pillH)
        bar.layer?.cornerRadius = pillH / 2

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
        return (hit === self || hit === bar) ? nil : hit
    }
}
