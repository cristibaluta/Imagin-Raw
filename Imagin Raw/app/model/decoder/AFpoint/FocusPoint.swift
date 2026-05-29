// PanasonicFocusPointExtractor.swift
//
// Extracts AF focus point data from Panasonic Lumix JPEG files.
//
// On Apple platforms, ImageIO decodes the Panasonic Makernote and surfaces
// the AF data under the "{ExifAux}" dictionary key "AFInfo" as a 5-element array:
//   [0] centerX   (Double, normalized 0.0–1.0)
//   [1] centerY   (Double, normalized 0.0–1.0)
//   [2] width     (Double, normalized)
//   [3] height    (Double, normalized)
//   [4] inFocus   (String "t"/"f" or Int 1/0)
//
// Requires: ImageIO (iOS 13+ / macOS 10.15+). No CoreImage needed.
//
// Usage:
//   let extractor = PanasonicFocusPointExtractor(url: imageURL)
//   if let result = extractor.extract() {
//       for point in result.focusPoints {
//           let rect = point.rect(in: imageSize)   // CGRect ready to draw
//       }
//   }

import Foundation
import ImageIO
import CoreGraphics

// MARK: - Data model

/// A single AF focus area in normalized image coordinates (0.0–1.0).
public struct FocusPoint: Equatable, CustomStringConvertible {
    /// Center X: 0.0 = left edge, 1.0 = right edge
    public let centerX: Double
    /// Center Y: 0.0 = top edge, 1.0 = bottom edge
    public let centerY: Double
    /// Width as fraction of image width
    public let width: Double
    /// Height as fraction of image height
    public let height: Double
    /// True if the camera locked focus on this point
    public let isInFocus: Bool

    public var description: String {
        String(format: "FocusPoint(cx=%.4f cy=%.4f w=%.4f h=%.4f inFocus=%@)",
               centerX, centerY, width, height, isInFocus ? "true" : "false")
    }

    /// Returns a CGRect ready to draw as a focus overlay on an image of the given pixel size.
    public func rect(in imageSize: CGSize) -> CGRect {
        CGRect(
            x:      (centerX - width  / 2.0) * imageSize.width,
            y:      (centerY - height / 2.0) * imageSize.height,
            width:  width  * imageSize.width,
            height: height * imageSize.height
        )
    }
}

/// All focus-related data extracted from a Panasonic image.
public struct PanasonicFocusResult {
    /// Image pixel dimensions (from EXIF, may differ from file dimensions for cropped exports)
    public let imageWidth:  Int
    public let imageHeight: Int
    /// Extracted focus points; usually one, but multi-point or face-detect modes can yield more
    public let focusPoints: [FocusPoint]
}

// MARK: - Extractor

public final class PanasonicFocusPointExtractor {

    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Returns nil if the file cannot be opened, is not a Panasonic file,
    /// or contains no usable AF data.
    public func extract() -> PanasonicFocusResult? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let props  = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return nil }

        guard isPanasonic(props: props) else { return nil }

        // Image dimensions — prefer the full-resolution PixelWidth/PixelHeight at the top
        // level, which reflect the actual sensor output. The Exif PixelXDimension values
        // seen in your dump (1920×1440) correspond to the embedded JPEG preview, not the
        // full 5776×4336 raw capture.
        let imageWidth  = props["PixelWidth"]  as? Int ?? 0
        let imageHeight = props["PixelHeight"] as? Int ?? 0

        var focusPoints: [FocusPoint] = []

        // ── Primary source: {ExifAux} → AFInfo ─────────────────────────────────────
        // Apple's ImageIO decodes the Panasonic Makernote AFPointPosition tag (0x004D)
        // into a clean 5-element array here. This is what your DC-G9M2 produces.
        if let exifAux = props["{ExifAux}"] as? [String: Any],
           let afInfo  = exifAux["AFInfo"] as? [Any] {
            if let point = focusPointFromAFInfo(afInfo) {
                focusPoints.append(point)
            }
        }

        // ── Fallback: scan all ImageIO-decoded top-level dicts for AFInfo ──────────
        // Some camera/OS combinations may nest it differently.
        if focusPoints.isEmpty {
            for value in props.values {
                if let dict = value as? [String: Any],
                   let afInfo = dict["AFInfo"] as? [Any],
                   let point  = focusPointFromAFInfo(afInfo) {
                    focusPoints.append(point)
                    break
                }
            }
        }

        guard !focusPoints.isEmpty else { return nil }
        RCLog(focusPoints)
        return PanasonicFocusResult(
            imageWidth:  imageWidth,
            imageHeight: imageHeight,
            focusPoints: focusPoints
        )
    }

    // MARK: - Private helpers

    /// Verifies the Make tag is Panasonic (or Leica, which shares the Makernote format).
    private func isPanasonic(props: [String: Any]) -> Bool {
        guard let tiff = props["{TIFF}"] as? [String: Any],
              let make = tiff["Make"] as? String
        else { return false }
        let m = make.uppercased()
        return m.contains("PANASONIC") || m.contains("LEICA")
    }

    /// Parses the 5-element AFInfo array that ImageIO surfaces from the Panasonic Makernote.
    ///
    /// Layout (confirmed from your DC-G9M2 dump):
    ///   [0] centerX  Double  0.8213542
    ///   [1] centerY  Double  0.6125
    ///   [2] width    Double  0.05
    ///   [3] height   Double  0.05
    ///   [4] inFocus  Any     "f" / "t" / 0 / 1
    private func focusPointFromAFInfo(_ info: [Any]) -> FocusPoint? {
        guard info.count >= 4,
              let cx = double(from: info[0]),
              let cy = double(from: info[1]),
              let w  = double(from: info[2]),
              let h  = double(from: info[3])
        else { return nil }

        // Sanity-check: coordinates must be within the image
        guard cx > 0, cx < 1, cy > 0, cy < 1,
              w > 0, w <= 1, h > 0, h <= 1
        else { return nil }

        // Element [4] encodes focus-lock status.
        // Observed values: "t" = true (in focus), "f" = false (not locked / hunt failed)
        // May also appear as Int 1/0 on some models or OS versions.
        let isInFocus: Bool = {
            guard info.count >= 5 else { return true }   // absent → assume locked
            let raw = info[4]
            if let s = raw as? String { return s.lowercased() == "t" || s == "1" }
            if let i = raw as? Int    { return i != 0 }
            if let b = raw as? Bool   { return b }
            return true
        }()

        return FocusPoint(centerX: cx, centerY: cy, width: w, height: h, isInFocus: isInFocus)
    }

    /// Coerces Any to Double, handling the numeric types ImageIO may use.
    private func double(from any: Any) -> Double? {
        switch any {
        case let d as Double: return d
        case let f as Float:  return Double(f)
        case let i as Int:    return Double(i)
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }
}

// MARK: - Convenience

/// Extract Panasonic AF focus points from a local image file URL.
/// Returns nil if the file is not a Panasonic image or has no AF data.
public func extractPanasonicFocusPoints(from url: URL) -> PanasonicFocusResult? {
    PanasonicFocusPointExtractor(url: url).extract()
}

// MARK: - SwiftUI / UIKit drawing helper (optional)

#if canImport(UIKit)
import UIKit

public extension FocusPoint {
    /// Draws a focus rectangle overlay on a UIView or UIImage context.
    /// Call this inside a `draw(_ rect:)` or after `UIGraphicsBeginImageContext`.
    func drawOverlay(in imageSize: CGSize,
                     color: UIColor = .systemYellow,
                     lineWidth: CGFloat = 2) {
        let r = rect(in: imageSize)
        let path = UIBezierPath(rect: r)
        path.lineWidth = lineWidth
        color.setStroke()
        path.stroke()
    }
}
#endif

// MARK: - Example (remove before shipping)
/*
let url = URL(fileURLWithPath: "/path/to/G9M2_photo.jpg")
if let result = extractPanasonicFocusPoints(from: url) {
    let size = CGSize(width: result.imageWidth, height: result.imageHeight)
    RCLog("Image: \(result.imageWidth) × \(result.imageHeight)")
    for (i, pt) in result.focusPoints.enumerated() {
        RCLog("Point \(i+1): \(pt)")
        RCLog("  → pixel rect: \(pt.rect(in: size))")
    }
} else {
    RCLog("No AF data found.")
}
// Expected output for your dump:
// Point 1: FocusPoint(cx=0.8214 cy=0.6125 w=0.0500 h=0.0500 inFocus=false)
// → pixel rect: (4614.1, 2509.4, 288.8, 216.8)
*/
