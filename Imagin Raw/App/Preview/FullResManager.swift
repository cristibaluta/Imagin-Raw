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

    /// Swap to LibRawDecoder() to use LibRaw's software demosaic instead.
    var decoder: RawDecoder = CoreGraphicsDecoder()

    private let cacheLimit = 5
    private var cache: [String: NSImage] = [:]
    private var order: [String] = []

    private let decodeQueue = DispatchQueue(label: "ro.imagin.fullres.decode", qos: .userInitiated)

    private init() {}

    // MARK: - Public

    func cachedImage(for path: String) -> NSImage? {
        cache[path]
    }

    func loadFullRes(for path: String, completion: @escaping (NSImage?) -> Void) {
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
                image = decoder.decodeFullRes(at: path)
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
                if let image { self.store(image, for: path) }
                completion(image)
            }
        }
    }

    func evict(path: String) {
        cache.removeValue(forKey: path)
        order.removeAll { $0 == path }
    }

    // MARK: - Private

    private func store(_ image: NSImage, for path: String) {
        if cache[path] != nil {
            order.removeAll { $0 == path }
            order.append(path)
            return
        }
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
