//
//  PhotoSource.swift
//  Imagin Raw
//

import Foundation

protocol PhotoSource {
    /// A stable string key used for both memory and disk caching.
    var cacheKey: String { get }

    /// Load a thumbnail image (short edge ≤ targetSize) and call completion on any thread.
    func loadThumbnail(targetSize: CGFloat, completion: @escaping (IRImage?) -> Void)

    /// Load a preview image (short edge ≤ targetSize) and call completion on any thread.
    func loadPreview(targetSize: CGFloat, completion: @escaping (IRImage?) -> Void)

    /// Load EXIF metadata asynchronously.
    func loadExif() async -> ExifInfo?
}
