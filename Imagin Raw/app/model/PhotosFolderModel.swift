//
//  PhotoFolderModel.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 10.06.2026.
//

import SwiftUI
import Combine

@MainActor
final class PhotosFolderModel: ObservableObject {
    let isLoadingSubject = CurrentValueSubject<Bool, Never>(false)
    var photos: Binding<[PhotoItem]>!
    private var isLoadingMetadata: Bool = false {
        didSet {
            isLoadingSubject.send(isLoadingMetadata)
        }
    }

    private let folder: FolderItem
    private let queue = OperationQueue()
    private let includeSubfolders: Bool

    init(folder: FolderItem, includeSubfolders: Bool) {
        self.folder = folder
        self.includeSubfolders = includeSubfolders
    }

    deinit {
        queue.cancelAllOperations()
        RCLog("🗑️ PhotosModel deallocated for: \(folder.url.lastPathComponent)")
    }

    func loadPhotos() {
        RCLog("Load photos (basic info) for: \(folder.url.lastPathComponent)")
        let fm = FileManager.default

        // Collect the folders to scan: the main folder, plus first-level
        // subfolders when includeSubfolders is true.
        var foldersToScan: [URL] = [folder.url]

        if includeSubfolders {
            let subfolders = (try? fm.contentsOfDirectory(
                at: folder.url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            let subDirectories = subfolders.filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            }
            foldersToScan.append(contentsOf: subDirectories)
        }

        // Analyze the files and split by category, across all scanned folders.
        var images: [URL] = []
        var acrLookup: Set<String> = Set()
        var jpgLookup: Set<String> = Set()
        var xmpLookup: Set<String> = Set()

        for folderURL in foldersToScan {
            let files = (try? fm.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            let rawBaseNames = Set(
                files
                    .filter { FilesExtensions.isRawImageFile($0) }
                    .map { $0.deletingPathExtension().lastPathComponent }
            )

            for file in files {
                let ext = file.pathExtension.lowercased()
                let baseName = file.deletingPathExtension().lastPathComponent
                if FilesExtensions.isImageFile(file) || FilesExtensions.isMovieFile(file) {
                    if FilesExtensions.isRawCounterpartFile(file) {
                        if rawBaseNames.contains(baseName) {
                            jpgLookup.insert(baseName)
                        } else {
                            images.append(file)
                        }
                    } else {
                        images.append(file)
                    }
                } else if ext == "xmp" {
                    xmpLookup.insert(baseName)
                } else if ext == "acr" {
                    acrLookup.insert(baseName)
                }
            }
        }

        // Create PhotoItems with basic info only - no XMP or rating yet
        let basicPhotos = images
            .sorted(by: { $0.path < $1.path })
            .map { imageFile in
                let baseName = imageFile.deletingPathExtension().lastPathComponent
                let resValues = try? imageFile.resourceValues(forKeys: [.creationDateKey,
                                                                        .contentModificationDateKey,
                                                                        .fileSizeKey])
                // dateCreated is not reliable
                let dateCreated = resValues?.creationDate ?? Date()
                let dateModified = resValues?.contentModificationDate
                let size = resValues?.fileSize as? Int
                let isRaw = FilesExtensions.isRawImageFile(imageFile)

                let hasACR = acrLookup.contains(baseName)
                let hasJPG = jpgLookup.contains(baseName)
                let hasXMP = xmpLookup.contains(baseName)

                return PhotoItem(id: UUID(),
                                 url: imageFile,
                                 path: imageFile.path,
                                 dateCreated: dateCreated,
                                 dateModified: dateModified,
                                 hasACR: hasACR,
                                 hasJPG: hasJPG,
                                 hasXMP: hasXMP,
                                 fileSizeBytes: Int64(size ?? 0),
                                 toDelete: false)
            }

        photos.wrappedValue = basicPhotos

        loadLocalExifs()
    }

    func reloadPhotos() {
        queue.cancelAllOperations()
        loadPhotos()
    }

    /// Surgically adds, removes, or reloads the batch of photos identified by their file URLs,
    /// without re-scanning the whole folder. filterAndSortPhotos() is called once by the caller after this returns.
    func applyFileSystemChanges(at urls: [URL]) {
        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path) else {
                // File gone — remove it
                photos.wrappedValue.removeAll { $0.url == url }
                continue
            }
            guard FilesExtensions.isImageFile(url) || FilesExtensions.isMovieFile(url) else {
                continue
            }
            if let idx = photos.wrappedValue.firstIndex(where: { $0.url == url }) {
                // File already known - reload its exif
                let photo = photos.wrappedValue[idx]
                let op = LoadExifOperation(photo: photo, forceReloadExif: true) { [weak self] updated in
                    Task { @MainActor in
                        self?.photos.wrappedValue[idx] = updated
                    }
                }
                queue.addOperation(op)
            } else {
                // New file - build a PhotoItem and append it, then load its EXIF
                let resValues = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey])
                let hasXMP = FileManager.default.fileExists(atPath: url.deletingPathExtension().appendingPathExtension("xmp").path)
                let newPhoto = PhotoItem(id: UUID(),
                                         url: url,
                                         path: url.path,
                                         dateCreated: resValues?.creationDate ?? Date(),
                                         dateModified: resValues?.contentModificationDate,
                                         hasACR: false,
                                         hasJPG: false,
                                         hasXMP: hasXMP,
                                         xmp: nil,
                                         exif: nil,
                                         fileSizeBytes: Int64(resValues?.fileSize ?? 0),
                                         toDelete: false)
                photos.wrappedValue.append(newPhoto)
                let insertedIdx = photos.wrappedValue.count - 1
                let op = LoadExifOperation(photo: newPhoto, forceReloadExif: true) { [weak self] updated in
                    Task { @MainActor in
                        guard let self,
                              insertedIdx < self.photos.wrappedValue.count,
                              self.photos.wrappedValue[insertedIdx].id == updated.id else {
                            return
                        }
                        self.photos.wrappedValue[insertedIdx] = updated
                    }
                }
                queue.addOperation(op)
            }
        }
    }

    func applyFileSystemChange(at url: URL) {
        applyFileSystemChanges(at: [url])
    }

    private func loadLocalExifs() {
        let startTime = Date()
        isLoadingMetadata = true

        queue.maxConcurrentOperationCount = ProcessInfo.processInfo.activeProcessorCount
        queue.qualityOfService = .utility
        RCLog("start loading exif using \(queue.maxConcurrentOperationCount) threads")

        var photosWithExifs: [PhotoItem] = []

        for photo in photos.wrappedValue {
            let op = LoadExifOperation(photo: photo) { photoWithExif in
                Task {
                    photosWithExifs.append(photoWithExif)
                }
            }
            queue.addOperation(op)
        }
        queue.addBarrierBlock {
            Task { @MainActor in
                RCLog("loaded Exifs \(photosWithExifs.count) from \(self.photos.wrappedValue.count) in \(String(format: "%.3f", Date().timeIntervalSince(startTime)))s")
                self.isLoadingMetadata = false
                self.photos.wrappedValue = photosWithExifs
            }
        }
    }

    func reloadMetadata(forSidecar sidecarURL: URL, completion: @escaping (() -> Void)) {
        let baseName = sidecarURL.deletingPathExtension().lastPathComponent

        // Find the matching photo by base filename (strip extension from both)
        guard let idx = photos.wrappedValue.firstIndex(where: {
            URL(fileURLWithPath: $0.path).deletingPathExtension().lastPathComponent == baseName
        }) else {
            RCLog("⚠️ reloadMetadata: no photo found for sidecar \(baseName)")
            return
        }

        let photo = photos.wrappedValue[idx]

        let op = LoadExifOperation(photo: photo, forceReloadExif: true) { [weak self] photoWithExif in
            Task { @MainActor in
                RCLog("🔄 reloadMetadata: updating photo at idx \(idx) for sidecar \(baseName)")
                self?.photos.wrappedValue[idx] = photoWithExif
                completion()
            }
        }
        queue.addOperation(op)
    }
}
