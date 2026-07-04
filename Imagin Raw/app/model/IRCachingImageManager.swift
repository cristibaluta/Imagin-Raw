//
//  PhotoIdentifiable.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 04.07.2026.
//

import Foundation

/// Adapts the async `PhotoCacheManager` to a PHCachingImageManager-style,
/// block-based API suitable for driving a UICollectionView with prefetching.
final class IRCachingImageManager: @unchecked Sendable {

    private let cacheManager: PhotoCacheManager
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private let lock = NSLock()

    init(cacheManager: PhotoCacheManager) {
        self.cacheManager = cacheManager
    }

    /// Requests the image for a photo, calling `completion` on the main thread.
    /// Mirrors PHImageManager.requestImage(for:...completion:).
    @discardableResult
    func requestImage(for photo: PhotoItem, completion: @escaping (IRImage?) -> Void) -> UUID {
        let id = photo.id
        let cacheManager = self.cacheManager

        // Cancel any previous in-flight request for this id, synchronously,
        // before starting the new one. No race: we're already on the main actor.
        lock.withLock {
            tasks[id]?.cancel()
        }

        let workTask = Task {
            let image = await cacheManager.getImage(for: photo)
            guard !Task.isCancelled else {
                return
            }
            DispatchQueue.main.async {
                completion(image)
            }
            _ = self.lock.withLock {
                self.tasks.removeValue(forKey: id)
            }
        }

        lock.withLock {
            tasks[id] = workTask
        }

        return id
    }

    /// Cancels a single in-flight request. Mirrors PHImageManager.cancelImageRequest(_:).
    func cancelRequest(for photo: PhotoItem) {
        let task = lock.withLock {
            tasks.removeValue(forKey: photo.id)
        }
        task?.cancel()
    }

    /// Starts caching images for the given photos ahead of time.
    /// Mirrors PHCachingImageManager.startCachingImages(for:...).
    func startCachingImages(for photos: [PhotoItem]) {
        let cacheManager = self.cacheManager
        for photo in photos {
            let id = photo.id

            let alreadyRunning = lock.withLock {
                tasks[id] != nil
            }

            // Don't restart if already in flight (from a previous prefetch or a cell request).
            guard !alreadyRunning else {
                continue
            }

            let workTask = Task { [weak self] in

                _ = await cacheManager.getImage(for: photo)

                guard let self, !Task.isCancelled else {
                    return
                }
                // Only clear if this task is still the one registered for id.
                _ = self.lock.withLock {
                    self.tasks.removeValue(forKey: id)
                }
            }

            lock.withLock {
                tasks[id] = workTask
            }
        }
    }

    /// Stops caching (cancels) images for the given photos.
    /// Mirrors PHCachingImageManager.stopCachingImages(for:...).
    func stopCachingImages(for photos: [PhotoItem]) {
        let tasksToCancel = lock.withLock {
            photos.compactMap { tasks.removeValue(forKey: $0.id) }
        }
        tasksToCancel.forEach { $0.cancel() }
    }

    func stopCachingImagesForAllAssets() {
        lock.lock()
        let all = tasks
        tasks.removeAll()
        lock.unlock()
        all.values.forEach { $0.cancel() }
    }
}
