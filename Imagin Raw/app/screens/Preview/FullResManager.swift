//
//  FullResManager.swift
//  Imagin Raw
//
//  Memory-only cache + serial queue for full-resolution image loading.
//  All decode work is delegated to the photo's PhotoSource implementation.
//

import Foundation

class FullResManager {
    static let shared = FullResManager()

    private let cacheLimit = 5
    private var cache: [String: IRImage] = [:]
    private var cacheOrder: [String] = []

    /// Serial queue — one full-res decode at a time so we never thrash memory/CPU.
    private let decodeQueue = DispatchQueue(label: "ro.imagin.fullres", qos: .userInitiated)
    private let lock = NSLock()
    /// In-flight keys — prevents duplicate requests for the same photo.
    private var inFlight: Set<String> = []

    private init() {}

    // MARK: - Public

    func cachedImage(for photo: PhotoItem) -> IRImage? {
        let key = photo.makeSource().cacheKey
        lock.lock()
        defer { lock.unlock() }
        return cache[key]
    }

    func loadFullRes(for photo: PhotoItem, completion: @escaping (IRImage?) -> Void) {
        let source = photo.makeSource()
        let key = source.cacheKey

        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            DispatchQueue.main.async { completion(cached) }
            return
        }
        if inFlight.contains(key) {
            lock.unlock()
            // Poll until the in-flight request finishes
            waitForInFlight(key: key, completion: completion)
            return
        }
        inFlight.insert(key)
        lock.unlock()

        decodeQueue.async { [weak self] in
            source.loadFullRes { [weak self] image in
                guard let self else { return }
                self.lock.lock()
                self.inFlight.remove(key)
                if let image {
                    self.store(image, for: key)
                }
                self.lock.unlock()
                DispatchQueue.main.async { completion(image) }
            }
        }
    }

    func evict(for photo: PhotoItem) {
        let key = photo.makeSource().cacheKey
        lock.lock()
        defer { lock.unlock() }
        cache.removeValue(forKey: key)
        cacheOrder.removeAll { $0 == key }
    }

    // MARK: - Private

    private func store(_ image: IRImage, for key: String) {
        if cache[key] != nil {
            cacheOrder.removeAll { $0 == key }
            cacheOrder.append(key)
            return
        }
        while cache.count >= cacheLimit, let oldest = cacheOrder.first {
            cache.removeValue(forKey: oldest)
            cacheOrder.removeFirst()
        }
        cache[key] = image
        cacheOrder.append(key)
    }

    private func waitForInFlight(key: String, completion: @escaping (IRImage?) -> Void) {
        decodeQueue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let image = self.cache[key]
            self.lock.unlock()
            DispatchQueue.main.async { completion(image) }
        }
    }
}
