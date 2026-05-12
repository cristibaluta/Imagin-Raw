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
    private var heap: [T] = []

    init() {}

    // O(n) bulk initialisation via Floyd's heapify
    init<S: Sequence>(_ sequence: S) where S.Element == T {
        heap = Array(sequence)
        guard heap.count > 1 else {
            return
        }
        for i in stride(from: heap.count / 2 - 1, through: 0, by: -1) {
            siftDown(from: i)
        }
    }

    // O(log n) insert via sift-up
    mutating func enqueue(_ element: T) {
        heap.append(element)
        siftUp(from: heap.count - 1)
    }

    // O(log n) remove-max via sift-down
    mutating func dequeue() -> T? {
        guard !heap.isEmpty else {
            return nil
        }
        if heap.count == 1 {
            return heap.removeLast()
        }
        let top = heap[0]
        heap[0] = heap.removeLast()
        siftDown(from: 0)
        return top
    }

    mutating func removeAll() {
        heap.removeAll()
    }

    var isEmpty: Bool { heap.isEmpty }

    // MARK: - Heap helpers

    private mutating func siftUp(from index: Int) {
        var child = index
        while child > 0 {
            let parent = (child - 1) / 2
            guard heap[child] > heap[parent] else {
                break
            }
            heap.swapAt(child, parent)
            child = parent
        }
    }

    private mutating func siftDown(from index: Int) {
        let count = heap.count
        var parent = index
        while true {
            let left = 2 * parent + 1
            let right = 2 * parent + 2
            var largest = parent
            if left < count && heap[left] > heap[largest] {
                largest = left
            }
            if right < count && heap[right] > heap[largest] {
                largest = right
            }
            guard largest != parent else {
                break
            }
            heap.swapAt(parent, largest)
            parent = largest
        }
    }
}

class ThumbsManager: ObservableObject {

    @Published private(set) var pendingQueueCount: Int = 0

    // Memory cache — protected by cacheLock (plain NSLock avoids sync/barrier overhead on the main thread)
    private var memoryCache: [String: CacheEntry] = [:]
    private var cacheAccessOrder: [String] = []
    private let maxMemoryCacheSize = 600
    private let cacheLock = NSLock()
    // .utility keeps decode workers from competing with the main thread for CPU during scrolling
    private let diskQueue = DispatchQueue(label: "ro.imagin.thumbs.disk", qos: .utility,
                                         attributes: .concurrent, autoreleaseFrequency: .workItem)

    private var accessLog: [String: Date] = [:]
    private let accessLogLock = NSLock()

    // Request queue — protected by queueLock
    private var pendingRequests: [String: ThumbnailRequest] = [:]
    private var priorityQueue = PriorityQueue<ThumbnailRequest>()
    private let queueLock = NSLock()
    private var requestCounter = 0

    private var activeWorkerCount = 0
    private let maxWorkers = 4

    private let cacheDirectory: URL
    private let accessLogURL: URL
    private let diskCacheLimitBytes: Int64 = 2 * 1024 * 1024 * 1024

    private let thumbSize: CGFloat = 256

    init() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDir.appendingPathComponent("ro.imagin.raw/256")
        accessLogURL = cachesDir.appendingPathComponent("ro.imagin.raw/cache_access_log.json")
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
        cacheLock.lock()
        memoryCache.removeValue(forKey: key)
        cacheAccessOrder.removeAll { $0 == key }
        cacheLock.unlock()
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

        cacheLock.lock()
        let prefix = "\(dirHash)_"
        let keysToRemove = memoryCache.keys.filter { $0.hasPrefix(prefix) }
        keysToRemove.forEach {
            memoryCache.removeValue(forKey: $0)
            cacheAccessOrder.removeAll { $0 == $0 }
        }
        cacheLock.unlock()
        diskQueue.async { [weak self] in
            guard let self else { return }
            try? FileManager.default.removeItem(at: subdirectory)
            accessLogLock.lock()
            accessLog.removeValue(forKey: subdirName)
            let snapshot = accessLog
            accessLogLock.unlock()
            saveAccessLogSnapshot(snapshot)
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
        autoreleasepool {
            // Disk cache hit — only meaningful for file-based sources
            if let diskSource = request.source as? DiskPhotoSource,
               let img = loadFromDisk(for: diskSource.path) {
                setCachedImage(img, for: request.cacheKey)
                DispatchQueue.main.async {
                    request.completion(img)
                }
                return
            }

            // For disk sources, ensure the file is local (iCloud)
            if let diskSource = request.source as? DiskPhotoSource {
                guard ICloudDownloader.ensureDownloaded(at: URL(fileURLWithPath: diskSource.path)) else {
                    DispatchQueue.main.async {
                        request.completion(nil)
                    }
                    return
                }
            }

            request.source.loadThumbnail(targetSize: thumbSize) { [weak self] img in
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
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let entry = memoryCache[key] else { return nil }
        cacheAccessOrder.removeAll { $0 == key }
        cacheAccessOrder.append(key)
        return entry.image
    }

    private func setCachedImage(_ image: IRImage, for key: String) {
        cacheLock.lock()
        memoryCache[key] = CacheEntry(image: image, lastAccessed: Date())
        cacheAccessOrder.removeAll { $0 == key }
        cacheAccessOrder.append(key)
        evictIfNeeded()
        cacheLock.unlock()
    }

    private func evictIfNeeded() {
        while memoryCache.count > maxMemoryCacheSize, !cacheAccessOrder.isEmpty {
            let lru = cacheAccessOrder.removeFirst()
            memoryCache.removeValue(forKey: lru)
        }
    }

    private func rebuildQueue() {
        priorityQueue = PriorityQueue(pendingRequests.values)
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
        // Called only from init (single-threaded), no lock needed
        accessLog = raw
    }

    private func saveAccessLog() {
        accessLogLock.lock()
        let snapshot = accessLog
        accessLogLock.unlock()
        saveAccessLogSnapshot(snapshot)
    }

    private func saveAccessLogSnapshot(_ snapshot: [String: Date]) {
        diskQueue.async { [weak self] in
            guard let self,
                  let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: accessLogURL, options: .atomic)
        }
    }

    private func registerCacheSubdirectory(_ subdirName: String) {
        accessLogLock.lock()
        guard accessLog[subdirName] == nil else {
            accessLogLock.unlock()
            return
        }
        accessLog[subdirName] = Date()
        let snapshot = accessLog
        accessLogLock.unlock()
        saveAccessLogSnapshot(snapshot)
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
            guard let self else { return }
            let totalSize = totalDiskCacheSize()
            guard totalSize > diskCacheLimitBytes else { return }

            accessLogLock.lock()
            let sorted = accessLog.sorted { $0.value < $1.value }
            let deleteCount = max(1, sorted.count / 3)
            for (subdirName, _) in sorted.prefix(deleteCount) {
                accessLog.removeValue(forKey: subdirName)
            }
            let snapshot = accessLog
            accessLogLock.unlock()

            for (subdirName, _) in sorted.prefix(deleteCount) {
                let subdirURL = cacheDirectory.appendingPathComponent(subdirName)
                try? FileManager.default.removeItem(at: subdirURL)
            }
            saveAccessLogSnapshot(snapshot)
        }
    }
}
