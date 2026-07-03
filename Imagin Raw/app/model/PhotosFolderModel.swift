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
    private let queueLock = NSLock()

    init(folder: FolderItem) {
        self.folder = folder
    }

    deinit {
        queue.cancelAllOperations()
        RCLog("🗑️ PhotosModel deallocated for: \(folder.url.lastPathComponent)")
    }

    func loadPhotos() {
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
            let baseName = file.deletingPathExtension().lastPathComponent
            if FilesExtensions.all.contains(ext) {
                if FilesExtensions.jpg.contains(ext) {
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

        // Create PhotoItems with basic info only - no XMP or rating yet
        let basicPhotos = images
            .sorted(by: { $0.path < $1.path })
            .map { imageFile in
                let baseName = imageFile.deletingPathExtension().lastPathComponent
                let fileExtension = imageFile.pathExtension.lowercased()
                let resValues = try? imageFile.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey])
                let creationDate = resValues?.creationDate ?? Date()
                let modifiedDate = resValues?.contentModificationDate
                let size = resValues?.fileSize as? Int
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
                                 fileSizeBytes: Int64(size ?? 0))
            }

        photos.wrappedValue = basicPhotos

        loadLocalExifs()
    }

    func reloadPhotos() {
        queue.cancelAllOperations()
        loadPhotos()
    }

    /// Surgically adds, removes, or reloads a single photo identified by its file URL,
    /// without re-scanning the whole folder.
    func applyFileSystemChange(at url: URL) {
        let exists = FileManager.default.fileExists(atPath: url.path)
        let ext = url.pathExtension.lowercased()
        guard FilesExtensions.all.contains(ext) else { return }

        if exists {
            if let idx = photos.wrappedValue.firstIndex(where: { $0.url == url }) {
                // File already known — reload its metadata in place
                let photo = photos.wrappedValue[idx]
                let op = LoadExifOperation(photo: photo, forceReloadExif: true) { [weak self] updated in
                    self?.queueLock.withLock {
                        self?.photos.wrappedValue[idx] = updated
                    }
                }
                queue.addOperation(op)
            } else {
                // New file — build a PhotoItem and append it, then load its EXIF
                let resValues = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey])
                let baseName = url.deletingPathExtension().lastPathComponent
                let isRaw = FilesExtensions.raw.contains(ext)
                let hasXMP = FileManager.default.fileExists(
                    atPath: url.deletingPathExtension().appendingPathExtension("xmp").path)
                let newPhoto = PhotoItem(url: url,
                                        path: url.path,
                                        dateCreated: resValues?.creationDate ?? Date(),
                                        dateModified: resValues?.contentModificationDate,
                                        hasACR: false,
                                        hasJPG: false,
                                        hasXMP: hasXMP,
                                        isRawFile: isRaw,
                                        fileSizeBytes: Int64(resValues?.fileSize ?? 0))
                photos.wrappedValue.append(newPhoto)
                let insertedIdx = photos.wrappedValue.count - 1
                let op = LoadExifOperation(photo: newPhoto, forceReloadExif: true) { [weak self] updated in
                    self?.queueLock.withLock {
                        guard let self,
                              insertedIdx < self.photos.wrappedValue.count,
                              self.photos.wrappedValue[insertedIdx].id == updated.id else { return }
                        self.photos.wrappedValue[insertedIdx] = updated
                    }
                }
                queue.addOperation(op)
            }
        } else {
            // File gone — remove it
            photos.wrappedValue.removeAll { $0.url == url }
        }
    }

    private func loadLocalExifs() {
        let startTime = Date()
        isLoadingMetadata = true

        queue.maxConcurrentOperationCount = ProcessInfo.processInfo.activeProcessorCount
        queue.qualityOfService = .utility
        RCLog("start loading exif using \(queue.maxConcurrentOperationCount) threads")

        var photosWithExifs: [PhotoItem] = []

        for photo in photos.wrappedValue {
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
                self.photos.wrappedValue = photosWithExifs
                self.isLoadingMetadata = false
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
            self?.queueLock.withLock {
                RCLog("🔄 reloadMetadata: updating photo at idx \(idx) for sidecar \(baseName)")
                self?.photos.wrappedValue[idx] = photoWithExif
                completion()
            }
        }
        queue.addOperation(op)
    }
}
