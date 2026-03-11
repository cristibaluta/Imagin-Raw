//
//  FullResManager.swift
//  Imagin Raw
//
//  Memory-only cache of full-resolution decoded RAW images.
//  Keeps the last N photos so toggling zoom on recently viewed photos is instant.
//

import Foundation
import AppKit

class FullResManager {
    static let shared = FullResManager()

    private let cacheLimit = 5
    private var cache: [String: NSImage] = [:]
    private var order: [String] = []  // oldest first

    // One background queue for decoding — reuses the same thread
    private let decodeQueue = DispatchQueue(label: "ro.imagin.fullres.decode", qos: .userInitiated)

    private init() {}

    // MARK: - Public

    /// Returns a cached image instantly, or nil if not cached.
    func cachedImage(for path: String) -> NSImage? {
        cache[path]
    }

    /// Loads (or returns from cache) the full-resolution image for `path`.
    /// Calls `completion` on the main thread.
    func loadFullRes(for path: String, completion: @escaping (NSImage?) -> Void) {
        // Cache hit — instant
        if let cached = cache[path] {
            print("🔎 [FullResManager] cache hit \(URL(fileURLWithPath: path).lastPathComponent)")
            DispatchQueue.main.async { completion(cached) }
            return
        }

        let t0 = Date()
        let filename = URL(fileURLWithPath: path).lastPathComponent
        print("🔎 [FullResManager] decode start \(filename)")

        decodeQueue.async { [weak self] in
            guard let self else { return }

            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            let image: NSImage?

            if FilesExtensions.raw.contains(ext) {
                // image = RawWrapper.shared().extractFullResolution(path)
                // CoreGraphics RAW decode — uses Apple's hardware-accelerated RAW engine,
                // typically 2-4x faster than LibRaw's software demosaic.
                // kCGImageSourceShouldAllowFloat: false  → 8-bit output
                // kRAWImageDecoderRenderTask: kRAWImageDecoderRenderTaskFullSize → full res
                let url = URL(fileURLWithPath: path)
                if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                   let cg = CGImageSourceCreateImageAtIndex(src, 0, [
                       kCGImageSourceShouldCacheImmediately: true,
                       kCGImageSourceShouldAllowFloat: false
                   ] as CFDictionary) {
                    // Normalize from YCbCr/native RAW color space to sRGB for display
                    let srgb = CGColorSpaceCreateDeviceRGB()
                    if let ctx = CGContext(
                        data: nil,
                        width: cg.width, height: cg.height,
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                    ) {
                        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                        if let normalized = ctx.makeImage() {
                            image = NSImage(cgImage: normalized, size: NSSize(width: normalized.width, height: normalized.height))
                        } else {
                            image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                        }
                    } else {
                        image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                    }
                } else {
                    image = nil
                }
                print("🔎 [FullResManager] CoreGraphics RAW done \(filename)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s  success=\(image != nil)  size=\(image?.size ?? .zero)")
            } else {
                // Non-RAW: load via CGImageSource at full size
                if let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                   let cg = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
                    image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                } else {
                    image = nil
                }
                print("🔎 [FullResManager] non-RAW loaded \(filename)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s")
            }

            DispatchQueue.main.async {
                if let image {
                    self.store(image, for: path)
                }
                completion(image)
            }
        }
    }

    /// Cancel is implicit — the decode queue processes one at a time.
    /// Call this to purge a specific path from cache (e.g. when photo changes).
    func evict(path: String) {
        cache.removeValue(forKey: path)
        order.removeAll { $0 == path }
    }

    // MARK: - Private

    private func store(_ image: NSImage, for path: String) {
        // Already cached — just update order
        if cache[path] != nil {
            order.removeAll { $0 == path }
            order.append(path)
            return
        }
        // Evict oldest if at limit
        while cache.count >= cacheLimit, let oldest = order.first {
            print("🔎 [FullResManager] evicting \(URL(fileURLWithPath: oldest).lastPathComponent)")
            cache.removeValue(forKey: oldest)
            order.removeFirst()
        }
        cache[path] = image
        order.append(path)
        print("🔎 [FullResManager] cached \(URL(fileURLWithPath: path).lastPathComponent) (\(cache.count)/\(cacheLimit))")
    }
}
