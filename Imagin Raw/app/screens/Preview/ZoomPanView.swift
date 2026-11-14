//
//  ZoomPanView.swift
//  Imagin Raw
//

import SwiftUI

/// Displays an image zoomed in. `scale` 1 means 100% (1 image pixel = 1 screen point).
/// The viewport pans automatically as the mouse moves — no click-drag needed.
/// Scrolling (mouse wheel or trackpad) and pinching change the zoom level.
/// When `focusPoint` is set (normalized image coordinates, origin top-left), the view
/// starts centered on it and stays there until the mouse is moved.
#if os(macOS)
struct ZoomPanView: View {
    let image: IRImage
    var focusPoint: CGPoint? = nil
    /// Size to draw the image at instead of its own pixels (used for a low-res stand-in).
    var pixelSizeOverride: CGSize? = nil
    @Binding var scale: CGFloat

    static let maxScale: CGFloat = 4

    @State private var position: CGPoint = CGPoint(x: 0.5, y: 0.5)
    /// Mouse location where the focus hold started; nil when panning follows the mouse.
    @State private var holdStart: CGPoint?
    @State private var isHoldingFocus = false
    @State private var showScaleBadge = false
    @State private var badgeTask: Task<Void, Never>?

    private var pixelSize: CGSize {
        if let pixelSizeOverride {
            return pixelSizeOverride
        }
        if let rep = image.representations.first as? NSBitmapImageRep {
            return CGSize(width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh))
        }
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return CGSize(width: CGFloat(cg.width), height: CGFloat(cg.height))
        }
        return image.size
    }

    /// Scale at which the whole image fits the view (never above 100%).
    private func fitScale(in size: CGSize) -> CGFloat {
        let px = pixelSize
        guard px.width > 0, px.height > 0, size.width > 0, size.height > 0 else {
            return 1
        }
        return min(1, size.width / px.width, size.height / px.height)
    }

    private func clampedScale(_ value: CGFloat, in size: CGSize) -> CGFloat {
        min(Self.maxScale, max(fitScale(in: size), value))
    }

    var body: some View {
        GeometryReader { geo in
            let s = clampedScale(scale, in: geo.size)
            let imgW = pixelSize.width * s
            let imgH = pixelSize.height * s
            let viewW = geo.size.width
            let viewH = geo.size.height
            let overflowX = imgW - viewW
            let overflowY = imgH - viewH
            // Pan when larger than the view, center when smaller
            let offsetX = overflowX > 0 ? -overflowX * position.x : -overflowX / 2
            let offsetY = overflowY > 0 ? -overflowY * position.y : -overflowY / 2

            Image(nsImage: image)
                .resizable()
                .interpolation(s > 1 && pixelSizeOverride == nil ? .none : .high)
                .allowedDynamicRange(.high)
                .frame(width: imgW, height: imgH)
                .offset(x: offsetX, y: offsetY)
                .frame(width: viewW, height: viewH, alignment: .topLeading)
                .clipped()
                .background(MouseTrackingView(
                    onMouseMoved: { point, viewSize in
                        handleMouseMoved(point, viewSize: viewSize)
                    },
                    onZoom: { factor, viewSize in
                        let current = clampedScale(scale, in: viewSize)
                        scale = clampedScale(current * factor, in: viewSize)
                        flashScaleBadge()
                    }).equatable())
                .overlay(alignment: .bottomLeading) {
                    if showScaleBadge {
                        Text("\(Int((s * 100).rounded()))%")
                            .font(.callout.monospacedDigit())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(12)
                            .transition(.opacity)
                    }
                }
                .onAppear {
                    applyFocus(in: geo.size, scale: s)
                }
                .onChange(of: focusPoint) { _, _ in
                    applyFocus(in: geo.size, scale: s)
                }
        }
    }

    // MARK: - Panning

    private func handleMouseMoved(_ point: CGPoint, viewSize: CGSize) {
        let nx = viewSize.width  > 0 ? max(0, min(1, point.x / viewSize.width))  : 0.5
        let ny = viewSize.height > 0 ? max(0, min(1, 1 - point.y / viewSize.height)) : 0.5
        let target = CGPoint(x: nx, y: ny)

        guard isHoldingFocus else {
            position = target
            return
        }
        // Keep the face centered until the mouse really moves, then glide to the mouse.
        guard let start = holdStart else {
            holdStart = point
            return
        }
        if hypot(point.x - start.x, point.y - start.y) > 40 {
            isHoldingFocus = false
            holdStart = nil
            withAnimation(.easeOut(duration: 0.35)) {
                position = target
            }
        }
    }

    /// Pans so `focusPoint` sits in the middle of the view.
    private func applyFocus(in size: CGSize, scale s: CGFloat) {
        guard let focus = focusPoint else {
            return
        }
        let imgW = pixelSize.width * s
        let imgH = pixelSize.height * s
        let overflowX = imgW - size.width
        let overflowY = imgH - size.height
        // offset = -overflow * p, and we want focus * img + offset == view / 2
        let px = overflowX > 0 ? (focus.x * imgW - size.width / 2) / overflowX : 0.5
        let py = overflowY > 0 ? (focus.y * imgH - size.height / 2) / overflowY : 0.5
        position = CGPoint(x: max(0, min(1, px)), y: max(0, min(1, py)))
        isHoldingFocus = true
        holdStart = nil
    }

    private func flashScaleBadge() {
        withAnimation(.easeOut(duration: 0.1)) {
            showScaleBadge = true
        }
        badgeTask?.cancel()
        badgeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }
            withAnimation(.easeIn(duration: 0.3)) {
                showScaleBadge = false
            }
        }
    }
}

// MARK: - NSView mouse tracker

struct MouseTrackingView: NSViewRepresentable, Equatable {
    let onMouseMoved: (@MainActor (CGPoint, CGSize) -> Void)?
    /// Called with a multiplier for the zoom level (> 1 zooms in) from scrolling or pinching.
    let onZoom: (@MainActor (CGFloat, CGSize) -> Void)?

    init(onMouseMoved: (@MainActor (CGPoint, CGSize) -> Void)?,
         onZoom: (@MainActor (CGFloat, CGSize) -> Void)? = nil) {
        self.onMouseMoved = onMouseMoved
        self.onZoom = onZoom
    }

    // Tell SwiftUI this view never needs to update
    nonisolated static func == (lhs: MouseTrackingView, rhs: MouseTrackingView) -> Bool {
        true  // always equal → SwiftUI never recreates it
    }

    func makeNSView(context: Context) -> TrackerNSView {
        let v = TrackerNSView()
        v.onMouseMoved = onMouseMoved
        v.onZoom = onZoom
        return v
    }

    func updateNSView(_ nsView: TrackerNSView, context: Context) {
        nsView.onMouseMoved = onMouseMoved
        nsView.onZoom = onZoom
    }

    static func dismantleNSView(_ nsView: TrackerNSView, coordinator: ()) {
        // Called by SwiftUI when the view is removed from the hierarchy
        nsView.onMouseMoved = nil
        nsView.onZoom = nil
        if let area = nsView.trackingArea {
            nsView.removeTrackingArea(area)
        }
        nsView.trackingArea = nil
    }
}

@MainActor
class TrackerNSView: NSView {
    var onMouseMoved: (@MainActor (CGPoint, CGSize) -> Void)?
    var onZoom: (@MainActor (CGFloat, CGSize) -> Void)?
    var trackingArea: NSTrackingArea?

    deinit {
        // TODO: AppKit should do an automatic cleanup on dealloc, but verify that it's true
//        trackingAreas.forEach {
//            removeTrackingArea($0)
//        }
//        trackingArea = nil
        onMouseMoved = nil
    }

    override var acceptsFirstResponder: Bool {
        false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach {
            removeTrackingArea($0)
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

    // Scroll / pinch are caught with a local event monitor so they work no matter
    // which view is on top under the pointer.
    private var zoomMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let zoomMonitor {
            NSEvent.removeMonitor(zoomMonitor)
            self.zoomMonitor = nil
        }
        guard window != nil else {
            return
        }
        zoomMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
            guard let self, let onZoom = self.onZoom,
                  event.window === self.window, !self.isHiddenOrHasHiddenAncestor else {
                return event
            }
            let point = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(point) else {
                return event
            }
            if event.type == .magnify {
                onZoom(1 + event.magnification, self.bounds.size)
                return nil
            }
            // Positive = wheel / fingers pushed away from you = zoom in,
            // whatever the "natural scrolling" setting is.
            var dy = event.scrollingDeltaY
            if event.isDirectionInvertedFromDevice {
                dy = -dy
            }
            if dy != 0 {
                // Trackpads send many small precise deltas, mouse wheels a few coarse ones
                let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.004 : 0.08
                onZoom(exp(dy * sensitivity), self.bounds.size)
            }
            return nil
        }
    }
}
#endif
