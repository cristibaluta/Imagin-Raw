//
//  MinimapView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 16.04.2026.
//

import SwiftUI

#if os(macOS)
// MARK: - Custom instant tooltip window

private final class TooltipWindow: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private let bubbleView = TooltipBubbleView()

    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask,
                  backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: [.nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = NSColor(white: 0.15, alpha: 1)
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.lineBreakMode = .byClipping

        bubbleView.addSubview(label)
        contentView = bubbleView
    }

    func show(text: String, near point: NSPoint) {
        label.stringValue = text
        label.sizeToFit()

        let hPad: CGFloat = 20
        let vPad: CGFloat = 12
        let arrowW: CGFloat = 7
        let arrowH: CGFloat = 10
        let cornerR: CGFloat = 6

        let bubbleW = label.frame.width + hPad * 2
        let bubbleH = label.frame.height + vPad * 2
        let totalW  = bubbleW + arrowW
        let totalH  = max(bubbleH, arrowH + cornerR * 2)

        label.frame = NSRect(x: hPad + arrowW, y: (totalH - label.frame.height) / 2,
                             width: label.frame.width, height: label.frame.height)

        bubbleView.arrowWidth  = arrowW
        bubbleView.arrowHeight = arrowH
        bubbleView.cornerRadius = cornerR
        bubbleView.frame = NSRect(origin: .zero, size: NSSize(width: totalW, height: totalH))
        bubbleView.needsDisplay = true

        // Position: to the right of the minimap, arrow tip pointing left at cursor
        let origin = NSPoint(x: point.x + 14, y: point.y - totalH / 2)
        setFrame(NSRect(origin: origin, size: NSSize(width: totalW, height: totalH)), display: true)
        orderFront(nil)
    }

    func hide() {
        orderOut(nil)
    }
}

/// A bubble with a right-pointing arrow on the trailing edge.
private final class TooltipBubbleView: NSView {
    var arrowWidth: CGFloat  = 7
    var arrowHeight: CGFloat = 10
    var cornerRadius: CGFloat = 6

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let aw = arrowWidth
        let ah = arrowHeight
        let r  = cornerRadius
        let b  = bounds
        let bh = b.height
        // Bubble rect starts after the arrow
        let bx: CGFloat = aw
        let bw = b.width - aw
        let midY = b.midY

        let path = NSBezierPath()
        // Start at top-left corner of bubble (after arrow), go clockwise
        path.move(to: NSPoint(x: bx + r, y: bh))
        path.line(to: NSPoint(x: bx + bw - r, y: bh))
        path.appendArc(withCenter: NSPoint(x: bx + bw - r, y: bh - r), radius: r,
                       startAngle: 90, endAngle: 0, clockwise: true)
        path.line(to: NSPoint(x: bx + bw, y: r))
        path.appendArc(withCenter: NSPoint(x: bx + bw - r, y: r), radius: r,
                       startAngle: 0, endAngle: -90, clockwise: true)
        path.line(to: NSPoint(x: bx + r, y: 0))
        path.appendArc(withCenter: NSPoint(x: bx + r, y: r), radius: r,
                       startAngle: -90, endAngle: 180, clockwise: true)
        // Arrow bottom shoulder → tip → top shoulder (pointing left)
        path.line(to: NSPoint(x: bx, y: midY - ah / 2))
        path.line(to: NSPoint(x: 0, y: midY))
        path.line(to: NSPoint(x: bx, y: midY + ah / 2))
        path.line(to: NSPoint(x: bx, y: bh - r))
        path.appendArc(withCenter: NSPoint(x: bx + r, y: bh - r), radius: r,
                       startAngle: 180, endAngle: 90, clockwise: true)
        path.close()

        NSColor.white.setFill()
        path.fill()

        NSColor(white: 0.0, alpha: 0.08).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }
}

// MARK: - NSView with tracking area for instant hover

private final class MinimapItemTrackingView: NSView {
    var onMouseEntered: ((NSPoint) -> Void)?
    var onMouseMoved: ((NSPoint) -> Void)?
    var onMouseExited: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Let clicks fall through to the SwiftUI tap gesture beneath
        return nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        onMouseEntered?(window?.convertPoint(toScreen: convert(p, to: nil)) ?? .zero)
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        onMouseMoved?(window?.convertPoint(toScreen: convert(p, to: nil)) ?? .zero)
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }
}

private struct MinimapItemTracker: NSViewRepresentable {
    let onEnter: (NSPoint) -> Void
    let onMove: (NSPoint) -> Void
    let onExit: () -> Void

    func makeNSView(context: Context) -> MinimapItemTrackingView {
        let v = MinimapItemTrackingView()
        v.onMouseEntered = onEnter
        v.onMouseMoved = onMove
        v.onMouseExited = onExit
        return v
    }
    func updateNSView(_ nsView: MinimapItemTrackingView, context: Context) {
        nsView.onMouseEntered = onEnter
        nsView.onMouseMoved = onMove
        nsView.onMouseExited = onExit
    }
}
#endif

// MARK: - MinimapView

enum MinimapStyle {
    /// Proportional rectangles that fill available height
    case proportional
    /// Fixed 10px circles equally spaced, centered vertically
    case compact
}

struct MinimapView: View {
    let groups: [(title: String, photos: [PhotoItem])]
    let onScrollTo: (UUID) -> Void
    /// Index of the section currently at the top of the scroll view.
    let visibleSectionIndex: Int
    var style: MinimapStyle = .compact

    @State private var hoveredIndex: Int? = nil
#if os(macOS)
    @State private var tooltipWindow = TooltipWindow()
#endif

    static let width: CGFloat = 16
    private let spacing: CGFloat = 2
    private let minSquareHeight: CGFloat = 4

    // Compact style constants
    private let circleSize: CGFloat = 8
    private let circleSpacing: CGFloat = 6

    var body: some View {
        switch style {
        case .proportional:
            proportionalBody
        case .compact:
            compactBody
        }
    }

    // MARK: Proportional

    private var proportionalBody: some View {
        GeometryReader { geo in
            let squareH = squareHeight(for: geo.size.height)
            VStack(spacing: spacing) {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    minimapItem(index: index, group: group)
                        .frame(width: MinimapView.width - 10, height: squareH)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }
            .frame(width: MinimapView.width - 10, alignment: .center)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.leading, 5)
        }
        .frame(width: MinimapView.width)
    }

    // MARK: Compact

    private var compactBody: some View {
        GeometryReader { geo in
            let count = CGFloat(groups.count)
            let totalH = count * circleSize + max(0, count - 1) * circleSpacing
            let topOffset = (geo.size.height - totalH) / 2

            VStack(spacing: circleSpacing) {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    minimapItem(index: index, group: group)
                        .frame(width: circleSize, height: circleSize)
                        .clipShape(Circle())
                }
            }
            .frame(width: MinimapView.width)
            .offset(y: max(0, topOffset))
        }
        .frame(width: MinimapView.width)
    }

    // MARK: Shared item

    @ViewBuilder
    private func minimapItem(index: Int, group: (title: String, photos: [PhotoItem])) -> some View {
        let isActive = index == visibleSectionIndex
        Color.secondary
            .opacity(isActive ? 1.0 : hoveredIndex == index ? 0.65 : 0.3)
            .contentShape(Rectangle())
            .onTapGesture {
                if let first = group.photos.first {
                    onScrollTo(first.id)
                }
            }
            #if os(macOS)
            .overlay(
                MinimapItemTracker(
                    onEnter: { screenPt in
                        withAnimation(.easeInOut(duration: 0.1)) { hoveredIndex = index }
                        tooltipWindow.show(text: group.title, near: screenPt)
                    },
                    onMove: { screenPt in
                        tooltipWindow.show(text: group.title, near: screenPt)
                    },
                    onExit: {
                        withAnimation(.easeInOut(duration: 0.1)) { hoveredIndex = nil }
                        tooltipWindow.hide()
                    }
                )
            )
            #endif
    }

    private func squareHeight(for availableHeight: CGFloat) -> CGFloat {
        guard !groups.isEmpty else {
            return minSquareHeight
        }
        let totalSpacing = spacing * CGFloat(groups.count - 1)
        let raw = (availableHeight - totalSpacing) / CGFloat(groups.count)
        return max(minSquareHeight, raw)
    }
}
