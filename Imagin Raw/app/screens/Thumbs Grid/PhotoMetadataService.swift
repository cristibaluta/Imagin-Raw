//
//  PhotoMetadataService.swift
//  Imagin Raw
//
//  Handles all rating, label, and delete-state mutations for PhotoItems.
//  Works for both RAW files (XMP sidecar) and JPEG/PNG/TIFF/HEIC (embedded metadata).
//

import Foundation

@MainActor
class PhotoMetadataService {

    // Injected by the owner; updated whenever a new PhotosModel is created.
    weak var photosModel: PhotosModel?
    weak var filesModel: FilesModel?
    /// Called after any mutation so the VM can refresh filteredPhotos.
    var onPhotoUpdated: (() -> Void)?

    // MARK: - Rating

    func applyRating(_ rating: Int, to photos: [PhotoItem]) {
        for photo in photos {
            let url = URL(fileURLWithPath: photo.path)
            if photo.isRawFile {
                setPhotoRating(photo: photo, rating: rating)
            } else if JpegMetadataWriter.isSupported(url) {
                let existing = JpegMetadataWriter.readMetadata(from: url)
                let ok = JpegMetadataWriter.write(
                    JpegMetadataWriter.Metadata(rating: rating, label: existing.label), to: url)
                if ok {
                    updatePhoto(photo, xmp: xmpUpdating(photo, rating: rating,
                                                        label: existing.label ?? photo.xmp?.label))
                }
            }
        }
    }

    // MARK: - Label

    func applyLabel(_ label: String, to photos: [PhotoItem]) {
        for photo in photos {
            let url = URL(fileURLWithPath: photo.path)
            if photo.isRawFile {
                createAndSaveXmpFile(for: photo, targetLabel: label)
            } else if JpegMetadataWriter.isSupported(url) {
                let existing = JpegMetadataWriter.readMetadata(from: url)
                let newLabel = (existing.label == label) ? "" : label
                let ok = JpegMetadataWriter.write(
                    JpegMetadataWriter.Metadata(rating: existing.rating, label: newLabel), to: url)
                if ok {
                    updatePhoto(photo, xmp: xmpUpdating(photo,
                                                        rating: existing.rating ?? photo.xmp?.rating,
                                                        label: newLabel.isEmpty ? nil : newLabel))
                }
            }
        }
    }

    func removeLabels(from photos: [PhotoItem]) {
        for photo in photos {
            let url = URL(fileURLWithPath: photo.path)
            if photo.isRawFile {
                removeAnyLabel(for: photo)
            } else if JpegMetadataWriter.isSupported(url) {
                let existing = JpegMetadataWriter.readMetadata(from: url)
                let ok = JpegMetadataWriter.write(
                    JpegMetadataWriter.Metadata(rating: existing.rating, label: ""), to: url)
                if ok {
                    updatePhoto(photo, xmp: xmpUpdating(photo,
                                                        rating: existing.rating ?? photo.xmp?.rating,
                                                        label: nil))
                }
            }
        }
    }

    // MARK: - Delete state

    func toggleDeleteState(for photos: [PhotoItem]) {
        for photo in photos { toggleToDeleteState(for: photo) }
    }

    // MARK: - Internal model update

    func updatePhoto(_ photo: PhotoItem, xmp: XmpMetadata) {
        updatePhotoWithXmpMetadata(photo: photo, xmpMetadata: xmp)
    }

    // MARK: - Private RAW/XMP helpers

    private func setPhotoRating(photo: PhotoItem, rating: Int) {
        let photoURL = URL(fileURLWithPath: photo.path)
        let dir = photoURL.deletingLastPathComponent()
        let name = photoURL.deletingPathExtension().lastPathComponent
        let xmpURL = dir.appendingPathComponent("\(name).xmp")

        var content: String
        if FileManager.default.fileExists(atPath: xmpURL.path) {
            guard let existing = try? String(contentsOf: xmpURL, encoding: .utf8) else { return }
            content = XmpParser.updateRating(in: existing, rating: rating)
        } else {
            content = XmpParser.createXmpContent(rating: rating, label: photo.xmp?.label)
        }
        guard (try? content.write(to: xmpURL, atomically: true, encoding: .utf8)) != nil else { return }
        if let parsed = XmpParser.parseMetadata(from: content) {
            updatePhotoWithXmpMetadata(photo: photo, xmpMetadata: parsed)
        }
    }

    private func createAndSaveXmpFile(for photo: PhotoItem, targetLabel: String) {
        let photoURL = URL(fileURLWithPath: photo.path)
        let dir = photoURL.deletingLastPathComponent()
        let name = photoURL.deletingPathExtension().lastPathComponent
        let xmpURL = dir.appendingPathComponent("\(name).xmp")

        var content: String
        var currentLabel: String? = nil
        if FileManager.default.fileExists(atPath: xmpURL.path) {
            guard let existing = try? String(contentsOf: xmpURL, encoding: .utf8) else { return }
            currentLabel = XmpParser.parseMetadata(from: existing)?.label
            let newLabel: String? = (currentLabel == targetLabel) ? nil : targetLabel
            content = updateXmpLabel(in: existing, newLabel: newLabel)
        } else {
            content = XmpParser.createXmpContent(rating: photo.xmp?.rating ?? 0, label: targetLabel)
        }
        guard (try? content.write(to: xmpURL, atomically: true, encoding: .utf8)) != nil else { return }
        if let parsed = XmpParser.parseMetadata(from: content) {
            updatePhotoWithXmpMetadata(photo: photo, xmpMetadata: parsed)
        }
    }

    private func removeAnyLabel(for photo: PhotoItem) {
        let photoURL = URL(fileURLWithPath: photo.path)
        let dir = photoURL.deletingLastPathComponent()
        let name = photoURL.deletingPathExtension().lastPathComponent
        let xmpURL = dir.appendingPathComponent("\(name).xmp")
        guard FileManager.default.fileExists(atPath: xmpURL.path),
              var content = try? String(contentsOf: xmpURL, encoding: .utf8) else { return }
        content = updateXmpLabel(in: content, newLabel: nil)
        guard (try? content.write(to: xmpURL, atomically: true, encoding: .utf8)) != nil else { return }
        if let parsed = XmpParser.parseMetadata(from: content) {
            updatePhotoWithXmpMetadata(photo: photo, xmpMetadata: parsed)
        }
    }

    private func toggleToDeleteState(for photo: PhotoItem) {
        guard let photosModel,
              let idx = photosModel.photos.firstIndex(where: { $0.path == photo.path }) else { return }
        let cur = photosModel.photos[idx]
        photosModel.photos[idx] = PhotoItem(id: cur.id, path: cur.path, xmp: cur.xmp,
                                            dateCreated: cur.dateCreated, dateModified: cur.dateModified,
                                            toDelete: !cur.toDelete, hasACR: cur.hasACR, hasJPG: cur.hasJPG,
                                            inCameraRating: cur.inCameraRating, isRawFile: cur.isRawFile,
                                            fileSizeBytes: cur.fileSizeBytes, width: cur.width, height: cur.height,
                                            cameraMake: cur.cameraMake, cameraModel: cur.cameraModel)
        filesModel?.selectedPhoto = photosModel.photos[idx]
        onPhotoUpdated?()
    }

    private func updatePhotoWithXmpMetadata(photo: PhotoItem, xmpMetadata: XmpMetadata) {
        guard let photosModel,
              let idx = photosModel.photos.firstIndex(where: { $0.path == photo.path }) else { return }
        let cur = photosModel.photos[idx]
        photosModel.photos[idx] = PhotoItem(id: photo.id, path: photo.path, xmp: xmpMetadata,
                                            dateCreated: photo.dateCreated, dateModified: cur.dateModified,
                                            toDelete: cur.toDelete, hasACR: cur.hasACR, hasJPG: cur.hasJPG,
                                            inCameraRating: cur.inCameraRating, isRawFile: cur.isRawFile,
                                            fileSizeBytes: cur.fileSizeBytes, width: cur.width, height: cur.height,
                                            cameraMake: cur.cameraMake, cameraModel: cur.cameraModel)
        filesModel?.selectedPhoto = photosModel.photos[idx]
        onPhotoUpdated?()
    }

    // MARK: - XMP string helpers

    private func xmpUpdating(_ photo: PhotoItem, rating: Int?, label: String?) -> XmpMetadata {
        let e = photo.xmp
        return XmpMetadata(label: label, rating: rating, creator: e?.creator, rights: e?.rights,
                           createDate: e?.createDate, modifyDate: e?.modifyDate, cameraModel: e?.cameraModel,
                           lens: e?.lens, focalLength: e?.focalLength, aperture: e?.aperture,
                           shutterSpeed: e?.shutterSpeed, iso: e?.iso, exposureBias: e?.exposureBias)
    }

    private func updateXmpLabel(in xmpContent: String, newLabel: String?) -> String {
        var s = xmpContent
        let labelPattern = #"xmp:Label="[^"]*""#
        if let range = s.range(of: labelPattern, options: .regularExpression) {
            s.replaceSubrange(range, with: "xmp:Label=\"\(newLabel ?? "")\"")
        } else if let newLabel {
            let descPattern = #"(<rdf:Description[^>]*)"#
            if let match = s.range(of: descPattern, options: .regularExpression) {
                s.insert(contentsOf: "\n   xmp:Label=\"\(newLabel)\"", at: match.upperBound)
            }
        }
        // Update MetadataDate
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withTimeZone, .withColonSeparatorInTimeZone]
        iso.timeZone = TimeZone.current
        let now = iso.string(from: Date())
        let mdPattern = #"xmp:MetadataDate="[^"]*""#
        if let range = s.range(of: mdPattern, options: .regularExpression) {
            s.replaceSubrange(range, with: "xmp:MetadataDate=\"\(now)\"")
        } else {
            let descPattern = #"(<rdf:Description[^>]*)"#
            if let match = s.range(of: descPattern, options: .regularExpression) {
                s.insert(contentsOf: "\n   xmp:MetadataDate=\"\(now)\"", at: match.upperBound)
            }
        }
        return s
    }
}
