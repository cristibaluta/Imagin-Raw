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
    @Published var reviewGroup: ReviewGroupItem?// Photos to be displayed in the review screen
    @Published var videoEditorPhotos: [PhotoItem]? = nil
    @Published var externalAppManager = ExternalAppManager()

    let thumbnailsCacheManager = PhotoCacheManager(thumbSize: .s256)
    let previewsCacheManager = PhotoCacheManager(thumbSize: .s1024)
    let fullResCacheManager = PhotoCacheManager(thumbSize: .full)

    let fileSystemModel: FileSystemModel
    let thumbsGridViewModel: ThumbGridViewModel
    let previewViewModel: PreviewViewModel
    let reviewViewModel: ReviewViewModel

    private var cancellables = Set<AnyCancellable>()

    init() {
        fileSystemModel = FileSystemModel()
        thumbsGridViewModel = ThumbGridViewModel(fileSystemModel: fileSystemModel,
                                                 thumbsManager: thumbnailsCacheManager)
        previewViewModel = PreviewViewModel(previewsCacheManager: previewsCacheManager,
                                            fullResCacheManager: fullResCacheManager)
        reviewViewModel = ReviewViewModel(previewsCacheManager: previewsCacheManager,
                                          fullResCacheManager: fullResCacheManager)

        // Monitor clicks
        // 1. When album changes, load the photos of that album
        fileSystemModel.$selectedFolder
            .sink { [weak self] folder in
                guard let self, let folder else {
                    return
                }
                Task {
                    self.previewViewModel.reset()
                    self.selectedFolder = folder
                    self.thumbsGridViewModel.loadPhotosForFolder(folder)
                }
            }
            .store(in: &cancellables)

        // 2a. Single-file update: add/remove/reload only the changed photo
        fileSystemModel.photoFileDidChangeSubject
            .sink { [weak self] url in
                self?.thumbsGridViewModel.applyFileSystemChange(at: url)
            }
            .store(in: &cancellables)

        // 2b. Broad reload fallback for directory-level changes (new subfolder, rename, etc.)
        fileSystemModel.folderContentDidChangeSubject
            .sink { [weak self] _ in
                self?.thumbsGridViewModel.reloadPhotos()
            }
            .store(in: &cancellables)

        // 3. When a thumbnail is selected, display it in the preview
        thumbsGridViewModel.$selectedPhoto
            .sink { [weak self] photo in
                guard let self, let photo else {
                    return
                }
                Task {
                    self.selectedPhoto = photo
                    self.previewViewModel.loadPhoto(photo)
                }
            }
            .store(in: &cancellables)
    }
}
