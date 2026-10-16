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

    /// File extensions of images that can act as a "developed" counterpart to a RAW file
    /// (e.g. camera-generated JPG/HEIC, or Sony's 10-bit HIF).
    /// "hif" is not a system-registered UTType extension, so it must be matched explicitly.
    static let rawCounterpartExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "hif"]

    static func isRawCounterpartFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if rawCounterpartExtensions.contains(ext) {
            return true
        }
        guard let type = UTType(filenameExtension: ext) else {
            return false
        }
        return type.conforms(to: .jpeg) || type.conforms(to: .heic) || type.conforms(to: .heif)
    }

    /// Short badge text to show in the UI for a RAW's companion image file, based on its extension.
    static func companionBadgeText(forExtension ext: String) -> String {
        switch ext.lowercased() {
            case "jpeg":
                return "+JPG"
            case "heic":
                return "+HEIC"
            case "heif":
                return "+HEIF"
            case "hif":
                return "+HIF"
            default:
                return "+\(ext.uppercased())"
        }
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

    static func isAffinityFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["af", "afphoto", "afdesign", "afpub", "aftemplate"].contains(ext)
    }

    // Use this to detect image files by looking at the content, but this is more costly so it could be done for photos with no extension
    static func isImageFileByContent(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return false
        }
        let type = CGImageSourceGetType(source) as String?
        return type != nil
    }

    // TODO: Is this replaceable by the generic isImageFile method? Do all images support metadata?
    /// File extensions that support embedded metadata writing via ImageIO.
    static let supportedFilesWithExif: Set<String> = ["jpg", "jpeg", "png", "tiff", "tif", "heic", "heif", "psd"]
}
