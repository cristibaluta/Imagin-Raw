//
//  DiskPhotoSource.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 16.04.2026.
//

import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import CryptoKit

struct DiskPhotoSource: PhotoSource {
    let url: URL

    var cacheKey: String {
        let dirHash = sha256Prefix(url.deletingLastPathComponent().path)
        return "\(dirHash)_\(url.lastPathComponent)"
    }

    func loadThumbnail(targetSize: CGFloat) -> IRImage? {

        // Ensure the file is local (iCloud)
        guard ICloudDownloader.ensureDownloaded(at: url) else {
            return nil
        }

        let ext = url.pathExtension.lowercased()

        if FilesExtensions.video.contains(ext) {
            return videoThumbnail(url: url, targetSize: targetSize)
        }
        if FilesExtensions.raw.contains(ext), let thubnail = rawThumbnail(url: url, targetSize: targetSize) {
            return thubnail
        }
        return jpegThumbnail(url: url, targetSize: targetSize)
    }
    func loadThumbnail(targetSize: CGFloat, completion: @escaping (IRImage?) -> Void) {

    }

    func loadPreview(targetSize: CGFloat) -> IRImage? {
        let ext = url.pathExtension.lowercased()
        if FilesExtensions.raw.contains(ext) {
            return LibRawDecoder().extractPreview(at: url, maxSize: targetSize)
        } else {
            return CoreGraphicsDecoder().extractPreview(at: url, maxSize: targetSize)
        }
    }
    func loadPreview(targetSize: CGFloat, completion: @escaping (IRImage?) -> Void) {

    }

    func loadFullRes() -> IRImage? {
        let ext = url.pathExtension.lowercased()
        if FilesExtensions.raw.contains(ext) {
            return LibRawDecoder().decodeFullRes(at: url)
        } else {
            return CoreGraphicsDecoder().decodeFullRes(at: url)
        }
    }
    func loadFullRes(completion: @escaping (IRImage?) -> Void) {

    }

    func loadExif() async -> ExifInfo? {
        let ext = url.pathExtension.lowercased()
        if FilesExtensions.raw.contains(ext) {
            if let raw = RawWrapper.shared().extractRawPhoto(url),
                  let dict = raw.exifData as? [String: Any] {
                return ExifInfo.from(rawExif: dict)
            }
        }
        // Fallback to coregraphics exif reading
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            return nil
        }
        return ExifInfo.from(imageProperties: props)
    }

    // MARK: - Helpers

    private func videoThumbnail(url: URL, targetSize: CGFloat) -> IRImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: targetSize * 2, height: targetSize * 2)
        guard let cg = try? gen.copyCGImage(at: .zero, actualTime: nil) else {
            return nil
        }
        let img = IRImage(cgImage: cg, size: IRSize(width: cg.width, height: cg.height))
        return img.resized(maxSize: targetSize)
    }

    private func rawThumbnail(url: URL, targetSize: CGFloat) -> IRImage? {
        guard let data = RawWrapper.shared().extractEmbeddedJPEG(url.absoluteString),
              let img = IRImage(data: data) else {
            return nil
        }
        return img.resized(maxSize: targetSize)
    }

    private func jpegThumbnail(url: URL, targetSize: CGFloat) -> IRImage? {
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailFromImageAlways: false,
            kCGImageSourceThumbnailMaxPixelSize: Int(targetSize * 2)
        ]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOptions as CFDictionary) else {
            return nil
        }
        // Apply EXIF orientation — iPhone HEIC is often stored rotated
        var orientation: Int32 = 1
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let o = props[kCGImagePropertyOrientation] as? Int32 {
            orientation = o
        }
        let oriented = orientation != 1
            ? (thumbnail.applyingOrientation(orientation) ?? thumbnail)
            : thumbnail
        let img = IRImage(cgImage: oriented, size: IRSize(width: oriented.width, height: oriented.height))
        return img
    }

    private func sha256Prefix(_ string: String) -> String {
        let hash = SHA256.hash(data: Data(string.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(8).description
    }
}
