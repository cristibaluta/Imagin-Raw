//
//  JpegMetadataWriter.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 04.06.2026.
//
//  Writes XMP rating and label directly into JPEG/PNG/TIFF/HEIC metadata
//  using CGImageDestinationCopyImageSource — the compressed pixel data is
//  never decoded or re-encoded, only the metadata segments are rewritten.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

enum JpegMetadataWriter {

    struct Metadata {
        var rating: Int?   // 0 = clear, 1-5 = set
        var label: String? // nil = don't touch, "" = clear
    }

    // MARK: - Public API

    /// Read current embedded XMP rating and label from a file.
    static func readMetadata(from url: URL) -> Metadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let raw = CGImageSourceCopyMetadataAtIndex(source, 0, nil) else {
            return Metadata()
        }
        var result = Metadata()
        if let ratingTag = CGImageMetadataCopyTagWithPath(raw, nil, "xmp:Rating" as CFString),
           let val = CGImageMetadataTagCopyValue(ratingTag) as? String {
            result.rating = Int(val)
        }
        if let labelTag = CGImageMetadataCopyTagWithPath(raw, nil, "xmp:Label" as CFString),
           let val = CGImageMetadataTagCopyValue(labelTag) as? String {
            result.label = val
        }
        return result
    }

    /// Write rating and/or label into the file's embedded metadata without re-encoding.
    /// - Returns: `true` on success.
    @discardableResult
    static func write(_ metadata: Metadata, to url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            RCLog("❌ JpegMetadataWriter: cannot create source for \(url.lastPathComponent)")
            return false
        }

        // Read existing metadata (so we merge, not overwrite everything)
        let existingCG = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
        let mutable: CGMutableImageMetadata
        if let existing = existingCG,
           let copy = CGImageMetadataCreateMutableCopy(existing) {
            mutable = copy
        } else {
            mutable = CGImageMetadataCreateMutable()
        }

        // Register xmp namespace
        CGImageMetadataRegisterNamespaceForPrefix(
            mutable,
            "http://ns.adobe.com/xap/1.0/" as CFString,
            "xmp" as CFString,
            nil
        )

        // Write rating
        if let rating = metadata.rating {
            let value = rating > 0 ? "\(rating)" : "0"
            if let tag = CGImageMetadataTagCreate(
                "http://ns.adobe.com/xap/1.0/" as CFString,
                "xmp" as CFString,
                "Rating" as CFString,
                .string,
                value as CFTypeRef
            ) {
                CGImageMetadataSetTagWithPath(mutable, nil, "xmp:Rating" as CFString, tag)
            }
        }

        // Write label
        if let label = metadata.label {
            if let tag = CGImageMetadataTagCreate(
                "http://ns.adobe.com/xap/1.0/" as CFString,
                "xmp" as CFString,
                "Label" as CFString,
                .string,
                label as CFTypeRef
            ) {
                CGImageMetadataSetTagWithPath(mutable, nil, "xmp:Label" as CFString, tag)
            }
        }

        // Write to a temp file then atomically replace the original
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp")

        guard let uti = CGImageSourceGetType(source),
              let dest = CGImageDestinationCreateWithURL(tempURL as CFURL, uti, 1, nil) else {
            RCLog("❌ JpegMetadataWriter: cannot create destination for \(url.lastPathComponent)")
            return false
        }

        let options: [String: Any] = [
            kCGImageDestinationMetadata as String: mutable,
            kCGImageDestinationMergeMetadata as String: true
        ]

        var error: Unmanaged<CFError>?
        let ok = CGImageDestinationCopyImageSource(dest, source, options as CFDictionary, &error)
        if !ok {
            RCLog("❌ JpegMetadataWriter: CGImageDestinationCopyImageSource failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }

        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
            RCLog("✅ JpegMetadataWriter: wrote metadata to \(url.lastPathComponent)")
            return true
        } catch {
            RCLog("❌ JpegMetadataWriter: replace failed: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }
    }

    // MARK: - Helpers

    /// File extensions that support embedded metadata writing via ImageIO.
    static let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "tiff", "tif", "heic", "psd"]

    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
