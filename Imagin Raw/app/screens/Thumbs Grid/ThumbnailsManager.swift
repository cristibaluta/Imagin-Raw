//
//  PhotoCache.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 15.06.2026.
//

import Foundation
import CryptoKit

actor PhotoCache {
    private let cache = NSCache<NSString, NSData>()
    private let cacheLimit: Int

    init(cacheLimit: Int = 0) {
        self.cacheLimit = cacheLimit
        self.cache.countLimit = cacheLimit
    }

    func setImageData(_ data: Data, for key: String) {
        cache.setObject(NSData(data: data), forKey: NSString(string: key))
    }

    func getImageData(for key: String) -> Data? {
        cache.object(forKey: NSString(string: key)) as Data?
    }
}

actor AccessLogs {
    private var accessLog: [String: Date] = [:]
    private let accessLogURL: URL

    init() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        accessLogURL = cachesDir.appendingPathComponent("ro.imagin.raw/cache_access_log.json")
        guard let data = try? Data(contentsOf: accessLogURL),
              let raw = try? JSONDecoder().decode([String: Date].self, from: data) else {
            return
        }
        accessLog = raw
    }

    func getSnapstot() -> [String: Date] {
        accessLog
    }
    
    func saveSnapshot(_ snapshot: [String: Date]) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        accessLog = snapshot
        try? data.write(to: accessLogURL, options: .atomic)
    }
}

enum ThumbSize: Int {
    case s256 = 256
    case s1024 = 1024
}

final class ThumbnailsManager: Sendable {
    let memoryCache = PhotoCache()
    let accessLogs = AccessLogs() // The access date of each folder. Older accesses are evicted first

    private let cacheDirectory: URL
    private let thumbSize: ThumbSize
    private let diskCacheLimitBytes: Int64 = 2 * 1024 * 1024 * 1024

    init(thumbSize: ThumbSize) {
        self.thumbSize = thumbSize
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDir.appendingPathComponent("ro.imagin.raw/\(thumbSize.rawValue)")
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        Task {
            await evictDiskCacheIfNeeded()
        }
    }
    
    func getThumbnail(for photo: PhotoItem) async -> IRImage? {
        // 1. Search for the image in the memory
        if let cachedData = await memoryCache.getImageData(for: photo.path) {
            return IRImage(data: cachedData)
        }

        // 2. Search for the image on disk cache
        let source = photo.makeSource()
        if let diskData = loadFromDisk(for: photo.url) {
            await memoryCache.setImageData(diskData, for: photo.path)
            return IRImage(data: diskData)
        }

        // 3. Generate the thumbnail
        guard let image = source.loadThumbnail(targetSize: CGFloat(thumbSize.rawValue)) else {
            return nil
        }
        guard let jpegData = image.bitmapRepresentation() else {
            return nil
        }
        // Only save to disk for file-based sources
        if source is DiskPhotoSource {
            saveToDisk(jpegData, for: photo.url)
        }

        // 4. Save the thumbnail to disk and memory
        await memoryCache.setImageData(jpegData, for: photo.path)

        return IRImage(data: jpegData)
    }

    func purgeCache(for folderURL: URL) async {
        let folderPath = folderURL.path
        let dirHash = persistentHash(for: folderPath)
        let subdirName = "\(folderURL.lastPathComponent)_\(dirHash)"
        let subdirectory = cacheDirectory.appendingPathComponent(subdirName)

//        let prefix = "\(dirHash)_"
//        let keysToRemove = await memoryCache.keys.filter { $0.hasPrefix(prefix) }
//        keysToRemove.forEach {
//            await memoryCache.removeValue(forKey: $0)
//        }
//        try? FileManager.default.removeItem(at: subdirectory)
//        accessLogs.removeValue(forKey: subdirName)
//        let snapshot = accessLog
//        saveAccessLogSnapshot(snapshot)
    }

    private func loadFromDisk(for photoUrl: URL) -> Data? {
        let cacheUrl = cachedPhotoUrl(for: photoUrl)
        if let data = try? Data(contentsOf: cacheUrl) {
            return data
        }
        return nil
    }

    private func saveToDisk(_ jpegData: Data, for url: URL) {
        let cacheDir = cacheDir(for: url)
        let isNew = !FileManager.default.fileExists(atPath: cacheDir.path)
        if isNew {
            guard (try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)) != nil else {
                RCLog("Couldn't create cache folder for \(cacheDir.path)")
                return
            }
            registerCacheSubdirectory(cacheDir.lastPathComponent)
        }
        // Add jpg extension to the original file name
        let cachedPhotoUrl = cacheDir.appendingPathComponent("\(url.lastPathComponent).jpg")
        try? jpegData.write(to: cachedPhotoUrl)
    }

    private func registerCacheSubdirectory(_ subdirName: String) {
        Task {
            var snapshot = await accessLogs.getSnapstot()
            guard snapshot[subdirName] == nil else {
                return
            }
            snapshot[subdirName] = Date()
            await accessLogs.saveSnapshot(snapshot)
        }
    }

    /// Returns a cache folder of the form <album name>_<album path hash>
    private func cachedPhotoUrl(for photoUrl: URL) -> URL {
        let cacheDir = cacheDir(for: photoUrl)
        return cacheDir.appendingPathComponent("\(photoUrl.lastPathComponent).jpg")
    }

    private func cacheDir(for photoUrl: URL) -> URL {
        let folderUrl = photoUrl.deletingLastPathComponent()
        let folderName = folderUrl.lastPathComponent
        let folderUrlHash = persistentHash(for: folderUrl.absoluteString)
        let dir = cacheDirectory.appendingPathComponent("\(folderName)_\(folderUrlHash)")
        return dir
    }

    private func persistentHash(for string: String) -> String {
        let hash = SHA256.hash(data: Data(string.utf8))
        return hash.compactMap {
            String(format: "%02x", $0)
        }.joined().prefix(8).description
    }

    private func totalDiskCacheSize() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private func evictDiskCacheIfNeeded() async {
        let totalSize = totalDiskCacheSize()
        guard totalSize > diskCacheLimitBytes else {
            return
        }

        var snapshot = await accessLogs.getSnapstot()
        let sorted = snapshot.sorted { $0.value < $1.value }
        let deleteCount = max(1, sorted.count / 3)// Delete one third of the old albums cache
        for (subdirName, _) in sorted.prefix(deleteCount) {
            snapshot.removeValue(forKey: subdirName)
        }

        for (subdirName, _) in sorted.prefix(deleteCount) {
            let subdirURL = cacheDirectory.appendingPathComponent(subdirName)
            try? FileManager.default.removeItem(at: subdirURL)
        }
        await accessLogs.saveSnapshot(snapshot)
    }
}
