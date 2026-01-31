//
//  ThumbsManager.swift
//  Bridge Replacement
//
//  Created by Cristian Baluta on 30.01.2026.
//

import Foundation
import AppKit

class ThumbsManager: ObservableObject {
    static let shared = ThumbsManager()

    // Memory cache for loaded thumbnails
    private var memoryCache: [String: NSImage] = [:]
    private let cacheQueue = DispatchQueue(label: "ro.imagin.thumbs.cache", attributes: .concurrent)
    private let diskQueue = DispatchQueue(label: "r.imagin.thumbs.disk", qos: .userInitiated)

    // Cache directory
    private let cacheDirectory: URL

    private let thumbSize: CGFloat = 256

    private init() {
        // Create cache directory in Application Support
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDir.appendingPathComponent("ro.imagin.Bridge-Replacement/256")

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
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

            if let diskImage = self.loadFromDisk(cacheKey: cacheKey, forPath: path) {
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
        // Use original filename as cache key
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func cacheSubdirectory(for path: String) -> URL {
        let url = URL(fileURLWithPath: path)
        let directoryPath = url.deletingLastPathComponent().path

        // Create folder name: originalFolderName_hash
        let lastComponent = url.deletingLastPathComponent().lastPathComponent
        let directoryHash = abs(directoryPath.hashValue)
        let safeFolderName = "\(lastComponent)_\(directoryHash)"

        return cacheDirectory.appendingPathComponent(safeFolderName)
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

    private func loadFromDisk(cacheKey: String, forPath path: String) -> NSImage? {
        let cacheSubdir = cacheSubdirectory(for: path)
        let diskPath = cacheSubdir.appendingPathComponent("\(cacheKey).jpg")

        guard FileManager.default.fileExists(atPath: diskPath.path),
              let data = try? Data(contentsOf: diskPath),
              let image = NSImage(data: data) else {
            return nil
        }
        return image
    }

    private func saveToDisk(_ image: NSImage, cacheKey: String, forPath path: String) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return
        }

        let cacheSubdir = cacheSubdirectory(for: path)

        // Create subdirectory if it doesn't exist
        try? FileManager.default.createDirectory(at: cacheSubdir, withIntermediateDirectories: true)

        let diskPath = cacheSubdir.appendingPathComponent("\(cacheKey).jpg")
        try? jpegData.write(to: diskPath)
    }

    private func generateThumbnail(for path: String, cacheKey: String, completion: @escaping (NSImage?) -> Void) {
        let url = URL(fileURLWithPath: path)
        let fileExtension = url.pathExtension.lowercased()

        // Define RAW file extensions
        let rawExtensions = ["arw", "orf", "rw2", "cr2", "cr3", "crw", "nef", "nrw",
                           "srf", "sr2", "raw", "raf", "pef", "ptx", "dng", "3fr",
                           "fff", "iiq", "mef", "mos", "x3f", "srw", "dcr", "kdc",
                           "k25", "kc2", "mrw", "erf", "bay", "ndd", "sti", "rwl", "r3d"]

        var originalImage: NSImage?

        if rawExtensions.contains(fileExtension) {
            // Generate thumbnail from RAW file using RawWrapper
            print("Generate RAW thumbnail for: \(path)")
            guard let data = RawWrapper.shared().extractEmbeddedJPEG(path) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            originalImage = NSImage(data: data)
        } else {
            // Load regular image file directly from disk
            print("Generate thumbnail for image file: \(path)")
            originalImage = NSImage(contentsOfFile: path)
        }

        guard let image = originalImage else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }

        let thumbnail = image.resized(maxSize: thumbSize)

        // Cache in memory
        setCachedImage(thumbnail, for: cacheKey)

        // Save to disk
        saveToDisk(thumbnail, cacheKey: cacheKey, forPath: path)

        // Return result
        DispatchQueue.main.async {
            completion(thumbnail)
        }
    }
}

// MARK: - Cache Statistics (for debugging)
//extension ThumbsManager {
//    var memoryCacheCount: Int {
//        return cacheQueue.sync {
//            return memoryCache.count
//        }
//    }
//
//    var diskCacheSize: Int64 {
//        guard let enumerator = FileManager.default.enumerator(at: cacheDirectory,
//                                                              includingPropertiesForKeys: [.fileSizeKey]) else {
//            return 0
//        }
//
//        var totalSize: Int64 = 0
//        for case let fileURL as URL in enumerator {
//            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
//               let fileSize = resourceValues.fileSize {
//                totalSize += Int64(fileSize)
//            }
//        }
//        return totalSize
//    }
//}
