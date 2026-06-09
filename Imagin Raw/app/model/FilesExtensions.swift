//
//  FilesExtensions.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 09.03.2026.
//

import Foundation

enum RawBrand {
    case olympus
    case panasonic
    case canon
    case nikon
    case sony
    case fuji
    case pentax
    case other

    /// Brands that support AF point parsing
    static let afPointSupported: Set<RawBrand> = []
}

enum FilesExtensions {
    static let raw: Set<String> = [
        "arw", "orf", "rw2", "cr2", "cr3", "crw", "nef", "nrw",
        "srf", "sr2", "raw", "raf", "pef", "ptx", "dng", "3fr",
        "fff", "iiq", "mef", "mos", "x3f", "srw", "dcr", "kdc",
        "k25", "kc2", "mrw", "erf", "bay", "ndd", "sti", "rwl", "r3d"
    ]

    /// This are the type of images used by cameras along the raw
    static let jpg: Set<String> = ["jpg", "jpeg", "heic"]

    static let other: Set<String> = ["png", "webp", "tiff", "tif", "psd", "psb"]

    static let video: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "hevc"]

    /// All supported extensions (RAW + JPG + other + video)
    static let all: Set<String> = raw.union(jpg).union(other).union(video)

    /// Determine the camera brand from a file extension
    static func brand(for extension: String) -> RawBrand {
        switch `extension`.lowercased() {
        case "orf":
            return .olympus
        case "rw2":
            return .panasonic
        case "cr2", "cr3", "crw":
            return .canon
        case "nef", "nrw":
            return .nikon
        case "arw", "srf", "sr2":
            return .sony
        case "raf":
            return .fuji
        case "pef", "ptx":
            return .pentax
        default:
            return .other
        }
    }

    /// Determine the camera brand from a file path
    static func brand(forPath path: String) -> RawBrand {
        let ext = (path as NSString).pathExtension
        return brand(for: ext)
    }
}
