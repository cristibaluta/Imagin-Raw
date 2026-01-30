//
//  ThumbsManager.swift
//  Imagin Bridge
//
//  Created by Cristian Baluta on 30.01.2026.
//

import Foundation
import AppKit

class ThumbsManager: ObservableObject {
    static let shared = ThumbsManager()

    // Memory cache for loaded thumbnails
    private var memoryCache: [String: NSImage] = [:]
    private let cacheQueue = DispatchQueue(label: "com.imagin.thumbs.cache", attributes: .concurrent)
    private let diskQueue = DispatchQueue(label: "com.imagin.thumbs.disk", qos: .userInitiated)

    // Cache directory
    private let cacheDirectory: URL

    private init() {
        // Create cache directory in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                in: .userDomainMask).first!
        cacheDirectory = appSupport.appendingPathComponent("Imagin Bridge/Thumbnails")

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: cacheDirectory,
                                               withIntermediateDirectories: true)
    }

    // MARK: - Public Interface

    /// Load thumbnail for given file path
    /// Returns cached image immediately if available, otherwise loads asynchronously
    func loadThumbnail(for path: String, completion: @escaping (NSImage?) -> Void) {
        let cacheKey = cacheKey(for: path)

        // 1. Check memory cache first
        if let cachedImage = getCachedImage(for: cacheKey) {
            DispatchQueue.main.async {
                completion(cachedImage)
            }
            return
        }

        // 2. Check disk cache
        diskQueue.async { [weak self] in
            guard let self = self else { return }
            
            if let diskImage = self.loadFromDisk(cacheKey: cacheKey) {
                self.setCachedImage(diskImage, for: cacheKey)
                DispatchQueue.main.async {
                    completion(diskImage)
                }
                return
            }

            // 3. Generate from RAW file
            self.generateThumbnail(for: path, cacheKey: cacheKey, completion: completion)
        }
    }

    /// Synchronous version for immediate use (checks memory cache only)
    func getCachedThumbnail(for path: String) -> NSImage? {
        let cacheKey = cacheKey(for: path)
        return getCachedImage(for: cacheKey)
    }

    /// Clear memory cache
    func clearMemoryCache() {
        cacheQueue.async(flags: .barrier) {
            self.memoryCache.removeAll()
        }
    }

    /// Clear disk cache
    func clearDiskCache() {
        diskQueue.async {
            try? FileManager.default.removeItem(at: self.cacheDirectory)
            try? FileManager.default.createDirectory(at: self.cacheDirectory,
                                                   withIntermediateDirectories: true)
        }
    }

    // MARK: - Private Methods

    private func cacheKey(for path: String) -> String {
        // Use just the filename (without extension) + .jpg
        let url = URL(fileURLWithPath: path)
        return url.deletingPathExtension().lastPathComponent
    }

    private func getCachedImage(for cacheKey: String) -> NSImage? {
        return cacheQueue.sync {
            return memoryCache[cacheKey]
        }
    }

    private func setCachedImage(_ image: NSImage, for cacheKey: String) {
        cacheQueue.async(flags: .barrier) {
            self.memoryCache[cacheKey] = image
        }
    }

    private func loadFromDisk(cacheKey: String) -> NSImage? {
        let diskPath = cacheDirectory.appendingPathComponent("\(cacheKey).jpg")
        guard FileManager.default.fileExists(atPath: diskPath.path),
              let data = try? Data(contentsOf: diskPath),
              let image = NSImage(data: data) else {
            return nil
        }
        return image
    }

    private func saveToDisk(_ image: NSImage, cacheKey: String) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return
        }

        let diskPath = cacheDirectory.appendingPathComponent("\(cacheKey).jpg")
        try? jpegData.write(to: diskPath)
    }

    private func generateThumbnail(for path: String, cacheKey: String, completion: @escaping (NSImage?) -> Void) {
        // Generate thumbnail from RAW file
        print("Generate thumbnail for: \(path)")
        guard let data = RawWrapper.shared().extractEmbeddedJPEG(path),
              let originalImage = NSImage(data: data) else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }

        // Resize to 100px on longest side
        let thumbnail = resizeImage(originalImage, maxSize: 100)

        // Cache in memory
        setCachedImage(thumbnail, for: cacheKey)

        // Save to disk
        saveToDisk(thumbnail, cacheKey: cacheKey)

        // Return result
        DispatchQueue.main.async {
            completion(thumbnail)
        }
    }

    private func resizeImage(_ image: NSImage, maxSize: CGFloat) -> NSImage {
        let originalSize = image.size
        let aspectRatio = originalSize.width / originalSize.height

        var newSize: NSSize
        if originalSize.width > originalSize.height {
            newSize = NSSize(width: maxSize, height: maxSize / aspectRatio)
        } else {
            newSize = NSSize(width: maxSize * aspectRatio, height: maxSize)
        }

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                  from: NSRect(origin: .zero, size: originalSize),
                  operation: .sourceOver,
                  fraction: 1.0)
        newImage.unlockFocus()

        return newImage
    }
}

// MARK: - Cache Statistics (for debugging)
extension ThumbsManager {
    var memoryCacheCount: Int {
        return cacheQueue.sync {
            return memoryCache.count
        }
    }

    var diskCacheSize: Int64 {
        guard let enumerator = FileManager.default.enumerator(at: cacheDirectory,
                                                            includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = resourceValues.fileSize {
                totalSize += Int64(fileSize)
            }
        }
        return totalSize
    }
}
