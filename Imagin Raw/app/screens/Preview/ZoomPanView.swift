//
//  ZoomPanView.swift
//  Imagin Raw
//

import SwiftUI

/// Displays an image at 100% pixel resolution (1 image pixel = 1 screen point).
/// The viewport pans automatically as the mouse moves — no click-drag needed.
#if os(macOS)
struct ZoomPanView: View {
    let image: IRImage
    var initialMousePosition: CGPoint = CGPoint(x: 0.5, y: 0.5)

    @State private var mousePosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
    private var pixelSize: CGSize {
        if let rep = image.representations.first as? NSBitmapImageRep {
            let s = CGSize(width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh))
//            print("🔎 [zoom] pixelSize from BitmapRep: \(s.width)×\(s.height)")
            return s
        }
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let s = CGSize(width: CGFloat(cg.width), height: CGFloat(cg.height))
//            print("🔎 [zoom] pixelSize from CGImage: \(s.width)×\(s.height)")
            return s
        }
//        print("🔎 [zoom] pixelSize fallback to image.size: \(image.size)")
        return image.size
    }

    var body: some View {
        GeometryReader { geo in
            let imgW = pixelSize.width
            let imgH = pixelSize.height
            let viewW = geo.size.width
            let viewH = geo.size.height
            let overflowX = max(0, imgW - viewW)
            let overflowY = max(0, imgH - viewH)
            let offsetX = -overflowX * mousePosition.x
            let offsetY = -overflowY * mousePosition.y

            Image(nsImage: image)
                .resizable()
                .frame(width: imgW, height: imgH)
                .offset(x: offsetX, y: offsetY)
                .frame(width: viewW, height: viewH, alignment: .topLeading)
                .clipped()
                .background(MouseTrackingView(onMouseMoved: { point, viewSize in
                    let nx = viewSize.width  > 0 ? max(0, min(1, point.x / viewSize.width))  : 0.5
                    let ny = viewSize.height > 0 ? max(0, min(1, 1 - point.y / viewSize.height)) : 0.5
                    mousePosition = CGPoint(x: nx, y: ny)
                }))
        }
        .onAppear {
            mousePosition = initialMousePosition
        }
    }
}

// MARK: - NSView mouse tracker

struct MouseTrackingView: NSViewRepresentable {
    let onMouseMoved: (CGPoint, CGSize) -> Void

    func makeNSView(context: Context) -> TrackerNSView {
        let v = TrackerNSView()
        v.onMouseMoved = onMouseMoved
        return v
    }

    func updateNSView(_ nsView: TrackerNSView, context: Context) {
        nsView.onMouseMoved = onMouseMoved
    }
}

class TrackerNSView: NSView {
    var onMouseMoved: ((CGPoint, CGSize) -> Void)?
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let old = trackingArea {
            removeTrackingArea(old)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onMouseMoved?(point, bounds.size)
    }

    override func mouseDown(with event: NSEvent) {
        // Don't consume the click — let SwiftUI keep focus
        nextResponder?.mouseDown(with: event)
    }
}
#endif
