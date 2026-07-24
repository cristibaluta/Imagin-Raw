//
//  CoreGraphicsDecoder.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 24.07.2026.
//

import ImageIO

struct CoreGraphicsDecoder: RawDecoder {

    func decodeFullRes(at url: URL) -> IRImage? {
        let t0 = Date()
        let filename = url.lastPathComponent

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        // 1. Extract embedded full-size JPEG (~100-200ms)
        let fastOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 10000
        ] as CFDictionary
        if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, fastOptions) {
            let n = normalizeToSRGB(cg)
            RCLog("Embedded JPEG \(filename) in \(String(format:"%.3f",-t0.timeIntervalSinceNow))s  \(n.width)×\(n.height)")
            return IRImage(cgImage: n, size: IRSize(width: n.width, height: n.height))
        }

        // 2. Fallback: full demosaic (slower)
        let slowOptions = [
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: false
        ] as CFDictionary
        if let cg = CGImageSourceCreateImageAtIndex(src, 0, slowOptions) {
            let n = normalizeToSRGB(cg)
            RCLog("Full demosaic \(filename) in \(String(format:"%.3f",-t0.timeIntervalSinceNow))s  \(n.width)×\(n.height)")
            return IRImage(cgImage: n, size: IRSize(width: n.width, height: n.height))
        }

        RCLog("Decoder failed \(filename)")
        return nil
    }

    func extractPreview(at url: URL, maxSize: CGFloat) -> IRImage? {
        let t0 = Date()

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        // 1. Extract the orientation
        var exifOrientation: Int32 = 1
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let o = props[kCGImagePropertyOrientation] as? Int32 {
            exifOrientation = o
        }
        // 2. Extract the preview
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: false, // we rotate ourselves below
            kCGImageSourceThumbnailMaxPixelSize: maxSize
        ] as CFDictionary

        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options) else {
            return nil
        }
        // 3. Apply the orientation
        guard let oriented = cg.applyingOrientation(exifOrientation) else {
            return nil
        }
        RCLog("extractPreview from \(url.lastPathComponent) in \(String(format:"%.3f", -t0.timeIntervalSinceNow))s")
        return IRImage(cgImage: oriented, size: IRSize(width: oriented.width, height: oriented.height))
    }

    /// Normalize any CGImage to sRGB + noneSkipLast (no alpha).
    private func normalizeToSRGB(_ cg: CGImage) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil,
                                  width: cg.width,
                                  height: cg.height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: cs,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return cg
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return ctx.makeImage() ?? cg
    }
}
