//
//  NSImage+Resize.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 29.01.2026.
//
import AppKit

extension IRImage {

    func resized(maxSize: CGFloat) -> IRImage {
        let ratio = min(maxSize / size.width, maxSize / size.height)
        let newSize = IRSize(
            width: size.width * ratio,
            height: size.height * ratio
        )

        let image = IRImage(size: newSize)
        image.lockFocus()
        draw(in: IRRect(origin: .zero, size: newSize))
        image.unlockFocus()

        return image
    }

    func bitmapRepresentation() -> Data? {
        guard let tiffData = self.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }
}
