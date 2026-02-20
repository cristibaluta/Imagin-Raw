//
//  PhotosModel.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 20.02.2026.
//

import Foundation
import SwiftUI

/// Model responsible for loading and managing photos for a specific folder
/// Each folder gets its own PhotosModel instance, ensuring clean state separation
@MainActor
final class PhotosModel: ObservableObject {
    @Published var photos: [PhotoItem] = []
    @Published var isLoadingMetadata: Bool = false
    
    private let folder: FolderItem
    private var metadataTask: Task<Void, Never>?
    
    init(folder: FolderItem) {
        self.folder = folder
    }
    
    deinit {
        // Cancel any pending metadata loading
        metadataTask?.cancel()
        
        // Stop any pending thumbnail generation
        ThumbsManager.shared.stopQueue()
        
        print("🗑️ PhotosModel deallocated for: \(folder.url.lastPathComponent)")
    }
    
    /// Load photos for the folder - call this when the model is created
    func loadPhotos() {
        // Load basic photo info immediately
        photos = Self.loadPhotosBasic(in: folder)
        
        // Load metadata asynchronously
        isLoadingMetadata = true
        metadataTask = Task {
            let photosWithMetadata = await Self.loadPhotosMetadataAsync(in: folder, photos: photos)
            
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                self.photos = photosWithMetadata
                self.isLoadingMetadata = false
            }
        }
    }
    
    /// Reload photos (called when folder contents change)
    func reloadPhotos() {
        // Cancel any pending metadata loading
        metadataTask?.cancel()
        
        // Stop any pending thumbnail generation
        ThumbsManager.shared.stopQueue()
        
        // Reload photos
        loadPhotos()
    }
    
    // MARK: - Static Photo Loading Methods
    
    private static func loadPhotosBasic(in folder: FolderItem) -> [PhotoItem] {
        let fm = FileManager.default
        let rawExtensions = ["arw", "orf", "rw2", "cr2", "cr3", "crw", "nef", "nrw",
                             "srf", "sr2", "raw", "raf", "pef", "ptx", "dng", "3fr",
                             "fff", "iiq", "mef", "mos", "x3f", "srw", "dcr", "kdc",
                             "k25", "kc2", "mrw", "erf", "bay", "ndd", "sti", "rwl", "r3d"]
        let jpgExtensions = ["jpg", "jpeg"]
        let otherExtensions = ["png", "heic", "tiff", "tif"]
        let allowed = rawExtensions + jpgExtensions + otherExtensions

        let files = (try? fm.contentsOfDirectory(
            at: folder.url,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        // Create a set of base filenames that have RAW versions
        let rawBaseNames = Set(files
            .filter { rawExtensions.contains($0.pathExtension.lowercased()) }
            .map { $0.deletingPathExtension().lastPathComponent })

        // Separate image files from XMP and ACR files, filtering out JPGs with RAW counterparts
        let imageFiles = files.filter { file in
            let ext = file.pathExtension.lowercased()
            guard allowed.contains(ext) else { return false }

            // If it's a JPG and a RAW version exists, skip it
            if jpgExtensions.contains(ext) {
                let baseName = file.deletingPathExtension().lastPathComponent
                return !rawBaseNames.contains(baseName)
            }

            return true
        }
        let acrFiles = files.filter { $0.pathExtension.lowercased() == "acr" }
        let jpgFiles = files.filter { jpgExtensions.contains($0.pathExtension.lowercased()) }

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
    
    private static func loadPhotosMetadataAsync(in folder: FolderItem, photos: [PhotoItem]) async -> [PhotoItem] {
        let fm = FileManager.default
        let rawExtensions = ["arw", "orf", "rw2", "cr2", "cr3", "crw", "nef", "nrw",
                             "srf", "sr2", "raw", "raf", "pef", "ptx", "dng", "3fr",
                             "fff", "iiq", "mef", "mos", "x3f", "srw", "dcr", "kdc",
                             "k25", "kc2", "mrw", "erf", "bay", "ndd", "sti", "rwl", "r3d"]

        let files = (try? fm.contentsOfDirectory(
            at: folder.url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        let xmpFiles = files.filter { $0.pathExtension.lowercased() == "xmp" }

        var xmpLookup: [String: String] = [:]
        for xmpFile in xmpFiles {
            let baseName = xmpFile.deletingPathExtension().lastPathComponent
            if let xmpContent = try? String(contentsOf: xmpFile, encoding: .utf8) {
                xmpLookup[baseName] = xmpContent
            }
        }

        let startTime = Date()

        return await withTaskGroup(of: (Int, XmpMetadata?, Int?, Bool, Int64?, Int?, Int?, String?, String?).self, returning: [PhotoItem].self) { group in
            for (index, photo) in photos.enumerated() {
                group.addTask {
                    let url = URL(fileURLWithPath: photo.path)
                    let baseName = url.deletingPathExtension().lastPathComponent
                    let fileExtension = url.pathExtension.lowercased()
                    let isRaw = rawExtensions.contains(fileExtension)

                    let xmp: XmpMetadata? = if let xmpContent = xmpLookup[baseName] {
                        XmpParser.parseMetadata(from: xmpContent)
                    } else {
                        nil
                    }

                    // Get file size
                    let fileSize: Int64? = (try? fm.attributesOfItem(atPath: photo.path))?[.size] as? Int64

                    // Extract metadata (rating, width, height, camera info) in a single call
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

            var updatedPhotos = photos
            for await (index, xmp, rating, isRaw, fileSize, width, height, cameraMake, cameraModel) in group {
                updatedPhotos[index] = PhotoItem(
                    id: photos[index].id,
                    path: photos[index].path,
                    xmp: xmp,
                    dateCreated: photos[index].dateCreated,
                    hasACR: photos[index].hasACR,
                    hasJPG: photos[index].hasJPG,
                    inCameraRating: rating,
                    isRawFile: isRaw,
                    fileSizeBytes: fileSize,
                    width: width,
                    height: height,
                    cameraMake: cameraMake,
                    cameraModel: cameraModel
                )
            }

            let totalTime = Date().timeIntervalSince(startTime)
            print("📊 loadPhotosMetadataAsync Performance:")
            print("   Total files: \(photos.count)")
            print("   Total time: \(String(format: "%.3f", totalTime))s")

            return updatedPhotos
        }
    }
}
