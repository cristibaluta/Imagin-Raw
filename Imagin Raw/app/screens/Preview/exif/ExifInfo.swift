//
//  ExifInfo.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 05.03.2026.
//

import Foundation
import ImageIO

struct ExifInfo {
    let aperture: Double?
    let shutterSpeed: Double?
    let iso: Int?
    let focalLength: Double?
    let cameraMake: String?
    let cameraModel: String?
    let lensModel: String?

    // MARK: - Parsing from RAW exifData dictionary
    static func from(rawExif: [String: Any]) -> ExifInfo {
        ExifInfo(
            aperture:     (rawExif["Aperture"] as? NSNumber)?.doubleValue,
            shutterSpeed: (rawExif["ShutterSpeed"] as? NSNumber)?.doubleValue,
            iso:          (rawExif["ISO"] as? NSNumber)?.intValue,
            focalLength:  (rawExif["FocalLength"] as? NSNumber)?.doubleValue,
            cameraMake:   rawExif["Make"] as? String,
            cameraModel:  rawExif["Model"] as? String,
            lensModel:    rawExif["LensModel"] as? String
        )
    }

    // MARK: - Parsing from CGImageSource properties (JPG/PNG/etc)
    static func from(imageProperties: [CFString: Any]) -> ExifInfo {
        let exif = imageProperties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = imageProperties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

        let isoRatings = exif?[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber]

        return ExifInfo(
            aperture:     (exif?[kCGImagePropertyExifFNumber] as? NSNumber)?.doubleValue,
            shutterSpeed: (exif?[kCGImagePropertyExifExposureTime] as? NSNumber)?.doubleValue,
            iso:          isoRatings?.first?.intValue,
            focalLength:  (exif?[kCGImagePropertyExifFocalLength] as? NSNumber)?.doubleValue,
            cameraMake:   tiff?[kCGImagePropertyTIFFMake] as? String,
            cameraModel:  tiff?[kCGImagePropertyTIFFModel] as? String,
            lensModel:    exif?[kCGImagePropertyExifLensModel] as? String
        )
    }
}
