//
//  PreviewsManager.swift
//  Imagin Raw
//

import Foundation
import CryptoKit
import Photos

class PreviewsManager {
    static let shared = PreviewsManager()

    var decoder: RawDecoder = LibRawDecoder()

    // MARK: - Config
    private let previewSize: CGFloat = 1024
    private let jpegQuality: CGFloat = 0.85
    private let maxMemoryCacheSize = 20
    private let processingLimit = 5

    // MARK: - Cache
    private var memoryCache: [String: CacheEntry] = [:]
    private var cacheAccessOrder: [String] = []
    private let cacheQueue = DispatchQueue(label: "ro.imagin.previews.cache", attributes: .concurrent)
    private let diskQueue = DispatchQueue(label: "ro.imagin.previews.disk", qos: .userInitiated)

    // MARK: - Request queue — protected by queueLock
    private var pendingRequests: [String: ThumbnailRequest] = [:]
    private var priorityQueue = PriorityQueue<ThumbnailRequest>()
    private let queueLock = NSLock()
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

    func loadPreview(for photo: PhotoItem, completion: @escaping (IRImage?, ExifInfo?) -> Void) {
        let source = photo.makeSource()
        let key = source.cacheKey

        if let cached = getCachedImage(for: key) {
            DispatchQueue.main.async {
                completion(cached, nil)
            }
            return
        }

        queueLock.lock()
        requestCounter += 1
        let order = requestCounter
        if let existing = pendingRequests[key] {
            if ThumbnailRequest.Priority.high.rawValue >= existing.priority.rawValue {
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
            priority: .high,
            requestOrder: order,
            source: source,
            completion: { img in completion(img, nil) }
        )
        pendingRequests[key] = request
        priorityQueue.enqueue(request)
        queueLock.unlock()

        processQueue()
    }

    func cancelPreview(for photo: PhotoItem) {
        let key = photo.makeSource().cacheKey
        queueLock.lock()
        pendingRequests.removeValue(forKey: key)
        rebuildQueue()
        queueLock.unlock()
    }

    func diskCacheURL(for path: String) -> URL {
        let subdir = cacheSubdirectory(for: path)
        let filename = URL(fileURLWithPath: path).lastPathComponent
        return subdir.appendingPathComponent("\(filename).jpg")
    }

    // MARK: - Private Queue

    private func processQueue() {
        queueLock.lock()
        guard !isProcessingQueue else {
            queueLock.unlock()
            return
        }
        isProcessingQueue = true
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

            guard let current = request else {
                break
            }

            queueLock.lock()
            let isValid: Bool
            if let pending = pendingRequests[current.cacheKey], pending.id == current.id {
                pendingRequests.removeValue(forKey: current.cacheKey)
                isValid = true
            } else {
                isValid = false
            }
            queueLock.unlock()

            guard isValid else {
                continue
            }

            processRequest(current)
        }

        queueLock.lock()
        isProcessingQueue = false
        queueLock.unlock()
    }

    private func processRequest(_ request: ThumbnailRequest) {
        processingSemaphore.wait()
        autoreleasepool {
            // Disk cache hit — file-based only
            if let diskSource = request.source as? DiskPhotoSource,
               let img = loadFromDisk(for: diskSource.path) {
                setCachedImage(img, for: request.cacheKey)
                DispatchQueue.main.async {
                    request.completion(img)
                }
                processingSemaphore.signal()
                return
            }

            // For disk sources, ensure iCloud file is local
            if let diskSource = request.source as? DiskPhotoSource {
                guard ICloudDownloader.ensureDownloaded(at: URL(fileURLWithPath: diskSource.path)) else {
                    DispatchQueue.main.async {
                        request.completion(nil)
                    }
                    processingSemaphore.signal()
                    return
                }
            }

            request.source.loadPreview(targetSize: previewSize) { [weak self] img in
                defer {
                    self?.processingSemaphore.signal()
                }
                guard let img else {
                    DispatchQueue.main.async {
                        request.completion(nil)
                    }
                    return
                }
                // Save to disk for file-based sources only
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
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return IRImage(contentsOf: url)
    }

    private func saveToDisk(_ image: IRImage, forPath path: String) {
        let subdir = cacheSubdirectory(for: path)
        let filename = URL(fileURLWithPath: path).lastPathComponent
        #if os(macOS)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }
        let mutable = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(mutable, "public.jpeg" as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            return
        }
        try? FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let diskURL = subdir.appendingPathComponent("\(filename).jpg")
        try? (mutable as Data).write(to: diskURL)
        #endif
    }

    // MARK: - Memory Cache

    private func getCachedImage(for key: String) -> IRImage? {
        cacheQueue.sync {
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
            while memoryCache.count > self.maxMemoryCacheSize, !self.cacheAccessOrder.isEmpty {
                let lru = self.cacheAccessOrder.removeFirst()
                self.memoryCache.removeValue(forKey: lru)
            }
        }
    }

    private func updateAccessOrder(for key: String) {
        cacheAccessOrder.removeAll { $0 == key }
        cacheAccessOrder.append(key)
    }

    // MARK: - Keys & Paths

    private func cacheSubdirectory(for path: String) -> URL {
        let url = URL(fileURLWithPath: path)
        let dirPath = url.deletingLastPathComponent().path
        let lastComp = url.deletingLastPathComponent().lastPathComponent
        let dirHash = persistentHash(for: dirPath)
        return cacheDirectory.appendingPathComponent("\(lastComp)_\(dirHash)")
    }

    private func persistentHash(for string: String) -> String {
        let hash = SHA256.hash(data: Data(string.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(8).description
    }

    private func rebuildQueue() {
        var q = PriorityQueue<ThumbnailRequest>()
        for r in pendingRequests.values {
            q.enqueue(r)
        }
        priorityQueue = q
    }
}
