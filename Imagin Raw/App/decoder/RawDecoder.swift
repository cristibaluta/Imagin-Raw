//
//  RawDecoder.swift
//  Imagin Raw
//
//  Protocol + implementations for full-resolution RAW decoding.
//  Switch between CoreGraphics (fast, camera-processed) and LibRaw
//  (slower, full software demosaic) by changing FullResManager.decoder.
//

import Foundation
import AppKit
import ImageIO

// MARK: - Protocol

protocol RawDecoder {
    /// Full demosaic / full-res decode. Called on a background thread.
    func decodeFullRes(at path: String) -> IRImage?

    /// Extract, orient and resize a preview image up to `maxSize` px on the longest edge.
    /// Handles EXIF orientation. Returns nil on failure.
    func extractPreview(at path: String, maxSize: CGFloat) -> IRImage?
}

// MARK: - CoreGraphics implementation

struct CoreGraphicsDecoder: RawDecoder {

    func decodeFullRes(at path: String) -> IRImage? {
        let url = URL(fileURLWithPath: path)
        let t0 = Date()
        let filename = url.lastPathComponent

        // Fast path: embedded full-size JPEG (~100-200ms)
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
               kCGImageSourceCreateThumbnailFromImageAlways: true,
               kCGImageSourceShouldCacheImmediately: true,
               kCGImageSourceCreateThumbnailWithTransform: true,
               kCGImageSourceThumbnailMaxPixelSize: 10000
           ] as CFDictionary) {
            let n = normalizeToSRGB(cg)
            print("🔎 [CoreGraphicsDecoder] embedded JPEG \(filename)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s  \(n.width)×\(n.height)")
            return IRImage(cgImage: n, size: IRSize(width: n.width, height: n.height))
        }

        // Slow fallback: full demosaic
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cg = CGImageSourceCreateImageAtIndex(src, 0, [
               kCGImageSourceShouldCacheImmediately: true,
               kCGImageSourceShouldAllowFloat: false
           ] as CFDictionary) {
            let n = normalizeToSRGB(cg)
            print("🔎 [CoreGraphicsDecoder] full demosaic \(filename)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s  \(n.width)×\(n.height)")
            return IRImage(cgImage: n, size: IRSize(width: n.width, height: n.height))
        }

        print("🔎 [CoreGraphicsDecoder] failed \(filename)")
        return nil
    }

    func extractPreview(at path: String, maxSize: CGFloat) -> IRImage? {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        let filename = url.lastPathComponent
        let t0 = Date()

        if !FilesExtensions.raw.contains(ext) {
            // Non-RAW: let ImageIO handle orientation + resize in one shot.
            // kCGImageSourceCreateThumbnailWithTransform applies EXIF orientation natively
            // without any CGContext bitmap format issues (PNG alpha, CMYK, etc.)
            return loadNonRAW(url: url, maxSize: maxSize, label: "CoreGraphicsDecoder", t0: t0)
        }

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
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
        print("🖼 [CoreGraphicsDecoder] extractPreview RAW \(filename)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s")

        guard let cg = sourceCG else { return nil }
        guard let oriented = cg.applyingOrientation(exifOrientation) else { return nil }
        print("🖼 [CoreGraphicsDecoder] oriented \(oriented.width)×\(oriented.height) orientation=\(exifOrientation)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s")
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

// MARK: - Shared non-RAW loader

/// Loads a non-RAW image via CGImageSource, letting ImageIO handle orientation
/// and resize in one pass. Avoids any CGContext bitmap format issues (PNG alpha,
/// CMYK, wide gamut, etc.) that arise when manually calling applyingOrientation.
private func loadNonRAW(url: URL, maxSize: CGFloat, label: String, t0: Date) -> IRImage? {
    let filename = url.lastPathComponent
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceShouldCacheImmediately: true,
              kCGImageSourceCreateThumbnailWithTransform: true, // applies EXIF orientation
              kCGImageSourceThumbnailMaxPixelSize: maxSize
          ] as CFDictionary) else { return nil }
    print("🖼 [\(label)] non-RAW \(filename)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s  \(cg.width)×\(cg.height)")
    return IRImage(cgImage: cg, size: IRSize(width: cg.width, height: cg.height))
}

// MARK: - LibRaw implementation

struct LibRawDecoder: RawDecoder {

    func decodeFullRes(at path: String) -> IRImage? {
        let t0 = Date()
        let filename = URL(fileURLWithPath: path).lastPathComponent
        let img = RawWrapper.shared().extractFullResolution(path)
        print("🔎 [LibRawDecoder] done \(filename)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s  success=\(img != nil)")
        return img
    }

    func extractPreview(at path: String, maxSize: CGFloat) -> IRImage? {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        let filename = url.lastPathComponent
        let t0 = Date()

        if !FilesExtensions.raw.contains(ext) {
            return loadNonRAW(url: url, maxSize: maxSize, label: "LibRawDecoder", t0: t0)
        }

        // RAW: RawWrapper extracts embedded JPEG, then we apply orientation
        guard let data = RawWrapper.shared().extractEmbeddedJPEG(path) else {
            print("🖼 [LibRawDecoder] extractEmbeddedJPEG failed \(filename)")
            return nil
        }
        print("🖼 [LibRawDecoder] extractEmbeddedJPEG \(filename)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s  bytes=\(data.count)")
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let sourceCG = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        var exifOrientation: Int32 = 1
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let o = props[kCGImagePropertyOrientation] as? Int32 {
            exifOrientation = o
        }

        guard let cg = sourceCG else { return nil }
        guard let oriented = cg.applyingOrientation(exifOrientation) else { return nil }
        print("🖼 [LibRawDecoder] oriented \(oriented.width)×\(oriented.height) orientation=\(exifOrientation)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s")

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
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(oriented, in: CGRect(x: 0, y: 0, width: dstW, height: dstH))
        guard let resized = ctx.makeImage() else { return nil }
        print("🖼 [LibRawDecoder] resized to \(dstW)×\(dstH)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s")
        return IRImage(cgImage: resized, size: IRSize(width: resized.width, height: resized.height))
    }
}
