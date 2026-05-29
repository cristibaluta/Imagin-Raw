//
//  OlympusAFPoint.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 28.05.2026.
//

import Foundation

// MARK: - Public types

public struct OlympusAFPoint {
    /// Normalized 0–1 center coordinates (origin = top-left)
    public let cx: Double
    public let cy: Double
    /// Normalized 0–1 box size (may be a small default if size is unavailable)
    public let width:  Double
    public let height: Double
}

// MARK: - Top-level entry point

/// Parse an ORF (or JPEG) file and return the Olympus AF point if present.
public func parseOlympusAFPoint(from url: URL) -> OlympusAFPoint? {
    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
    return OlympusMakernoteParser(data: data).parse()
}

// MARK: - Parser

private final class OlympusMakernoteParser {

    private let data: Data
    private var bigEndian = false

    init(data: Data) {
        self.data = data
    }

    // MARK: - Entry point

    func parse() -> OlympusAFPoint? {
        if isJPEG {
            return parseJPEG()
        } else if isORF {
            return parseTIFF(start: 0)
        }
        return nil
    }

    // MARK: - Format detection

    private var isJPEG: Bool { data.count > 2 && data[0] == 0xFF && data[1] == 0xD8 }
    private var isORF:  Bool {
        guard data.count > 4 else { return false }
        let bom = u16(at: 0, be: false)
        guard bom == 0x4949 || bom == 0x4D4D else { return false }
        let magic = u16(at: 2, be: bom == 0x4D4D)
        return magic == 0x4F52  // "OR" — ORF magic
            || magic == 0x004F  // alternate
            || magic == 0x5352  // "SR" — some older Olympus
            || magic == 0x002A  // standard TIFF (some ORF files use this)
    }

    // MARK: - JPEG parsing

    private func parseJPEG() -> OlympusAFPoint? {
        var offset = 2  // skip SOI
        while offset + 4 <= data.count {
            guard data[offset] == 0xFF else { return nil }
            let marker = data[offset + 1]
            let length = Int(u16(at: offset + 2, be: true))
            if marker == 0xE1, offset + 10 <= data.count,
               data[(offset+4)...(offset+9)].elementsEqual([0x45,0x78,0x69,0x66,0x00,0x00]) {
                return parseTIFF(start: offset + 10)
            }
            offset += 2 + length
        }
        return nil
    }

    // MARK: - TIFF traversal

    private func parseTIFF(start: Int) -> OlympusAFPoint? {
        guard start + 8 <= data.count else { return nil }
        let bom = u16(at: start, be: false)
        guard bom == 0x4949 || bom == 0x4D4D else { return nil }
        bigEndian = (bom == 0x4D4D)
        // Olympus ORF uses magic 0x4F52; standard TIFF uses 0x002A — both are valid
        let ifd0Off = Int(u32(at: start + 4))
        return parseIFD0(tiffStart: start, ifdOffset: ifd0Off)
    }

    private func parseIFD0(tiffStart: Int, ifdOffset: Int) -> OlympusAFPoint? {
        let abs = tiffStart + ifdOffset
        guard abs + 2 <= data.count else { return nil }
        let count = Int(u16(at: abs))
        var exifOff: Int?
        var mnOff: Int?
        var mnLen = 0
        for i in 0..<count {
            let e = abs + 2 + i * 12
            guard e + 12 <= data.count else { break }
            let tag = u16(at: e); let type = u16(at: e+2); let cnt = Int(u32(at: e+4))
            switch tag {
            case 0x8769: exifOff = Int(u32(at: e+8))
            case 0x927C:
                let (off, len) = resolveOffset(vOff: e+8, type: type, count: cnt, base: tiffStart)
                mnOff = off; mnLen = len
            default: break
            }
        }
        if let mn = mnOff { return parseMakerNote(at: mn, length: mnLen, tiffStart: tiffStart) }
        if let exif = exifOff { return parseExifIFD(tiffStart: tiffStart, ifdOffset: exif) }
        return nil
    }

    private func parseExifIFD(tiffStart: Int, ifdOffset: Int) -> OlympusAFPoint? {
        let abs = tiffStart + ifdOffset
        guard abs + 2 <= data.count else { return nil }
        let count = Int(u16(at: abs))
        for i in 0..<count {
            let e = abs + 2 + i * 12
            guard e + 12 <= data.count else { break }
            let tag = u16(at: e); let type = u16(at: e+2); let cnt = Int(u32(at: e+4))
            if tag == 0x927C {
                let (off, len) = resolveOffset(vOff: e+8, type: type, count: cnt, base: tiffStart)
                return parseMakerNote(at: off, length: len, tiffStart: tiffStart)
            }
        }
        return nil
    }

    // MARK: - Olympus MakerNote

    // Olympus MakerNote formats:
    //   Newer (E-M series / OM series): "OLYMPUS\0II\x03\0" (12 bytes) then IFD
    //   Older (C/E series):             "OLYMP\0"           (6 bytes)  then standard TIFF IFD
    // In both cases offsets within the MN IFD are relative to the start of the MN.

    private let hdr12LE: [UInt8] = [
        0x4F,0x4C,0x59,0x4D,0x50,0x55,0x53,0x00,  // "OLYMPUS\0"
        0x49,0x49,0x03,0x00                          // "II" + 0x0003
    ]
    private let hdr12BE: [UInt8] = [
        0x4F,0x4C,0x59,0x4D,0x50,0x55,0x53,0x00,  // "OLYMPUS\0"
        0x4D,0x4D,0x00,0x03                          // "MM" + 0x0003
    ]
    private let hdr6:    [UInt8] = [
        0x4F,0x4C,0x59,0x4D,0x50,0x00               // "OLYMP\0"
    ]

    private func parseMakerNote(at offset: Int, length: Int, tiffStart: Int) -> OlympusAFPoint? {
        guard offset + 8 <= data.count else { return nil }

        // Dump first 20 bytes of the MakerNote so we can see the header
        let headerBytes = (0..<min(20, data.count-offset)).map { String(format: "%02X", data[offset+$0]) }.joined(separator: " ")
        RCLog("[OlympusAF] MakerNote at offset=\(offset), first 20 bytes: \(headerBytes)")

        let mnOrigin: Int  // start of "OLYMPUS\0"
        let mnBase:   Int  // base for resolving data offsets inside MN
        let ifdStart: Int  // where the IFD entry count lives

        // Detect which header variant
        if matchesBytes(hdr12LE, at: offset) || matchesBytes(hdr12BE, at: offset) {
            bigEndian = data[offset+8] == 0x4D
            mnOrigin = offset
            mnBase   = offset + 8   // "II"/"MM" position
            ifdStart = offset + 12  // IFD count immediately follows 12-byte header
            RCLog("[OlympusAF] Format: OLYMPUS+TIFF mnOrigin=\(mnOrigin) mnBase=\(mnBase) ifdStart=\(ifdStart)")
        } else if matchesBytes(hdr6, at: offset) {
            mnOrigin = offset; mnBase = offset; ifdStart = offset + 8
            RCLog("[OlympusAF] Format: OLYMP (older) ifdStart=\(ifdStart)")
        } else {
            mnOrigin = offset; mnBase = offset; ifdStart = offset
            RCLog("[OlympusAF] Format: unknown, trying ifdStart=\(ifdStart)")
        }

        RCLog("[OlympusAF] MN IFD count = \(ifdStart+2 <= data.count ? Int(u16(at: ifdStart)) : -1)")
        return parseMNTopIFD(at: ifdStart, mnOrigin: mnOrigin, mnBase: mnBase, tiffStart: tiffStart)
    }

    private func parseMNTopIFD(at ifdOffset: Int, mnOrigin: Int, mnBase: Int, tiffStart: Int) -> OlympusAFPoint? {
        guard ifdOffset + 2 <= data.count else { return nil }
        let count = Int(u16(at: ifdOffset))
        guard count > 0, count < 4096 else { RCLog("[OlympusAF] MN top count out of range: \(count)"); return nil }

        for i in 0..<count {
            let e = ifdOffset + 2 + i * 12
            guard e + 12 <= data.count else { break }
            let tag = u16(at: e); let type = u16(at: e+2); let cnt = Int(u32(at: e+4))
            let vOff = e + 8
            RCLog(String(format: "[OlympusAF] MN tag=0x%04X type=%d count=%d", tag, type, cnt))

            if tag == 0x2020 {
                let rawValue = Int(u32(at: vOff))
                // Try all three bases and print count at each to find the right one
                for (name, base) in [("tiffStart", tiffStart), ("mnOrigin", mnOrigin), ("mnBase", mnBase)] {
                    let cand = base + rawValue
                    let c = cand+2 <= data.count ? Int(u16(at: cand)) : -1
                    RCLog("[OlympusAF] 0x2020 base=\(name)(\(base)) rawVal=\(rawValue) → abs=\(cand) count=\(c)")
                }
                // Auto-pick whichever base gives a plausible count (1–511)
                var chosenOff = mnBase + rawValue
                for (_, base) in [("tiffStart", tiffStart), ("mnOrigin", mnOrigin), ("mnBase", mnBase)] {
                    let cand = base + rawValue
                    let c = cand+2 <= data.count ? Int(u16(at: cand)) : 0
                    if c > 0 && c < 512 { chosenOff = cand; break }
                }
                RCLog("[OlympusAF] → CameraSettings at \(chosenOff)")
                return parseCameraSettingsIFD(at: chosenOff, mnBase: mnOrigin)
            }
        }
        RCLog("[OlympusAF] 0x2020 not found"); return nil
    }

    private func parseCameraSettingsIFD(at ifdOffset: Int, mnBase: Int) -> OlympusAFPoint? {
        guard ifdOffset+2 <= data.count else { RCLog("[OlympusAF] CS out of bounds"); return nil }
        let count = Int(u16(at: ifdOffset))
        RCLog("[OlympusAF] CameraSettings count=\(count) at \(ifdOffset)")
        guard count > 0, count < 4096 else { RCLog("[OlympusAF] CS count out of range: \(count)"); return nil }

        var afTargetOff: Int?; var afTargetCount = 0
        var afSelectedOff: Int?; var afSelectedCount = 0

        for i in 0..<count {
            let e = ifdOffset + 2 + i * 12
            guard e + 12 <= data.count else { break }
            let tag = u16(at: e); let type = u16(at: e+2); let cnt = Int(u32(at: e+4)); let vOff = e+8
            switch tag {
            case 0x030a:
                let sz = typeSize(type) * cnt
                afTargetOff = sz <= 4 ? vOff : mnBase + Int(u32(at: vOff))
                afTargetCount = cnt
                RCLog(String(format: "[OlympusAF] AFTargetInfo count=%d off=0x%X", cnt, afTargetOff!))
            case 0x0305:
                let sz = typeSize(type) * cnt
                afSelectedOff = sz <= 4 ? vOff : mnBase + Int(u32(at: vOff))
                afSelectedCount = cnt
                RCLog(String(format: "[OlympusAF] AFPointSelected count=%d off=0x%X", cnt, afSelectedOff!))
            default: break
            }
        }

        // AFTargetInfo: int16u[10] → frameW, frameH, focusX, focusY, focusW, focusH
        if let off = afTargetOff, afTargetCount >= 6 {
            let fw = Double(u16(at: off)), fh = Double(u16(at: off+2))
            if fw > 0, fh > 0 {
                let x = Double(u16(at: off+4)), y = Double(u16(at: off+6))
                let w = Double(u16(at: off+8)), h = Double(u16(at: off+10))
                if w > 0, h > 0 {
                    let cx = (x + w/2) / fw, cy = (y + h/2) / fh
                    if cx > 0, cx < 1, cy > 0, cy < 1 {
                        RCLog(String(format: "[OlympusAF] AFTargetInfo → cx=%.4f cy=%.4f w=%.4f h=%.4f", cx, cy, w/fw, h/fh))
                        return OlympusAFPoint(cx: cx, cy: cy, width: w/fw, height: h/fh)
                    }
                }
            }
        }

        // AFPointSelected: rational64s[5] — [0]=mode, [1]=cx, [2]=cy, [3]=?, [4]=?
        // Each rational is pixel_coord / frame_dimension, giving a 0–1 fraction directly
        if let off = afSelectedOff, afSelectedCount >= 3 {
            // Debug: print raw rational values
            for idx in 0..<min(afSelectedCount, 5) {
                let rOff = off + idx * 8
                if rOff + 8 <= data.count {
                    let num = Int32(bitPattern: u32(at: rOff))
                    let den = Int32(bitPattern: u32(at: rOff + 4))
                    RCLog("[OlympusAF] AFPointSelected[\(idx)] num=\(num) den=\(den) → \(den != 0 ? Double(num)/Double(den) : 0)")
                }
            }
            // Index 1 = cx (x_pixel / frame_width), Index 2 = cy (y_pixel / frame_height)
            if let cx = readSignedRational(at: off + 8), let cy = readSignedRational(at: off + 16),
               cx > 0, cx < 1, cy > 0, cy < 1 {
                // For area size, use indices 3,4 if they differ from 1,2; otherwise default
                var nw = 0.05, nh = 0.05
                if afSelectedCount >= 5,
                   let x2 = readSignedRational(at: off + 24),
                   let y2 = readSignedRational(at: off + 32),
                   x2 > 0, y2 > 0 {
                    // If indices 3,4 differ from 1,2, they define the box extents
                    let diffW = abs(x2 - cx)
                    let diffH = abs(y2 - cy)
                    if diffW > 0.001 { nw = diffW * 2 }
                    if diffH > 0.001 { nh = diffH * 2 }
                }
                RCLog(String(format: "[OlympusAF] AFPointSelected → cx=%.4f cy=%.4f w=%.4f h=%.4f", cx, cy, nw, nh))
                return OlympusAFPoint(cx: cx, cy: cy, width: nw, height: nh)
            }
        }

        RCLog("[OlympusAF] AF position not available"); return nil
    }

    // MARK: - Binary helpers

    private func matchesBytes(_ pattern: [UInt8], at offset: Int) -> Bool {
        guard offset + pattern.count <= data.count else { return false }
        return pattern.enumerated().allSatisfy { data[offset + $0.offset] == $0.element }
    }

    private func resolveOffset(vOff: Int, type: UInt16, count: Int, base: Int) -> (Int, Int) {
        let size = typeSize(type) * count
        return size <= 4 ? (vOff, size) : (base + Int(u32(at: vOff)), size)
    }

    private func typeSize(_ type: UInt16) -> Int {
        switch type {
        case 1,2,6,7: return 1; case 3,8: return 2
        case 4,9,11:  return 4; case 5,10,12: return 8
        default: return 1
        }
    }

    private func readSignedRational(at offset: Int) -> Double? {
        guard offset+8 <= data.count else { return nil }
        let num = Int32(bitPattern: u32(at: offset))
        let den = Int32(bitPattern: u32(at: offset+4))
        guard den != 0 else { return nil }
        return Double(num) / Double(den)
    }

    private func u16(at offset: Int, be: Bool? = nil) -> UInt16 {
        guard offset+2 <= data.count else { return 0 }
        let isBE = be ?? bigEndian
        let lo = UInt16(data[offset]), hi = UInt16(data[offset+1])
        return isBE ? (lo<<8|hi) : (hi<<8|lo)
    }

    private func u32(at offset: Int) -> UInt32 {
        guard offset+4 <= data.count else { return 0 }
        let b0=UInt32(data[offset]),b1=UInt32(data[offset+1]),b2=UInt32(data[offset+2]),b3=UInt32(data[offset+3])
        return bigEndian ? (b0<<24|b1<<16|b2<<8|b3) : (b3<<24|b2<<16|b1<<8|b0)
    }
}

// MARK: - Usage example
/*
let url = URL(fileURLWithPath: "/path/to/PA140123.ORF")
if let af = parseOlympusAFPoint(from: url) {
    RCLog(String(format: "cx=%.4f cy=%.4f w=%.4f h=%.4f", af.cx, af.cy, af.width, af.height))
}
*/
