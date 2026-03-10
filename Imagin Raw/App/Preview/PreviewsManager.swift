//
//  PreviewsManager.swift
//  Imagin Raw
//

import Foundation
import AppKit
import CryptoKit

/// Manages a persistent disk + memory cache of 1024px preview images.
/// Same architecture as ThumbsManager but larger images, higher JPEG quality.
class PreviewsManager {
    static let shared = PreviewsManager()

    // MARK: - Config

    private let previewSize: CGFloat = 1024
    private let jpegQuality: CGFloat = 0.92
    private let maxMemoryCacheSize = 20
    private let processingLimit = 2

    // MARK: - Cache

    private var memoryCache: [String: CacheEntry] = [:]
    private var cacheAccessOrder: [String] = []
    private let cacheQueue = DispatchQueue(label: "ro.imagin.previews.cache", attributes: .concurrent)
    private let diskQueue = DispatchQueue(label: "ro.imagin.previews.disk", qos: .userInitiated)

    // MARK: - Request Queue

    private var pendingRequests: [String: ThumbnailRequest] = [:]
    private var priorityQueue = PriorityQueue<ThumbnailRequest>()
    private let requestQueue = DispatchQueue(label: "ro.imagin.previews.requests")
    private var isProcessingQueue = false
    private var requestCounter = 0
    private let processingSemaphore: DispatchSemaphore

    // MARK: - Disk

    private let cacheDirectory: URL

    private init() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDir.appendingPathComponent("ro.imagin.raw/1024")
        processingSemaphore = DispatchSemaphore(value: processingLimit)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public Interface

    func loadPreview(for path: String, completion: @escaping (NSImage?, ExifInfo?) -> Void) {
        let key = cacheKey(for: path)

        // 1. Memory cache hit
        if let cached = getCachedImage(for: key) {
            DispatchQueue.main.async { completion(cached, nil) }
            return
        }

        // 2. Enqueue
        requestQueue.async { [weak self] in
            guard let self else { return }
            self.requestCounter += 1
            let order = self.requestCounter

            if let existing = self.pendingRequests[key] {
                if ThumbnailRequest.Priority.high.rawValue >= existing.priority.rawValue {
                    self.pendingRequests.removeValue(forKey: key)
                    self.rebuildQueue()
                } else {
                    return
                }
            }

            let request = ThumbnailRequest(
                path: path,
                cacheKey: key,
                priority: .high,
                requestOrder: order,
                completion: { image in completion(image, nil) }
            )
            self.pendingRequests[key] = request
            self.priorityQueue.enqueue(request)
            self.processQueue()
        }
    }

    /// Cancel all pending requests for a given path
    func cancelPreview(for path: String) {
        let key = cacheKey(for: path)
        requestQueue.async { [weak self] in
            self?.pendingRequests.removeValue(forKey: key)
            self?.rebuildQueue()
        }
    }

    /// Returns the disk URL for a preview (may not exist yet)
    func diskCacheURL(for path: String) -> URL {
        let subdir = cacheSubdirectory(for: path)
        let filename = diskFilename(for: path)
        return subdir.appendingPathComponent("\(filename).jpg")
    }

    // MARK: - Private Queue

    private func processQueue() {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true
        diskQueue.async { [weak self] in self?.processAllRequests() }
    }

    private func processAllRequests() {
        while true {
            var request: ThumbnailRequest?
            requestQueue.sync { request = priorityQueue.dequeue() }
            guard let current = request else { break }

            let valid = requestQueue.sync { () -> Bool in
                if let pending = pendingRequests[current.cacheKey], pending.id == current.id {
                    pendingRequests.removeValue(forKey: current.cacheKey)
                    return true
                }
                return false
            }
            if !valid { continue }

            processRequest(current)
        }
        requestQueue.async { [weak self] in self?.isProcessingQueue = false }
    }

    private func processRequest(_ request: ThumbnailRequest) {
        processingSemaphore.wait()
        autoreleasepool {
            // Disk hit
            if let img = loadFromDisk(for: request.path) {
                setCachedImage(img, for: request.cacheKey)
                DispatchQueue.main.async { request.completion(img) }
                processingSemaphore.signal()
                return
            }

            // Generate
            generate(for: request.path, cacheKey: request.cacheKey) { [weak self] img in
                defer { self?.processingSemaphore.signal() }
                guard let img else {
                    DispatchQueue.main.async { request.completion(nil) }
                    return
                }
                self?.setCachedImage(img, for: request.cacheKey)
                DispatchQueue.main.async { request.completion(img) }
            }
        }
    }

    // MARK: - Generation

    private func generate(for path: String, cacheKey: String, completion: @escaping (NSImage?) -> Void) {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()

        autoreleasepool {
            var original: NSImage?

            if FilesExtensions.raw.contains(ext) {
                guard let data = RawWrapper.shared().extractEmbeddedJPEG(path) else {
                    completion(nil); return
                }
                original = NSImage(data: data)
            } else {
                original = NSImage(contentsOfFile: path)
            }

            guard let src = original else { completion(nil); return }

            let preview: NSImage? = autoreleasepool { src.resized(maxSize: previewSize) }
            guard let final = preview else { completion(nil); return }

            saveToDisk(final, for: path)
            completion(final)
        }
    }

    // MARK: - Disk I/O

    private func loadFromDisk(for path: String) -> NSImage? {
        let url = diskCacheURL(for: path)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let img = NSImage(data: data) else { return nil }
        return img
    }

    private func saveToDisk(_ image: NSImage, for path: String) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: jpegQuality]) else { return }
        let subdir = cacheSubdirectory(for: path)
        try? FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let diskURL = subdir.appendingPathComponent("\(diskFilename(for: path)).jpg")
        try? jpeg.write(to: diskURL)
    }

    // MARK: - Memory Cache

    private func getCachedImage(for key: String) -> NSImage? {
        cacheQueue.sync {
            guard let entry = memoryCache[key] else { return nil }
            updateAccessOrder(for: key)
            return entry.image
        }
    }

    private func setCachedImage(_ image: NSImage, for key: String) {
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            memoryCache[key] = CacheEntry(image: image, lastAccessed: Date())
            updateAccessOrder(for: key)
            while memoryCache.count > maxMemoryCacheSize, !cacheAccessOrder.isEmpty {
                let lru = cacheAccessOrder.removeFirst()
                memoryCache.removeValue(forKey: lru)
            }
        }
    }

    private func updateAccessOrder(for key: String) {
        cacheAccessOrder.removeAll { $0 == key }
        cacheAccessOrder.append(key)
    }

    // MARK: - Keys & Paths

    private func cacheKey(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let dirHash = persistentHash(for: url.deletingLastPathComponent().path)
        return "\(dirHash)_\(url.lastPathComponent)"
    }

    private func cacheSubdirectory(for path: String) -> URL {
        let url = URL(fileURLWithPath: path)
        let dirPath = url.deletingLastPathComponent().path
        let lastComp = url.deletingLastPathComponent().lastPathComponent
        let dirHash = persistentHash(for: dirPath)
        return cacheDirectory.appendingPathComponent("\(lastComp)_\(dirHash)")
    }

    private func diskFilename(for path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    private func persistentHash(for string: String) -> String {
        let hash = SHA256.hash(data: Data(string.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(8).description
    }

    private func rebuildQueue() {
        var q = PriorityQueue<ThumbnailRequest>()
        for r in pendingRequests.values { q.enqueue(r) }
        priorityQueue = q
    }
}
