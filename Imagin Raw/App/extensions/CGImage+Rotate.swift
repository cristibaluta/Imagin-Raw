//
//  CGImage+Rotate.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 11.03.2026.
//

import Foundation
import CoreGraphics
import ImageIO

extension CGImage {

    func applyingOrientation(_ orientation: Int32) -> CGImage? {

        let originalWidth = self.width
        let originalHeight = self.height
        let bitsPerComponent = self.bitsPerComponent
        let bitmapInfo = self.bitmapInfo

        guard let colorSpace = self.colorSpace else {
            return nil
        }

        var degreesToRotate: Double = 0.0
        var swapWidthHeight: Bool = false
        var mirrored: Bool = false

        switch CGImagePropertyOrientation(rawValue: UInt32(orientation)) {
            case .up:
                break
            case .upMirrored:
                mirrored = true
            case .right:
                degreesToRotate = -90.0
                swapWidthHeight = true
            case .rightMirrored:
                degreesToRotate = -90.0
                swapWidthHeight = true
                mirrored = true
            case .down:
                degreesToRotate = 180.0
            case .downMirrored:
                degreesToRotate = 180.0
                mirrored = true
            case .left:
                degreesToRotate = 90.0
                swapWidthHeight = true
            case .leftMirrored:
                degreesToRotate = 90.0
                swapWidthHeight = true
                mirrored = true
            default:
                break
        }

        let radians = degreesToRotate * Double.pi / 180.0
        let orientedSize = swapWidthHeight
            ? CGSize(width: originalHeight, height: originalWidth)
            : CGSize(width: originalWidth, height: originalHeight)

        let bytesPerRow = (Int(orientedSize.width) * bitsPerPixel) / 8

        let contextRef = CGContext(data: nil,
                                   width: Int(orientedSize.width),
                                   height: Int(orientedSize.height),
                                   bitsPerComponent: bitsPerComponent,
                                   bytesPerRow: bytesPerRow,
                                   space: colorSpace,
                                   bitmapInfo: bitmapInfo.rawValue)

        contextRef?.translateBy(x: orientedSize.width / 2.0, y: orientedSize.height / 2.0)

        if mirrored {
            contextRef?.scaleBy(x: -1.0, y: 1.0)
        }

        contextRef?.rotate(by: CGFloat(radians))

        if swapWidthHeight {
            contextRef?.translateBy(x: -orientedSize.height / 2.0, y: -orientedSize.width / 2.0)
        } else {
            contextRef?.translateBy(x: -orientedSize.width / 2.0, y: -orientedSize.height / 2.0)
        }

        contextRef?.draw(self, in: CGRect(x: 0.0,
                                          y: 0.0,
                                          width: CGFloat(originalWidth),
                                          height: CGFloat(originalHeight)))

        return contextRef?.makeImage()
    }
}
