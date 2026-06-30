//
//  ExportCanvasPreview.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 17.06.2026.
//

import SwiftUI

struct Layout {
    let dispCanvasW: CGFloat
    let dispCanvasH: CGFloat
    let dispImgW: CGFloat
    let dispImgH: CGFloat
    let imgOffX: CGFloat
    let imgOffY: CGFloat
}

struct ExportCanvasPreview: View, Animatable {
    let image: IRImage
    var geo: GeometryProxy
    let targetRatio: ExportAspectRatio
    var padding: Double
    let alignment: ExportAlignment

    var animatableData: Double {
        get { padding }
        set { padding = newValue }
    }

    private let pixelSize: CGSize

    init(image: IRImage, geo: GeometryProxy, targetRatio: ExportAspectRatio, padding: Double, alignment: ExportAlignment) {
        self.image = image
        self.geo = geo
        self.targetRatio = targetRatio
        self.padding = padding
        self.alignment = alignment
        #if os(macOS)
        if let rep = image.representations.first as? NSBitmapImageRep {
            self.pixelSize = CGSize(width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh))
        } else if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            self.pixelSize = CGSize(width: CGFloat(cg.width), height: CGFloat(cg.height))
        } else {
            self.pixelSize = image.size
        }
        #else
        self.pixelSize = image.size
        #endif
    }

    private func layout(in available: CGSize) -> Layout {
        let src = pixelSize
        let pad = CGFloat(padding)
        let paddedW = src.width + pad * 2
        let paddedH = src.height + pad * 2

        let canvasW: CGFloat
        let canvasH: CGFloat
        if let ratio = targetRatio.ratio {
            let paddedRatio = paddedW / paddedH
            if paddedRatio > ratio {
                canvasW = paddedW
                canvasH = paddedW / ratio
            } else if paddedRatio < ratio {
                canvasW = paddedH * ratio
                canvasH = paddedH
            } else {
                canvasW = paddedW
                canvasH = paddedH
            }
        } else {
            canvasW = paddedW
            canvasH = paddedH
        }

        let scale = min(available.width / canvasW, available.height / canvasH)
        let dispCanvasW = canvasW * scale
        let dispCanvasH = canvasH * scale
        let dispImgW = src.width * scale
        let dispImgH = src.height * scale

        // Horizontal offset based on alignment
        let extraSpace = (dispCanvasW - dispImgW) / 2
        let imgOffX: CGFloat
        switch alignment {
            case .left:   imgOffX = -extraSpace + pad * scale
            case .center: imgOffX = 0
            case .right:  imgOffX = extraSpace - pad * scale
        }
        let imgOffY = 0.0
//        RCLog("alignment: \(alignment), dispCanvas: \(dispCanvasW) \(dispCanvasH), dispImg: \(dispImgW) \(dispImgH), imgOff: \(imgOffX) \(imgOffY)")

        return Layout(
            dispCanvasW: dispCanvasW, dispCanvasH: dispCanvasH,
            dispImgW: dispImgW, dispImgH: dispImgH,
            imgOffX: imgOffX, imgOffY: imgOffY
        )
    }

    var body: some View {
        let _ = Self._printChanges()
        let l = layout(in: geo.size)
        ZStack {
            Rectangle()
                .fill(Color.black)
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: l.dispImgW, height: l.dispImgH)
                .offset(x: l.imgOffX, y: l.imgOffY)
        }
        .frame(width: l.dispCanvasW, height: l.dispCanvasH)
    }
}
