//
//  PhotoKitModel.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 10.06.2026.
//

import Photos
import SwiftUI
import Combine

@MainActor
final class PhotosKitModel: ObservableObject {
    let photosSubject = CurrentValueSubject<[PhotoItem], Never>([])
    let isLoadingSubject = CurrentValueSubject<Bool, Never>(false)
    private var photos: [PhotoItem] = [] {
        didSet {
            photosSubject.send(photos)
        }
    }
    private var isLoadingMetadata: Bool = false {
        didSet {
            isLoadingSubject.send(isLoadingMetadata)
        }
    }

    private let folder: FolderItem
    private var photokitTask: Task<Void, Never>?

    init(folder: FolderItem) {
        self.folder = folder
    }

    func loadPhotos() {
        isLoadingMetadata = true
        photokitTask = Task {
            // Step 1 — fast: load basic items (no PHAssetResource lookup)
            let basicItems = await Task.detached(priority: .userInitiated) { [folder] in
                if folder.url.isPhotoLibraryRoot {
                    return PhotoKitSource.loadAllPhotos(basic: true)
                } else {
                    return PhotoKitSource.loadPhotos(
                        albumIdentifier: folder.url.photoKitAlbumIdentifier ?? "",
                        basic: true)
                }
            }.value

            if Task.isCancelled {
                return
            }

            self.photos = basicItems

            // Step 2 — slower: enrich with real filenames in background batches
            let batchSize = 200
            var enriched = basicItems
            let total = enriched.count
            var idx = 0
            while idx < total {
                if Task.isCancelled {
                    break
                }
                let end = min(idx + batchSize, total)
                let slice = Array(enriched[idx..<end])
                let filled = await Task.detached(priority: .utility) {
                    slice.map { item -> PhotoItem in
                        guard let asset = item.phAsset else {
                            return item
                        }
                        let resources = PHAssetResource.assetResources(for: asset)
                        let primary = resources.first(where: {
                            $0.type == .photo || $0.type == .video || $0.type == .fullSizePhoto
                        }) ?? resources.first
                        guard let filename = primary?.originalFilename else {
                            return item
                        }
                        return item.withFilename(filename)
                    }
                }.value
                enriched.replaceSubrange(idx..<end, with: filled)
                self.photos = enriched
                idx = end
            }
            isLoadingMetadata = false
        }
    }

    func reloadPhotos() {
        photokitTask?.cancel()
        loadPhotos()
    }
}
