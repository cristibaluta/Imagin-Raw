//
//  ZoomMinimapView.swift
//  Imagin Raw
//
//  Scaled down image with a draggable rectangle showing the zoomed visible area.
//

import SwiftUI

struct ZoomMinimapView: View {
    let image: IRImage
    /// Visible fraction of the image per axis (0...1)
    let viewport: CGSize
    /// Normalized pan position (0...1)
    @Binding var position: CGPoint

    private let maxSize = CGSize(width: 180, height: 140)

    private var imageSize: CGSize {
        let s = image.size
        guard s.width > 0, s.height > 0 else {
            return maxSize
        }
        let scale = min(maxSize.width / s.width, maxSize.height / s.height)
        return CGSize(width: s.width * scale, height: s.height * scale)
    }

    var body: some View {
        let size = imageSize
        let rectW = size.width * viewport.width
        let rectH = size.height * viewport.height
        let rectX = (size.width - rectW) * position.x
        let rectY = (size.height - rectH) * position.y

        ZStack(alignment: .topLeading) {
            Image(nsImage: image)
                .resizable()
                .frame(width: size.width, height: size.height)
            Rectangle()
                .fill(Color.accentColor.opacity(0.2))
                .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1.5))
                .frame(width: rectW, height: rectH)
                .offset(x: rectX, y: rectY)
        }
        .frame(width: size.width, height: size.height)
        .overlay(Rectangle().stroke(Color.white.opacity(0.6), lineWidth: 1))
        .shadow(radius: 4)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let freeW = size.width - rectW
                    let freeH = size.height - rectH
                    let x = freeW > 0.5 ? (value.location.x - rectW / 2) / freeW : 0.5
                    let y = freeH > 0.5 ? (value.location.y - rectH / 2) / freeH : 0.5
                    position = CGPoint(x: min(1, max(0, x)), y: min(1, max(0, y)))
                }
        )
    }
}
