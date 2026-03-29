//
//  AppKitStarRatingView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 17.03.2026.
//
import Foundation
import AppKit

final class AppKitStarRatingView: NSView {

    var rating: Int = 0 {
        didSet {
            if oldValue != rating {
                needsDisplay = true
            }
        }
    }
    var maxRating: Int = 5
    var starSize: CGFloat = 14
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

//    override func mouseMoved(with event: NSEvent) {
//        let loc = convert(event.locationInWindow, from: nil)
//        let spacing: CGFloat = 2
//        let total = CGFloat(maxRating) * starSize + CGFloat(maxRating - 1) * spacing
//        let startX = (bounds.width - total) / 2
//        for i in 1...maxRating {
//            let x = startX + CGFloat(i - 1) * (starSize + spacing)
//            if loc.x >= x && loc.x <= x + starSize {
//                let newRating = (rating == i) ? 0 : i
//                rating = newRating
//                return
//            }
//        }
//    }

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
