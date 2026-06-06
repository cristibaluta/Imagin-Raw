//
//  PhotosModel.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 20.02.2026.
//

import Foundation
import SwiftUI
import Photos

/// Model responsible for loading and managing photos for a specific folder
/// Each folder gets its own PhotosModel instance, ensuring clean state separation
@MainActor
final class PhotosModel: ObservableObject {
    @Published var photos: [PhotoItem] = []
    @Published var isLoadingMetadata: Bool = false

    private let folder: FolderItem
    private var metadataTask: Task<Void, Never>?
    let queue = OperationQueue()
    let queueLock = NSLock()

    init(folder: FolderItem) {
        self.folder = folder
    }

    deinit {
        metadataTask?.cancel()
        queue.cancelAllOperations()
        RCLog("🗑️ PhotosModel deallocated for: \(folder.url.lastPathComponent)")
    }

    func loadPhotos() {
        if folder.url.isPhotoKitAlbum || folder.url.isPhotoLibraryRoot {
            loadPhotoKitPhotos()
        } else {
            loadLocalPhotos()
            loadLocalExifs()
        }
    }

    private func loadPhotoKitPhotos() {
        isLoadingMetadata = true
        metadataTask = Task {
            // Step 1 — fast: load basic items (no PHAssetResource lookup)
            let basicItems = await Task.detached(priority: .userInitiated) { [folder] in
                if folder.url.isPhotoLibraryRoot {
                    return PhotoKitSource.loadAllPhotos(basic: true)
                } else {
                    return PhotoKitSource.loadPhotos(
                        albumIdentifier: folder.url.photoKitAlbumIdentifier ?? "",
                        basic: true)
                }
            }.value

            if Task.isCancelled {
                return
            }

            self.photos = basicItems

            // Step 2 — slower: enrich with real filenames in background batches
            let batchSize = 200
            var enriched = basicItems
            let total = enriched.count
            var idx = 0
            while idx < total {
                if Task.isCancelled {
                    break
                }
                let end = min(idx + batchSize, total)
                let slice = Array(enriched[idx..<end])
                let filled = await Task.detached(priority: .utility) {
                    slice.map { item -> PhotoItem in
                        guard let asset = item.phAsset else {
                            return item
                        }
                        let resources = PHAssetResource.assetResources(for: asset)
                        let primary = resources.first(where: {
                            $0.type == .photo || $0.type == .video || $0.type == .fullSizePhoto
                        }) ?? resources.first
                        guard let filename = primary?.originalFilename else {
                            return item
                        }
                        return item.withFilename(filename)
                    }
                }.value
                enriched.replaceSubrange(idx..<end, with: filled)
                self.photos = enriched
                idx = end
            }
            isLoadingMetadata = false
        }
    }

    private func loadLocalPhotos() {
        RCLog("Load photos (basic info) for: \(folder.url.lastPathComponent)")
        let fm = FileManager.default

        let files = (try? fm.contentsOfDirectory(
            at: folder.url,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        // Analyze the files and split by category
        var images: [URL] = []
        var acrLookup: Set<String> = Set()
        var jpgLookup: Set<String> = Set()
        var xmpLookup: Set<String> = Set()

        let rawBaseNames = Set(
            files
                .filter { FilesExtensions.raw.contains($0.pathExtension.lowercased()) }
                .map { $0.deletingPathExtension().lastPathComponent }
        )

        for file in files {
            let ext = file.pathExtension.lowercased()
            if FilesExtensions.all.contains(ext) {
                if FilesExtensions.jpg.contains(ext) {
                    if rawBaseNames.contains(file.deletingPathExtension().lastPathComponent) {
                        jpgLookup.insert(file.lastPathComponent)
                    } else {
                        images.append(file)
                    }
                } else {
                    images.append(file)
                }
            } else if ext == "xmp" {
                xmpLookup.insert(file.deletingPathExtension().lastPathComponent)
            } else if ext == "acr" {
                acrLookup.insert(file.deletingPathExtension().lastPathComponent)
            }
        }

        // Create PhotoItems with basic info only - no XMP or rating yet
        let basicPhotos = images
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { imageFile in
                let baseName = imageFile.deletingPathExtension().lastPathComponent
                let fileExtension = imageFile.pathExtension.lowercased()
                let resValues = try? imageFile.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey])
                let creationDate = resValues?.creationDate ?? Date()
                let modifiedDate = resValues?.contentModificationDate
                let size = resValues?.fileSize as? Int64
                let isRaw = FilesExtensions.raw.contains(fileExtension)

                let hasACR = acrLookup.contains(baseName)
                let hasJPG = jpgLookup.contains(baseName)
                let hasXMP = xmpLookup.contains(baseName)

                return PhotoItem(url: imageFile,
                                 path: imageFile.path,
                                 dateCreated: creationDate,
                                 dateModified: modifiedDate,
                                 hasACR: hasACR,
                                 hasJPG: hasJPG,
                                 hasXMP: hasXMP,
                                 isRawFile: isRaw,
                                 fileSizeBytes: size)
            }

        self.photos = basicPhotos
    }

    private func loadLocalExifs() {
        let startTime = Date()
        isLoadingMetadata = true

        queue.maxConcurrentOperationCount = ProcessInfo.processInfo.activeProcessorCount
        queue.qualityOfService = .utility
        RCLog("start loading exif using \(queue.maxConcurrentOperationCount) threads")

        var photosWithExifs: [PhotoItem] = []

        for photo in photos {
            let op = LoadExifOperation(photo: photo) { [weak self] photoWithExif in
                self?.queueLock.withLock {
                    photosWithExifs.append(photoWithExif)
                }
            }
            queue.addOperation(op)
        }
        queue.addBarrierBlock {
            DispatchQueue.main.async {
                RCLog("loaded Exifs in \(String(format: "%.3f", Date().timeIntervalSince(startTime)))s")
                self.photos = photosWithExifs
                self.isLoadingMetadata = false
            }
        }
    }

    func reloadPhotos() {
        metadataTask?.cancel()
        loadPhotos()
    }

    /// Re-reads XMP for a single photo (identified by its sidecar URL) and updates it in-place,
    /// preserving the PhotoItem UUID so the grid only redraws that one cell.
    func reloadMetadata(forSidecar sidecarURL: URL, completion: @escaping (() -> Void)) {
        let baseName = sidecarURL.deletingPathExtension().lastPathComponent

        // Find the matching photo by base filename (strip extension from both)
        guard let idx = photos.firstIndex(where: {
            URL(fileURLWithPath: $0.path).deletingPathExtension().lastPathComponent == baseName
        }) else {
            RCLog("⚠️ reloadMetadata: no photo found for sidecar \(baseName)")
            return
        }

        let photo = photos[idx]

        let op = LoadExifOperation(photo: photo, forceReloadExif: true) { [weak self] photoWithExif in
            self?.queueLock.withLock {
                RCLog("🔄 reloadMetadata: updating photo at idx \(idx) for sidecar \(baseName)")
                self?.photos[idx] = photoWithExif
                completion()
            }
        }
        queue.addOperation(op)
    }
}
