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
        var xmp: XmpMetadata?
        if photo.hasXMP || forceReloadExif {
            let xmpFile = photo.url.deletingPathExtension().appendingPathExtension("xmp")
            if let content = try? String(contentsOf: xmpFile, encoding: .utf8) {
                xmp = XmpParser.parseMetadata(from: content)
            }
        }
        // Extract metadata from the raw file
        var inCameraRating: Int? = nil
        var width: Int? = nil
        var height: Int? = nil
        var cameraMake: String? = nil
        var cameraModel: String? = nil
        var exifDate: Date? = nil
        if let metadata = RawWrapper.shared().extractMetadata(photo.path) {
            inCameraRating = (metadata["rating"] as? NSNumber)?.intValue
            width = (metadata["width"] as? NSNumber)?.intValue
            height = (metadata["height"] as? NSNumber)?.intValue
            cameraMake = metadata["cameraMake"] as? String
            cameraModel = metadata["cameraModel"] as? String
            exifDate = metadata["captureDate"] as? Date
        }
//        let fpoints = extractPanasonicFocusPoints(from: URL(fileURLWithPath: photo.path))
//        RCLog(">>>>> focus points: \(fpoints)")

        if xmp == nil && !photo.isRawFile && JpegMetadataWriter.isSupported(photo.url) {
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
        // Capture date priority:
        // 1. EXIF DateTimeOriginal from ImageIO/LibRaw (actual shutter press time)
        // 2. XMP CreateDate from sidecar (set by camera or Lightroom)
        // 3. Keep existing date (file system creation date, last resort)
        let captureDate: Date
        if let exifDate {
            captureDate = exifDate
        } else if let xmpDateStr = xmp?.createDate, let parsed = parseXmpDate(xmpDateStr) {
            captureDate = parsed
        } else {
            captureDate = photo.dateCreated
        }

        return PhotoItem(
            id: photo.id,
            url: photo.url,
            path: photo.path,
            dateCreated: captureDate,
            dateModified: photo.dateModified,
            toDelete: photo.toDelete,
            hasACR: photo.hasACR,
            hasJPG: photo.hasJPG,
            hasXMP: xmp != nil,
            xmp: xmp,
            inCameraRating: inCameraRating,
            isRawFile: photo.isRawFile,
            fileSizeBytes: photo.fileSizeBytes,
            width: width,
            height: height,
            cameraMake: cameraMake,
            cameraModel: cameraModel
        )
    }

    /// Parse an XMP/ISO 8601 date string into a Date.
    /// Handles formats: "YYYY:MM:DD HH:MM:SS", "YYYY-MM-DDTHH:MM:SS", "YYYY-MM-DDTHH:MM:SS+HH:MM"
    private func parseXmpDate(_ string: String) -> Date? {
        let formatters: [DateFormatter] = [
            {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "yyyy:MM:dd HH:mm:ss"
                return f
            }(),
            {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                return f
            }(),
        ]
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: string) {
            return d
        }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: string) {
            return d
        }
        for f in formatters {
            if let d = f.date(from: string) {
                return d
            }
        }
        return nil
    }
}
