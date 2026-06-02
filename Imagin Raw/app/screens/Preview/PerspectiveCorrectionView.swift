//
//  PerspectiveCorrectionView.swift
//  Imagin Raw
//

import SwiftUI
import CoreImage

// MARK: - Model

struct PerspectiveLine {
    var start: CGPoint
    var end: CGPoint
}

enum PerspectiveDrawState {
    case idle
    case drawingLine1(start: CGPoint)
    case line1Done(PerspectiveLine)
    case drawingLine2(line1: PerspectiveLine, start: CGPoint)
    case bothLines(PerspectiveLine, PerspectiveLine)
}

// MARK: - Main View

struct PerspectiveCorrectionView: View {
    let image: IRImage
    /// Called with the corrected image, or nil to cancel
    let onResult: (IRImage?) -> Void

    @State private var drawState: PerspectiveDrawState = .idle
    @State private var currentDrag: CGPoint? = nil
    @State private var correctedImage: IRImage? = nil
    @State private var isProcessing = false
    @State private var renderedSize: CGSize = .zero
    @State private var renderedOffset: CGPoint = .zero

    var body: some View {
        GeometryReader { geo in
            let (rSize, rOffset) = imageRect(in: geo.size)
            ZStack {
                // Background
                Color.black.ignoresSafeArea()

                // Image (corrected or original)
                Image(nsImage: correctedImage ?? image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: rSize.width, height: rSize.height)
                    .position(x: rOffset.x + rSize.width / 2, y: rOffset.y + rSize.height / 2)

                // Line overlay
                Canvas { ctx, size in
                    drawLines(ctx: ctx, rSize: rSize, rOffset: rOffset)
                }
                .allowsHitTesting(false)

                // Drag capture
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { val in
                                currentDrag = val.location
                                handleDragChanged(val.location)
                            }
                            .onEnded { val in
                                currentDrag = nil
                                handleDragEnded(val.location)
                            }
                    )

                // Instructions
                VStack {
                    instructionBanner
                    Spacer()
                    bottomBar
                }
            }
            .onAppear {
                renderedSize = rSize
                renderedOffset = rOffset
            }
            .onChange(of: geo.size) { _, newSize in
                let (s, o) = imageRect(in: newSize)
                renderedSize = s
                renderedOffset = o
            }
        }
    }

    // MARK: - Instruction Banner

    private var instructionBanner: some View {
        Group {
            switch drawState {
            case .idle:
                banner("Draw line 1: click and drag along a line that should be vertical or horizontal")
            case .drawingLine1:
                banner("Release to finish line 1")
            case .line1Done:
                banner("Draw line 2: a second line parallel to the first")
            case .drawingLine2:
                banner("Release to finish line 2")
            case .bothLines:
                banner(isProcessing ? "Processing…" : "Lines set — tap Apply or redraw")
            }
        }
    }

    private func banner(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            .padding(.top, 12)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button("Cancel") { onResult(nil) }
                .buttonStyle(.bordered)

            Button("Reset") { reset() }
                .buttonStyle(.bordered)
                .disabled(isIdle && correctedImage == nil)

            Spacer()

            if correctedImage != nil {
                Button("Done") { onResult(correctedImage) }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Apply") {
                    applyCorrection()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasBothLines || isProcessing)
                .overlay {
                    if isProcessing {
                        ProgressView().controlSize(.small).padding(.trailing, 4)
                    }
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: Rectangle())
    }

    private var isIdle: Bool {
        if case .idle = drawState { return true }
        return false
    }

    private var hasBothLines: Bool {
        if case .bothLines = drawState { return true }
        return false
    }

    // MARK: - Drawing

    private func drawLines(ctx: GraphicsContext, rSize: CGSize, rOffset: CGPoint) {
        func drawLine(_ line: PerspectiveLine, color: Color) {
            var path = Path()
            path.move(to: line.start)
            path.addLine(to: line.end)
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            // Endpoints
            for pt in [line.start, line.end] {
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)), with: .color(color))
            }
        }

        switch drawState {
        case .idle:
            break
        case .drawingLine1(let start):
            if let drag = currentDrag {
                drawLine(PerspectiveLine(start: start, end: drag), color: .yellow)
            }
        case .line1Done(let l1):
            drawLine(l1, color: .yellow)
        case .drawingLine2(let l1, let start):
            drawLine(l1, color: .yellow)
            if let drag = currentDrag {
                drawLine(PerspectiveLine(start: start, end: drag), color: .cyan)
            }
        case .bothLines(let l1, let l2):
            drawLine(l1, color: .yellow)
            drawLine(l2, color: .cyan)
        }
    }

    // MARK: - Drag Handling

    private func handleDragChanged(_ pt: CGPoint) {
        switch drawState {
        case .idle:
            drawState = .drawingLine1(start: pt)
        default:
            break
        }
    }

    private func handleDragEnded(_ pt: CGPoint) {
        switch drawState {
        case .drawingLine1(let start):
            guard distance(start, pt) > 10 else { drawState = .idle; return }
            drawState = .line1Done(PerspectiveLine(start: start, end: pt))
        case .line1Done(let l1):
            drawState = .drawingLine2(line1: l1, start: pt)
        case .drawingLine2(let l1, let start):
            guard distance(start, pt) > 10 else { drawState = .line1Done(l1); return }
            drawState = .bothLines(l1, PerspectiveLine(start: start, end: pt))
        default:
            break
        }
    }

    private func reset() {
        drawState = .idle
        currentDrag = nil
        correctedImage = nil
    }

    // MARK: - Perspective Correction

    private func applyCorrection() {
        guard case .bothLines(let l1, let l2) = drawState else { return }
        isProcessing = true

        // Capture value types before entering detached task
        let img = image
        let rSize = renderedSize
        let rOffset = renderedOffset

        Task.detached(priority: .userInitiated) {
            let result = await Self.correct(image: img,
                                            line1: l1, line2: l2,
                                            renderedSize: rSize,
                                            renderedOffset: rOffset)
            await MainActor.run {
                isProcessing = false
                correctedImage = result
            }
        }
    }

    static func correct(image: IRImage,
                        line1: PerspectiveLine,
                        line2: PerspectiveLine,
                        renderedSize: CGSize,
                        renderedOffset: CGPoint) async -> IRImage? {

        guard let cgInput = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let imgW = CGFloat(cgInput.width)
        let imgH = CGFloat(cgInput.height)

        // Convert screen coords → image pixel coords (top-left origin)
        func toImg(_ pt: CGPoint) -> CGPoint {
            CGPoint(
                x: ((pt.x - renderedOffset.x) / renderedSize.width  * imgW).clamped(0, imgW),
                y: ((pt.y - renderedOffset.y) / renderedSize.height * imgH).clamped(0, imgH)
            )
        }

        let a = toImg(line1.start), b = toImg(line1.end)
        let c = toImg(line2.start), d = toImg(line2.end)

        // Vanishing point = where the two lines meet
        guard let vp = lineIntersection(p1: a, p2: b, p3: c, p4: d) else { return nil }

        // Determine whether lines are mostly vertical or horizontal
        let isVertical = (abs(b.y-a.y) + abs(d.y-c.y)) > (abs(b.x-a.x) + abs(d.x-c.x))

        // Compute keystone correction amount.
        // The idea: find how far each horizontal edge (top/bottom) or vertical edge (left/right)
        // deviates in width due to the converging lines, then correct by scaling one edge.
        //
        // For vertical lines converging to VP at (vpX, vpY):
        //   At row y, the apparent width ratio = (imgH - vpY) / (y - vpY)
        //   We measure at top (y=0) and bottom (y=imgH) and correct relative to middle.
        //
        // CIPerspectiveTransformWithExtent: the 4 input points are where the OUTPUT corners
        // map TO in the INPUT image. So we compute src quad that should be stretched to fill.

        let dstTL: CGPoint  // top-left in source that maps to output top-left
        let dstTR: CGPoint
        let dstBL: CGPoint
        let dstBR: CGPoint

        if isVertical {
            // Lines converge vertically. VP is above or below.
            // At each y, the x-shift needed = (vp.x) * (y - imgH/2) / (imgH/2 - vp.y)
            // But simpler: scale top and bottom edges relative to center row
            let cx = imgW / 2
            let cy = imgH / 2

            // Factor by which top edge is compressed vs bottom (or vice versa)
            // If vp.y < cy: top is narrower → we need to crop a wider slice at top
            // At y=0:    scale = (cy - vp.y) / cy          (distance from VP to center / half height)
            // At y=imgH: scale = (vp.y + cy) / cy
            let topFactor = (vp.y - cy) / (0 - cy + 1e-10)   // how much wider top needs to be cropped
            let botFactor = (vp.y - cy) / (imgH - cy + 1e-10)

            let topHalfW = (imgW / 2) * topFactor
            let botHalfW = (imgW / 2) * botFactor

            dstTL = CGPoint(x: cx - topHalfW, y: 0)
            dstTR = CGPoint(x: cx + topHalfW, y: 0)
            dstBL = CGPoint(x: cx - botHalfW, y: imgH)
            dstBR = CGPoint(x: cx + botHalfW, y: imgH)
        } else {
            // Lines converge horizontally.
            let cx = imgW / 2
            let cy = imgH / 2

            let leftFactor  = (vp.x - cx) / (0 - cx + 1e-10)
            let rightFactor = (vp.x - cx) / (imgW - cx + 1e-10)

            let leftHalfH  = (imgH / 2) * leftFactor
            let rightHalfH = (imgH / 2) * rightFactor

            dstTL = CGPoint(x: 0,    y: cy - leftHalfH)
            dstBL = CGPoint(x: 0,    y: cy + leftHalfH)
            dstTR = CGPoint(x: imgW, y: cy - rightHalfH)
            dstBR = CGPoint(x: imgW, y: cy + rightHalfH)
        }

        // CI coordinate system: origin = bottom-left, y flipped
        func ci(_ p: CGPoint) -> CIVector { CIVector(x: p.x, y: imgH - p.y) }

        let ciImage = CIImage(cgImage: cgInput)

        // CIPerspectiveTransformWithExtent: maps the src quad to fill the given extent
        guard let filter = CIFilter(name: "CIPerspectiveTransformWithExtent") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: CGRect(x: 0, y: 0, width: imgW, height: imgH)), forKey: "inputExtent")
        filter.setValue(ci(dstTL), forKey: "inputTopLeft")
        filter.setValue(ci(dstTR), forKey: "inputTopRight")
        filter.setValue(ci(dstBR), forKey: "inputBottomRight")
        filter.setValue(ci(dstBL), forKey: "inputBottomLeft")

        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        guard let output = filter.outputImage,
              let cgOut = ctx.createCGImage(output, from: CGRect(x: 0, y: 0, width: imgW, height: imgH))
        else { return nil }

        return NSImage(cgImage: cgOut, size: NSSize(width: cgOut.width, height: cgOut.height))
    }

    // MARK: - Geometry helpers

    private func imageRect(in size: CGSize) -> (CGSize, CGPoint) {
        let ia = image.size.width / image.size.height
        let ca = size.width / size.height
        if ia > ca {
            let w = size.width
            let h = size.width / ia
            return (CGSize(width: w, height: h), CGPoint(x: 0, y: (size.height - h) / 2))
        } else {
            let h = size.height
            let w = size.height * ia
            return (CGSize(width: w, height: h), CGPoint(x: (size.width - w) / 2, y: 0))
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt((a.x-b.x)*(a.x-b.x) + (a.y-b.y)*(a.y-b.y))
    }
}

// MARK: - Math helpers (file-private)

private func lineIntersection(p1: CGPoint, p2: CGPoint, p3: CGPoint, p4: CGPoint) -> CGPoint? {
    let d1 = CGPoint(x: p2.x - p1.x, y: p2.y - p1.y)
    let d2 = CGPoint(x: p4.x - p3.x, y: p4.y - p3.y)
    let cross = d1.x * d2.y - d1.y * d2.x
    guard abs(cross) > 1e-6 else { return nil } // parallel
    let t = ((p3.x - p1.x) * d2.y - (p3.y - p1.y) * d2.x) / cross
    return CGPoint(x: p1.x + t * d1.x, y: p1.y + t * d1.y)
}

private extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        self < lo ? lo : (self > hi ? hi : self)
    }
}
