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

    /// Per-album ThumbsManager — created fresh for each folder, so memory cache is scoped to the album.
    let thumbsManager = ThumbsManager()

    private let folder: FolderItem
    private var metadataTask: Task<Void, Never>?

    init(folder: FolderItem) {
        self.folder = folder
        ThumbsManager.current = thumbsManager
    }

    deinit {
        metadataTask?.cancel()
        thumbsManager.stopQueue()
        print("🗑️ PhotosModel deallocated for: \(folder.url.lastPathComponent)")
    }

    /// Load photos for the folder - call this when the model is created
    func loadPhotos() {
        // PhotoKit path
        if folder.url.isPhotoKitAlbum || folder.url.isPhotoLibraryRoot {
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
                guard !Task.isCancelled else {
                    return
                }
                self.photos = basicItems

                // Step 2 — slower: enrich with real filenames in background batches
                let batchSize = 200
                var enriched = basicItems
                let total = enriched.count
                var idx = 0
                while idx < total {
                    guard !Task.isCancelled else {
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
                self.isLoadingMetadata = false
            }
            return
        }
        // File-based path
        let basicPhotos = Self.loadPhotosBasic(in: folder)
        photos = basicPhotos

        print("📸 Loaded \(basicPhotos.count) photos (basic info) for: \(folder.url.lastPathComponent)")

        // Load metadata asynchronously
        isLoadingMetadata = true
        let folderName = folder.url.lastPathComponent

        metadataTask = Task {
            print("🔄 Starting metadata loading for: \(folderName)")

            var currentPhotos = basicPhotos
            let batchCallback: @Sendable ([PhotoItem]) async -> Void = { [weak self] batch in
                guard let self else { return }
                await MainActor.run {
                    self.photos = batch
                }
            }

            let photosWithMetadata = await Self.loadPhotosMetadataAsync(
                in: folder,
                photos: basicPhotos,
                onBatch: batchCallback
            )

            guard !Task.isCancelled else {
                print("⚠️ Metadata loading cancelled for: \(folderName)")
                await MainActor.run { self.isLoadingMetadata = false }
                return
            }

            await MainActor.run {
                print("✅ Metadata loading completed for: \(folderName)")
                self.photos = photosWithMetadata
                self.isLoadingMetadata = false
            }
        }
    }

    func reloadPhotos() {
        metadataTask?.cancel()
        ThumbsManager.current?.stopQueue()
        loadPhotos()
    }

    // MARK: - Static Photo Loading Methods

    /// Load a specific list of file URLs as PhotoItems (used for search results).
    /// Returns basic info immediately, then enriches with metadata.
    static func loadPhotos(for urls: [URL]) async -> [PhotoItem] {
        let fm = FileManager.default

        // Build basic PhotoItems first
        var basicPhotos: [PhotoItem] = urls.map { url in
            let date = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
            return PhotoItem(path: url.path, xmp: nil, dateCreated: date, hasACR: false, hasJPG: false, inCameraRating: nil)
        }

        // Enrich with metadata in parallel
        return await withTaskGroup(of: (Int, XmpMetadata?, Int?, Bool, Int64?, Int?, Int?, String?, String?).self, returning: [PhotoItem].self) { group in
            for (index, photo) in basicPhotos.enumerated() {
                group.addTask {
                    let url = URL(fileURLWithPath: photo.path)
                    let ext = url.pathExtension.lowercased()
                    let isRaw = FilesExtensions.raw.contains(ext)

                    // Try XMP sidecar
                    let xmpURL = url.deletingPathExtension().appendingPathExtension("xmp")
                    let xmp: XmpMetadata? = (try? String(contentsOf: xmpURL, encoding: .utf8)).flatMap {
                        XmpParser.parseMetadata(from: $0)
                    }

                    let fileSize: Int64? = (try? fm.attributesOfItem(atPath: photo.path))?[.size] as? Int64
                    var inCameraRating: Int? = nil
                    var width: Int? = nil
                    var height: Int? = nil
                    var cameraMake: String? = nil
                    var cameraModel: String? = nil

                    if let metadata = RawWrapper.shared().extractMetadata(photo.path) {
                        inCameraRating = (metadata["rating"] as? NSNumber)?.intValue
                        width = (metadata["width"] as? NSNumber)?.intValue
                        height = (metadata["height"] as? NSNumber)?.intValue
                        cameraMake = metadata["cameraMake"] as? String
                        cameraModel = metadata["cameraModel"] as? String
                    }

                    return (index, xmp, inCameraRating, isRaw, fileSize, width, height, cameraMake, cameraModel)
                }
            }

            for await (index, xmp, rating, isRaw, fileSize, width, height, cameraMake, cameraModel) in group {
                basicPhotos[index] = PhotoItem(
                    id: basicPhotos[index].id,
                    path: basicPhotos[index].path,
                    xmp: xmp,
                    dateCreated: basicPhotos[index].dateCreated,
                    toDelete: basicPhotos[index].toDelete,
                    hasACR: basicPhotos[index].hasACR,
                    hasJPG: basicPhotos[index].hasJPG,
                    inCameraRating: rating,
                    isRawFile: isRaw,
                    fileSizeBytes: fileSize,
                    width: width,
                    height: height,
                    cameraMake: cameraMake,
                    cameraModel: cameraModel
                )
            }
            return basicPhotos
        }
    }

    private static func loadPhotosBasic(in folder: FolderItem) -> [PhotoItem] {
        let fm = FileManager.default
        let allowed = FilesExtensions.all

        let files = (try? fm.contentsOfDirectory(
            at: folder.url,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        // Create a set of base filenames that have RAW versions
        let rawBaseNames = Set(files
            .filter { FilesExtensions.raw.contains($0.pathExtension.lowercased()) }
            .map { $0.deletingPathExtension().lastPathComponent })

        // Separate image files from XMP and ACR files, filtering out JPGs with RAW counterparts
        let imageFiles = files.filter { file in
            let ext = file.pathExtension.lowercased()
            guard allowed.contains(ext) else { return false }

            // If it's a JPG and a RAW version exists, skip it
            if ["jpg", "jpeg"].contains(ext) {
                let baseName = file.deletingPathExtension().lastPathComponent
                return !rawBaseNames.contains(baseName)
            }

            return true
        }
        let acrFiles = files.filter { $0.pathExtension.lowercased() == "acr" }
        let jpgFiles = files.filter { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }

        var acrLookup: Set<String> = Set()
        for acrFile in acrFiles {
            let baseName = acrFile.deletingPathExtension().lastPathComponent
            acrLookup.insert(baseName)
        }

        var jpgLookup: Set<String> = Set()
        for jpgFile in jpgFiles {
            let baseName = jpgFile.deletingPathExtension().lastPathComponent
            jpgLookup.insert(baseName)
        }

        // Create PhotoItems with basic info only - no XMP or rating yet
        let startTime = Date()
        let result = imageFiles
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { imageFile in
                let baseName = imageFile.deletingPathExtension().lastPathComponent

                // Get creation date from the file attributes we already retrieved
                let creationDate = (try? imageFile.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()

                // Check for ACR file
                let hasACR = acrLookup.contains(baseName)

                // Check for JPG file
                let hasJPG = jpgLookup.contains(baseName)

                return PhotoItem(path: imageFile.path, xmp: nil, dateCreated: creationDate, hasACR: hasACR, hasJPG: hasJPG, inCameraRating: nil)
            }

        let totalTime = Date().timeIntervalSince(startTime)
        print("📊 loadPhotos (basic) Performance:")
        print("   Total files: \(imageFiles.count)")
        print("   Total time: \(String(format: "%.3f", totalTime))s")

        return result
    }

    private static func loadPhotosMetadataAsync(
        in folder: FolderItem,
        photos: [PhotoItem],
        onBatch: (@Sendable ([PhotoItem]) async -> Void)? = nil
    ) async -> [PhotoItem] {
        let fm = FileManager.default

        let files = (try? fm.contentsOfDirectory(
            at: folder.url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        // Build XMP lookup off main thread
        let xmpLookup: [String: String] = await Task.detached(priority: .utility) {
            var lookup: [String: String] = [:]
            for xmpFile in files where xmpFile.pathExtension.lowercased() == "xmp" {
                let baseName = xmpFile.deletingPathExtension().lastPathComponent
                if let content = try? String(contentsOf: xmpFile, encoding: .utf8) {
                    lookup[baseName] = content
                }
            }
            return lookup
        }.value

        // Parse XMP off main thread
        let xmpParsed: [String: XmpMetadata] = await Task.detached(priority: .utility) {
            var parsed: [String: XmpMetadata] = [:]
            for (baseName, content) in xmpLookup {
                parsed[baseName] = XmpParser.parseMetadata(from: content)
            }
            return parsed
        }.value

        // File sizes off main thread
        let fileSizes: [String: Int64] = await Task.detached(priority: .utility) {
            var sizes: [String: Int64] = [:]
            for photo in photos {
                sizes[photo.path] = (try? fm.attributesOfItem(atPath: photo.path))?[.size] as? Int64
            }
            return sizes
        }.value

        let startTime = Date()

        // Extract RAW metadata in batches on main actor, yielding between batches
        // so thumbnails and previews can load concurrently
        let batchSize = 20
        var updatedPhotos = photos

        for batchStart in stride(from: 0, to: photos.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, photos.count)
            let batch = Array(photos[batchStart..<batchEnd])

            // Process one batch off the main thread — extractMetadata is thread-safe
            let batchResults: [(Int, Int?, Int?, Int?, String?, String?)] = await Task.detached(priority: .utility) {
                batch.enumerated().map { (localIndex, photo) in
                    let globalIndex = batchStart + localIndex
                    var inCameraRating: Int? = nil
                    var width: Int? = nil
                    var height: Int? = nil
                    var cameraMake: String? = nil
                    var cameraModel: String? = nil
                    if let metadata = RawWrapper.shared().extractMetadata(photo.path) {
                        inCameraRating = (metadata["rating"] as? NSNumber)?.intValue
                        width = (metadata["width"] as? NSNumber)?.intValue
                        height = (metadata["height"] as? NSNumber)?.intValue
                        cameraMake = metadata["cameraMake"] as? String
                        cameraModel = metadata["cameraModel"] as? String
                    }
                    return (globalIndex, inCameraRating, width, height, cameraMake, cameraModel)
                }
            }.value

            for (index, rating, width, height, cameraMake, cameraModel) in batchResults {
                let photo = photos[index]
                let url = URL(fileURLWithPath: photo.path)
                let baseName = url.deletingPathExtension().lastPathComponent
                let fileExtension = url.pathExtension.lowercased()
                updatedPhotos[index] = PhotoItem(
                    id: photo.id,
                    path: photo.path,
                    xmp: xmpParsed[baseName],
                    dateCreated: photo.dateCreated,
                    toDelete: photo.toDelete,
                    hasACR: photo.hasACR,
                    hasJPG: photo.hasJPG,
                    inCameraRating: rating,
                    isRawFile: FilesExtensions.raw.contains(fileExtension),
                    fileSizeBytes: fileSizes[photo.path],
                    width: width,
                    height: height,
                    cameraMake: cameraMake,
                    cameraModel: cameraModel
                )
            }

            // Publish partial results so thumbs/preview update progressively
            if let onBatch {
                await onBatch(updatedPhotos)
            }

            // Yield to let other tasks (thumb generation, preview loading) run
            await Task.yield()
        }

        let totalTime = Date().timeIntervalSince(startTime)
        print("📊 loadPhotosMetadataAsync Performance:")
        print("   Total files: \(photos.count)")
        print("   Total time: \(String(format: "%.3f", totalTime))s")

        return updatedPhotos
    }
}
