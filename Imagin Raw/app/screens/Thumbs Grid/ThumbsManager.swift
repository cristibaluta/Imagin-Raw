//
//  ThumbsManager.swift
//  Imagin Raw
//

import Foundation
import CryptoKit
import AVFoundation
import Photos

// MARK: - Supporting types

struct CacheEntry {
    let image: IRImage
    let lastAccessed: Date
}

struct ThumbnailRequest: Comparable {
    enum Priority: Int {
        case low = 0, medium = 1, high = 2
    }

    let id = UUID()
    let path: String
    let cacheKey: String
    let priority: Priority
    let requestOrder: Int
    let source: PhotoSource
    let completion: (IRImage?) -> Void

    static func < (lhs: ThumbnailRequest, rhs: ThumbnailRequest) -> Bool {
        if lhs.priority.rawValue != rhs.priority.rawValue {
            return lhs.priority.rawValue < rhs.priority.rawValue
        }
        return lhs.requestOrder < rhs.requestOrder
    }

    static func == (lhs: ThumbnailRequest, rhs: ThumbnailRequest) -> Bool {
        lhs.id == rhs.id
    }
}

struct PriorityQueue<T: Comparable> {
    private var elements: [T] = []

    mutating func enqueue(_ element: T) {
        elements.append(element)
        elements.sort(by: >)
    }

    mutating func dequeue() -> T? {
        guard !elements.isEmpty else {
            return nil
        }
        return elements.removeLast()
    }

    mutating func removeAll() {
        elements.removeAll()
    }

    var isEmpty: Bool { elements.isEmpty }
}

class ThumbsManager: ObservableObject {

    /// Points to the ThumbsManager of the currently loaded album.
    /// Updated by PhotosModel when a new album is loaded. All call sites use this
    /// instead of a singleton so cache is automatically scoped per album.
    static weak var current: ThumbsManager?

    @Published private(set) var pendingQueueCount: Int = 0

    // Memory cache
    private var memoryCache: [String: CacheEntry] = [:]
    private var cacheAccessOrder: [String] = []
    private let maxMemoryCacheSize = 200
    private let cacheQueue = DispatchQueue(label: "ro.imagin.thumbs.cache", attributes: .concurrent)
    private let diskQueue = DispatchQueue(label: "ro.imagin.thumbs.disk", qos: .userInitiated)

    // Request queue — protected by queueLock
    private var pendingRequests: [String: ThumbnailRequest] = [:]
    private var priorityQueue = PriorityQueue<ThumbnailRequest>()
    private let queueLock = NSLock()
    private var requestCounter = 0

    private let processingLimit = 4
    private let processingSemaphore: DispatchSemaphore
    // Number of workers currently draining the queue
    private var activeWorkerCount = 0
    private let maxWorkers = 4

    private let cacheDirectory: URL
    private let accessLogURL: URL
    private let diskCacheLimitBytes: Int64 = 2 * 1024 * 1024 * 1024

    private var accessLog: [String: Date] = [:]

    private let thumbSize: CGFloat = 256

    init() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDir.appendingPathComponent("ro.imagin.raw/256")
        accessLogURL = cachesDir.appendingPathComponent("ro.imagin.raw/cache_access_log.json")
        processingSemaphore = DispatchSemaphore(value: processingLimit)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        loadAccessLog()
        evictDiskCacheIfNeeded()
    }

    // MARK: - Public Interface

    func loadThumbnail(for photo: PhotoItem,
                       priority: ThumbnailRequest.Priority = .medium,
                       completion: @escaping (IRImage?) -> Void) {
        let source = photo.makeSource()
        let key = source.cacheKey

        if let cached = getCachedImage(for: key) {
            DispatchQueue.main.async {
                completion(cached)
            }
            return
        }

        // PhotoKit: bypass the disk queue — PHImageManager manages its own concurrency
        if let pkSource = source as? PhotoKitPhotoSource {
            pkSource.loadThumbnail(targetSize: thumbSize) { [weak self] img in
                guard let img else {
                    return
                }
                self?.setCachedImage(img, for: key)
                DispatchQueue.main.async {
                    completion(img)
                }
            }
            return
        }

        // Disk-based: go through the priority queue
        queueLock.lock()
        requestCounter += 1
        let order = requestCounter
        if let existing = pendingRequests[key] {
            if priority.rawValue >= existing.priority.rawValue {
                pendingRequests.removeValue(forKey: key)
                rebuildQueue()
            } else {
                queueLock.unlock()
                return
            }
        }
        let request = ThumbnailRequest(
            path: photo.path,
            cacheKey: key,
            priority: priority,
            requestOrder: order,
            source: source,
            completion: completion
        )
        pendingRequests[key] = request
        priorityQueue.enqueue(request)
        queueLock.unlock()

        scheduleQueueCountUpdate()
        processQueue(source: source)
    }

    func loadThumbnail(for path: String,
                       priority: ThumbnailRequest.Priority = .medium,
                       completion: @escaping (IRImage?) -> Void) {
        let source = DiskPhotoSource(path: path)
        let key = source.cacheKey

        if let cached = getCachedImage(for: key) {
            DispatchQueue.main.async {
                completion(cached)
            }
            return
        }

        queueLock.lock()
        requestCounter += 1
        let order = requestCounter
        if let existing = pendingRequests[key] {
            if priority.rawValue >= existing.priority.rawValue {
                pendingRequests.removeValue(forKey: key)
                rebuildQueue()
            } else {
                queueLock.unlock()
                return
            }
        }
        let request = ThumbnailRequest(
            path: path,
            cacheKey: key,
            priority: priority,
            requestOrder: order,
            source: source,
            completion: completion
        )
        pendingRequests[key] = request
        priorityQueue.enqueue(request)
        queueLock.unlock()

        scheduleQueueCountUpdate()
        processQueue(source: source)
    }

    func getCachedThumbnail(for path: String) -> IRImage? {
        let key = DiskPhotoSource(path: path).cacheKey
        return getCachedImage(for: key)
    }

    func getCachedThumbnail(for photo: PhotoItem) -> IRImage? {
        return getCachedImage(for: photo.makeSource().cacheKey)
    }

    func stopQueue() {
        queueLock.lock()
        pendingRequests.removeAll()
        priorityQueue.removeAll()
        activeWorkerCount = 0
        queueLock.unlock()
        scheduleQueueCountUpdate()
    }

    /// Cancel all pending requests that are below .high priority.
    /// Called when scrolling stops so visible cells can jump to the front.
    func cancelLowPriorityRequests() {
        queueLock.lock()
        let before = pendingRequests.count
        pendingRequests = pendingRequests.filter { $0.value.priority == .high }
        let removed = before - pendingRequests.count
        if removed > 0 {
            rebuildQueue()
        }
        queueLock.unlock()
    }

    func deleteCachedThumbnail(for path: String) {
        let source = DiskPhotoSource(path: path)
        let key = source.cacheKey
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self else {
                return
            }
            memoryCache.removeValue(forKey: key)
            cacheAccessOrder.removeAll { $0 == key }
        }
        diskQueue.async {
            let diskURL = self.diskCacheURL(for: source)
            if FileManager.default.fileExists(atPath: diskURL.path) {
                try? FileManager.default.removeItem(at: diskURL)
            }
        }
    }

    func cacheURL(for folderURL: URL) -> URL {
        let hash = persistentHash(for: folderURL.path)
        return cacheDirectory.appendingPathComponent("\(folderURL.lastPathComponent)_\(hash)")
    }

    func purgeCache(for folderURL: URL) {
        let folderPath = folderURL.path
        let dirHash = persistentHash(for: folderPath)
        let subdirName = "\(folderURL.lastPathComponent)_\(dirHash)"
        let subdirectory = cacheDirectory.appendingPathComponent(subdirName)

        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self else {
                return
            }
            let prefix = "\(dirHash)_"
            let keysToRemove = self.memoryCache.keys.filter { $0.hasPrefix(prefix) }
            keysToRemove.forEach {
                self.memoryCache.removeValue(forKey: $0)
                self.cacheAccessOrder.removeAll { $0 == $0 }
            }
        }
        diskQueue.async { [weak self] in
            guard let self else {
                return
            }
            try? FileManager.default.removeItem(at: subdirectory)
            accessLog.removeValue(forKey: subdirName)
            saveAccessLog()
        }
    }

    func diskCacheURL(for path: String) -> URL {
        diskCacheURL(for: DiskPhotoSource(path: path))
    }

    private func diskCacheURL(for source: DiskPhotoSource) -> URL {
        let url = URL(fileURLWithPath: source.path)
        let dirHash = persistentHash(for: url.deletingLastPathComponent().path)
        let lastComp = url.deletingLastPathComponent().lastPathComponent
        let subdir = cacheDirectory.appendingPathComponent("\(lastComp)_\(dirHash)")
        return subdir.appendingPathComponent("\(url.lastPathComponent).jpg")
    }

    private var queueCountDirty = false

    private func scheduleQueueCountUpdate() {
        guard !queueCountDirty else { return }
        queueCountDirty = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            queueLock.lock()
            let count = pendingRequests.count
            queueCountDirty = false
            queueLock.unlock()
            self.pendingQueueCount = count
        }
    }

    // MARK: - Queue

    private func processQueue(source: PhotoSource) {
        queueLock.lock()
        guard activeWorkerCount < maxWorkers else {
            queueLock.unlock()
            return
        }
        activeWorkerCount += 1
        queueLock.unlock()

        diskQueue.async { [weak self] in
            self?.processAllRequests()
        }
    }

    private func processAllRequests() {
        while true {
            queueLock.lock()
            let request = priorityQueue.dequeue()
            queueLock.unlock()

            guard let current = request else { break }

            queueLock.lock()
            let isValid: Bool
            if let pending = pendingRequests[current.cacheKey], pending.id == current.id {
                pendingRequests.removeValue(forKey: current.cacheKey)
                isValid = true
            } else {
                isValid = false
            }
            queueLock.unlock()

            scheduleQueueCountUpdate()

            guard isValid else { continue }
            processRequest(current)
        }

        queueLock.lock()
        activeWorkerCount -= 1
        queueLock.unlock()
    }

    private func processRequest(_ request: ThumbnailRequest) {
        processingSemaphore.wait()
        autoreleasepool {
            // Disk cache hit — only meaningful for file-based sources
            if let diskSource = request.source as? DiskPhotoSource,
               let img = loadFromDisk(for: diskSource.path) {
                setCachedImage(img, for: request.cacheKey)
                DispatchQueue.main.async {
                    request.completion(img)
                }
                processingSemaphore.signal()
                return
            }

            // For disk sources, ensure the file is local (iCloud)
            if let diskSource = request.source as? DiskPhotoSource {
                guard ICloudDownloader.ensureDownloaded(at: URL(fileURLWithPath: diskSource.path)) else {
                    DispatchQueue.main.async {
                        request.completion(nil)
                    }
                    processingSemaphore.signal()
                    return
                }
            }

            request.source.loadThumbnail(targetSize: thumbSize) { [weak self] img in
                defer {
                    self?.processingSemaphore.signal()
                }
                guard let img else {
                    DispatchQueue.main.async {
                        request.completion(nil)
                    }
                    return
                }
                // Only save to disk for file-based sources
                if let diskSource = request.source as? DiskPhotoSource {
                    self?.saveToDisk(img, forPath: diskSource.path)
                }
                self?.setCachedImage(img, for: request.cacheKey)
                DispatchQueue.main.async {
                    request.completion(img)
                }
            }
        }
    }

    // MARK: - Disk I/O

    private func loadFromDisk(for path: String) -> IRImage? {
        let url = diskCacheURL(for: path)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let img = IRImage(data: data) else {
            return nil
        }
        return img
    }

    private func saveToDisk(_ image: IRImage, forPath path: String) {
        guard let jpegData = image.bitmapRepresentation() else {
            return
        }
        let url = URL(fileURLWithPath: path)
        let dirHash = persistentHash(for: url.deletingLastPathComponent().path)
        let lastComp = url.deletingLastPathComponent().lastPathComponent
        let subdir = cacheDirectory.appendingPathComponent("\(lastComp)_\(dirHash)")
        let isNew = !FileManager.default.fileExists(atPath: subdir.path)
        try? FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        if isNew {
            registerCacheSubdirectory(subdir.lastPathComponent)
        }
        let diskURL = subdir.appendingPathComponent("\(url.lastPathComponent).jpg")
        try? jpegData.write(to: diskURL)
    }

    // MARK: - Memory Cache

    private func getCachedImage(for key: String) -> IRImage? {
        return cacheQueue.sync {
            guard let entry = memoryCache[key] else {
                return nil
            }
            updateAccessOrder(for: key)
            return entry.image
        }
    }

    private func setCachedImage(_ image: IRImage, for key: String) {
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self else {
                return
            }
            memoryCache[key] = CacheEntry(image: image, lastAccessed: Date())
            updateAccessOrder(for: key)
            evictIfNeeded()
        }
    }

    private func updateAccessOrder(for key: String) {
        cacheAccessOrder.removeAll { $0 == key }
        cacheAccessOrder.append(key)
    }

    private func evictIfNeeded() {
        while memoryCache.count > maxMemoryCacheSize, !cacheAccessOrder.isEmpty {
            let lru = cacheAccessOrder.removeFirst()
            memoryCache.removeValue(forKey: lru)
        }
    }

    private func rebuildQueue() {
        var q = PriorityQueue<ThumbnailRequest>()
        for r in pendingRequests.values {
            q.enqueue(r)
        }
        priorityQueue = q
    }

    // MARK: - Disk Cache Management

    private func persistentHash(for string: String) -> String {
        let hash = SHA256.hash(data: Data(string.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(8).description
    }

    private func loadAccessLog() {
        guard let data = try? Data(contentsOf: accessLogURL),
              let raw = try? JSONDecoder().decode([String: Date].self, from: data) else {
            return
        }
        accessLog = raw
    }

    private func saveAccessLog() {
        diskQueue.async { [weak self] in
            guard let self,
                  let data = try? JSONEncoder().encode(accessLog) else {
                return
            }
            try? data.write(to: accessLogURL, options: .atomic)
        }
    }

    private func registerCacheSubdirectory(_ subdirName: String) {
        guard accessLog[subdirName] == nil else {
            return
        }
        accessLog[subdirName] = Date()
        saveAccessLog()
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

    private func evictDiskCacheIfNeeded() {
        diskQueue.async { [weak self] in
            guard let self else {
                return
            }
            let totalSize = totalDiskCacheSize()
            guard totalSize > diskCacheLimitBytes else {
                return
            }
            let sorted = accessLog.sorted { $0.value < $1.value }
            let deleteCount = max(1, sorted.count / 3)
            for (subdirName, _) in sorted.prefix(deleteCount) {
                let subdirURL = cacheDirectory.appendingPathComponent(subdirName)
                try? FileManager.default.removeItem(at: subdirURL)
                accessLog.removeValue(forKey: subdirName)
            }
            saveAccessLog()
        }
    }
}
