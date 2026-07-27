//
//  LoadExifOperation.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 06.06.2026.
//
import Foundation

final class LoadExifOperation: Operation, @unchecked Sendable {
    private let photo: PhotoItem
    private let forceReloadExif: Bool
    private let completion: (PhotoItem) -> Void

    init(photo: PhotoItem, forceReloadExif: Bool = false, completion: @escaping (PhotoItem) -> Void) {
        self.photo = photo
        self.forceReloadExif = forceReloadExif
        self.completion = completion
    }

    override func main() {
        if isCancelled {
            return
        }
        let enriched = loadExif(for: photo)
        if isCancelled {
            return
        }
        completion(enriched)
    }

    private func loadExif(for photo: PhotoItem) -> PhotoItem {
        // 1. Load xmp data from disk
        var xmp: XmpMetadata?
        if photo.hasXMP || forceReloadExif {
            let xmpFile = photo.url.deletingPathExtension().appendingPathExtension("xmp")
            if let content = try? String(contentsOf: xmpFile, encoding: .utf8) {
                xmp = XmpParser.parseMetadata(from: content)
            }
        }
        if xmp == nil && !photo.isRaw && JpegMetadataWriter.isSupported(photo.url) {
            // No sidecar — read embedded XMP from the file itself (JPEG, PNG, TIFF, HEIC)
            let embedded = JpegMetadataWriter.readMetadata(from: photo.url)
            if embedded.rating != nil || embedded.label != nil {
                xmp = XmpMetadata(label: embedded.label,
                                  rating: embedded.rating,
                                  creator: nil,
                                  rights: nil,
                                  createDate: nil,
                                  modifyDate: nil,
                                  cameraModel: nil,
                                  lens: nil,
                                  focalLength: nil,
                                  aperture: nil,
                                  shutterSpeed: nil,
                                  iso: nil,
                                  exposureBias: nil,
                                  hasEdits: false)
            }
        }

        // 2. Extract exif from the photo
        var exif: ExifData? = nil
        if FilesExtensions.isRawImageFile(photo.url) {
            exif = LibRawDecoder().extractExif(at: photo.url)
        }
        if exif == nil {
            // Fallback to CoreGraphics exif reading
            exif = CoreGraphicsDecoder().extractExif(at: photo.url)
        }

        // 3. Build PhotoItem
        return PhotoItem(id: photo.id,
                         url: photo.url,
                         path: photo.path,
                         dateCreated: photo.dateCreated,
                         dateModified: photo.dateModified,
                         hasACR: photo.hasACR,
                         hasJPG: photo.hasJPG,
                         hasXMP: xmp != nil,
                         xmp: xmp,
                         exif: exif,
                         fileSizeBytes: photo.fileSizeBytes,
                         toDelete: photo.toDelete)
    }
}
