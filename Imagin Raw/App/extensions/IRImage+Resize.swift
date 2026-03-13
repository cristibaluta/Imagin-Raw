//
//  NSImage+Resize.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 29.01.2026.
//
import Foundation
import SwiftUI

extension IRImage {

    #if os(macOS)
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
    #elseif os(iOS)
    convenience init(cgImage: CGImage, size: IRSize) {
        self.init(cgImage: cgImage)
    }
    convenience init?(contentsOf: URL) {
        guard let data = try? Data(contentsOf: contentsOf) else {
            return nil
        }
        self.init(data: data)
    }
    func resized(maxSize: CGFloat) -> IRImage {
        return self
    }
    func bitmapRepresentation() -> Data? {
        nil
    }
    #endif
}

extension Image {
    #if os(iOS)
    init(nsImage: IRImage) {
        self.init(uiImage: nsImage)
    }
    #endif
}
