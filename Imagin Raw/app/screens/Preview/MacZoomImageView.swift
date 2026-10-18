//
//  MacZoomImageView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 18/10/2026.
//

import AppKit

/// Shows an image at 100% pixel size, panned by a normalized position.
final class MacZoomImageView: NSView {
    private let contentLayer = CALayer()
    private var pixelSize: CGSize = .zero

    var position = CGPoint(x: 0.5, y: 0.5) {
        didSet { updateContentFrame() }
    }

    var image: NSImage? {
        didSet {
            if let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                pixelSize = CGSize(width: cg.width, height: cg.height)
                contentLayer.contents = cg
            } else {
                pixelSize = .zero
                contentLayer.contents = nil
            }
            updateContentFrame()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        contentLayer.anchorPoint = .zero
        layer?.addSublayer(contentLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateContentFrame()
    }

    private func updateContentFrame() {
        let overflowX = max(0, pixelSize.width - bounds.width)
        let overflowY = max(0, pixelSize.height - bounds.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.bounds = CGRect(origin: .zero, size: pixelSize)
        // Layer origin is bottom-left; position.y = 0 means top of the image
        contentLayer.position = CGPoint(x: -overflowX * position.x,
                                        y: bounds.height - pixelSize.height + overflowY * position.y)
        CATransaction.commit()
    }
}
