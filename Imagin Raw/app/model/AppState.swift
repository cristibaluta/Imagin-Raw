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
    @Published var includeSubfolders: Bool = false
    @Published var selectedPhoto: PhotoItem?
    @Published var reviewGroup: ReviewGroupItem?// Photos to be displayed in the review screen
    @Published var videoEditorPhotos: [PhotoItem]? = nil
    @Published var pdfEditorPhotos: [PhotoItem]? = nil
    @Published var externalAppManager = ExternalAppManager()

    #if os(iOS)
    @Published var feedPhotos: [PhotoItem] = []
    #endif

    let thumbnailsCacheManager = PhotoCacheManager(thumbSize: .s256)
    let previewsCacheManager = PhotoCacheManager(thumbSize: .s1024)
    let fullResCacheManager = PhotoCacheManager(thumbSize: .full)

    let fileSystemModel: FileSystemModel
    let thumbsGridViewModel: ThumbGridViewModel
    let previewViewModel: PreviewViewModel
    let reviewViewModel: ReviewViewModel
    let trashService: PhotoTrashService

    private var cancellables = Set<AnyCancellable>()

    init() {
        fileSystemModel = FileSystemModel()
        let trashService = PhotoTrashService(fileSystemModel: fileSystemModel,
                                             cacheManagers: [thumbnailsCacheManager, previewsCacheManager, fullResCacheManager])
        self.trashService = trashService

        thumbsGridViewModel = ThumbGridViewModel(fileSystemModel: fileSystemModel,
                                                 thumbsManager: thumbnailsCacheManager,
                                                 trashService: trashService)
        previewViewModel = PreviewViewModel(previewsCacheManager: previewsCacheManager,
                                            fullResCacheManager: fullResCacheManager)
        reviewViewModel = ReviewViewModel(previewsCacheManager: previewsCacheManager,
                                          fullResCacheManager: fullResCacheManager)

        // Monitor clicks
        // 1a. When album changes in the sidebar, load the thumbnails of that album
        fileSystemModel.$selectedFolder
            .sink { [weak self] folder in
                guard let self, let folder else {
                    return
                }
                Task {
                    self.previewViewModel.reset()
                    self.selectedFolder = folder
                    self.thumbsGridViewModel.loadPhotosForFolder(folder, includeSubfolders: self.includeSubfolders)
                    // Reset the subfolder state for the next single clicks
                    self.includeSubfolders = false
                }
            }
            .store(in: &cancellables)

        // 1b. When root folders are added or removed from the sidebar
        fileSystemModel.$rootFolders
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // 2a. Batch file update: add/remove/reload only the changed photos
        fileSystemModel.photoFileDidChangeSubject
            .sink { [weak self] urls in
                guard let self else {
                    return
                }
                // External deletes — evict from all cache tiers
                let allPhotos = self.thumbsGridViewModel.photosModel?.photos ?? []
                for url in urls where !FileManager.default.fileExists(atPath: url.path) {
                    if let photo = allPhotos.first(where: { $0.url == url }) {
                        self.trashService.cacheManagers.forEach { $0.deleteThumbnail(for: photo) }
                    }
                }
                self.thumbsGridViewModel.applyFileSystemChanges(at: urls)
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

    /// Pending URL to open — set before the window is ready, consumed in handleOpenUrl.
    static var pendingOpenURL: URL? = nil

    func handleOpenUrl(_ url: URL) {
        var isDir: ObjCBool = false
        let isDirectory = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        let folderURL = isDirectory ? url : url.deletingLastPathComponent()
        let fileURL = isDirectory ? nil : url

        RCLog("received: \(url.lastPathComponent) | isDirectory: \(isDirectory) | folderURL: \(folderURL.path)")

        guard let folder = fileSystemModel.findOrBuildFolder(for: folderURL) else {
            RCLog("🔗 [handleOpenUrl] ❌ folderURL not under any known root: \(folderURL.path)")
            return
        }

        if let fileURL {
            thumbsGridViewModel.pendingSelectURL = fileURL
        }
        RCLog("setting selectedFolder: \(folder.url.path)")
        fileSystemModel.selectedFolder = folder
    }

}
