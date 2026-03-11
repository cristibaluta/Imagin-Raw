//
//  PhotoItem.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 29.01.2026.
//

import Foundation

struct PhotoItem: Identifiable, Hashable {
    let id: UUID
    let path: String
    let xmp: XmpMetadata?
    let dateCreated: Date
    let hasACR: Bool // Indicates if an ACR (Adobe Camera Raw) file exists for this photo
    let hasJPG: Bool // Indicates if a JPG counterpart exists for this RAW photo
    let inCameraRating: Int? // Canon in-camera rating from IPTC metadata (0-5)
    let isRawFile: Bool // Indicates if this is a RAW file format
    let fileSizeBytes: Int64? // File size in bytes
    let width: Int? // Image width in pixels
    let height: Int? // Image height in pixels
    let cameraMake: String? // Camera manufacturer (e.g., "Canon")
    let cameraModel: String? // Camera model (e.g., "Canon EOS R5")
    var toDelete: Bool = false // Transient property, not saved to XMP

    var isVideo: Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return FilesExtensions.video.contains(ext)
    }

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

    // Initializer that preserves the existing ID when updating XMP metadata
    init(id: UUID, path: String, xmp: XmpMetadata?, dateCreated: Date, hasACR: Bool = false, hasJPG: Bool = false, inCameraRating: Int? = nil, isRawFile: Bool = false, fileSizeBytes: Int64? = nil, width: Int? = nil, height: Int? = nil, cameraMake: String? = nil, cameraModel: String? = nil) {
        self.id = id
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

    // Initializer that preserves the existing ID and toDelete state when updating XMP metadata
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
}
