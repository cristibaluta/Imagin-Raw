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
    private let jpegQuality: CGFloat = 0.85
    private let maxMemoryCacheSize = 20
    private let processingLimit = 5

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
        let filename = URL(fileURLWithPath: path).lastPathComponent
        let t0 = Date()
        print("🖼 [PreviewsManager] loadPreview \(filename)")

        // 1. Memory cache hit
        if let cached = getCachedImage(for: key) {
            print("🖼 [PreviewsManager] memory hit \(filename)")
            DispatchQueue.main.async { completion(cached, nil) }
            return
        }

        // 2. Enqueue
        requestQueue.async { [weak self] in
            guard let self else { return }
            print("🖼 [PreviewsManager] enqueued \(filename)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s")
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
        let filename = URL(fileURLWithPath: request.path).lastPathComponent
        let t0 = Date()
        print("🖼 [PreviewsManager] processRequest \(filename)")
        processingSemaphore.wait()
        print("🖼 [PreviewsManager] semaphore acquired \(filename)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s")
        autoreleasepool {
            // Disk hit
            if let img = loadFromDisk(for: request.path) {
                print("🖼 [PreviewsManager] disk hit \(filename)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s")
                setCachedImage(img, for: request.cacheKey)
                DispatchQueue.main.async { request.completion(img) }
                processingSemaphore.signal()
                return
            }
            print("🖼 [PreviewsManager] disk miss, generating \(filename)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s")

            // Generate
            generate(for: request.path, cacheKey: request.cacheKey) { [weak self] img in
                defer { self?.processingSemaphore.signal() }
                print("🖼 [PreviewsManager] generate done \(filename)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s  image=\(img != nil)")
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
        let filename = url.lastPathComponent
        let t0 = Date()

        autoreleasepool {
            // 1. Get source CGImage — embedded JPEG for RAW, CGImageSource for others
            let sourceCG: CGImage?
            var exifOrientation: Int32 = 1

            if FilesExtensions.raw.contains(ext) {
                guard let data = RawWrapper.shared().extractEmbeddedJPEG(path) else {
                    print("🖼 [PreviewsManager] extractEmbeddedJPEG failed \(filename)")
                    completion(nil);
                    return
                }
                print("🖼 [PreviewsManager] extractEmbeddedJPEG done \(filename)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s  bytes=\(data.count)")
                if let src = CGImageSourceCreateWithData(data as CFData, nil) {
                    sourceCG = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
                    if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                       let orientation = props[kCGImagePropertyOrientation] as? Int32 {
                        exifOrientation = orientation
                    }
                } else {
                    sourceCG = nil
                }
            } else {
                guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                    completion(nil);
                    return
                }
                sourceCG = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
                if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                   let orientation = props[kCGImagePropertyOrientation] as? Int32 {
                    exifOrientation = orientation
                }
                print("🖼 [PreviewsManager] loaded non-RAW \(filename)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s")
            }

            guard let cg = sourceCG else {
                completion(nil);
                return
            }
            print("🖼 [PreviewsManager] cg bitsPerComponent=\(cg.bitsPerComponent) bitsPerPixel=\(cg.bitsPerPixel) colorSpace=\(String(describing: cg.colorSpace)) alphaInfo=\(cg.alphaInfo.rawValue)")

            // 2. Apply EXIF orientation
            guard let oriented = cg.applyingOrientation(exifOrientation) else {
                return
            }
            let srcW = CGFloat(oriented.width)
            let srcH = CGFloat(oriented.height)
            print("🖼 [PreviewsManager] source pixels=\(Int(srcW))×\(Int(srcH)) orientation=\(exifOrientation)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s")

            let finalCG: CGImage
            let maxDim = max(srcW, srcH)
            if maxDim <= previewSize {
                finalCG = oriented
                print("🖼 [PreviewsManager] skip resize  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s")
            } else {
                let scale = previewSize / maxDim
                let dstW = Int((srcW * scale).rounded())
                let dstH = Int((srcH * scale).rounded())
                let cs = CGColorSpaceCreateDeviceRGB()
                let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
                guard let ctx = CGContext(data: nil,
                                          width: dstW,
                                          height: dstH,
                                          bitsPerComponent: 8,
                                          bytesPerRow: 0,
                                          space: cs,
                                          bitmapInfo: bitmapInfo) else {
                    completion(nil);
                    return
                }
                ctx.interpolationQuality = .high
                ctx.draw(oriented, in: CGRect(x: 0, y: 0, width: dstW, height: dstH))
                guard let resized = ctx.makeImage() else {
                    completion(nil);
                    return
                }
                finalCG = resized
                print("🖼 [PreviewsManager] resized to \(dstW)×\(dstH)  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s")
            }

            // 3. Encode directly to JPEG via CGImageDestination (no TIFF round-trip)
            let mutable = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(mutable, "public.jpeg" as CFString, 1, nil) else {
                completion(nil);
                return
            }
            CGImageDestinationAddImage(dest, finalCG, [
                kCGImageDestinationLossyCompressionQuality: jpegQuality
            ] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else {
                completion(nil);
                return
            }
            let jpegData = mutable as Data
            print("🖼 [PreviewsManager] JPEG encoded \(filename) \(jpegData.count / 1024)KB  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s")

            // 4. Save to disk
            let subdir = cacheSubdirectory(for: path)
            try? FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
            let diskURL = subdir.appendingPathComponent("\(diskFilename(for: path)).jpg")
            try? jpegData.write(to: diskURL)
            print("🖼 [PreviewsManager] written to disk  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s")

            // 5. Return NSImage
            let result = NSImage(cgImage: finalCG, size: NSSize(width: finalCG.width, height: finalCG.height))
            completion(result)
        }
    }

    // MARK: - Disk I/O

    private func loadFromDisk(for path: String) -> NSImage? {
        let url = diskCacheURL(for: path)
        guard FileManager.default.fileExists(atPath: url.path),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, [
                  kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }

        // Normalize to sRGB — JPEG from disk is YCbCr which NSImage can render black
        let srgb = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
        guard let ctx = CGContext(data: nil,
                                  width: cg.width,
                                  height: cg.height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: srgb,
                                  bitmapInfo: bitmapInfo),
              let normalized = { ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height)); return ctx.makeImage() }()
        else {
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        return NSImage(cgImage: normalized, size: NSSize(width: normalized.width, height: normalized.height))
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
