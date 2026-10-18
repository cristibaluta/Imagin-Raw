//
//  MacFitCellView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 18/10/2026.
//

import AppKit

/// Cell root view: reports the normalized mouse position (0...1, origin top-left).
final class MacFitCellView: NSView {
    var onMouseMoved: ((CGPoint) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }
        let p = convert(event.locationInWindow, from: nil)
        let nx = max(0, min(1, p.x / bounds.width))
        let ny = max(0, min(1, 1 - p.y / bounds.height))
        onMouseMoved?(CGPoint(x: nx, y: ny))
    }
}
