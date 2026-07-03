//
//  PhotoTrashService.swift
//  Imagin Raw
//
//  Handles moving photos to trash and undo.
//

import Foundation

@MainActor
class PhotoTrashService {

    weak var photosModel: PhotosModel?
    let cacheManagers: [PhotoCacheManager]
    private(set) weak var fileSystemModel: FileSystemModel?
    private var undoStack: [[(trashedURL: URL, originalURL: URL)]] = []

    init(fileSystemModel: FileSystemModel, cacheManagers: [PhotoCacheManager]) {
        self.fileSystemModel = fileSystemModel
        self.cacheManagers = cacheManagers
    }

    func movePhotosToTrash(_ photos: [PhotoItem]) {
        var undoEntry: [(trashedURL: URL, originalURL: URL)] = []

        // Suppress FSEvent callbacks for the entire batch so the monitor
        // doesn't fire applyFileSystemChange for every file we delete.
        fileSystemModel?.muteFSEvents()
        defer { fileSystemModel?.unmuteFSEvents() }

        for photo in photos {
            let url = URL(fileURLWithPath: photo.path)
            let ext = url.pathExtension.lowercased()
            let base = url.deletingPathExtension().lastPathComponent
            let dir = url.deletingLastPathComponent()

            do {
                var trashedURL: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
                if let t = trashedURL as? URL {
                    undoEntry.append((t, url))
                }

                for manager in cacheManagers {
                    manager.deleteThumbnail(for: photo)
                }

                if FilesExtensions.raw.contains(ext) {
                    for jpgExt in ["jpg", "jpeg", "heic", "JPG", "JPEG", "HEIC"] {
                        let j = dir.appendingPathComponent("\(base).\(jpgExt)")
                        if FileManager.default.fileExists(atPath: j.path) {
                            var t: NSURL?
                            try? FileManager.default.trashItem(at: j, resultingItemURL: &t)
                            if let t = t as? URL {
                                undoEntry.append((t, j))
                            }
                        }
                    }
                    for sidecar in ["\(base).xmp", "\(base).acr"] {
                        let s = dir.appendingPathComponent(sidecar)
                        if FileManager.default.fileExists(atPath: s.path) {
                            var t: NSURL?
                            try? FileManager.default.trashItem(at: s, resultingItemURL: &t)
                            if let t = t as? URL {
                                undoEntry.append((t, s))
                            }
                        }
                    }
                }

                if let idx = photosModel?.photos.firstIndex(where: { $0.id == photo.id }) {
                    photosModel?.photos.remove(at: idx)
                }
            } catch {}
        }

        if !undoEntry.isEmpty {
            undoStack.append(undoEntry)
        }
    }

    func undoLastTrash() {
        guard let last = undoStack.popLast() else {
            return
        }
        for item in last {
            try? FileManager.default.moveItem(at: item.trashedURL, to: item.originalURL)
        }
    }
}
