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
    weak var filesModel: FilesModel?
    var thumbsManager: PhotoCacheManager?

    private var undoStack: [[(trashedURL: URL, originalURL: URL)]] = []

    func movePhotosToTrash(_ photos: [PhotoItem]) {
        var undoEntry: [(trashedURL: URL, originalURL: URL)] = []

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

                thumbsManager?.deleteThumbnail(for: photo)

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
                    filesModel?.lastDeletedFiles.append(url)
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
