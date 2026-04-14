//
//  PhotoSource.swift
//  Imagin Raw
//
//  Common interface for loading thumbnail images, preview images, and EXIF
//  from either a local disk file or a PhotoKit asset.
//
//  ThumbsManager and PreviewsManager instantiate the right source depending
//  on what PhotoItem they receive. All caching lives in the managers.
//

import Foundation
import ImageIO
import Photos
import CryptoKit
import AVFoundation

// MARK: - Protocol

/// Knows how to fetch a thumbnail, a preview, and EXIF for a single photo.
/// Implementations must be thread-safe — they are called from background queues.
protocol PhotoSource {
    /// A stable string key used for both memory and disk caching.
    var cacheKey: String { get }

    /// Load a thumbnail image (short edge ≤ targetSize) and call completion on any thread.
    func loadThumbnail(targetSize: CGFloat, completion: @escaping (IRImage?) -> Void)

    /// Load a preview image (short edge ≤ targetSize) and call completion on any thread.
    func loadPreview(targetSize: CGFloat, completion: @escaping (IRImage?) -> Void)

    /// Load EXIF metadata asynchronously.
    func loadExif() async -> ExifInfo?
}

// MARK: - Disk source

/// Handles any file that lives on disk (RAW, JPEG, HEIF, video, …).
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
}

// MARK: - PhotoKit source

/// Handles assets that come from the Photos library via PHAsset.
struct PhotoKitPhotoSource: PhotoSource {
    let asset: PHAsset
    /// The path stored on PhotoItem (localIdentifier[/filename]) used as cache key.
    let photoPath: String

    var cacheKey: String {
        let url = URL(fileURLWithPath: photoPath)
        let dirHash = sha256Prefix(url.deletingLastPathComponent().path)
        return "\(dirHash)_\(url.lastPathComponent)"
    }

    func loadThumbnail(targetSize: CGFloat, completion: @escaping (IRImage?) -> Void) {
        let size = CGSize(width: targetSize * 2, height: targetSize * 2)
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            guard let image else {
                return
            }
            completion(image)
        }
    }

    func loadPreview(targetSize: CGFloat, completion: @escaping (IRImage?) -> Void) {
        let size = CGSize(width: targetSize * 2, height: targetSize * 2)
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            guard let image, !degraded else {
                if image == nil {
                    completion(nil)
                }
                return
            }
            completion(image)
        }
    }

    func loadExif() async -> ExifInfo? {
        return await withCheckedContinuation { cont in
            let opts = PHContentEditingInputRequestOptions()
            opts.isNetworkAccessAllowed = true
            asset.requestContentEditingInput(with: opts) { input, _ in
                guard let url = input?.fullSizeImageURL,
                      let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: ExifInfo.from(imageProperties: props))
            }
        }
    }
}

// MARK: - Factory

extension PhotoItem {
    /// Returns the appropriate PhotoSource for this item.
    func makeSource() -> PhotoSource {
        if let asset = phAsset {
            return PhotoKitPhotoSource(asset: asset, photoPath: path)
        }
        return DiskPhotoSource(path: path)
    }
}

// MARK: - Shared hash helper

private func sha256Prefix(_ string: String) -> String {
    let hash = SHA256.hash(data: Data(string.utf8))
    return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(8).description
}
