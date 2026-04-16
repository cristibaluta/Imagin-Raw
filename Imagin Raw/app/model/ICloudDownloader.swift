//
//  ICloudDownloader.swift
//  Imagin Raw
//
//  Ensures an iCloud Drive file is fully downloaded before callers read it.
//  Uses NSFileCoordinator, which is the correct API: it automatically triggers
//  the download and blocks until the file is locally present.
//

import Foundation

enum ICloudDownloader {

    /// Ensures `url` is fully downloaded from iCloud Drive.
    ///
    /// - For files that are already local this is a very cheap check.
    /// - For iCloud placeholders this triggers the download via
    ///   `NSFileCoordinator` and blocks the **calling thread** until the
    ///   data is on disk (or an error occurs).
    ///
    /// Must be called from a **background thread** — never from the main thread.
    ///
    /// - Returns: `true` if the file is ready to read, `false` on error.
    @discardableResult
    static func ensureDownloaded(at url: URL) -> Bool {
        let fm = FileManager.default

        // ── Fast path: file exists locally and is not an iCloud placeholder ──
        // Check ubiquitous status first; if we can't read it the file is either
        // local or doesn't exist at all.
        if let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]) {
            let status = values.ubiquitousItemDownloadingStatus
            if status == nil {
                // Not a ubiquitous item — plain local file.
                return fm.fileExists(atPath: url.path)
            }
            if status == .current {
                // Already downloaded.
                return true
            }
            // status is .notDownloaded or .downloaded (partial) — fall through.
            print("☁️ [ICloudDownloader] \(url.lastPathComponent) status=\(String(describing: status?.rawValue)) — triggering download")
        } else {
            // Can't read resource values — assume local.
            return fm.fileExists(atPath: url.path)
        }

        // ── Coordinate a read: this tells iCloud to materialise the file ──
        // NSFileCoordinator.coordinate(readingItemAt:options:error:byAccessor:)
        // will block until the file is downloaded when passed the
        // .withoutChanges option (it does NOT evict the file afterwards).
        var coordinatorError: NSError?
        var success = false

        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: url,
                               options: .withoutChanges,
                               error: &coordinatorError) { localURL in
            // Inside this block the file is guaranteed to be on disk.
            success = fm.fileExists(atPath: localURL.path)
            print("☁️ [ICloudDownloader] coordinator block executed — exists=\(success): \(localURL.lastPathComponent)")
        }

        if let err = coordinatorError {
            print("☁️ [ICloudDownloader] coordinator error for \(url.lastPathComponent): \(err.localizedDescription)")
            return false
        }

        return success
    }
}
