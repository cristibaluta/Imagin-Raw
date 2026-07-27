//
//  RawDecoder.swift
//  Imagin Raw
//
//  Protocol + implementations for full-resolution RAW decoding.
//  Switch between CoreGraphics (fast, camera-processed) and LibRaw
//  (slower, full software demosaic) by changing FullResManager.decoder.
//

import Foundation

protocol RawDecoder {
    /// Full demosaic / full-res decode.
    func decodeFullRes(at url: URL) -> IRImage?

    /// Extract, orient and resize a preview image up to `maxSize` px on the longest edge.
    /// Handles EXIF orientation. Returns nil on failure.
    func extractPreview(at url: URL, maxSize: CGFloat) -> IRImage?

    /// Extracts  exif from a photo.
    func extractExif(at url: URL) -> ExifData?
}
