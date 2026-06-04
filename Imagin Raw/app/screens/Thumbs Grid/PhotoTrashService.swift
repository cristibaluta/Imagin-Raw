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
    var thumbsManager: ThumbsManager?
    var onPhotosChanged: (() -> Void)?

    private var undoStack: [[(trashedURL: URL, originalURL: URL)]] = []

    func movePhotosToTrash(_ photos: [PhotoItem],
                           filteredPhotos: [PhotoItem],
                           lastSelectedIndex: Int?) -> (newSelectedPhoto: PhotoItem?, newLastIndex: Int?) {
        var undoEntry: [(trashedURL: URL, originalURL: URL)] = []

        for photo in photos {
            let url = URL(fileURLWithPath: photo.path)
            let ext = url.pathExtension.lowercased()
            let base = url.deletingPathExtension().lastPathComponent
            let dir = url.deletingLastPathComponent()

            do {
                var trashedURL: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
                if let t = trashedURL as? URL { undoEntry.append((t, url)) }

                thumbsManager?.deleteCachedThumbnail(for: photo.path)

                if FilesExtensions.raw.contains(ext) {
                    for jpgExt in ["jpg", "jpeg", "JPG", "JPEG"] {
                        let j = dir.appendingPathComponent("\(base).\(jpgExt)")
                        if FileManager.default.fileExists(atPath: j.path) {
                            var t: NSURL?
                            try? FileManager.default.trashItem(at: j, resultingItemURL: &t)
                            if let t = t as? URL { undoEntry.append((t, j)) }
                        }
                    }
                    for sidecar in ["\(base).xmp", "\(base).acr"] {
                        let s = dir.appendingPathComponent(sidecar)
                        if FileManager.default.fileExists(atPath: s.path) {
                            var t: NSURL?
                            try? FileManager.default.trashItem(at: s, resultingItemURL: &t)
                            if let t = t as? URL { undoEntry.append((t, s)) }
                        }
                    }
                }

                if let idx = photosModel?.photos.firstIndex(where: { $0.id == photo.id }) {
                    photosModel?.photos.remove(at: idx)
                    filesModel?.lastDeletedFiles.append(url)
                }
            } catch {}
        }

        if !undoEntry.isEmpty { undoStack.append(undoEntry) }

        // Compute next selection
        onPhotosChanged?()

        let remaining = photosModel?.photos ?? []
        if remaining.isEmpty { return (nil, nil) }

        let targetIndex = min(lastSelectedIndex ?? 0, remaining.count - 1)
        // filteredPhotos isn't yet updated here, so use photosModel directly
        // The VM will call updateFilteredPhotos right after
        return (remaining[safe: targetIndex], targetIndex)
    }

    func undoLastTrash(reloadPhotos: () -> Void) {
        guard let last = undoStack.popLast() else { return }
        for item in last {
            do {
                try FileManager.default.moveItem(at: item.trashedURL, to: item.originalURL)
                thumbsManager?.deleteCachedThumbnail(for: item.originalURL.path)
            } catch {}
        }
        reloadPhotos()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
