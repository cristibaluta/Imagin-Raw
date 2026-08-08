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
import QuickLookThumbnailing

struct DiskPhotoSource: PhotoSource {
    let url: URL

    var cacheKey: String {
        let dirHash = sha256Prefix(url.deletingLastPathComponent().path)
        return "\(dirHash)_\(url.lastPathComponent)"
    }

    func loadThumbnail(targetSize: CGFloat) async -> IRImage? {

        // Ensure the file is local (iCloud)
        guard ICloudDownloader.ensureDownloaded(at: url) else {
            return nil
        }
        if FilesExtensions.isMovieFile(url) {
            return videoThumbnail(url: url, targetSize: targetSize)
        }
        if FilesExtensions.isRawImageFile(url), let thubnail = rawThumbnail(url: url, targetSize: targetSize) {
            return thubnail
        }
        if FilesExtensions.isSvgFile(url) {
            return svgThumbnail(url: url, maxSize: targetSize)
        }
        if FilesExtensions.isAffinityFile(url) {
            return affinityThumbnail(url: url, maxSize: targetSize)
        }
        if url.pathExtension == "nc" {
            return ncPreview(url: url)
        }
        if url.pathExtension == "stl" {
            return await extractSTLPreview(from: url)
        }
        return jpegThumbnail(url: url, targetSize: targetSize)
    }

    func loadThumbnail(targetSize: CGFloat, completion: @escaping (IRImage?) -> Void) {

    }

    func loadPreview(targetSize: CGFloat) async -> IRImage? {
        if FilesExtensions.isRawImageFile(url) {
            return LibRawDecoder().extractPreview(at: url, maxSize: targetSize)
        } else if FilesExtensions.isSvgFile(url) {
            return svgThumbnail(url: url, maxSize: targetSize)
        } else if FilesExtensions.isAffinityFile(url) {
            return affinityThumbnail(url: url, maxSize: targetSize)
        } else if url.pathExtension == "nc" {
            return ncPreview(url: url)
        } else if url.pathExtension == "stl" {
            return await extractSTLPreview(from: url, size: CGSize(width: targetSize, height: targetSize))
        } else {
            return CoreGraphicsDecoder().extractPreview(at: url, maxSize: targetSize)
        }
    }

    func loadPreview(targetSize: CGFloat, completion: @escaping (IRImage?) -> Void) {

    }

    func loadFullRes() -> IRImage? {
        if FilesExtensions.isRawImageFile(url) {
            return LibRawDecoder().decodeFullRes(at: url)
        } else {
            return CoreGraphicsDecoder().decodeFullRes(at: url)
        }
    }

    func loadFullRes(completion: @escaping (IRImage?) -> Void) {

    }

    func loadExif() async -> ExifData? {
        return nil
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
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            RCLog("Failed to create CGImageSource for \(url.lastPathComponent)")
            return nil
        }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailFromImageAlways: false,
            kCGImageSourceThumbnailMaxPixelSize: Int(targetSize * 2)
        ]

        var thumbnail: CGImage?
        thumbnail = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOptions as CFDictionary)

        if thumbnail == nil {
            // Fallback for images that do not embed a thumbnail
            let thumbOptions: [CFString: Any] = [
                kCGImageSourceShouldCacheImmediately: false,
                kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(targetSize * 2)
            ]
            thumbnail = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOptions as CFDictionary)
        }

        guard let thumbnail else {
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

    private func svgThumbnail(url: URL, maxSize: CGFloat) -> IRImage? {
        guard let image = IRImage(contentsOf: url) else {
            return nil
        }

        // NSImage loaded from SVG reports its intrinsic/viewBox size;
        // rasterize it into a bitmap at the target resolution.
        let aspectRatio = image.size.width / image.size.height
        let targetSize: IRSize
        if aspectRatio > 1 {
            targetSize = IRSize(width: maxSize, height: maxSize / aspectRatio)
        } else {
            targetSize = IRSize(width: maxSize * aspectRatio, height: maxSize)
        }

        #if os(macOS)
        let rasterized = IRImage(size: targetSize)
        rasterized.lockFocus()
        image.draw(in: IRRect(origin: .zero, size: targetSize),
                   from: IRRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        rasterized.unlockFocus()
        #elseif os(iOS)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let rasterized = renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: targetSize),
                       blendMode: .copy,
                       alpha: 1.0)
        }
        #endif

        return rasterized
    }

    private func affinityThumbnail(url: URL, maxSize: CGFloat) -> IRImage? {
        // TODO: using quicklook to extract the thumbnail returns error 102
        let resultImage = extractAnyAffinityPreview(from: url)
        return resultImage
    }

    func extractAnyAffinityPreview(from fileURL: URL) -> IRImage? {
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer {
            try? fileHandle.close()
        }

        guard let fileSize = try? fileHandle.seekToEnd(), fileSize > 0 else {
            return nil
        }

        // Read the last 15 Megabytes where the preview is trailing
        let bufferSize = min(fileSize, UInt64(15 * 1024 * 1024))
        guard (try? fileHandle.seek(toOffset: fileSize - bufferSize)) != nil else {
            return nil
        }
        guard let buffer = try? fileHandle.read(upToCount: Int(bufferSize)) else {
            return nil
        }

        // Magic Byte Signatures
        let pngStart = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) // \x89PNG
        let pngEnd   = "IEND".data(using: .ascii)!

        let jpegStart = Data([0xFF, 0xD8, 0xFF]) // SOI (Start of Image)
        let jpegEnd   = Data([0xFF, 0xD9])       // EOI (End of Image)

        // 1. Try PNG Scanning First
        if let startRange = buffer.range(of: pngStart, options: .backwards, in: 0..<buffer.count),
           let endRange = buffer.range(of: pngEnd, options: .backwards, in: startRange.upperBound..<buffer.count) {

            let totalLength = (endRange.upperBound + 4) - startRange.lowerBound // Add 4 bytes for IEND chunk CRC
            let pngData = buffer.subdata(in: startRange.lowerBound..<(startRange.lowerBound + totalLength))
            return IRImage(data: pngData)
        }

        // 2. Fallback to JPEG Scanning (Crucial for modern .af formats)
        if let startRange = buffer.range(of: jpegStart, options: .backwards, in: 0..<buffer.count),
           let endRange = buffer.range(of: jpegEnd, options: .backwards, in: startRange.upperBound..<buffer.count) {

            let totalLength = endRange.upperBound - startRange.lowerBound
            let jpegData = buffer.subdata(in: startRange.lowerBound..<(startRange.lowerBound + totalLength))
            return IRImage(data: jpegData)
        }

        RCLog("No valid embedded PNG or JPEG stream located in file trailing block.")
        return nil
    }

    private func ncPreview(url: URL) -> IRImage? {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer {
            try? fileHandle.close()
        }

        let beginMarker = ";(thumbnail_image_begin)"
        let endMarker = ";(thumbnail_image_end)"

        var base64String = ""
        var isCollecting = false
        var foundEnd = false

        // Read the file in chunks and split into lines manually, since .nc files
        // can be large and we want to bail out as soon as the end marker is hit
        // rather than loading the whole file into memory.
        let chunkSize = 64 * 1024
        var leftover = ""

        while !foundEnd {
            guard let chunk = try? fileHandle.read(upToCount: chunkSize), !chunk.isEmpty else {
                break
            }
            guard let chunkString = String(data: chunk, encoding: .utf8) else {
                // Fall back to ASCII if the file isn't strictly UTF-8
                guard let asciiString = String(data: chunk, encoding: .ascii) else {
                    return nil
                }
                leftover += asciiString
                continue
            }
            leftover += chunkString

            var lines = leftover.components(separatedBy: .newlines)
            // Keep the last (possibly incomplete) line for the next chunk
            leftover = lines.removeLast()

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                if trimmed == endMarker {
                    foundEnd = true
                    break
                }

                if isCollecting {
                    // Strip the leading ";" comment prefix before appending
                    if trimmed.hasPrefix(";") {
                        base64String += trimmed.dropFirst()
                    } else {
                        base64String += trimmed
                    }
                } else if trimmed == beginMarker {
                    isCollecting = true
                }
            }
        }

        // Handle end marker if it landed in the final leftover fragment
        if !foundEnd {
            let trimmed = leftover.trimmingCharacters(in: .whitespaces)
            if isCollecting && trimmed == endMarker {
                foundEnd = true
            } else if isCollecting && !trimmed.isEmpty {
                base64String += trimmed.hasPrefix(";") ? String(trimmed.dropFirst()) : trimmed
            }
        }

        guard !base64String.isEmpty else {
            RCLog("No thumbnail_image markers found in .nc file: \(url.lastPathComponent)")
            return nil
        }

        guard let imageData = Data(base64Encoded: base64String) else {
            RCLog("Failed to decode base64 thumbnail in .nc file: \(url.lastPathComponent)")
            return nil
        }

        return IRImage(data: imageData)
    }

    func extractSTLPreview(from url: URL, size: CGSize = CGSize(width: 1024, height: 1024)) async -> IRImage? {
        let scale = await MainActor.run {
            NSScreen.main?.backingScaleFactor ?? 2.0
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail // we only actually want the real thumbnail, not the icon
        )

        return await withCheckedContinuation { continuation in
            var didResume = false
            let resumeOnce: (IRImage?) -> Void = { image in
                guard !didResume else {
                    return
                }
                guard let image else {
                    return
                }
                didResume = true
                continuation.resume(returning: image)
            }

            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, error in
                if let error {
                    RCLog("QuickLook thumbnail generation failed for \(url.lastPathComponent): \(error)")
                    resumeOnce(nil)
                    return
                }
                guard let nsImage = representation?.nsImage else {
                    resumeOnce(nil)
                    return
                }
                resumeOnce(IRImage(data: nsImage.tiffRepresentation ?? Data()))
            }
        }
    }

    private func sha256Prefix(_ string: String) -> String {
        let hash = SHA256.hash(data: Data(string.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(8).description
    }
}
