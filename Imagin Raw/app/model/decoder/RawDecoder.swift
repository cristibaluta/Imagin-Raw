//
//  RawDecoder.swift
//  Imagin Raw
//
//  Protocol + implementations for full-resolution RAW decoding.
//  Switch between CoreGraphics (fast, camera-processed) and LibRaw
//  (slower, full software demosaic) by changing FullResManager.decoder.
//

import Foundation
import ImageIO

// MARK: - Protocol

protocol RawDecoder {
    /// Full demosaic / full-res decode. Called on a background thread.
    func decodeFullRes(at url: URL) -> IRImage?

    /// Extract, orient and resize a preview image up to `maxSize` px on the longest edge.
    /// Handles EXIF orientation. Returns nil on failure.
    func extractPreview(at url: URL, maxSize: CGFloat) -> IRImage?
}

// MARK: - CoreGraphics implementation

struct CoreGraphicsDecoder: RawDecoder {

    func decodeFullRes(at url: URL) -> IRImage? {
        let t0 = Date()
        let filename = url.lastPathComponent

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        // Fast path: embedded full-size JPEG (~100-200ms)
        if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
               kCGImageSourceCreateThumbnailFromImageAlways: true,
               kCGImageSourceShouldCacheImmediately: true,
               kCGImageSourceCreateThumbnailWithTransform: true,
               kCGImageSourceThumbnailMaxPixelSize: 10000
           ] as CFDictionary) {
            let n = normalizeToSRGB(cg)
            RCLog("🔎 [CoreGraphicsDecoder] embedded JPEG \(filename)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s  \(n.width)×\(n.height)")
            return IRImage(cgImage: n, size: IRSize(width: n.width, height: n.height))
        }

        // Slow fallback: full demosaic
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cg = CGImageSourceCreateImageAtIndex(src, 0, [
               kCGImageSourceShouldCacheImmediately: true,
               kCGImageSourceShouldAllowFloat: false
           ] as CFDictionary) {
            let n = normalizeToSRGB(cg)
            RCLog("🔎 [CoreGraphicsDecoder] full demosaic \(filename)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s  \(n.width)×\(n.height)")
            return IRImage(cgImage: n, size: IRSize(width: n.width, height: n.height))
        }

        RCLog("🔎 [CoreGraphicsDecoder] failed \(filename)")
        return nil
    }

    func extractPreview(at url: URL, maxSize: CGFloat) -> IRImage? {
        let filename = url.lastPathComponent
        let t0 = Date()

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        var exifOrientation: Int32 = 1
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let o = props[kCGImagePropertyOrientation] as? Int32 {
            exifOrientation = o
        }
        let sourceCG = CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: false, // we rotate ourselves below
            kCGImageSourceThumbnailMaxPixelSize: maxSize
        ] as CFDictionary)
        RCLog("🖼 [CoreGraphicsDecoder] extractPreview from \(filename)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s")

        guard let cg = sourceCG else {
            return nil
        }
        guard let oriented = cg.applyingOrientation(exifOrientation) else {
            return nil
        }
        RCLog("🖼 [CoreGraphicsDecoder] oriented \(oriented.width)×\(oriented.height) orientation=\(exifOrientation)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s")
        return IRImage(cgImage: oriented, size: IRSize(width: oriented.width, height: oriented.height))
    }

    /// Normalize any CGImage to sRGB + noneSkipLast (no alpha).
    private func normalizeToSRGB(_ cg: CGImage) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: cg.width, height: cg.height,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return cg }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return ctx.makeImage() ?? cg
    }
}

// MARK: - LibRaw implementation

struct LibRawDecoder: RawDecoder {

    func decodeFullRes(at url: URL) -> IRImage? {
        let t0 = Date()
        let filename = url.lastPathComponent
        let img = RawWrapper.shared().extractFullResolution(url.absoluteString)
        RCLog("🔎 [LibRawDecoder] done \(filename)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s  success=\(img != nil)")
        return img
    }

    func extractPreview(at url: URL, maxSize: CGFloat) -> IRImage? {
        let filename = url.lastPathComponent
        let t0 = Date()

        // RAW: RawWrapper extracts embedded JPEG, then we apply orientation
        guard let data = RawWrapper.shared().extractEmbeddedJPEG(url.absoluteString) else {
            RCLog("🖼 [LibRawDecoder] extractEmbeddedJPEG failed \(filename)")
            return nil
        }
        RCLog("🖼 [LibRawDecoder] extractEmbeddedJPEG \(filename)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s  bytes=\(data.count)")
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let sourceCG = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        var exifOrientation: Int32 = 1
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let o = props[kCGImagePropertyOrientation] as? Int32 {
            exifOrientation = o
        }

        guard let cg = sourceCG else {
            return nil
        }
        guard let oriented = cg.applyingOrientation(exifOrientation) else {
            return nil
        }
        RCLog("🖼 [LibRawDecoder] oriented \(oriented.width)×\(oriented.height) orientation=\(exifOrientation)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s")

        let srcW = CGFloat(oriented.width)
        let srcH = CGFloat(oriented.height)
        let maxDim = max(srcW, srcH)
        guard maxDim > maxSize else {
            return IRImage(cgImage: oriented, size: IRSize(width: oriented.width, height: oriented.height))
        }
        let scale = maxSize / maxDim
        let dstW = Int((srcW * scale).rounded())
        let dstH = Int((srcH * scale).rounded())
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: dstW, height: dstH,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }
        ctx.interpolationQuality = .high
        ctx.draw(oriented, in: CGRect(x: 0, y: 0, width: dstW, height: dstH))
        guard let resized = ctx.makeImage() else {
            return nil
        }
        RCLog("🖼 [LibRawDecoder] resized to \(dstW)×\(dstH)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s")
        return IRImage(cgImage: resized, size: IRSize(width: resized.width, height: resized.height))
    }
}
