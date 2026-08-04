//
//  DuplicatesViewModel.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 04.08.2026.
//

import SwiftUI

@MainActor
class DuplicatesFinderViewModel: ObservableObject {

    @Published var cachingQueueCount: Int = 0
    @Published var isFindingDuplicates: Bool = false
    @Published var isDuplicateMode: Bool = false
    @Published var duplicateScanProgress: (done: Int, total: Int) = (0, 0)
    @Published var duplicateScanResult: DuplicateScanResult? = nil
    @Published var similarityMode: DuplicateFinderService.SimilarityMode

    var sortOption: SortOption = .name
    private var findingDuplicatesTask: Task<Void, Never>?
    private var duplicateScanData: DuplicateScanData? = nil

    private let thumbsManager: PhotoCacheManager

    private var photoSortComparator: (PhotoItem, PhotoItem) -> Bool {
        PhotoFilterService.comparator(for: sortOption)
    }

    init(thumbsManager: PhotoCacheManager) {
        self.thumbsManager = thumbsManager
        similarityMode = DuplicateFinderService.SimilarityMode(rawValue: appPrefs.int(.similarityMode)) ?? .loose
    }

    func findDuplicates(in photosToScan: [PhotoItem]) {
        guard !isFindingDuplicates else {
            return
        }
        guard !photosToScan.isEmpty else {
            return
        }
        isFindingDuplicates = true
        duplicateScanProgress = (0, photosToScan.count)

        findingDuplicatesTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else {
                return
            }

            // Ensure all thumbnail are downloaded
            RCLog("Resolving thumbnail URLs...")
            var imageURLs: [Int: URL] = [:]
            var missingUrls: [Int: PhotoItem] = [:]

            // 1. Find the photos that are not cached yet
            for (index, photo) in photosToScan.enumerated() {
                let diskURL = self.thumbsManager.cachedPhotoUrl(for: photo.url)
                if FileManager.default.fileExists(atPath: diskURL.path) {
                    imageURLs[index] = diskURL
                } else {
                    missingUrls[index] = photo
                }
            }

            // 2. Cache the missing photos
            var toComplete = missingUrls.count
            let tc_i = toComplete
            DispatchQueue.main.async {
                self.cachingQueueCount = tc_i
            }
            for (index, photo) in missingUrls {
                // Check before each iteration
                if Task.isCancelled {
                    RCLog("Thumbnail generation cancelled at index \(index)")
                    DispatchQueue.main.async {
                        self.cachingQueueCount = 0
                        self.isFindingDuplicates = false
                        self.isDuplicateMode = false
                    }
                    return
                }
                let diskURL = self.thumbsManager.cachedPhotoUrl(for: photo.url)
                _ = await self.thumbsManager.getImage(for: photo)

                if FileManager.default.fileExists(atPath: diskURL.path) {
                    imageURLs[index] = diskURL
                } else {
                    RCLog("Thumb missing after generation: \(diskURL.lastPathComponent)")
                }
                toComplete -= 1
                let tc_o = toComplete
                DispatchQueue.main.async {
                    self.cachingQueueCount = tc_o
                }
            }

            // 3. Find duplicates
            let data = await DuplicateFinderService.scan(photos: photosToScan,
                                                         cachedImagesURLs: imageURLs,
                                                         progress: { done, total in
                                                            DispatchQueue.main.async {
                                                                self.duplicateScanProgress = (done, total)
                                                            }
                                                         },
                                                         isCancelled: { Task.isCancelled })
            // If data was cancelled, indexes are incomplete and we need to stop the rest of the scan
            if Task.isCancelled {
                RCLog("Duplicate finds were cancelled")
                DispatchQueue.main.async {
                    self.isFindingDuplicates = false
                    self.isDuplicateMode = false
                }
                return
            }
            await MainActor.run {
                self.duplicateScanData = data
                self.isDuplicateMode = true
                self.isFindingDuplicates = false
                if let data {
                    let result = data.recluster(threshold: self.similarityMode.distanceThreshold,
                                                sortBy: self.photoSortComparator)
                    self.duplicateScanResult = result
                    RCLog("Scan complete: \(result.groups.count) group(s) in \(String(format: "%.2f", data.scanDuration))s")
                }
//                self.filterAndSortPhotos()
            }
        }
    }

    func cancelFindingDuplicates() {
        findingDuplicatesTask?.cancel()
        findingDuplicatesTask = nil
    }

    func setSimilarityMode(_ mode: DuplicateFinderService.SimilarityMode) {
        similarityMode = mode
        appPrefs.set(mode.rawValue, forKey: .similarityMode)
        if let data = duplicateScanData {
            duplicateScanResult = data.recluster(threshold: mode.distanceThreshold, sortBy: photoSortComparator)
        }
    }

    func exitDuplicateMode() {
        isDuplicateMode = false
        duplicateScanResult = nil
        duplicateScanData = nil
    }
}
