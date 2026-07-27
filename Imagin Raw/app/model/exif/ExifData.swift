//
//  ExifData.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 26.07.2026.
//

import Foundation

struct ExifData: Equatable, Hashable {
    let dateCaptured: Date?
    let width: Int?
    let height: Int?
    let cameraMake: String?
    let cameraModel: String?
    let lensModel: String?
    let lensFocalLength: Double?
    let iso: Int?
    let aperture: Double?
    let shutterSpeed: Double?
    let exposureCompensation: Double?
    /// For raw images this is a rating writen in camera
    let rating: Int?
}
