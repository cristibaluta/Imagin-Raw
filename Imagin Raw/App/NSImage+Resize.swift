//
//  NSImage+Resize.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 29.01.2026.
//

import AppKit

extension NSImage {

    func resized(maxSize: CGFloat) -> NSImage {
        let ratio = min(maxSize / size.width, maxSize / size.height)
        let newSize = NSSize(
            width: size.width * ratio,
            height: size.height * ratio
        )

        let image = NSImage(size: newSize)
        image.lockFocus()
        draw(in: NSRect(origin: .zero, size: newSize))
        image.unlockFocus()

        return image
    }
}
