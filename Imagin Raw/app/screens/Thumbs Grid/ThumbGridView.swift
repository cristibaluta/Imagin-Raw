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

    let searchPhotoResults: [PhotoItem]?
    let onEnterReviewMode: (() -> Void)?
    let onToggleSidebar: (() -> Void)?
    let isSidebarCollapsed: Bool
    let windowWidth: CGFloat

    @State private var scrollToPhotoId: UUID? = nil
    @State private var scrollToCenteredPhotoId: UUID? = nil
    @State private var visibleSectionIndex: Int = 0
    @State private var copyToViewModel: CopyToViewModel? = nil
    @State private var renameSheetPhotos: PhotosSheetItem? = nil
    @State private var showDuplicatesSheet: Bool = false
    @State private var isSelectMode: Bool = false
    @State private var hasAppeared = false
    @State private var ignoringSearchResults = false

    init(appState: AppState,
         viewModel: ThumbGridViewModel,
         searchPhotoResults: [PhotoItem]? = nil,
         onEnterReviewMode: (() -> Void)?,
         onToggleSidebar: (() -> Void)? = nil,
         isSidebarCollapsed: Bool = false,
         windowWidth: CGFloat = 1200) {

        self.appState = appState
        self.viewModel = viewModel
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
                ThumbsBottomBar(viewModel: viewModel, showDuplicatesSheet: $showDuplicatesSheet)
            }
        }
        .preference(key: GridWidthPreferenceKey.self, value: viewModel.gridWidth)
        .sheet(item: $copyToViewModel) { vm in
            CopyToView(viewModel: vm)
                .environmentObject(appState.fileSystemModel)
                .interactiveDismissDisabled(false)
        }
        .sheet(item: $renameSheetPhotos) { item in
            RenameView(photosToRename: item.photos)
                .interactiveDismissDisabled(false)
        }
        .sheet(isPresented: $showDuplicatesSheet) {
            DuplicatesResultSheet(viewModel: viewModel)
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
            delegate: self,
            photos: viewModel.groupedPhotos,
            selectedPhotos: viewModel.selectedPhotos,
            itemSize: viewModel.gridType.thumbSize,
            cellHeight: viewModel.gridType.cellHeight,
            isDuplicateMode: viewModel.isDuplicateMode,
            onReview: { groupIndex in
                appState.reviewGroup = buildReviewGroupItem(groupIndex: groupIndex)
            },
            onKeyPress: { event in
                viewModel.handleKeyEvent(
                    event,
                    scrollTo: { photoId in scrollToCenteredPhotoId = photoId },
                    openPhotos: { photos in appState.externalAppManager.openPhotos(photos) },
                    onToggleSidebar: { onToggleSidebar?() },
                    onReviewSelected: { photos in appState.reviewGroup = buildReviewGroupItemFromPhotos(photos) }
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

    private func buildReviewGroupItem(groupIndex: Int) -> ReviewGroupItem {
        guard let groups = viewModel.duplicateScanResult?.groups, groupIndex < groups.count else {
            fatalError()
        }
        let group = groups[groupIndex]
        return ReviewGroupItem(
            group: group,
            index: groupIndex,
            totalGroups: groups.count,
            onRatingChanged: { photo, rating in
                viewModel.applyRating(rating, to: [photo])
            },
            onApprove: { photo in
                viewModel.applyLabel(.approved, to: [photo])
            },
            onMarkForDeletion: { photo in
                viewModel.toggleRejectedState(for: [photo])
            },
            onNavigate: { newIndex in
                guard newIndex >= 0, newIndex < groups.count else {
                    return
                }
                appState.reviewGroup = buildReviewGroupItem(groupIndex: newIndex)
                appState.reviewViewModel.setup(with: appState.reviewGroup!)
            }
        )
    }

    private func buildReviewGroupItemFromPhotos(_ photos: [PhotoItem]) -> ReviewGroupItem {
        let group = DuplicateGroup(photos: photos, distance: 0)
        return ReviewGroupItem(
            group: group,
            index: 0,
            totalGroups: 1,
            onRatingChanged: { photo, rating in
                viewModel.applyRating(rating, to: [photo])
            },
            onApprove: { photo in
                viewModel.applyLabel(.approved, to: [photo])
            },
            onMarkForDeletion: { photo in
                viewModel.toggleRejectedState(for: [photo])
            },
            onNavigate: { _ in }
        )
    }
}

// TODO: this should stay in the viewModel
extension ThumbGridView: ThumbCellDelegate {

    func image(for photo: PhotoItem, completion: @escaping @Sendable (IRImage?) -> Void) -> Void {
        viewModel.requestImage(for: photo, completion: completion)
    }

    func startCachingImages(for photos: [PhotoItem]) {
        viewModel.startCachingImages(for: photos)
    }

    func stopCachingImages(for photos: [PhotoItem]) {
        viewModel.stopCachingImages(for: photos)
    }

    func onTap(photo: PhotoItem, modifiers: NSEvent.ModifierFlags) {
        viewModel.handlePhotoTap(photo: photo, modifiers: modifiers)
    }

    func onDoubleClick(photo: PhotoItem) {
        if viewModel.selectedPhotos.contains(where: { $0.id == photo.id }) {
            // If we double click one of the selected photos, open all of them
            appState.externalAppManager.openPhotos(viewModel.selectedPhotos)
        } else {
            appState.externalAppManager.openPhotos([photo])
        }
    }

    func onRatingChanged(photo: PhotoItem, rating: Int) {
        viewModel.applyRating(rating, to: [photo])
    }

    func onLabelChanged(photo: PhotoItem, label: PhotoLabel?) {
        if let label {
            viewModel.applyLabel(label, to: [photo])
        } else {
            viewModel.removeLabels(from: [photo])
        }
    }

    func onMoveToTrash(photo: PhotoItem) {
        viewModel.movePhotosToTrash([photo])
    }

    func onCopyTo(photo: PhotoItem) {
        let photos = viewModel.selectedPhotos.contains(photo)
            ? viewModel.selectedPhotos
            : [photo]
        copyToViewModel = CopyToViewModel(photos: photos)
    }

    func onQuickCopy(photo: PhotoItem) {
        let photos = viewModel.selectedPhotos.contains(photo)
            ? viewModel.selectedPhotos
            : [photo]
        viewModel.quickCopy(photos: photos)
    }

    func onRenameTo(photo: PhotoItem) {
        let photos = viewModel.selectedPhotos.contains(photo)
            ? viewModel.selectedPhotos
            : [photo]
        renameSheetPhotos = PhotosSheetItem(photos: photos)
    }

    func onMoveAllMarkedToTrash(photo: PhotoItem) {
        let marked = viewModel.getPhotosMarkedForDeletion()
        viewModel.movePhotosToTrash(marked)
    }

    func onApprove(photo: PhotoItem) {
        viewModel.applyLabel(.approved, to: [photo])
    }

    func onReject(photo: PhotoItem) {
        viewModel.toggleRejectedState(for: [photo])
    }

    func onReviewSelected(photo: PhotoItem) {
        let photos = viewModel.selectedPhotos.contains(photo)
            ? viewModel.selectedPhotos
            : [photo]
        appState.reviewGroup = buildReviewGroupItemFromPhotos(photos)
    }

    func onOpenWith(photo: PhotoItem, app: PhotoApp) {
        let photos = viewModel.selectedPhotos.contains(photo)
            ? viewModel.selectedPhotos
            : [photo]
        appState.externalAppManager.openPhotos(photos, with: app)
    }

    func onCreateVideo(photos: [PhotoItem]) {
        // If the tapped photo is part of the current selection, use all selected
        let triggerPhoto = photos.first
        let isInSelection = triggerPhoto.map { viewModel.selectedPhotos.contains($0) } ?? false
        guard isInSelection else {
            return
        }
        appState.previewViewModel.showVideoEditor = true
    }

    func onCreatePDF(photos: [PhotoItem]) {
        let triggerPhoto = photos.first
        let isInSelection = triggerPhoto.map { viewModel.selectedPhotos.contains($0) } ?? false
        guard isInSelection else {
            return
        }
        appState.previewViewModel.showPDFEditor = true
    }

    func selectedPhotosCount() -> Int {
        viewModel.selectedPhotos.count
    }

    func markedForDeletionCount() -> Int {
        viewModel.getPhotosMarkedForDeletion().count
    }

    func discoveredPhotoApps() -> [PhotoApp] {
        appState.externalAppManager.discoveredPhotoApps
    }
}
