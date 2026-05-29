//
//  PanasonicAFPoint.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 26.05.2026.
//


// PanasonicMakernoteParser.swift
//
// Pure Swift parser for Panasonic AF focus point data.
// No ImageIO, no ExifTool, no external dependencies.
//
// Reads binary JPEG/RW2 files directly, walks the TIFF/EXIF IFD tree,
// finds the Panasonic Makernote, and extracts:
//   - AFPointPosition  (tag 0x004D) → rational64u[2]: normalized cx, cy
//   - AFAreaSize       (tag 0x0109) → rational64u[2]: normalized width, height
//
// Spec sources:
//   https://exiftool.org/TagNames/Panasonic.html
//   https://exiv2.org/tags-panasonic.html
//   JEITA EXIF 2.32 spec (TIFF/IFD layout)

import Foundation

// MARK: - Public types

public struct PanasonicAFPoint {
    /// Normalized 0–1 center coordinates
    public let cx: Double
    public let cy: Double
    /// Normalized 0–1 box size (may be (0,0) if AFAreaSize tag absent)
    public let width:  Double
    public let height: Double
}

// MARK: - Top-level entry point

/// Parse a JPEG or RW2 file and return the Panasonic AF point if present.
public func parsePanasonicAFPoint(from url: URL) -> PanasonicAFPoint? {
    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
    return PanasonicMakernoteParser(data: data).parse()
}

// MARK: - Parser

private final class PanasonicMakernoteParser {

    private let data: Data

    init(data: Data) {
        self.data = data
    }

    func parse() -> PanasonicAFPoint? {
        // Detect file format and find the start of the TIFF header
        if isJPEG {
            return parseJPEG()
        } else if isRW2 {
            return parseTIFF(start: 0)   // RW2 is a TIFF variant; starts at byte 0
        }
        return nil
    }

    // MARK: - Format detection

    private var isJPEG: Bool { data.count > 2 && data[0] == 0xFF && data[1] == 0xD8 }
    private var isRW2:  Bool {
        // RW2 starts with TIFF magic: 0x4949 (LE) or 0x4D4D (BE) followed by 0x0055
        guard data.count > 4 else { return false }
        let magic = readUInt16(at: 0, bigEndian: false)
        return (magic == 0x4949 || magic == 0x4D4D) &&
               (readUInt16(at: 2, bigEndian: magic == 0x4D4D) == 0x0055 ||
                readUInt16(at: 2, bigEndian: magic == 0x4D4D) == 0x002A)
    }

    // MARK: - JPEG parsing

    /// Walk JPEG segments looking for APP1 (0xFFE1), which contains the EXIF/TIFF block.
    private func parseJPEG() -> PanasonicAFPoint? {
        var offset = 2  // skip SOI marker
        while offset + 4 <= data.count {
            guard data[offset] == 0xFF else { return nil }
            let marker = data[offset + 1]
            let length = Int(readUInt16(at: offset + 2, bigEndian: true))

            if marker == 0xE1 {   // APP1
                // APP1 payload starts at offset+4; check for "Exif\0\0" header
                if offset + 10 <= data.count,
                   data[offset + 4...offset + 9].elementsEqual([0x45,0x78,0x69,0x66,0x00,0x00]) {
                    let tiffStart = offset + 10
                    return parseTIFF(start: tiffStart)
                }
            }

            // Skip to next segment (length includes the 2-byte length field itself)
            offset += 2 + length
        }
        return nil
    }

    // MARK: - TIFF/IFD parsing

    private var bigEndian = false

    /// Parse a TIFF block starting at `start`, walk IFD0 → ExifIFD → MakerNote.
    private func parseTIFF(start: Int) -> PanasonicAFPoint? {
        guard start + 8 <= data.count else { return nil }

        let bom = readUInt16(at: start, bigEndian: false)
        guard bom == 0x4949 || bom == 0x4D4D else { return nil }
        bigEndian = (bom == 0x4D4D)

        let magic = readUInt16(at: start + 2)
        guard magic == 42 || magic == 85 else { return nil }

        let ifd0Offset = Int(readUInt32(at: start + 4))
        return parseRW2IFD0(tiffStart: start, ifdOffset: ifd0Offset)
    }

    private func parseRW2IFD0(tiffStart: Int, ifdOffset: Int) -> PanasonicAFPoint? {
        let abs = tiffStart + ifdOffset
        guard abs + 2 <= data.count else { return nil }

        let entryCount = Int(readUInt16(at: abs))
        for i in 0..<entryCount {
            let entryStart = abs + 2 + i * 12
            guard entryStart + 12 <= data.count else { break }
            let tag   = readUInt16(at: entryStart)
            let type  = readUInt16(at: entryStart + 2)
            let count = Int(readUInt32(at: entryStart + 4))
            let vOff  = entryStart + 8

            if tag == 0x002E {  // JpgFromRaw — embedded JPEG
                let (offset, _) = resolveOffset(valueOrOffset: vOff, type: type,
                                                count: count, tiffStart: tiffStart)
                RCLog(String(format: "Found JpgFromRaw at offset 0x%X, parsing embedded JPEG...", offset))
                // Parse the embedded JPEG blob directly from the RW2 data
                return parseJPEGAt(offset: offset)
            }
        }
        return nil
    }

    /// Parse a JPEG starting at an absolute byte offset within `data`.
    private func parseJPEGAt(offset: Int) -> PanasonicAFPoint? {
        guard offset + 2 <= data.count,
              data[offset] == 0xFF, data[offset + 1] == 0xD8
        else { return nil }

        var pos = offset + 2
        while pos + 4 <= data.count {
            guard data[pos] == 0xFF else { return nil }
            let marker = data[pos + 1]
            let length = Int(readUInt16(at: pos + 2, bigEndian: true))

            if marker == 0xE1, pos + 10 <= data.count,
               data[pos+4...pos+9].elementsEqual([0x45,0x78,0x69,0x66,0x00,0x00]) {
                let tiffStart = pos + 10
                // Reset endianness for the embedded JPEG's own TIFF block
                bigEndian = false
                return parseJPEGTIFF(start: tiffStart)
            }
            pos += 2 + length
        }
        return nil
    }

    /// Parse the TIFF block inside an embedded JPEG — walks IFD0 → ExifIFD → MakerNote.
    private func parseJPEGTIFF(start: Int) -> PanasonicAFPoint? {
        guard start + 8 <= data.count else { return nil }

        let bom = readUInt16(at: start, bigEndian: false)
        guard bom == 0x4949 || bom == 0x4D4D else { return nil }
        bigEndian = (bom == 0x4D4D)

        let ifd0Offset = Int(readUInt32(at: start + 4))
        return parseJPEGIFD0(tiffStart: start, ifdOffset: ifd0Offset)
    }

    private func parseJPEGIFD0(tiffStart: Int, ifdOffset: Int) -> PanasonicAFPoint? {
        let abs = tiffStart + ifdOffset
        guard abs + 2 <= data.count else { return nil }

        let entryCount = Int(readUInt16(at: abs))
        for i in 0..<entryCount {
            let entryStart = abs + 2 + i * 12
            guard entryStart + 12 <= data.count else { break }
            let tag  = readUInt16(at: entryStart)
            let vOff = entryStart + 8

            if tag == 0x8769 {  // ExifIFD
                let exifOffset = Int(readUInt32(at: vOff))
                return parseJPEGExifIFD(tiffStart: tiffStart, ifdOffset: exifOffset)
            }
        }
        return nil
    }

    private func parseJPEGExifIFD(tiffStart: Int, ifdOffset: Int) -> PanasonicAFPoint? {
        let abs = tiffStart + ifdOffset
        guard abs + 2 <= data.count else { return nil }

        let entryCount = Int(readUInt16(at: abs))
        for i in 0..<entryCount {
            let entryStart = abs + 2 + i * 12
            guard entryStart + 12 <= data.count else { break }
            let tag   = readUInt16(at: entryStart)
            let type  = readUInt16(at: entryStart + 2)
            let count = Int(readUInt32(at: entryStart + 4))
            let vOff  = entryStart + 8

            if tag == 0x927C {  // MakerNote
                let (mnOffset, mnLength) = resolveOffset(valueOrOffset: vOff, type: type,
                                                         count: count, tiffStart: tiffStart)
                return parseMakerNote(at: mnOffset, length: mnLength, tiffStart: tiffStart)
            }
        }
        return nil
    }

    private func parseMakerNote(at offset: Int, length: Int, tiffStart: Int) -> PanasonicAFPoint? {
        guard offset + 14 <= data.count else { return nil }
        // Verify "Panasonic\0\0\0" header
        for (i, byte) in panasonicHeader.enumerated() {
            guard data[offset + i] == byte else { return nil }
        }
        // IFD starts after 12-byte header; offsets are relative to makernote start
        return parseMakerNoteIFD(at: offset + 12, mnStart: offset)
    }

    private func parseMakerNoteIFD(at ifdOffset: Int, mnStart: Int) -> PanasonicAFPoint? {
        guard ifdOffset + 2 <= data.count else { return nil }

        let entryCount = Int(readUInt16(at: ifdOffset))
        guard entryCount < 512 else { return nil }

        var afPointPosition: (cx: Double, cy: Double)? = nil
        var afAreaSize:      (w: Double,  h: Double)?  = nil

        for i in 0..<entryCount {
            let entryStart = ifdOffset + 2 + i * 12
            guard entryStart + 12 <= data.count else { break }

            let tag   = readUInt16(at: entryStart)
            let type  = readUInt16(at: entryStart + 2)
            let count = Int(readUInt32(at: entryStart + 4))
            let vOff  = entryStart + 8
            RCLog(String(format: "IFD tag: 0x%04X", tag))
            switch tag {
            case 0x004D:  // AFPointPosition
                if type == 5 || type == 10, count >= 2 {
                    let dataOff = mnStart + Int(readUInt32(at: vOff))
                    if let cx = readRational(at: dataOff),
                       let cy = readRational(at: dataOff + 8),
                       cx > 0, cx < 1, cy > 0, cy < 1 {
                        afPointPosition = (cx, cy)
                    }
                }
            case 0x0109:  // AFAreaSize
                if type == 5 || type == 10, count >= 2 {
                    let dataOff = mnStart + Int(readUInt32(at: vOff))
                    if let w = readRational(at: dataOff),
                       let h = readRational(at: dataOff + 8),
                       w > 0, w <= 1, h > 0, h <= 1 {
                        afAreaSize = (w, h)
                    }
                }
            case 0x0126, 0x0127:  // ExifIFD pointer — follow it, Panasonic puts 0x004D in here on some models
                let subIFDOffset = mnStart + Int(readUInt32(at: vOff))
                RCLog(String(format: "Following ExifIFD at offset 0x%X", subIFDOffset))
                if let result = parseMakerNoteIFD(at: subIFDOffset, mnStart: mnStart) {
                    return result
                }
            default: break
            }

            if afPointPosition != nil && afAreaSize != nil { break }
        }

        guard let pos = afPointPosition else { return nil }
        return PanasonicAFPoint(cx: pos.cx, cy: pos.cy,
                                width:  afAreaSize?.w ?? 0.05,
                                height: afAreaSize?.h ?? 0.05)
    }

    private func parseIFD0(tiffStart: Int, ifdOffset: Int) -> PanasonicAFPoint? {
        let abs = tiffStart + ifdOffset
        guard abs + 2 <= data.count else { return nil }

        let entryCount = Int(readUInt16(at: abs))
        var exifIFDOffset: Int? = nil
        var makerNoteOffset: Int? = nil
        var makerNoteLength: Int = 0

        for i in 0..<entryCount {
            let entryStart = abs + 2 + i * 12
            guard entryStart + 12 <= data.count else { break }
            let tag    = readUInt16(at: entryStart)
            let type   = readUInt16(at: entryStart + 2)
            let count  = Int(readUInt32(at: entryStart + 4))
            let valueOrOffset = entryStart + 8  // 4-byte value-or-offset field
            RCLog(String(format: "IFD0 tag: 0x%04X", tag))
            switch tag {
            case 0x8769:   // ExifIFD pointer
                exifIFDOffset = Int(readUInt32(at: valueOrOffset))
            case 0x927C:   // MakerNote (sometimes appears in IFD0 on RW2)
                let (off, len) = resolveOffset(valueOrOffset: valueOrOffset,
                                               type: type, count: count,
                                               tiffStart: tiffStart)
                makerNoteOffset = off
                makerNoteLength = len
            default: break
            }
        }

        // Prefer MakerNote found directly; otherwise go through ExifIFD
        if let mnOff = makerNoteOffset {
            return parseMakerNote(at: mnOff, length: makerNoteLength, tiffStart: tiffStart)
        }
        if let exifOff = exifIFDOffset {
            return parseExifIFD(tiffStart: tiffStart, ifdOffset: exifOff)
        }
        return nil
    }

    private func parseExifIFD(tiffStart: Int, ifdOffset: Int) -> PanasonicAFPoint? {
        let abs = tiffStart + ifdOffset
        guard abs + 2 <= data.count else { return nil }

        let entryCount = Int(readUInt16(at: abs))
        for i in 0..<entryCount {
            let entryStart = abs + 2 + i * 12
            guard entryStart + 12 <= data.count else { break }
            let tag   = readUInt16(at: entryStart)
            let type  = readUInt16(at: entryStart + 2)
            let count = Int(readUInt32(at: entryStart + 4))
            let valueOrOffset = entryStart + 8
            RCLog(String(format: "tag: 0x%04X (%d)", tag, tag))
            if tag == 0x927C {  // MakerNote
                let (off, len) = resolveOffset(valueOrOffset: valueOrOffset,
                                               type: type, count: count,
                                               tiffStart: tiffStart)
                return parseMakerNote(at: off, length: len, tiffStart: tiffStart)
            }
        }
        return nil
    }

    // MARK: - Panasonic Makernote

    // Panasonic Makernote layout:
    //   Bytes 0–11 : ASCII header "Panasonic\0\0\0" (12 bytes)
    //   Bytes 12–13: IFD entry count (uint16, same endianness as outer TIFF)
    //   Bytes 14+  : IFD entries (12 bytes each), offsets relative to makernote start

    private let panasonicHeader: [UInt8] = [
        0x50,0x61,0x6E,0x61,0x73,0x6F,0x6E,0x69,0x63,0x00,0x00,0x00  // "Panasonic\0\0\0"
    ]

    private func parseMakerNoteOld(at offset: Int, length: Int, tiffStart: Int) -> PanasonicAFPoint? {
        guard offset + 14 <= data.count else { return nil }

        // Verify Panasonic header
        for (i, byte) in panasonicHeader.enumerated() {
            guard offset + i < data.count, data[offset + i] == byte else { return nil }
        }

        let mnStart   = offset          // makernote-relative offsets are from here
        let ifdStart  = offset + 12     // header is 12 bytes
        guard ifdStart + 2 <= data.count else { return nil }

        let entryCount = Int(readUInt16(at: ifdStart))
        guard entryCount < 512 else { return nil }  // sanity cap

        var afPointPosition: (cx: Double, cy: Double)?  = nil
        var afAreaSize:      (w:  Double, h:  Double)?  = nil

        for i in 0..<entryCount {
            let entryStart = ifdStart + 2 + i * 12
            guard entryStart + 12 <= data.count else { break }

            let tag   = readUInt16(at: entryStart)
            let type  = readUInt16(at: entryStart + 2)
            let count = Int(readUInt32(at: entryStart + 4))
            let vOff  = entryStart + 8

            switch tag {

            case 0x004D:  // AFPointPosition — rational64u[2]: cx, cy
                if type == 5 || type == 10, count >= 2 {
                    let dataOff = mnStart + Int(readUInt32(at: vOff))
                    if let cx = readRational(at: dataOff),
                       let cy = readRational(at: dataOff + 8),
                       cx > 0, cx < 1, cy > 0, cy < 1 {
                        afPointPosition = (cx, cy)
                    }
                }

            case 0x0109:  // AFAreaSize — rational64u[2]: width, height
                if type == 5 || type == 10, count >= 2 {
                    let dataOff = mnStart + Int(readUInt32(at: vOff))
                    if let w = readRational(at: dataOff),
                       let h = readRational(at: dataOff + 8),
                       w > 0, w <= 1, h > 0, h <= 1 {
                        afAreaSize = (w, h)
                    }
                }

            default: break
            }

            // Early exit once we have both
            if afPointPosition != nil && afAreaSize != nil { break }
        }

        guard let pos = afPointPosition else { return nil }

        return PanasonicAFPoint(
            cx:     pos.cx,
            cy:     pos.cy,
            width:  afAreaSize?.w  ?? 0.05,   // 5% fallback matches digiKam default
            height: afAreaSize?.h  ?? 0.05
        )
    }

    // MARK: - Binary read helpers

    /// Resolves a TIFF IFD value-or-offset field to an absolute file offset + byte length.
    /// If data fits in 4 bytes it is stored inline; otherwise the field is an offset into
    /// the TIFF block.
    private func resolveOffset(valueOrOffset: Int, type: UInt16,
                                count: Int, tiffStart: Int) -> (offset: Int, length: Int) {
        let byteSize = tiffTypeSize(type) * count
        if byteSize <= 4 {
            return (valueOrOffset, byteSize)
        } else {
            let off = tiffStart + Int(readUInt32(at: valueOrOffset))
            return (off, byteSize)
        }
    }

    private func tiffTypeSize(_ type: UInt16) -> Int {
        switch type {
        case 1, 2, 6, 7: return 1
        case 3, 8:        return 2
        case 4, 9, 11:    return 4
        case 5, 10, 12:   return 8
        default:          return 1
        }
    }

    /// Reads a TIFF rational (numerator uint32 / denominator uint32) as Double.
    private func readRational(at offset: Int) -> Double? {
        guard offset + 8 <= data.count else { return nil }
        let num = readUInt32(at: offset)
        let den = readUInt32(at: offset + 4)
        guard den != 0, num != 0xFFFFFFFF else { return nil }  // 0xFFFF/0xFFFF = "not set"
        return Double(num) / Double(den)
    }

    private func readUInt16(at offset: Int, bigEndian: Bool? = nil) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        let be = bigEndian ?? self.bigEndian
        let lo = UInt16(data[offset])
        let hi = UInt16(data[offset + 1])
        return be ? (lo << 8 | hi) : (hi << 8 | lo)
    }

    private func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])
        return bigEndian
            ? (b0 << 24 | b1 << 16 | b2 << 8 | b3)
            : (b3 << 24 | b2 << 16 | b1 << 8 | b0)
    }
}

// MARK: - Usage example
/*
let url = URL(fileURLWithPath: "/path/to/P1015143.RW2")
if let af = parsePanasonicAFPoint(from: url) {
    RCLog(String(format: "cx=%.4f cy=%.4f w=%.4f h=%.4f", af.cx, af.cy, af.width, af.height))
    // Expected from your exiftool output:
    //   cx=0.3600 cy=0.1600 w=0.2119 h=0.2832
}
*/
