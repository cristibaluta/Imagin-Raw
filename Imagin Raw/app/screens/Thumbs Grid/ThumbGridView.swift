//
//  ThumbGridView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 06.02.2026.
//

import SwiftUI

struct PhotosSheetItem: Identifiable {
    let id = UUID()
    let photos: [PhotoItem]
}

struct GridWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 450
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

@MainActor
struct ThumbGridView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var viewModel: ThumbGridViewModel
    @ObservedObject private var duplicatesFinderModel: DuplicatesFinderViewModel

    let searchPhotoResults: [PhotoItem]?
    let onEnterReviewMode: (() -> Void)?
    let onToggleSidebar: (() -> Void)?
    let isSidebarCollapsed: Bool
    let windowWidth: CGFloat

    @State private var scrollToPhotoId: UUID? = nil
    @State private var scrollToCenteredPhotoId: UUID? = nil
    @State private var visibleSectionIndex: Int = 0
    @State private var isSelectMode: Bool = false
    @State private var hasAppeared = false
    @State private var ignoringSearchResults = false

    init(appState: AppState,
         viewModel: ThumbGridViewModel,
         duplicatesFinderModel: DuplicatesFinderViewModel,
         searchPhotoResults: [PhotoItem]? = nil,
         onEnterReviewMode: (() -> Void)?,
         onToggleSidebar: (() -> Void)? = nil,
         isSidebarCollapsed: Bool = false,
         windowWidth: CGFloat = 1200) {

        self.appState = appState
        self.viewModel = viewModel
        self.duplicatesFinderModel = duplicatesFinderModel
        self.searchPhotoResults = searchPhotoResults
        self.onEnterReviewMode = onEnterReviewMode
        self.onToggleSidebar = onToggleSidebar
        self.isSidebarCollapsed = isSidebarCollapsed
        self.windowWidth = windowWidth
    }

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        VStack(spacing: 0) {
            // Top line separator
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: 1)

            if viewModel.filteredAndSortedPhotos.isEmpty {
                // No photos found
                HStack(spacing: 0) {
                    EmptyStateView(viewModel: viewModel)
                        .padding(20)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1)
                }
            } else {
                // Photos
                HStack(spacing: 0) {
                    // Minimap
                    if viewModel.showMinimap {
                        MinimapView(
                            groups: viewModel.groupedPhotos,
                            onScrollTo: { photoId in scrollToPhotoId = photoId },
                            visibleSectionIndex: visibleSectionIndex)
                    }

                    // Grid
                    collectionPhotoGridView

                    // Separator to previews
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1)
                }
            }
            // Bottom bar
            if !viewModel.photos.isEmpty {
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(height: 1)
                ThumbsBottomBar(viewModel: viewModel, duplicateViewModel: duplicatesFinderModel)
            }
        }
        .preference(key: GridWidthPreferenceKey.self, value: viewModel.gridWidth)
        .sheet(item: $viewModel.copyToViewModel) { vm in
            CopyToView(viewModel: vm)
                .environmentObject(appState.fileSystemModel)
                .interactiveDismissDisabled(false)
        }
        .sheet(item: $viewModel.renameViewModel) { vm in
            RenameView(photosToRename: vm.photos)
                .interactiveDismissDisabled(false)
        }
        .sheet(isPresented: $duplicatesFinderModel.showDuplicatesSheet) {
            DuplicatesResultSheet(viewModel: duplicatesFinderModel)
        }
        .onChange(of: searchPhotoResults) { oldResults, newResults in
            if let results = newResults {
                // If we were ignoring search results due to folder selection,
                // only keep ignoring if the results haven't actually changed (same search query).
                // New/different results mean the user typed again.
                if ignoringSearchResults {
                    if oldResults?.count != results.count || oldResults?.first?.id != results.first?.id {
                        ignoringSearchResults = false
                    } else {
                        return
                    }
                }
                viewModel.loadSearchResults(results)
            } else {
                ignoringSearchResults = false
                viewModel.clearSearchResults()
                if let folder = appState.fileSystemModel.selectedFolder {
                    viewModel.loadPhotosForFolder(folder, includeSubfolders: false)
                }
            }
        }
        .onChange(of: appState.fileSystemModel.photoMetadataDidChangeURL) { _, url in
            if let url {
                viewModel.reloadMetadata(forSidecar: url)
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
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        #if os(macOS)
        return MacThumbGridView(
            delegate: viewModel,
            photos: viewModel.groupedPhotos,
            selectedPhotos: viewModel.selectedPhotos,
            itemSize: viewModel.gridType.thumbSize,
            cellHeight: viewModel.gridType.cellHeight,
            isDuplicateMode: duplicatesFinderModel.isDuplicateMode,
            onReview: { groupIndex in
                viewModel.buildReviewGroupItem(groupIndex: groupIndex)
            },
            onKeyPress: { event in
                viewModel.handleKeyEvent(
                    event,
                    scrollTo: { photoId in scrollToCenteredPhotoId = photoId },
                    openPhotos: { photos in appState.externalAppManager.openPhotos(photos) },
                    onToggleSidebar: { onToggleSidebar?() },
                    onReviewSelected: { photos in viewModel.buildReviewGroupItemFromPhotos(photos) }
                )
            },
            thumbsManager: viewModel.thumbsManager,
            isSearchActive: searchPhotoResults != nil,
            scrollToPhotoId: $scrollToPhotoId,
            scrollToCenteredPhotoId: $scrollToCenteredPhotoId,
            visibleSectionIndex: $visibleSectionIndex
        )
        .id(appState.selectedFolder?.id)
        .onChange(of: viewModel.filteredAndSortedPhotos) { oldPhotos, newPhotos in
            // Scroll to top when a new folder's photos first appear (transition from empty to non-empty)
            if oldPhotos.isEmpty && !newPhotos.isEmpty, let first = newPhotos.first {
                scrollToPhotoId = first.id
            }
        }
        .onChange(of: viewModel.isLoadingMetadata) { oldValue, newValue in
            if oldValue == true && newValue == false {
                viewModel.clearInvalidFilters()
            }
        }
        #elseif os(iOS)
        IosThumbGridView(
            delegate: self,
            photos: viewModel.filteredAndSortedPhotos,
            itemSize: viewModel.gridType.thumbSize,
            cellHeight: viewModel.gridType.cellHeight,
            columnCount: viewModel.gridType.columnCount,
            selectedPhotos: viewModel.selectedPhotos,
            isSelectMode: isSelectMode,
            onSelectToggle: {_ in },
            onNavigate: { photo in

            },
            onSelectRange: {_ in },
            duplicateResult: viewModel.isDuplicateMode ? viewModel.duplicateScanResult : nil,
            onReview: { group, index in
                appState.reviewGroup = buildReviewGroupItem(group: group, index: index)
            },
            dateGroups: viewModel.dateGroups,
            sortOption: viewModel.sortOption,
            scrollToPhotoId: $scrollToPhotoId,
            visibleSectionIndex: $visibleSectionIndex,
            thumbsManager: viewModel.thumbsManager,
            isLoadingMetadata: viewModel.isLoadingMetadata,
            onStartSelectMode: { photo in
                isSelectMode = true
                viewModel.handlePhotoTap(photo: photo, modifiers: .none)
            },
            onEndSelectMode: {
                isSelectMode = false
                viewModel.selectedPhotos.removeAll()
            }
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSelectMode {
                    Button("End Selection") {
                        isSelectMode = false
                        viewModel.selectedPhotos.removeAll()
                    }
                }
            }
        }
        .onChange(of: viewModel.filteredAndSortedPhotos) { oldPhotos, newPhotos in
//            currentPhotos = newPhotos
            let url = appState.fileSystemModel.selectedFolder?.url
            let isPhotoKit = url?.isPhotoLibraryRoot == true || url?.isPhotoKitAlbum == true
            // Only scroll when photos are actually added, not on metadata updates
            if isPhotoKit, newPhotos.count > oldPhotos.count, let last = newPhotos.last {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    scrollToPhotoId = last.id
                }
            }
        }
        #endif
    }
}
