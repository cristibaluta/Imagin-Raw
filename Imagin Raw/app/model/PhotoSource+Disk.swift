//
//  DiskPhotoSource.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 16.04.2026.
//

import Foundation
import AVFoundation
import CryptoKit

struct DiskPhotoSource: PhotoSource {
    let path: String

    var cacheKey: String {
        let url = URL(fileURLWithPath: path)
        let dirHash = sha256Prefix(url.deletingLastPathComponent().path)
        return "\(dirHash)_\(url.lastPathComponent)"
    }

    func loadThumbnail(targetSize: CGFloat, completion: @escaping (IRImage?) -> Void) {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()

        if FilesExtensions.video.contains(ext) {
            completion(videoThumbnail(url: url, targetSize: targetSize))
            return
        }
        if FilesExtensions.raw.contains(ext) {
            guard let data = RawWrapper.shared().extractEmbeddedJPEG(path),
                  let img = IRImage(data: data) else {
                completion(nil)
                return
            }
            completion(img.resized(maxSize: targetSize))
            return
        }
        guard let img = IRImage(contentsOfFile: path) else {
            completion(nil)
            return
        }
        completion(img.resized(maxSize: targetSize))
    }

    func loadPreview(targetSize: CGFloat, completion: @escaping (IRImage?) -> Void) {
        let decoder = LibRawDecoder()
        let img = decoder.extractPreview(at: path, maxSize: targetSize)
        completion(img)
    }

    func loadFullRes(completion: @escaping (IRImage?) -> Void) {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        DispatchQueue.global(qos: .userInitiated).async {
            let image: IRImage?
            if FilesExtensions.raw.contains(ext) {
                image = CoreGraphicsDecoder().decodeFullRes(at: path)
            } else if let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                      let cg = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
                // Read EXIF orientation and apply it so HEIC/JPEG from iPhone
                // display in the correct portrait/landscape orientation.
                var orientation: Int32 = 1
                if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                   let o = props[kCGImagePropertyOrientation] as? Int32 {
                    orientation = o
                }
                let oriented = (orientation != 1) ? (cg.applyingOrientation(orientation) ?? cg) : cg
                image = IRImage(cgImage: oriented, size: IRSize(width: oriented.width, height: oriented.height))
            } else {
                image = nil
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    func loadExif() async -> ExifInfo? {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        if FilesExtensions.raw.contains(ext) {
            guard let raw = RawWrapper.shared().extractRawPhoto(path),
                  let dict = raw.exifData as? [String: Any] else {
                return nil
            }
            return ExifInfo.from(rawExif: dict)
        }
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

    private func sha256Prefix(_ string: String) -> String {
        let hash = SHA256.hash(data: Data(string.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(8).description
    }
}
