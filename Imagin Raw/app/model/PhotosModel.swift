//
//  PhotosModel.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 20.02.2026.
//

import Foundation
import SwiftUI

protocol PhotosModelProtocol {
    var photos: [PhotoItem] { get }
    var isLoadingMetadata: Bool { get }
    func loadPhotos()
    func reloadPhotos()
    func reloadMetadata(forSidecar sidecarURL: URL, completion: @escaping (() -> Void))
}

/// Model responsible for loading and managing photos for a specific folder
/// Each folder gets its own PhotosModel instance, ensuring clean state separation
@MainActor
final class PhotosModel: ObservableObject {
    @Published var photos: [PhotoItem] = []
    @Published var isLoadingMetadata: Bool = false

    private let folder: FolderItem
    private let folderModel: PhotosFolderModel
    private let photokitModel: PhotosKitModel

    init(folder: FolderItem) {
        self.folder = folder

        folderModel = PhotosFolderModel(folder: folder)
        photokitModel = PhotosKitModel(folder: folder)

        folderModel.photosSubject.assign(to: &$photos)
        folderModel.isLoadingSubject.assign(to: &$isLoadingMetadata)

        photokitModel.photosSubject.assign(to: &$photos)
        photokitModel.isLoadingSubject.assign(to: &$isLoadingMetadata)
    }

    func loadPhotos() {
        if folder.url.isPhotoKitAlbum || folder.url.isPhotoLibraryRoot {
            photokitModel.loadPhotos()
        } else {
            folderModel.loadPhotos()
        }
    }

    func reloadPhotos() {
        if folder.url.isPhotoKitAlbum || folder.url.isPhotoLibraryRoot {
            photokitModel.reloadPhotos()
        } else {
            folderModel.reloadPhotos()
        }
    }

    /// Re-reads XMP for a single photo (identified by its sidecar URL) and updates it in-place,
    /// preserving the PhotoItem UUID so the grid only redraws that one cell.
    func reloadMetadata(forSidecar sidecarURL: URL, completion: @escaping (() -> Void)) {
        if folder.url.isPhotoKitAlbum || folder.url.isPhotoLibraryRoot {

        } else {
            folderModel.reloadMetadata(forSidecar: sidecarURL) {
                completion()
            }
        }
    }
}
