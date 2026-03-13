//
//  ExportService.swift
//  Imagin Raw
//

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum ExportAspectRatio: String, CaseIterable, Identifiable {
    case r1x1      = "1:1"
    case r3x4      = "3:4"
    case r4x5      = "4:5"

    var id: String { rawValue }

    var ratio: CGFloat? {
        switch self {
        case .r1x1:     return 1.0
        case .r3x4:     return 3.0 / 4.0
        case .r4x5:     return 4.0 / 5.0
        }
    }
}

enum ExportAlignment: String, CaseIterable, Identifiable {
    case left   = "Left"
    case center = "Center"
    case right  = "Right"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .left:   return "align.horizontal.left"
        case .center: return "align.horizontal.center"
        case .right:  return "align.horizontal.right"
        }
    }
}

enum ExportService {

    /// Renders the source image onto a larger canvas with black bars and saves as PNG.
    /// - Parameters:
    ///   - sourcePath: original photo path (any format the app supports)
    ///   - targetRatio: desired aspect ratio (nil = keep original)
    ///   - padding: extra pixels to add around the longest side before fitting the ratio
    ///   - outputURL: destination PNG file
    static func export(
        sourcePath: String,
        targetRatio: ExportAspectRatio,
        padding: Int,
        alignment: ExportAlignment,
        outputURL: URL
    ) throws {

        guard let cgImage = loadCGImage(from: sourcePath) else {
            throw ExportError.imageLoadFailed
        }

        let srcW = CGFloat(cgImage.width)
        let srcH = CGFloat(cgImage.height)
        let pad = CGFloat(padding)
        let padded = CGSize(width: srcW + pad * 2, height: srcH + pad * 2)

        let canvas: CGSize
        if let ratio = targetRatio.ratio {
            let paddedRatio = padded.width / padded.height
            if paddedRatio > ratio {
                canvas = CGSize(width: padded.width, height: padded.width / ratio)
            } else if paddedRatio < ratio {
                canvas = CGSize(width: padded.height * ratio, height: padded.height)
            } else {
                canvas = padded
            }
        } else {
            canvas = padded
        }

        let intW = Int(canvas.width.rounded())
        let intH = Int(canvas.height.rounded())

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: intW, height: intH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw ExportError.contextCreationFailed
        }

        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: intW, height: intH))

        // Horizontal position based on alignment
        let x: CGFloat
        switch alignment {
        case .left:   x = pad
        case .center: x = (canvas.width - srcW) / 2
        case .right:  x = canvas.width - srcW - pad
        }
        let y = (canvas.height - srcH) / 2
        ctx.draw(cgImage, in: CGRect(x: x, y: y, width: srcW, height: srcH))

        guard let result = ctx.makeImage() else {
            throw ExportError.renderFailed
        }

        // Save as PNG
        guard let dest = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1, nil
        ) else {
            throw ExportError.destinationCreationFailed
        }
        CGImageDestinationAddImage(dest, result, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw ExportError.writeFailed
        }
    }

    // MARK: - Output URL

    static func outputURL(for sourcePath: String) -> URL {
        let source = URL(fileURLWithPath: sourcePath)
        let name = source.deletingPathExtension().lastPathComponent
        return source.deletingLastPathComponent()
            .appendingPathComponent("\(name)_export.png")
    }

    // MARK: - Image Loading

    private static func loadCGImage(from path: String) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()

        if FilesExtensions.raw.contains(ext) {
            guard let rawPhoto = RawWrapper.shared().extractRawPhoto(path),
                  let data = rawPhoto.imageData,
                  let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(src, 0, nil)
        } else {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(src, 0, nil)
        }
    }

    // MARK: - Errors

    enum ExportError: LocalizedError {
        case imageLoadFailed
        case contextCreationFailed
        case renderFailed
        case destinationCreationFailed
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .imageLoadFailed:          return "Could not load source image."
            case .contextCreationFailed:    return "Could not create graphics context."
            case .renderFailed:             return "Could not render image."
            case .destinationCreationFailed:return "Could not create output file."
            case .writeFailed:              return "Could not write PNG to disk."
            }
        }
    }
}
