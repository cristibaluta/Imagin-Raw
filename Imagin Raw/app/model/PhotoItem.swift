//
//  PhotoItem.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 29.01.2026.
//

import Foundation
import Photos

struct PhotoItem: Identifiable, Sendable {
    let id: UUID
    let url: URL
    var path: String// file path on disk, OR PHAsset.localIdentifier for PhotoKit items

    let dateCreated: Date
    let dateModified: Date?

    let hasACR: Bool
    let hasJPG: Bool
    let hasXMP: Bool
    let xmp: XmpMetadata?
    let exif: ExifData?
    let fileSizeBytes: Int64?
    
    var toDelete: Bool = false

    // Non-nil when this item comes from the Photos library.
    // Excluded from Hashable / Equatable so PHAsset object identity
    // doesn't interfere with existing diffing logic.
    var phAsset: PHAsset? = nil

    var isPhotoKitBacked: Bool {
        phAsset != nil
    }

    /// XMP rating if set and > 0, otherwise in-camera rating, otherwise 0.
    var effectiveRating: Int {
        if let r = xmp?.rating, r > 0 {
			return r
		}
        return exif?.rating ?? 0
    }

    var isRaw: Bool {
        return FilesExtensions.isRawImageFile(url)
    }

    var isVideo: Bool {
		if let asset = phAsset {
            return asset.mediaType == .video
        }
        return FilesExtensions.isMovieFile(url)
    }

    // MARK: Init

    init(id: UUID,
         url: URL,
         path: String,
         dateCreated: Date,
         dateModified: Date? = nil,
         hasACR: Bool = false,
         hasJPG: Bool = false,
         hasXMP: Bool = false,
         xmp: XmpMetadata? = nil,
         exif: ExifData? = nil,
         fileSizeBytes: Int64? = nil,
         toDelete: Bool) {

        self.id = id
        self.url = url
        self.path = path
        self.dateCreated = dateCreated
        self.dateModified = dateModified
        self.hasACR = hasACR
        self.hasJPG = hasJPG
        self.hasXMP = hasXMP
        self.xmp = xmp
        self.exif = exif
        self.fileSizeBytes = fileSizeBytes
        self.toDelete = toDelete
    }

    // MARK: - PhotoKit init

    init(asset: PHAsset, basic: Bool = false) {
        self.id = UUID()
        if #available(iOS 26.0, macOS 26.0, *) {
            let dateAdded = asset.value(forKey: "addedDate") as? Date
            self.dateCreated = dateAdded ?? asset.creationDate ?? Date()// TODO: Use asset.addedDate when compiling from Xcode26
        } else {
            self.dateCreated = asset.creationDate ?? Date()
        }
        self.dateModified = asset.modificationDate
        self.hasACR = false
        self.hasJPG = false
        self.hasXMP = false
        self.toDelete = false
        self.phAsset = asset
        self.fileSizeBytes = nil
        self.xmp = nil
        self.exif = ExifData(dateCaptured: self.dateCreated,
                             width: asset.pixelWidth == 0 ? nil : asset.pixelWidth,
                             height: asset.pixelHeight == 0 ? nil : asset.pixelHeight,
                             cameraMake: nil,
                             cameraModel: nil,
                             lensModel: nil,
                             lensFocalLength: nil,
                             iso: nil,
                             aperture: nil,
                             shutterSpeed: nil,
                             exposureCompensation: nil,
                             rating: nil)

        if basic {
            // Fast path — no PHAssetResource lookup.
            // A background enrichment pass will call withFilename() afterwards.
            self.path = asset.localIdentifier
        } else {
            let resources = PHAssetResource.assetResources(for: asset)
            let primary = resources.first(where: {
                $0.type == .photo || $0.type == .video || $0.type == .fullSizePhoto
            }) ?? resources.first
            let filename = primary?.originalFilename ?? asset.localIdentifier
            self.path = asset.localIdentifier + "/" + filename
        }
        self.url = URL(string: self.path)!
    }

    /// Returns a copy with the real filename appended — used by the background enrichment pass.
    func withFilename(_ filename: String) -> PhotoItem {
        let base = phAsset?.localIdentifier ?? path
        var copy = self
        copy.path = base + "/" + filename
        return copy
    }
}

// MARK: - Hashable / Equatable
// phAsset is intentionally excluded — only identity fields matter for diffing.

extension PhotoItem: Hashable {
    static func == (lhs: PhotoItem, rhs: PhotoItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.path == rhs.path &&
        lhs.xmp == rhs.xmp &&
        lhs.exif == rhs.exif &&
        lhs.dateModified == rhs.dateModified &&
        lhs.hasACR == rhs.hasACR &&
        lhs.hasJPG == rhs.hasJPG &&
        lhs.hasXMP == rhs.hasXMP &&
        lhs.fileSizeBytes == rhs.fileSizeBytes &&
        lhs.toDelete == rhs.toDelete
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(path)
    }
}

extension PhotoItem {
    /// Returns the appropriate PhotoSource for this item.
    func makeSource() -> PhotoSource {
        if let asset = phAsset {
            return PhotoKitPhotoSource(asset: asset, photoPath: path)
        }
        return DiskPhotoSource(url: url)
    }
}
