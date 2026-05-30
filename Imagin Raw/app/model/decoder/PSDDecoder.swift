//
//  PSDDecoder.swift
//  Imagin Raw
//
//  Extracts embedded thumbnails from PSD/PSB files by parsing the
//  Image Resources section. No external libraries required.
//
//  PSD structure:
//    [Header 26b][Color Mode Data][Image Resources][Layer & Mask][Image Data]
//
//  Thumbnail resource IDs:
//    0x0409 (1033) — Photoshop 4.0 (BGR, obsolete)
//    0x040C (1036) — Photoshop 5.0+ (RGB, preferred)
//
//  Thumbnail resource data layout (after the 8BIM block header):
//    format        4b  (1 = JPEG)
//    width         4b
//    height        4b
//    widthBytes    4b
//    totalSize     4b
//    compressedSize 4b
//    bitsPerPixel  2b
//    planes        2b
//    data          compressedSize bytes  (JPEG)
//

import Foundation
import CoreGraphics
import ImageIO

struct PSDDecoder {

    // MARK: - Public

    /// Extract the embedded JPEG thumbnail from a PSD/PSB file.
    /// Returns raw JPEG bytes on success, nil if the file has no thumbnail resource.
    static func extractThumbnailData(at path: String) -> Data? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else {
            return nil
        }
        return extractThumbnailData(from: data)
    }

    /// Decode the embedded thumbnail and return a resized IRImage.
    static func thumbnail(at path: String, maxSize: CGFloat) -> IRImage? {
        guard let jpegData = extractThumbnailData(at: path),
              let src = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(maxSize * 2)
              ] as CFDictionary) else {
            return nil
        }
        let img = IRImage(cgImage: cg, size: IRSize(width: cg.width, height: cg.height))
        return img.resized(maxSize: maxSize)
    }

    /// Decode the full PSD (composite image) via ImageIO as a full-res IRImage.
    static func fullRes(at path: String) -> IRImage? {
        let url = URL(fileURLWithPath: path)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, [
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceShouldAllowFloat: false
              ] as CFDictionary) else {
            return nil
        }
        return IRImage(cgImage: cg, size: IRSize(width: cg.width, height: cg.height))
    }

    // MARK: - Private Parsing

    private static func extractThumbnailData(from data: Data) -> Data? {
        let count = data.count
        guard count > 26 else { return nil }

        // Validate "8BPS" signature
        guard data[0] == 0x38, data[1] == 0x42,
              data[2] == 0x50, data[3] == 0x53 else { return nil }

        let isPSB = data[4] == 0x00 && data[5] == 0x02  // version 2 = PSB

        var offset = 26

        // Skip Color Mode Data section
        guard offset + 4 <= count else { return nil }
        let colorModeLen = Int(readU32BE(data, at: offset))
        offset += 4 + colorModeLen

        // Image Resources section
        guard offset + 4 <= count else { return nil }
        let imageResourcesLen = Int(readU32BE(data, at: offset))
        offset += 4

        let imageResourcesEnd = offset + imageResourcesLen
        guard imageResourcesEnd <= count else { return nil }

        // Walk resource blocks looking for 0x040C (preferred) or 0x0409 (fallback)
        var thumbnailOffset: Int? = nil
        var thumbnailResourceID: UInt16 = 0

        while offset + 12 <= imageResourcesEnd {
            // 8BIM signature
            guard data[offset] == 0x38, data[offset+1] == 0x42,
                  data[offset+2] == 0x49, data[offset+3] == 0x4D else {
                break  // malformed
            }
            offset += 4

            let resourceID = readU16BE(data, at: offset)
            offset += 2

            // Pascal string (length byte + chars, padded to even)
            let nameLen = Int(data[offset])
            offset += 1 + nameLen
            if (nameLen + 1) % 2 != 0 { offset += 1 }  // pad to even

            guard offset + 4 <= imageResourcesEnd else { break }
            let dataLen = Int(readU32BE(data, at: offset))
            offset += 4

            let dataStart = offset
            // Pad data length to even
            let paddedLen = dataLen + (dataLen % 2)

            if resourceID == 0x040C || (resourceID == 0x0409 && thumbnailOffset == nil) {
                thumbnailOffset = dataStart
                thumbnailResourceID = resourceID
            }

            offset += paddedLen
        }

        guard let thumbStart = thumbnailOffset else { return nil }

        // Parse thumbnail resource header (20 bytes)
        guard thumbStart + 28 <= count else { return nil }
        let format = readU32BE(data, at: thumbStart)
        guard format == 1 else { return nil }  // 1 = JPEG

        let compressedSize = Int(readU32BE(data, at: thumbStart + 20))
        let jpegStart = thumbStart + 28

        guard jpegStart + compressedSize <= count else { return nil }

        return data.subdata(in: jpegStart ..< jpegStart + compressedSize)
    }

    // MARK: - Byte Helpers

    private static func readU32BE(_ data: Data, at offset: Int) -> UInt32 {
        return (UInt32(data[offset]) << 24)
             | (UInt32(data[offset+1]) << 16)
             | (UInt32(data[offset+2]) << 8)
             |  UInt32(data[offset+3])
    }

    private static func readU16BE(_ data: Data, at offset: Int) -> UInt16 {
        return (UInt16(data[offset]) << 8) | UInt16(data[offset+1])
    }
}
