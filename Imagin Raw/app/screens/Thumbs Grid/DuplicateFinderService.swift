//
//  DuplicateFinderService.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 09.03.2026.
//

import Foundation
import Vision

struct DuplicateGroup: Identifiable, Sendable {
    let id = UUID()
    let photos: [PhotoItem]
    let distance: Float
}

struct DuplicateScanResult: Sendable {
    let groups: [DuplicateGroup]
    let totalScanned: Int
    let duration: TimeInterval
}

/// All pairwise distances computed in a single scan pass.
/// Re-clustering from this is O(n²) float comparisons — no Vision re-run needed.
struct DuplicateScanData: Sendable {
    let photos: [PhotoItem]
    /// distances[i][j] where j > i — upper-triangle only
    let distances: [[Float]]
    let scanDuration: TimeInterval

    func recluster(threshold: Float, sortBy: ((PhotoItem, PhotoItem) -> Bool)? = nil) -> DuplicateScanResult {
        let start = Date()
        let indices = photos.indices
        var assigned = Set<Int>()
        var groups: [DuplicateGroup] = []

        for i in indices {
            guard !assigned.contains(i) else { continue }
            var groupIndices: [Int] = [i]
            var maxDist: Float = 0

            for j in indices where j > i {
                guard !assigned.contains(j) else { continue }
                let dist = distances[i][j - i - 1]
                if dist <= threshold {
                    groupIndices.append(j)
                    maxDist = max(maxDist, dist)
                }
            }

            if groupIndices.count > 1 {
                var groupPhotos = groupIndices.map { photos[$0] }
                if let sortBy { groupPhotos.sort(by: sortBy) }
                groups.append(DuplicateGroup(photos: groupPhotos, distance: maxDist))
                assigned.formUnion(groupIndices)
            }
        }

        let sorted: [DuplicateGroup]
        if let sortBy {
            sorted = groups.sorted { a, b in
                guard let firstA = a.photos.first, let firstB = b.photos.first else { return false }
                return sortBy(firstA, firstB)
            }
        } else {
            sorted = groups.sorted {
                $0.photos.count != $1.photos.count ? $0.photos.count > $1.photos.count : $0.distance < $1.distance
            }
        }
        return DuplicateScanResult(groups: sorted, totalScanned: photos.count, duration: Date().timeIntervalSince(start))
    }
}

enum DuplicateFinderService {

    /// Predefined similarity thresholds (distance = 1 - similarity).
    enum SimilarityMode: Int, CaseIterable {
        case veryLoose = 50   // distance ≤ 0.50
        case loose     = 65   // distance ≤ 0.35
        case medium    = 75   // distance ≤ 0.25
        case strict    = 90   // distance ≤ 0.10

        var label: String { "\(rawValue)%" }

        var distanceThreshold: Float {
            1.0 - Float(rawValue) / 100.0
        }
    }

    /// Loosest threshold — always scan at this so we can re-cluster without re-scanning.
    private static let scanThreshold: Float = SimilarityMode.veryLoose.distanceThreshold

    /// Runs Vision feature prints + pairwise distances once.
    /// Call `DuplicateScanData.recluster(threshold:)` to filter without re-scanning.
    static func scan(photos: [PhotoItem],
                     cachedImagesURLs: [Int: URL],
                     progress: @Sendable @escaping (Int, Int) -> Void,
                     isCancelled: () -> Bool) async -> DuplicateScanData? {

        let total = photos.count
        RCLog("🔍 Starting duplicate scan for \(total) photos (threshold ≤ \(scanThreshold))")

        guard #available(macOS 10.15, *) else {
            RCLog("❌ VNGenerateImageFeaturePrintRequest requires macOS 10.15+")
            return nil
        }

        let start = Date()

        var prints: [Int: VNFeaturePrintObservation] = [:]
        let indices = Array(cachedImagesURLs.keys).sorted()

        for (i, index) in indices.enumerated() {
            if isCancelled() {
                break
            }
            guard let imageURL = cachedImagesURLs[index],
                  FileManager.default.isReadableFile(atPath: imageURL.path) else {
                DispatchQueue.main.async {
                    progress(i + 1, total)
                }
                continue
            }
            if let obs = featurePrint(at: imageURL) {
                prints[index] = obs
            }
            DispatchQueue.main.async {
                progress(i + 1, total)
            }
        }

        // Compute upper-triangle pairwise distances (O(n²) float ops, very fast)
        let sortedIndices = Array(prints.keys).sorted()
        let n = sortedIndices.count
        // distances[i] holds distances from sortedIndices[i] to sortedIndices[i+1...n-1]
        var distanceMatrix: [[Float]] = Array(repeating: [], count: n)

        for i in 0..<n {
            if isCancelled() {
                break
            }
            guard let pi = prints[sortedIndices[i]] else {
                distanceMatrix[i] = Array(repeating: Float.greatestFiniteMagnitude, count: n - i - 1)
                continue
            }
            var row: [Float] = []
            for j in (i+1)..<n {
                guard let pj = prints[sortedIndices[j]] else {
                    row.append(Float.greatestFiniteMagnitude)
                    continue
                }
                var dist: Float = 0
                try? pi.computeDistance(&dist, to: pj)
                row.append(dist)
            }
            distanceMatrix[i] = row
        }

        // Map back from sorted feature-print indices to original photo indices
        // (sortedIndices[i] is the photo index in the original array)
        let photosInOrder = sortedIndices.map { photos[$0] }

        let scanDuration = Date().timeIntervalSince(start)
        RCLog("🔍 Scan done in \(String(format: "%.2f", scanDuration))s")
        return DuplicateScanData(photos: photosInOrder, distances: distanceMatrix, scanDuration: scanDuration)
    }

    // MARK: - Feature Print

    @available(macOS 10.15, *)
    private static func featurePrint(at imageURL: URL) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFill
        guard let data = try? Data(contentsOf: imageURL), !data.isEmpty else {
            RCLog("  ❌ Could not read data from \(imageURL.lastPathComponent)")
            return nil
        }
        do {
            let handler = VNImageRequestHandler(data: data, options: [:])
            try handler.perform([request])
            return request.results?.first
        } catch let error as NSError {
            RCLog("  ❌ Vision failed for \(imageURL.lastPathComponent): [\(error.domain) \(error.code)] \(error.localizedDescription)")
            return nil
        }
    }
}
