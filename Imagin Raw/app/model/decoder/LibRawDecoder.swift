//
//  LibRawDecoder.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 24.07.2026.
//

import Foundation

struct LibRawDecoder: RawDecoder {

    func decodeFullRes(at url: URL) -> IRImage? {
        let t0 = Date()
        let img = RawWrapper.shared().extractFullResolution(url.absoluteString)
        RCLog("LibRaw decoded \(url.lastPathComponent) in \(String(format:"%.3f",-t0.timeIntervalSinceNow))s  success=\(img != nil)")
        return img
    }

    func extractPreview(at url: URL, maxSize: CGFloat) -> IRImage? {
        let filename = url.lastPathComponent
        let t0 = Date()

        // RAW: RawWrapper extracts embedded JPEG, then we apply orientation
        guard let data = RawWrapper.shared().extractEmbeddedJPEG(url.absoluteString) else {
            RCLog("extractEmbeddedJPEG failed \(filename)")
            return nil
        }
        RCLog("extractEmbeddedJPEG \(filename) in \(String(format:"%.3f", -t0.timeIntervalSinceNow))s  bytes=\(data.count)")
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let sourceCG = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        var exifOrientation: Int32 = 1
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let o = props[kCGImagePropertyOrientation] as? Int32 {
            exifOrientation = o
        }

        guard let cg = sourceCG else {
            return nil
        }
        guard let oriented = cg.applyingOrientation(exifOrientation) else {
            return nil
        }

        let srcW = CGFloat(oriented.width)
        let srcH = CGFloat(oriented.height)
        let maxDim = max(srcW, srcH)
        guard maxDim > maxSize else {
            return IRImage(cgImage: oriented, size: IRSize(width: oriented.width, height: oriented.height))
        }

        let scale = maxSize / maxDim
        let dstW = Int((srcW * scale).rounded())
        let dstH = Int((srcH * scale).rounded())
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil,
                                  width: dstW,
                                  height: dstH,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: cs,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return nil
        }
        ctx.interpolationQuality = .high
        ctx.draw(oriented, in: CGRect(x: 0, y: 0, width: dstW, height: dstH))

        guard let resized = ctx.makeImage() else {
            return nil
        }
        RCLog("Resized to \(dstW)×\(dstH) in \(String(format:"%.3f", -t0.timeIntervalSinceNow))s")
        return IRImage(cgImage: resized, size: IRSize(width: resized.width, height: resized.height))
    }

    func extractExif(at url: URL) -> ExifData? {
        guard let exifDict = RawWrapper.shared().extractExif(url) as? [String: Any] else {
            return nil
        }
        return ExifData(
            dateCaptured: exifDict["DateTime"] as? Date,
            width:        exifDict["width"] as? Int,
            height:       exifDict["height"] as? Int,
            cameraMake:   exifDict["Make"] as? String,
            cameraModel:  exifDict["Model"] as? String,
            lensModel:    exifDict["LensModel"] as? String,
            lensFocalLength:  (exifDict["FocalLength"] as? NSNumber)?.doubleValue,
            iso:          (exifDict["ISO"] as? NSNumber)?.intValue,
            aperture:     (exifDict["Aperture"] as? NSNumber)?.doubleValue,
            shutterSpeed: (exifDict["ShutterSpeed"] as? NSNumber)?.doubleValue,
            exposureCompensation: nil,
            rating: nil
        )
    }
}
