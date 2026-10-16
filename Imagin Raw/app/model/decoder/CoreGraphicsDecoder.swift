//
//  CoreGraphicsDecoder.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 24.07.2026.
//

import ImageIO
import CoreImage
import UniformTypeIdentifiers

struct CoreGraphicsDecoder: RawDecoder {

    func decodeFullRes(at url: URL) -> IRImage? {
        decodeFullRes(at: url, hasGainMap: FilesExtensions.hasGainMap(at: url))
    }

    /// - Parameter hasGainMap: Pass a pre-computed value (cached on `PhotoItem` from the EXIF
    ///   loading pass) to skip re-detecting the gain map on every decode call.
    func decodeFullRes(at url: URL, hasGainMap: Bool) -> IRImage? {
        let t0 = Date()
        let filename = url.lastPathComponent

        // Gain map (HDR) images need a different decode path to preserve the extended
        // dynamic range content — the regular ImageIO + CGContext path below flattens
        // everything to 8-bit sRGB, which would discard the gain map.
        if hasGainMap, let hdr = decodeGainMapImage(at: url, maxPixelSize: nil) {
            RCLog("HDR gain map \(filename) in \(String(format:"%.3f",-t0.timeIntervalSinceNow))s  \(hdr.width)×\(hdr.height)")
            return IRImage(cgImage: hdr, size: IRSize(width: hdr.width, height: hdr.height))
        }

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        // 1. Extract embedded full-size JPEG (~100-200ms)
        let fastOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 10000
        ] as CFDictionary
        if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, fastOptions) {
            let n = normalizeToSRGB(cg)
            RCLog("Embedded JPEG \(filename) in \(String(format:"%.3f",-t0.timeIntervalSinceNow))s  \(n.width)×\(n.height)")
            return IRImage(cgImage: n, size: IRSize(width: n.width, height: n.height))
        }

        // 2. Fallback: full demosaic (slower)
        let slowOptions = [
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: false
        ] as CFDictionary
        if let cg = CGImageSourceCreateImageAtIndex(src, 0, slowOptions) {
            let n = normalizeToSRGB(cg)
            RCLog("Full demosaic \(filename) in \(String(format:"%.3f",-t0.timeIntervalSinceNow))s  \(n.width)×\(n.height)")
            return IRImage(cgImage: n, size: IRSize(width: n.width, height: n.height))
        }

        RCLog("Decoder failed \(filename)")
        return nil
    }

    func extractPreview(at url: URL, maxSize: CGFloat) -> IRImage? {
        extractPreview(at: url, maxSize: maxSize, hasGainMap: FilesExtensions.hasGainMap(at: url))
    }

    /// - Parameter hasGainMap: Pass a pre-computed value (cached on `PhotoItem` from the EXIF
    ///   loading pass) to skip re-detecting the gain map on every decode call.
    func extractPreview(at url: URL, maxSize: CGFloat, hasGainMap: Bool) -> IRImage? {
        let t0 = Date()

        // Gain map (HDR) images: decode + downscale via CoreImage so the extended
        // dynamic range content is preserved (orientation is applied automatically too,
        // so we must NOT run this through applyingOrientation(_:) below, which would
        // flatten the gain map away via a plain CGContext draw).
        if hasGainMap, let hdr = decodeGainMapImage(at: url, maxPixelSize: maxSize) {
            RCLog("extractPreview (HDR) from \(url.lastPathComponent) in \(String(format:"%.3f", -t0.timeIntervalSinceNow))s")
            return IRImage(cgImage: hdr, size: IRSize(width: hdr.width, height: hdr.height))
        }

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        // 1. Extract the orientation
        var exifOrientation: Int32 = 1
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let o = props[kCGImagePropertyOrientation] as? Int32 {
            exifOrientation = o
        }
        // 2. Extract the preview
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: false, // we rotate ourselves below
            kCGImageSourceThumbnailMaxPixelSize: maxSize
        ] as CFDictionary

        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options) else {
            return nil
        }
        // 3. Apply the orientation
        guard let oriented = cg.applyingOrientation(exifOrientation) else {
            return nil
        }
        RCLog("extractPreview from \(url.lastPathComponent) in \(String(format:"%.3f", -t0.timeIntervalSinceNow))s")
        return IRImage(cgImage: oriented, size: IRSize(width: oriented.width, height: oriented.height))
    }

    func extractExif(at url: URL) -> ExifData? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            return nil
        }

        let exifDict = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let exifAuxDict = props[kCGImagePropertyExifAuxDictionary] as? [CFString: Any]
        let tiffDict = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

        // Camera make / model
        let cameraMake: String? = tiffDict?[kCGImagePropertyTIFFMake] as? String
        let cameraModel: String? = tiffDict?[kCGImagePropertyTIFFModel] as? String

        // Rating — IPTC StarRating first (Canon in-camera rating lives here)
        var rating: Int? = nil
        if let iptcDict = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any],
           let starRating = iptcDict["StarRating" as CFString] as? Int, starRating > 0 {
            rating = starRating
        }

        // Fallback: standard EXIF UserRating
        if rating == nil,
           let exifRating = exifDict?["UserRating" as CFString] as? Int, exifRating > 0 {
            rating = exifRating
        }

        // Capture date — EXIF DateTimeOriginal > DateTimeDigitized > TIFF DateTime
        var dateCaptured: Date? = nil
        let dateTimeStr = (exifDict?[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (exifDict?[kCGImagePropertyExifDateTimeDigitized] as? String)
            ?? (tiffDict?[kCGImagePropertyTIFFDateTime] as? String)

        if let dateTimeStr, !dateTimeStr.isEmpty {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy:MM:dd HH:mm:ss"
            fmt.locale = Locale(identifier: "en_US_POSIX")
            dateCaptured = fmt.date(from: dateTimeStr)
        }

        // TODO: width and height are not present in the lumix raws, they are nowhere in props
        // Resolution — swap width/height for 90°/270° EXIF orientation
        var width: Int? = nil
        var height: Int? = nil
        if let owidth = props[kCGImagePropertyPixelWidth] as? Int,
           let oheight = props[kCGImagePropertyPixelHeight] as? Int {
            let orientation = (props[kCGImagePropertyOrientation] as? Int) ?? 1
            if orientation >= 5 && orientation <= 8 {
                width = oheight
                height = owidth
            } else {
                width = owidth
                height = oheight
            }
        }

        // Lens model — try main EXIF dict first, then ExifAux (some cameras only populate one)
        let lensModel: String? = (exifDict?[kCGImagePropertyExifLensModel] as? String)
            ?? (exifAuxDict?[kCGImagePropertyExifAuxLensModel] as? String)

        // Focal length, in mm
        let lensFocalLength: Double? = exifDict?[kCGImagePropertyExifFocalLength] as? Double

        // ISO — reported as an array in EXIF (ISOSpeedRatings); take the first value
        let iso: Int? = (exifDict?[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first

        // Aperture — prefer FNumber (actual f-stop) over ApertureValue (APEX units)
        let aperture: Double? = exifDict?[kCGImagePropertyExifFNumber] as? Double

        // Shutter speed — prefer ExposureTime (actual seconds) over ShutterSpeedValue (APEX units)
        let shutterSpeed: Double? = exifDict?[kCGImagePropertyExifExposureTime] as? Double

        // Exposure compensation, in EV
        let exposureCompensation: Double? = exifDict?[kCGImagePropertyExifExposureBiasValue] as? Double

        return ExifData(dateCaptured: dateCaptured,
                        width: width,
                        height: height,
                        cameraMake: cameraMake,
                        cameraModel: cameraModel,
                        lensModel: lensModel,
                        lensFocalLength: lensFocalLength,
                        iso: iso,
                        aperture: aperture,
                        shutterSpeed: shutterSpeed,
                        exposureCompensation: exposureCompensation,
                        rating: rating)
    }

    /// Normalize any CGImage to sRGB + noneSkipLast (no alpha).
    private func normalizeToSRGB(_ cg: CGImage) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil,
                                  width: cg.width,
                                  height: cg.height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: cs,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return cg
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return ctx.makeImage() ?? cg
    }

    /// Decodes an image that contains an embedded HDR gain map (e.g. Apple ProRAW-derived HEIC,
    /// iPhone HDR photos, or Sony's 10-bit HIF), combining the base image with the gain map to
    /// produce a full extended-range image.
    /// EXIF orientation is applied automatically by CoreImage (`.applyOrientationProperty`), so
    /// the result must NOT be passed through `applyingOrientation(_:)` or `normalizeToSRGB(_:)`,
    /// both of which redraw into a plain 8-bit sRGB CGContext and would discard the gain map /
    /// extended range data.
    private func decodeGainMapImage(at url: URL, maxPixelSize: CGFloat?) -> CGImage? {
        guard var ciImage = CIImage(contentsOf: url, options: [
            .expandToHDR: true,
            .applyOrientationProperty: true
        ]) else {
            return nil
        }

        if let maxPixelSize {
            let longestEdge = max(ciImage.extent.width, ciImage.extent.height)
            if longestEdge > maxPixelSize {
                let scale = maxPixelSize / longestEdge
                ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
        }

        guard let extendedColorSpace = CGColorSpace(name: CGColorSpace.extendedSRGB) else {
            return nil
        }
        let context = CIContext(options: [.workingColorSpace: extendedColorSpace])
        return context.createCGImage(ciImage,
                                      from: ciImage.extent,
                                      format: .RGBAh,
                                      colorSpace: extendedColorSpace)
    }
}
