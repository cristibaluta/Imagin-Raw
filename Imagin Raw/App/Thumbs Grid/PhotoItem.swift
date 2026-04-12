//
//  PhotoItem.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 29.01.2026.
//

import Foundation
import Photos

struct PhotoItem: Identifiable {
    let id: UUID
    let path: String          // file path on disk, OR PHAsset.localIdentifier for PhotoKit items
    let xmp: XmpMetadata?
    let dateCreated: Date
    let hasACR: Bool
    let hasJPG: Bool
    let inCameraRating: Int?
    let isRawFile: Bool
    let fileSizeBytes: Int64?
    let width: Int?
    let height: Int?
    let cameraMake: String?
    let cameraModel: String?
    var toDelete: Bool = false

    // Non-nil when this item comes from the Photos library.
    // Excluded from Hashable / Equatable so PHAsset object identity
    // doesn't interfere with existing diffing logic.
    var phAsset: PHAsset? = nil

    var isPhotoKitBacked: Bool {
        return phAsset != nil
    }

    var isVideo: Bool {
        if let asset = phAsset {
            return asset.mediaType == .video
        }
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return FilesExtensions.video.contains(ext)
    }

    // MARK: - File-based init

    init(path: String, xmp: XmpMetadata? = nil, dateCreated: Date, hasACR: Bool = false, hasJPG: Bool = false, inCameraRating: Int? = nil, isRawFile: Bool = false, fileSizeBytes: Int64? = nil, width: Int? = nil, height: Int? = nil, cameraMake: String? = nil, cameraModel: String? = nil) {
        self.id = UUID()
        self.path = path
        self.xmp = xmp
        self.dateCreated = dateCreated
        self.hasACR = hasACR
        self.hasJPG = hasJPG
        self.inCameraRating = inCameraRating
        self.isRawFile = isRawFile
        self.fileSizeBytes = fileSizeBytes
        self.width = width
        self.height = height
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.toDelete = false
    }

    // Preserves the existing ID when updating XMP metadata
    init(id: UUID, path: String, xmp: XmpMetadata?, dateCreated: Date, toDelete: Bool, hasACR: Bool = false, hasJPG: Bool = false, inCameraRating: Int? = nil, isRawFile: Bool = false, fileSizeBytes: Int64? = nil, width: Int? = nil, height: Int? = nil, cameraMake: String? = nil, cameraModel: String? = nil) {
        self.id = id
        self.path = path
        self.xmp = xmp
        self.dateCreated = dateCreated
        self.toDelete = toDelete
        self.hasACR = hasACR
        self.hasJPG = hasJPG
        self.inCameraRating = inCameraRating
        self.isRawFile = isRawFile
        self.fileSizeBytes = fileSizeBytes
        self.width = width
        self.height = height
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
    }

    // MARK: - PhotoKit init

    init(asset: PHAsset) {
        self.id = UUID()
        self.path = asset.localIdentifier   // used as stable key throughout the app
        self.xmp = nil
        self.dateCreated = asset.creationDate ?? Date()
        self.hasACR = false
        self.hasJPG = false
        self.inCameraRating = nil
        self.isRawFile = false
        self.fileSizeBytes = nil
        self.width = asset.pixelWidth == 0 ? nil : asset.pixelWidth
        self.height = asset.pixelHeight == 0 ? nil : asset.pixelHeight
        self.cameraMake = nil
        self.cameraModel = nil
        self.toDelete = false
        self.phAsset = asset
    }
}

// MARK: - Hashable / Equatable
// phAsset is intentionally excluded — only identity fields matter for diffing.

extension PhotoItem: Hashable {
    static func == (lhs: PhotoItem, rhs: PhotoItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.path == rhs.path &&
        lhs.xmp == rhs.xmp &&
        lhs.dateCreated == rhs.dateCreated &&
        lhs.hasACR == rhs.hasACR &&
        lhs.hasJPG == rhs.hasJPG &&
        lhs.inCameraRating == rhs.inCameraRating &&
        lhs.isRawFile == rhs.isRawFile &&
        lhs.fileSizeBytes == rhs.fileSizeBytes &&
        lhs.width == rhs.width &&
        lhs.height == rhs.height &&
        lhs.cameraMake == rhs.cameraMake &&
        lhs.cameraModel == rhs.cameraModel &&
        lhs.toDelete == rhs.toDelete
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(path)
    }
}
