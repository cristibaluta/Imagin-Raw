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
    static let threshold: Float = 0.25

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

        // Pre-extract embedded JPEGs for RAW files.
        // Must happen on the main actor because RawWrapper.shared() is @MainActor-isolated.
        // We use a continuation instead of await MainActor.run to avoid re-entrant
        // deadlock when findDuplicates is called from @MainActor code (e.g. ThumbGridViewModel).
        print("🔍 Pre-extracting embedded JPEGs...")
        let imageURLs: [Int: URL] = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                var urls: [Int: URL] = [:]
                for (index, photo) in photos.enumerated() {
                    let url = URL(fileURLWithPath: photo.path)
                    let ext = url.pathExtension.lowercased()
                    if FilesExtensions.raw.contains(ext) {
                        if let jpegData = RawWrapper.shared().extractEmbeddedJPEG(photo.path),
                           let tempURL = writeTempJPEG(jpegData, name: "\(index)_\(url.deletingPathExtension().lastPathComponent)") {
                            urls[index] = tempURL
                        } else {
                            print("  ⚠️ JPEG extraction failed for \(url.lastPathComponent), falling back to RAW")
                            urls[index] = url
                        }
                    } else {
                        urls[index] = url
                    }
                }
                continuation.resume(returning: urls)
            }
        }
        print("🔍 Image URLs ready (\(imageURLs.count)/\(total))")

        // Run entirely serial and detached — no TaskGroup, no thread pool exhaustion.
        // Progress is reported via DispatchQueue.main.async (fire-and-forget) to avoid
        // any await inside the detached task which could re-enter the main actor.
        let prints: [Int: VNFeaturePrintObservation] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var results: [Int: VNFeaturePrintObservation] = [:]
                let indices = Array(imageURLs.keys).sorted()

                for (i, index) in indices.enumerated() {
                    guard let imageURL = imageURLs[index] else { continue }
                    let filename = imageURL.lastPathComponent

                    guard FileManager.default.fileExists(atPath: imageURL.path) else {
                        print("  ❌ File not found: \(imageURL.path)")
                        DispatchQueue.main.async { progress(i + 1, total) }
                        continue
                    }
                    guard FileManager.default.isReadableFile(atPath: imageURL.path) else {
                        print("  ❌ File not readable: \(imageURL.path)")
                        DispatchQueue.main.async { progress(i + 1, total) }
                        continue
                    }

                    if let observation = featurePrint(at: imageURL) {
                        results[index] = observation
                        print("  ✅ [\(i+1)/\(total)] \(filename)")
                    } else {
                        print("  ⚠️ [\(i+1)/\(total)] No feature print: \(filename)")
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
        request.imageCropAndScaleOption = .scaleFill

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

    // MARK: - Temp JPEG

    private static func writeTempJPEG(_ data: Data, name: String) -> URL? {
        let safe = name.replacingOccurrences(of: "/", with: "_")
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("imagin_fp_\(safe).jpg")
        do {
            try data.write(to: tmp, options: .atomic)
            return tmp
        } catch {
            print("  ❌ Failed to write temp JPEG '\(name)': \(error)")
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
