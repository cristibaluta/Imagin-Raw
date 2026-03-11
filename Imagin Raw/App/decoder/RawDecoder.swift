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
    /// Synchronously decode a full-resolution image from `path`.
    /// Called on a background thread — must NOT touch the main thread.
    func decodeFullRes(at path: String) -> NSImage?

    /// Synchronously extract the embedded JPEG preview from a RAW file.
    /// Much faster than a full demosaic — used as a fast-path when quality
    /// requirements allow it.
    func extractEmbeddedJPEG(at path: String) -> NSImage?
}

// MARK: - CoreGraphics implementation

/// Uses Apple's built-in RAW engine via CGImageSource.
/// ~2-4x faster than LibRaw on Apple Silicon (hardware-accelerated).
/// Color rendering matches the camera's embedded profile.
struct CoreGraphicsDecoder: RawDecoder {

    func decodeFullRes(at path: String) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        let t0 = Date()

        // Fast path: extract the embedded full-size JPEG preview from the RAW.
        // This is ~20x faster than demosaicing (~100-200ms vs 3-5s) and uses
        // the camera's own JPEG engine (sharpening, NR, colour profile).
        // kCGImageSourceThumbnailMaxPixelSize set larger than any current sensor
        // forces CoreGraphics to return the embedded full JPEG without downscaling.
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
               kCGImageSourceCreateThumbnailFromImageAlways: true,
               kCGImageSourceShouldCacheImmediately: true,
               kCGImageSourceCreateThumbnailWithTransform: true,
               kCGImageSourceThumbnailMaxPixelSize: 10000
           ] as CFDictionary) {
            let img = NSImage(cgImage: normalize(cg), size: NSSize(width: cg.width, height: cg.height))
            print("🔎 [CoreGraphicsDecoder] embedded JPEG \(url.lastPathComponent)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s  \(cg.width)×\(cg.height)")
            return img
        }

        // Slow fallback: full CoreGraphics RAW demosaic
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cg = CGImageSourceCreateImageAtIndex(src, 0, [
               kCGImageSourceShouldCacheImmediately: true,
               kCGImageSourceShouldAllowFloat: false
           ] as CFDictionary) {
            let img = NSImage(cgImage: normalize(cg), size: NSSize(width: cg.width, height: cg.height))
            print("🔎 [CoreGraphicsDecoder] full demosaic fallback \(url.lastPathComponent)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s  \(cg.width)×\(cg.height)")
            return img
        }

        print("🔎 [CoreGraphicsDecoder] failed \(url.lastPathComponent)")
        return nil
    }

    func extractEmbeddedJPEG(at path: String) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceShouldCacheImmediately: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 10000
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: normalize(cg), size: NSSize(width: cg.width, height: cg.height))
    }

    /// Normalize to sRGB noneSkipLast — required because CoreGraphics returns
    /// RAW/JPEG images in YCbCr or wide-gamut spaces that NSImage renders incorrectly.
    private func normalize(_ cg: CGImage) -> CGImage {
        let srgb = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: cg.width, height: cg.height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: srgb,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return cg }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return ctx.makeImage() ?? cg
    }
}

// MARK: - LibRaw implementation

/// Uses LibRaw's full software demosaic pipeline via RawWrapper.
/// Slower (~3-5s) but gives access to the raw sensor data without
/// any in-camera processing applied.
struct LibRawDecoder: RawDecoder {

    func decodeFullRes(at path: String) -> NSImage? {
        let t0 = Date()
        let filename = URL(fileURLWithPath: path).lastPathComponent
        let img = RawWrapper.shared().extractFullResolution(path)
        print("🔎 [LibRawDecoder] done \(filename)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s  success=\(img != nil)")
        return img
    }

    func extractEmbeddedJPEG(at path: String) -> NSImage? {
        guard let data = RawWrapper.shared().extractEmbeddedJPEG(path) else { return nil }
        return NSImage(data: data)
    }
}
