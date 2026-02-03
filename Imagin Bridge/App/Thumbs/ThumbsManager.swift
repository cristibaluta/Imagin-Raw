//
//  ThumbsManager.swift
//  Imagin Bridge
//
//  Created by Cristian Baluta on 30.01.2026.
//

import Foundation
import AppKit
import CryptoKit

// MARK: - Supporting Data Structures

struct CacheEntry {
    let image: NSImage
    let lastAccessed: Date
}

struct ThumbnailRequest: Comparable {
    let id: UUID = UUID()
    let path: String
    let cacheKey: String
    let priority: Priority
    let timestamp: Date = Date()
    let requestOrder: Int // Order in which request was made
    let completion: (NSImage?) -> Void

    enum Priority: Int, Comparable {
        case high = 3    // Currently visible
        case medium = 2  // Near viewport
        case low = 1     // Background/prefetch

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    static func < (lhs: ThumbnailRequest, rhs: ThumbnailRequest) -> Bool {
        if lhs.priority == rhs.priority {
            // For same priority, prefer more recent requests (higher requestOrder)
            return lhs.requestOrder < rhs.requestOrder
        }
        return lhs.priority > rhs.priority // Higher priority first
    }

    static func == (lhs: ThumbnailRequest, rhs: ThumbnailRequest) -> Bool {
        return lhs.id == rhs.id
    }
}

struct PriorityQueue<Element: Comparable> {
    private var elements: [Element] = []

    var isEmpty: Bool {
        return elements.isEmpty
    }

    var count: Int {
        return elements.count
    }

    mutating func enqueue(_ element: Element) {
        elements.append(element)
        // Sort in descending order so the highest priority/most recent comes first
        elements.sort { $0 > $1 }
    }

    mutating func dequeue() -> Element? {
        return elements.isEmpty ? nil : elements.removeFirst()
    }

    mutating func removeAll() {
        elements.removeAll()
    }
}

class ThumbsManager: ObservableObject {
    static let shared = ThumbsManager()

    // Memory cache with LRU eviction
    private var memoryCache: [String: CacheEntry] = [:]
    private var cacheAccessOrder: [String] = []
    private let maxMemoryCacheSize = 200 // Maximum number of images in memory
    private let cacheQueue = DispatchQueue(label: "ro.imagin.thumbs.cache", attributes: .concurrent)
    private let diskQueue = DispatchQueue(label: "r.imagin.thumbs.disk", qos: .userInitiated)

    // Priority queue for thumbnail generation
    private var pendingRequests: [String: ThumbnailRequest] = [:]
    private var priorityQueue = PriorityQueue<ThumbnailRequest>()
    private let requestQueue = DispatchQueue(label: "ro.imagin.thumbs.requests")
    private var isProcessingQueue = false
    private var requestCounter = 0 // Counter to track request order

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

    /// Load thumbnail with priority for given file path
    /// Returns cached image immediately if available, otherwise loads asynchronously
    func loadThumbnail(for path: String, priority: ThumbnailRequest.Priority = .medium, completion: @escaping (NSImage?) -> Void) {
        let cacheKey = cacheKey(for: path)

        // 1. Check memory cache first
        if let cachedImage = getCachedImage(for: cacheKey) {
            DispatchQueue.main.async {
                completion(cachedImage)
            }
            return
        }

        // 2. Check if request is already pending
        requestQueue.async { [weak self] in
            guard let self = self else { return }

            // Increment request counter for ordering
            self.requestCounter += 1
            let currentRequestOrder = self.requestCounter

            // Check if there's already a pending request for this image
            if let existingRequest = self.pendingRequests[cacheKey] {
                // If new request has higher or equal priority, replace the old one
                // This automatically prioritizes more recent requests
                if priority.rawValue >= existingRequest.priority.rawValue {
                    self.pendingRequests.removeValue(forKey: cacheKey)
                    // Rebuild the priority queue to remove the old request
                    self.rebuildQueue()
                } else {
                    // Lower priority request - ignore it
                    return
                }
            }

            // Create new request with current order
            let request = ThumbnailRequest(
                path: path,
                cacheKey: cacheKey,
                priority: priority,
                requestOrder: currentRequestOrder,
                completion: completion
            )

            self.pendingRequests[cacheKey] = request
            self.priorityQueue.enqueue(request)

            self.processQueue()
        }
    }

    /// Load thumbnail for given file path (legacy method for compatibility)
    func loadThumbnail(for path: String, completion: @escaping (NSImage?) -> Void) {
        loadThumbnail(for: path, priority: .medium, completion: completion)
    }

    /// Synchronous version for immediate use (checks memory cache only)
    func getCachedThumbnail(for path: String) -> NSImage? {
        let cacheKey = cacheKey(for: path)
        return getCachedImage(for: cacheKey)
    }

    /// Clear memory cache
    func clearMemoryCache() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.memoryCache.removeAll()
            self?.cacheAccessOrder.removeAll()
        }
    }

    /// Clear disk cache
    func clearDiskCache() {
        diskQueue.async { [weak self] in
            guard let self = self else { return }
            try? FileManager.default.removeItem(at: self.cacheDirectory)
            try? FileManager.default.createDirectory(at: self.cacheDirectory,
                                                   withIntermediateDirectories: true)
        }
    }

    /// Stop all pending thumbnail requests and clear the queue
    /// Useful when switching folders to prevent processing thumbnails for old folder
    func stopQueue() {
        requestQueue.async { [weak self] in
            guard let self = self else { return }

            // Clear all pending requests
            self.pendingRequests.removeAll()
            self.priorityQueue.removeAll()

            // Reset the processing flag so new requests can start fresh
            self.isProcessingQueue = false

            print("ThumbsManager: Queue stopped and cleared")
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
        let directoryHash = persistentHash(for: directoryPath)
        let safeFolderName = "\(lastComponent)_\(directoryHash)"

        return cacheDirectory.appendingPathComponent(safeFolderName)
    }

    private func persistentHash(for string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(8).description
    }

    private func getCachedImage(for cacheKey: String) -> NSImage? {
        return cacheQueue.sync {
            guard let entry = memoryCache[cacheKey] else { return nil }

            // Update access order for LRU
            updateAccessOrder(for: cacheKey)

            return entry.image
        }
    }

    private func setCachedImage(_ image: NSImage, for cacheKey: String) {
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let entry = CacheEntry(image: image, lastAccessed: Date())
            self.memoryCache[cacheKey] = entry
            self.updateAccessOrder(for: cacheKey)

            // Enforce cache size limit with LRU eviction
            self.evictIfNeeded()
        }
    }

    private func updateAccessOrder(for cacheKey: String) {
        // Remove from current position
        cacheAccessOrder.removeAll { $0 == cacheKey }
        // Add to end (most recently used)
        cacheAccessOrder.append(cacheKey)
    }

    private func evictIfNeeded() {
        while memoryCache.count > maxMemoryCacheSize && !cacheAccessOrder.isEmpty {
            let lruKey = cacheAccessOrder.removeFirst()
            memoryCache.removeValue(forKey: lruKey)
        }
    }

    private func processQueue() {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true

        diskQueue.async { [weak self] in
            self?.processAllRequests()
        }
    }

    private func processAllRequests() {
        while true {
            var request: ThumbnailRequest?

            // Get next request from queue
            requestQueue.sync {
                request = self.priorityQueue.dequeue()
            }

            guard let currentRequest = request else {
                // No more requests
                break
            }

            // Check if request is still valid (not replaced by newer request)
            let isValid = requestQueue.sync {
                if let pendingRequest = self.pendingRequests[currentRequest.cacheKey] {
                    if pendingRequest.id == currentRequest.id {
                        self.pendingRequests.removeValue(forKey: currentRequest.cacheKey)
                        return true
                    }
                }
                return false
            }

            if !isValid {
                // This request was replaced by a newer one, skip it
                continue
            }

            // Process the request
            self.processRequest(currentRequest)
        }

        requestQueue.async { [weak self] in
            self?.isProcessingQueue = false
        }
    }

    private func processRequest(_ request: ThumbnailRequest) {
        // First check disk cache
        if let diskImage = loadFromDisk(cacheKey: request.cacheKey, forPath: request.path) {
            setCachedImage(diskImage, for: request.cacheKey)
            DispatchQueue.main.async {
                request.completion(diskImage)
            }
            return
        }

        // Generate thumbnail from source
        generateThumbnail(for: request.path, cacheKey: request.cacheKey) { [weak self] image in
            guard let image = image else {
                DispatchQueue.main.async {
                    request.completion(nil)
                }
                return
            }

            self?.setCachedImage(image, for: request.cacheKey)
            DispatchQueue.main.async {
                request.completion(image)
            }
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
                completion(nil)
                return
            }
            originalImage = NSImage(data: data)
        } else {
            // Load regular image file directly from disk
            print("Generate thumbnail for image file: \(path)")
            originalImage = NSImage(contentsOfFile: path)
        }

        guard let image = originalImage else {
            completion(nil)
            return
        }

        let thumbnail = image.resized(maxSize: thumbSize)

        // Save to disk
        saveToDisk(thumbnail, cacheKey: cacheKey, forPath: path)

        // Return result
        completion(thumbnail)
    }

    private func rebuildQueue() {
        // Rebuild priority queue with current pending requests
        var newQueue = PriorityQueue<ThumbnailRequest>()
        for request in pendingRequests.values {
            newQueue.enqueue(request)
        }
        priorityQueue = newQueue
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
