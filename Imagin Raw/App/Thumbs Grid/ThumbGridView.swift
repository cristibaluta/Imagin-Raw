//
//  ThumbGridView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 06.02.2026.
//

import SwiftUI

struct ReviewGroupItem: Identifiable {
    let id = UUID()
    let group: DuplicateGroup
    let index: Int
    let totalGroups: Int
    let onRatingChanged: (PhotoItem, Int) -> Void
    let onApprove: (PhotoItem) -> Void
    let onMarkForDeletion: (PhotoItem) -> Void
    let onNavigate: (Int) -> Void
}

private struct ReviewGroupItemID: Identifiable {
    let id = UUID()
}

struct ThumbGridView: View {
    @StateObject private var viewModel: ThumbGridViewModel
    @EnvironmentObject var externalAppManager: ExternalAppManager
    @EnvironmentObject var filesModel: FilesModel

    let searchPhotoResults: [PhotoItem]?
    let onOpenSelectedPhotos: (([PhotoItem]) -> Void)?
    let onEnterReviewMode: (() -> Void)?
    let onToggleSidebar: (() -> Void)?
    let isSidebarCollapsed: Bool
    let windowWidth: CGFloat
//    @FocusState private var isFocused: Bool
    @Binding var openSelectedPhotosCallback: (() -> Void)?

    @State private var useCollectionView = true
    @State private var scrollToPhotoId: UUID? = nil
    @State private var copyToViewModel: CopyToViewModel? = nil
    @State private var renameSheetPhotos: PhotosSheetItem? = nil
    @State private var showDuplicatesSheet: Bool = false
    @Binding var reviewGroup: ReviewGroupItem?
    @State private var hasAppeared = false

    init(filesModel: FilesModel,
         searchPhotoResults: [PhotoItem]? = nil,
         onOpenSelectedPhotos: (([PhotoItem]) -> Void)?,
         onEnterReviewMode: (() -> Void)?,
         onToggleSidebar: (() -> Void)? = nil,
         isSidebarCollapsed: Bool = false,
         windowWidth: CGFloat = 1200,
         openSelectedPhotosCallback: Binding<(() -> Void)?>,
         reviewGroup: Binding<ReviewGroupItem?>) {

        self._viewModel = StateObject(wrappedValue: ThumbGridViewModel(filesModel: filesModel))
        self.searchPhotoResults = searchPhotoResults
        self.onOpenSelectedPhotos = onOpenSelectedPhotos
        self.onEnterReviewMode = onEnterReviewMode
        self.onToggleSidebar = onToggleSidebar
        self.isSidebarCollapsed = isSidebarCollapsed
        self.windowWidth = windowWidth
        self._openSelectedPhotosCallback = openSelectedPhotosCallback
        self._reviewGroup = reviewGroup
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
//            Button("useCollectionView \(useCollectionView)", action: {
//                useCollectionView.toggle()
//            })
        }
        .preference(key: GridWidthPreferenceKey.self, value: viewModel.gridWidth)
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
        .onChange(of: windowWidth) { _, newWidth in
            viewModel.windowWidth = newWidth
        }
        .onChange(of: isSidebarCollapsed) { _, collapsed in
            viewModel.isSidebarCollapsed = collapsed
        }
        .onAppear {
            viewModel.windowWidth = windowWidth
            viewModel.isSidebarCollapsed = isSidebarCollapsed
        }
    }

    // MARK: - Photo Grid
    // NSCollectionView-based grid
    private var collectionPhotoGridView: some View {
        #if os(macOS)
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
                },
                onReviewSelected: { rightClickedPhoto in
                    let photos = viewModel.selectedPhotos.contains(rightClickedPhoto.id)
                        ? viewModel.getSelectedPhotosForBulkAction()
                        : [rightClickedPhoto]
                    reviewGroup = buildReviewGroupItemFromPhotos(photos)
                }
            ),
            duplicateResult: viewModel.isDuplicateMode ? viewModel.duplicateScanResult : nil,
            onReview: { group, index in
                reviewGroup = buildReviewGroupItem(group: group, index: index)
            },
            dateGroups: viewModel.dateGroups,
            sortOption: viewModel.sortOption,
            scrollToPhotoId: $scrollToPhotoId,
            onKeyPress: { event in
                viewModel.handleKeyEvent(
                    event,
                    scrollTo: { photoId in scrollToPhotoId = photoId },
                    openPhotos: { photos in externalAppManager.openPhotos(photos) },
                    onToggleSidebar: { onToggleSidebar?() },
                    onReviewSelected: { photos in reviewGroup = buildReviewGroupItemFromPhotos(photos) }
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
        #elseif os(iOS)
        UICollectionThumbGridView(
            photos: viewModel.filteredPhotos,
            itemSize: viewModel.gridType.thumbSize,
            cellHeight: viewModel.gridType.cellHeight,
            selectedPhotos: viewModel.selectedPhotos,
            callbacks: ThumbCellCallbacks(
                onTap: { photo, _ in
                    viewModel.handlePhotoTap(photo: photo, modifiers: .none)
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
                },
                onReviewSelected: { rightClickedPhoto in
                    let photos = viewModel.selectedPhotos.contains(rightClickedPhoto.id)
                        ? viewModel.getSelectedPhotosForBulkAction()
                        : [rightClickedPhoto]
                    reviewGroup = buildReviewGroupItemFromPhotos(photos)
                }
            ),
            duplicateResult: viewModel.isDuplicateMode ? viewModel.duplicateScanResult : nil,
            onReview: { group, index in
                reviewGroup = buildReviewGroupItem(group: group, index: index)
            },
            dateGroups: viewModel.dateGroups,
            sortOption: viewModel.sortOption,
            scrollToPhotoId: $scrollToPhotoId
        )
        #endif
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

    private func buildReviewGroupItem(group: DuplicateGroup, index: Int) -> ReviewGroupItem {
        let groups = viewModel.duplicateScanResult?.groups ?? []
        return ReviewGroupItem(
            group: group,
            index: index,
            totalGroups: groups.count,
            onRatingChanged: { photo, rating in viewModel.applyRating(rating, to: [photo]) },
            onApprove: { photo in viewModel.applyLabel("Approved", to: [photo]) },
            onMarkForDeletion: { photo in viewModel.toggleDeleteState(for: [photo]) },
            onNavigate: { newIndex in
                guard newIndex >= 0, newIndex < groups.count else { return }
                reviewGroup = buildReviewGroupItem(group: groups[newIndex], index: newIndex)
            }
        )
    }

    private func buildReviewGroupItemFromPhotos(_ photos: [PhotoItem]) -> ReviewGroupItem {
        let group = DuplicateGroup(photos: photos, distance: 0)
        return ReviewGroupItem(
            group: group,
            index: 0,
            totalGroups: 1,
            onRatingChanged: { photo, rating in viewModel.applyRating(rating, to: [photo]) },
            onApprove: { photo in viewModel.applyLabel("Approved", to: [photo]) },
            onMarkForDeletion: { photo in viewModel.toggleDeleteState(for: [photo]) },
            onNavigate: { _ in }
        )
    }
}

struct PhotosSheetItem: Identifiable {
    let id = UUID()
    let photos: [PhotoItem]
}
