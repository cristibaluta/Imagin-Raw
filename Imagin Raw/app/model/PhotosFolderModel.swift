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
    let photosSubject = CurrentValueSubject<[PhotoItem], Never>([])
    let isLoadingSubject = CurrentValueSubject<Bool, Never>(false)
    private var photos: [PhotoItem] = [] {
        didSet {
            photosSubject.send(photos)
        }
    }
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

        photos = basicPhotos

        loadLocalExifs()
    }

    func reloadPhotos() {
        queue.cancelAllOperations()
        loadPhotos()
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
