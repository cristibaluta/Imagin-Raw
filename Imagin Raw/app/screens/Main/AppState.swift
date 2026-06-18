//
//  AppState.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 18.06.2026.
//

import Foundation
import Combine

@MainActor
class AppState: ObservableObject {

    // Used to display info in the nav bar
    @Published var selectedFolder: FolderItem?
    @Published var selectedPhoto: PhotoItem?

    private let thumbnailsCacheManager = PhotoCacheManager(thumbSize: .s256)
    private let previewsCacheManager = PhotoCacheManager(thumbSize: .s1024)
    private let fullResCacheManager = PhotoCacheManager(thumbSize: .s1024)

    let filesModel: FilesModel
    let thumbsGridViewModel: ThumbGridViewModel
    let previewViewModel: PreviewViewModel

    private var cancellables = Set<AnyCancellable>()

    init() {
        filesModel = FilesModel()
        thumbsGridViewModel = ThumbGridViewModel(filesModel: filesModel,
                                                 thumbsManager: thumbnailsCacheManager)
        previewViewModel = PreviewViewModel(previewsCacheManager: previewsCacheManager,
                                            fullResCacheManager: fullResCacheManager)

        // Monitor clicks
        // 1. When album changes, load the photos of that album
        filesModel
        .objectWillChange
        .sink { [weak self] _ in
            guard let self else { return }
            Task {
                self.selectedFolder = self.filesModel.selectedFolder
                guard let folder = self.selectedFolder else { return }
                self.thumbsGridViewModel.loadPhotosForFolder(folder)
            }
        }
        .store(in: &cancellables)

        // 2. When thumbnail is selected, display it in the preview
        thumbsGridViewModel
        .objectWillChange
        .sink { [weak self] _ in
            guard let self else { return }
            Task {
                self.selectedPhoto = self.thumbsGridViewModel.selectedPhoto
                guard let photo = self.selectedPhoto else { return }
                self.previewViewModel.loadPhoto(photo)
            }
        }
        .store(in: &cancellables)
    }
}
