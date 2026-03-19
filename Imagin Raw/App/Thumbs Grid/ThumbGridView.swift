//
//  ThumbGridView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 06.02.2026.
//

import SwiftUI

struct ThumbGridView: View {
    @StateObject private var viewModel: ThumbGridViewModel
    @EnvironmentObject var externalAppManager: ExternalAppManager
    @EnvironmentObject var filesModel: FilesModel

    let searchPhotoResults: [PhotoItem]?
    let onOpenSelectedPhotos: (([PhotoItem]) -> Void)?
    let onEnterReviewMode: (() -> Void)?
    let onToggleSidebar: (() -> Void)?
//    @FocusState private var isFocused: Bool
    @Binding var openSelectedPhotosCallback: (() -> Void)?

    @State private var useCollectionView = true
    @State private var scrollToPhotoId: UUID? = nil
    @State private var copyToViewModel: CopyToViewModel? = nil
    @State private var renameSheetPhotos: PhotosSheetItem? = nil
    @State private var showDuplicatesSheet: Bool = false

    @State private var hasAppeared = false

    init(filesModel: FilesModel,
         searchPhotoResults: [PhotoItem]? = nil,
         onOpenSelectedPhotos: (([PhotoItem]) -> Void)?,
         onEnterReviewMode: (() -> Void)?,
         onToggleSidebar: (() -> Void)? = nil,
         openSelectedPhotosCallback: Binding<(() -> Void)?>) {

        self._viewModel = StateObject(wrappedValue: ThumbGridViewModel(filesModel: filesModel))
        self.searchPhotoResults = searchPhotoResults
        self.onOpenSelectedPhotos = onOpenSelectedPhotos
        self.onEnterReviewMode = onEnterReviewMode
        self.onToggleSidebar = onToggleSidebar
        self._openSelectedPhotosCallback = openSelectedPhotosCallback
    }

    var body: some View {
        let _ = Self._printChanges()
        VStack(spacing: 0) {
            if viewModel.filteredPhotos.isEmpty {
                EmptyStateView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if useCollectionView {
                    collectionPhotoGridView
                } else {
                    swiftUIPhotoGridView
                }
            }
            if !viewModel.photos.isEmpty {
                ThumbsBottomBar(viewModel: viewModel, showDuplicatesSheet: $showDuplicatesSheet)
            }
            Button("useCollectionView \(useCollectionView)", action: {
                useCollectionView.toggle()
            })
        }
        .preference(key: GridWidthPreferenceKey.self, value: viewModel.gridWidth+16)
        .sheet(item: $copyToViewModel) { vm in
            CopyToView(viewModel: vm)
                .environmentObject(filesModel)
                .interactiveDismissDisabled(false)
        }
        .sheet(item: $renameSheetPhotos) { item in
            RenameView(photosToRename: item.photos)
                .interactiveDismissDisabled(false)
        }
        .sheet(isPresented: $showDuplicatesSheet) {
            DuplicatesResultSheet(viewModel: viewModel)
        }
        .onAppear {
            // Only run once
            guard !hasAppeared else { return }
            hasAppeared = true

            openSelectedPhotosCallback = { [viewModel] in
                let selectedPhotoItems = viewModel.getSelectedPhotosForBulkAction()
                onOpenSelectedPhotos?(selectedPhotoItems)
            }
            if let results = searchPhotoResults {
                viewModel.loadSearchResults(results)
            } else if let folder = filesModel.selectedFolder {
                viewModel.loadPhotosForFolder(folder)
            }
        }
        .onChange(of: searchPhotoResults) { _, newResults in
            if let results = newResults {
                viewModel.loadSearchResults(results)
            } else {
                viewModel.clearSearchResults()
                if let folder = filesModel.selectedFolder {
                    viewModel.loadPhotosForFolder(folder)
                }
            }
        }
        .onChange(of: filesModel.selectedFolder) { oldFolder, newFolder in
            guard let folder = newFolder, oldFolder?.url != newFolder?.url else { return }
            viewModel.clearSearchResults()
            viewModel.loadPhotosForFolder(folder)
            viewModel.exitDuplicateMode()
            filesModel.selectedPhoto = nil
            viewModel.selectedPhotos.removeAll()
        }
        .onChange(of: filesModel.folderContentDidChange) { oldValue, newValue in
            if newValue != nil {
                viewModel.reloadPhotos()
            }
        }
    }

    // MARK: - Photo Grid
    // NSCollectionView-based grid
    private var collectionPhotoGridView: some View {
        CollectionThumbGridView(
            photos: viewModel.filteredPhotos,
            itemSize: viewModel.gridType.thumbSize,
            cellHeight: viewModel.gridType.cellHeight,
            selectedPhotos: viewModel.selectedPhotos,
            callbacks: ThumbCellCallbacks(
                onTap: { photo, modifiers in
                    viewModel.handlePhotoTap(photo: photo, modifiers: modifiers)
                },
                onDoubleClick: { photo in
                    handleDoubleClick(photo: photo)
                },
                onRatingChanged: { photo, rating in
                    viewModel.applyRating(rating, to: [photo])
                },
                onMoveToTrash: { rightClickedPhoto in
                    let photosToTrash = viewModel.selectedPhotos.contains(rightClickedPhoto.id)
                        ? viewModel.getSelectedPhotosForBulkAction()
                        : [rightClickedPhoto]
                    viewModel.movePhotosToTrash(photosToTrash)
                },
                onCopyTo: { rightClickedPhoto in
                    let photos = viewModel.selectedPhotos.contains(rightClickedPhoto.id)
                        ? viewModel.getSelectedPhotosForBulkAction()
                        : [rightClickedPhoto]
                    copyToViewModel = CopyToViewModel(photos: photos)
                },
                onRenameTo: { rightClickedPhoto in
                    let photos = viewModel.selectedPhotos.contains(rightClickedPhoto.id)
                        ? viewModel.getSelectedPhotosForBulkAction()
                        : [rightClickedPhoto]
                    renameSheetPhotos = PhotosSheetItem(photos: photos)
                },
                onMoveAllMarkedToTrash: { photo in
                    guard photo.toDelete else { return nil }
                    let marked = viewModel.getPhotosMarkedForDeletion()
                    return (count: marked.count, action: { viewModel.movePhotosToTrash(marked) })
                }
            ),
            scrollToPhotoId: $scrollToPhotoId,
            onKeyPress: { event in
                viewModel.handleKeyEvent(
                    event,
                    scrollTo: { photoId in scrollToPhotoId = photoId },
                    openPhotos: { photos in externalAppManager.openPhotos(photos) },
                    onToggleSidebar: { onToggleSidebar?() }
                )
            }
        )
        .onAppear {
            viewModel.initializeSelection()
        }
        .onChange(of: viewModel.photos) { oldPhotos, newPhotos in
            if filesModel.selectedPhoto == nil && !newPhotos.isEmpty {
                filesModel.selectedPhoto = newPhotos.first
                viewModel.selectedPhotos.removeAll()
                viewModel.selectedPhotos.insert(newPhotos.first!.id)
                viewModel.lastSelectedIndex = 0
            }
        }
        .onChange(of: viewModel.isLoadingMetadata) { oldValue, newValue in
            if oldValue == true && newValue == false {
                viewModel.clearInvalidFilters()
            }
        }
        .onChange(of: filesModel.selectedFolder) { _, _ in
            if let firstPhoto = viewModel.filteredPhotos.first {
                filesModel.selectedPhoto = firstPhoto
                viewModel.selectedPhotos.removeAll()
                viewModel.selectedPhotos.insert(firstPhoto.id)
                viewModel.lastSelectedIndex = 0
                scrollToPhotoId = firstPhoto.id
            }
        }
    }

    private var swiftUIPhotoGridView: some View {
        PhotoGridView(viewModel: viewModel)
    }

    // MARK: - Event Handlers

    private func handleDoubleClick(photo: PhotoItem) {
        filesModel.selectedPhoto = photo
        if viewModel.selectedPhotos.count > 1 {
            let selectedPhotoItems = viewModel.filteredPhotos.filter {
                viewModel.selectedPhotos.contains($0.id)
            }
            externalAppManager.openPhotos(selectedPhotoItems)
        } else {
            externalAppManager.openPhotos([photo])
        }
    }
}

struct PhotosSheetItem: Identifiable {
    let id = UUID()
    let photos: [PhotoItem]
}
