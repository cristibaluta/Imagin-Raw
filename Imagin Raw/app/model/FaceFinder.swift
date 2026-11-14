//
//  FaceFinder.swift
//  Imagin Raw
//
//  Finds faces with Core Image's built-in face detector (CIDetector).
//  Runs entirely on this Mac: no AI model download, no network.
//

import CoreImage
import CoreGraphics

enum FaceFinder {

    /// Center of the largest face in `image`, normalized 0...1 with the origin at the top-left,
    /// or nil when no face is found. Call it off the main thread.
    static func largestFaceCenter(in image: CGImage) -> CGPoint? {
        guard image.width > 0, image.height > 0 else {
            return nil
        }
        // A small copy is plenty to find faces and keeps it fast
        var ciImage = CIImage(cgImage: image)
        let longest = CGFloat(max(image.width, image.height))
        let scale = min(1, 1024 / longest)
        if scale < 1 {
            ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else {
            return nil
        }

        let detector = CIDetector(ofType: CIDetectorTypeFace,
                                  context: nil,
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let faces = detector?.features(in: ciImage) ?? []
        guard let largest = faces.max(by: { area($0.bounds) < area($1.bounds) }) else {
            return nil
        }
        // Core Image uses a bottom-left origin
        let x = (largest.bounds.midX - extent.minX) / extent.width
        let y = 1 - (largest.bounds.midY - extent.minY) / extent.height
        return CGPoint(x: max(0, min(1, x)), y: max(0, min(1, y)))
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.width * rect.height
    }
}
