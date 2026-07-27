//
//  XmpMetadata.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 26.07.2026.
//

import Foundation

struct XmpMetadata: Equatable, Hashable {
    let label: String?
    let rating: Int?
    let creator: String?
    let rights: String?
    let createDate: String?
    let modifyDate: String?
    let cameraModel: String?
    let lens: String?
    let focalLength: String?
    let aperture: String?
    let shutterSpeed: String?
    let iso: String?
    let exposureBias: String?
    let hasEdits: Bool
}
