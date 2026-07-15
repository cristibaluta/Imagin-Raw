//
//  FilesExtensions.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 09.03.2026.
//

import Foundation
import UniformTypeIdentifiers

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

    static func isImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return type.conforms(to: .image)
    }

    static func isRawImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return type.conforms(to: .rawImage) // Apple's built-in RAW image UTType (macOS 10.15+/iOS 13+)
    }

    static func isRawCounterpartFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return type.conforms(to: .jpeg) || type.conforms(to: .heic) || type.conforms(to: .heif)
    }

    static func isMovieFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return type.conforms(to: .movie)
    }

    static func isSvgFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return type.conforms(to: .svg)
    }

    // Use this to detect image files by looking at the content, but this is more costly so it could be done for photos with no extension
    static func isImageFileByContent(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return false
        }
        let type = CGImageSourceGetType(source) as String?
        return type != nil
    }

}
