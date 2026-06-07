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
        // Enumerate all tags to find xmp:Rating and xmp:Label regardless of namespace registration
        CGImageMetadataEnumerateTagsUsingBlock(raw, nil, nil) { path, tag in
            let pathStr = path as String
            let value = CGImageMetadataTagCopyValue(tag)
            if pathStr.hasSuffix(":Rating") || pathStr == "Rating" {
                if let v = value as? String { result.rating = Int(v) }
                else if let v = value as? NSNumber { result.rating = v.intValue }
            } else if pathStr.hasSuffix(":Label") || pathStr == "Label" {
                if let v = value as? String, !v.isEmpty { result.label = v }
            }
            return true
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

    /// Dumps all metadata tags to the log for debugging.
    static func dumpMetadata(from url: URL) {
        RCLog("🔍 JpegMetadataWriter.dumpMetadata: \(url.lastPathComponent)")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            RCLog("  ❌ Cannot create image source")
            return
        }
        // Also dump top-level image properties (EXIF, IPTC, etc.)
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            RCLog("  📦 CGImageSourceCopyPropertiesAtIndex keys: \(props.keys.sorted())")
            for (key, val) in props.sorted(by: { $0.key < $1.key }) {
                if let dict = val as? [String: Any] {
                    RCLog("  [\(key)]:")
                    for (k2, v2) in dict.sorted(by: { $0.key < $1.key }) {
                        RCLog("    \(k2) = \(v2)")
                    }
                } else {
                    RCLog("  \(key) = \(val)")
                }
            }
        }
        // Dump CGImageMetadata tags (XMP)
        guard let raw = CGImageSourceCopyMetadataAtIndex(source, 0, nil) else {
            RCLog("  ⚠️ No CGImageMetadata found")
            return
        }
        RCLog("  📋 CGImageMetadata tags:")
        CGImageMetadataEnumerateTagsUsingBlock(raw, nil, nil) { path, tag in
            let ns   = CGImageMetadataTagCopyNamespace(tag) as String? ?? "?"
            let prefix = CGImageMetadataTagCopyPrefix(tag) as String? ?? "?"
            let name = CGImageMetadataTagCopyName(tag) as String? ?? "?"
            let value = CGImageMetadataTagCopyValue(tag)
            RCLog("    path=\(path)  ns=\(ns)  prefix=\(prefix)  name=\(name)  value=\(String(describing: value))")
            return true
        }
    }

    /// File extensions that support embedded metadata writing via ImageIO.
    static let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "tiff", "tif", "heic", "psd"]

    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
