//
//  DuplicateFinderService.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 09.03.2026.
//

import Foundation
import Vision

struct DuplicateGroup: Identifiable {
    let id = UUID()
    let photos: [PhotoItem]       // all photos in this group, most similar first
    let distance: Float           // max pairwise distance within the group (lower = more similar)
}

struct DuplicateScanResult {
    let groups: [DuplicateGroup]
    let totalScanned: Int
    let duration: TimeInterval
}

enum DuplicateFinderService {

    /// Similarity threshold: 0 = identical, higher = more different.
    /// 0.25 catches near-duplicates (exposure tweaks, slight crops).
    /// Raise to ~0.45 for looser "similar scene" matching.
    static let threshold: Float = 0.35

    // MARK: - Public API

    static func findDuplicates(
        in photos: [PhotoItem],
        progress: @escaping (Int, Int) -> Void   // (done, total)
    ) async -> DuplicateScanResult {
        let start = Date()
        let total = photos.count
        print("🔍 Starting duplicate scan for \(total) photos")
        print("🔍 macOS version: \(ProcessInfo.processInfo.operatingSystemVersionString)")

        // Guard: VNGenerateImageFeaturePrintRequest requires macOS 10.15+
        guard #available(macOS 10.15, *) else {
            print("❌ VNGenerateImageFeaturePrintRequest requires macOS 10.15+")
            return DuplicateScanResult(groups: [], totalScanned: total, duration: 0)
        }

        // Resolve thumbnail URLs on the main actor.
        // For each photo: if the thumb is already on disk, use it directly.
        // If not, generate it now via ThumbsManager (which also caches it for future use).
        print("🔍 Resolving thumbnail URLs...")
        let imageURLs: [Int: URL] = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let group = DispatchGroup()
                var urls: [Int: URL] = [:]
                let lock = NSLock()

                for (index, photo) in photos.enumerated() {
                    let diskURL = ThumbsManager.shared.diskCacheURL(for: photo.path)

                    if FileManager.default.fileExists(atPath: diskURL.path) {
                        // Thumbnail already on disk — use it directly, no I/O needed
                        lock.lock()
                        urls[index] = diskURL
                        lock.unlock()
                        print("  ✅ Cached thumb [\(index+1)/\(total)]: \(diskURL.lastPathComponent)")
                    } else {
                        // Generate the thumbnail now; ThumbsManager caches it to disk automatically
                        print("  ⏳ Generating thumb [\(index+1)/\(total)]: \(URL(fileURLWithPath: photo.path).lastPathComponent)")
                        group.enter()
                        ThumbsManager.shared.loadThumbnail(for: photo.path, priority: .high) { _ in
                            // After generation the file is on disk at diskURL
                            if FileManager.default.fileExists(atPath: diskURL.path) {
                                lock.lock()
                                urls[index] = diskURL
                                lock.unlock()
                            } else {
                                print("  ⚠️ Thumb still missing after generation: \(diskURL.lastPathComponent)")
                            }
                            group.leave()
                        }
                    }
                }

                group.notify(queue: .main) {
                    print("🔍 Thumbnail URLs ready: \(urls.count)/\(total)")
                    continuation.resume(returning: urls)
                }
            }
        }

        // Run Vision serially on a background thread.
        // VNImageRequestHandler.perform is synchronous + CPU-bound; using a plain
        // DispatchQueue avoids cooperative-thread-pool exhaustion.
        let prints: [Int: VNFeaturePrintObservation] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var results: [Int: VNFeaturePrintObservation] = [:]
                let indices = Array(imageURLs.keys).sorted()

                for (i, index) in indices.enumerated() {
                    guard let imageURL = imageURLs[index] else { continue }

                    guard FileManager.default.isReadableFile(atPath: imageURL.path) else {
                        print("  ❌ Not readable: \(imageURL.path)")
                        DispatchQueue.main.async { progress(i + 1, total) }
                        continue
                    }

                    if let observation = featurePrint(at: imageURL) {
                        results[index] = observation
                        print("  ✅ [\(i+1)/\(total)] \(imageURL.lastPathComponent)")
                    } else {
                        print("  ⚠️ [\(i+1)/\(total)] No feature print: \(imageURL.lastPathComponent)")
                    }

                    DispatchQueue.main.async { progress(i + 1, total) }
                }

                print("🔍 Feature prints done: \(results.count)/\(total)")
                continuation.resume(returning: results)
            }
        }

        print("🔍 Clustering \(prints.count) prints...")
        let groups = cluster(photos: photos, prints: prints)

        let duration = Date().timeIntervalSince(start)
        print("🔍 Done in \(String(format: "%.2f", duration))s — \(groups.count) duplicate group(s)")
        return DuplicateScanResult(groups: groups, totalScanned: total, duration: duration)
    }

    // MARK: - Feature Print

    @available(macOS 10.15, *)
    private static func featurePrint(at imageURL: URL) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFit

        // Try loading image data first to catch corrupt/unreadable files early
        guard let data = try? Data(contentsOf: imageURL), !data.isEmpty else {
            print("  ❌ Could not read data from \(imageURL.lastPathComponent)")
            return nil
        }

        do {
            let handler = VNImageRequestHandler(data: data, options: [:])
            try handler.perform([request])
            guard let result = request.results?.first else {
                print("  ❌ Vision returned empty results for \(imageURL.lastPathComponent)")
                return nil
            }
            return result
        } catch let error as NSError {
            print("  ❌ Vision failed for \(imageURL.lastPathComponent): [\(error.domain) \(error.code)] \(error.localizedDescription)")
            if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error {
                print("     Underlying: \(underlying)")
            }
            return nil
        }
    }

    // MARK: - Clustering

    @available(macOS 10.15, *)
    private static func cluster(
        photos: [PhotoItem],
        prints: [Int: VNFeaturePrintObservation]
    ) -> [DuplicateGroup] {

        guard !prints.isEmpty else {
            print("🔍 No prints to cluster")
            return []
        }

        let indices = Array(prints.keys).sorted()
        var assigned = Set<Int>()
        var groups: [DuplicateGroup] = []

        for i in indices {
            guard !assigned.contains(i), let pi = prints[i] else { continue }

            var groupIndices: [Int] = [i]
            var maxDist: Float = 0

            for j in indices where j > i {
                guard !assigned.contains(j), let pj = prints[j] else { continue }
                var distance: Float = 0
                do {
                    try pi.computeDistance(&distance, to: pj)
                    if distance <= threshold {
                        groupIndices.append(j)
                        maxDist = max(maxDist, distance)
                    }
                } catch {
                    print("  ⚠️ computeDistance(\(i),\(j)) failed: \(error)")
                }
            }

            if groupIndices.count > 1 {
                let groupPhotos = groupIndices.map { photos[$0] }
                groups.append(DuplicateGroup(photos: groupPhotos, distance: maxDist))
                assigned.formUnion(groupIndices)
            }
        }

        return groups.sorted {
            $0.photos.count != $1.photos.count
                ? $0.photos.count > $1.photos.count
                : $0.distance < $1.distance
        }
    }
}
