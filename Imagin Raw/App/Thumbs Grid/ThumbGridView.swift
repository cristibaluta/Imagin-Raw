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
    @FocusState private var isFocused: Bool
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
            if viewModel.isDuplicateMode {
                duplicateGridView
            } else if viewModel.filteredPhotos.isEmpty {
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

    // MARK: - Duplicate Grid

    private var duplicateGridView: some View {
        Group {
            if let result = viewModel.duplicateScanResult {
                if result.groups.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                        Text("No duplicates found")
                            .font(.headline)
                        Text("Scanned \(result.totalScanned) photos in \(String(format: "%.2f", result.duration))s")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                            ForEach(Array(result.groups.enumerated()), id: \.element.id) { groupIndex, group in
                                Section {
                                    LazyVGrid(columns: viewModel.dynamicColumns, spacing: 8) {
                                        ForEach(group.photos) { photo in
                                            createThumbCell(for: photo)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.bottom, 16)
                                } header: {
                                    duplicateGroupHeader(group: group, index: groupIndex, total: result.groups.count)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func duplicateGroupHeader(group: DuplicateGroup, index: Int, total: Int) -> some View {
        let pct = max(0, min(100, Int(((1.0 - Double(group.distance)) * 100).rounded())))
        return HStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Group \(index + 1)")
                    .font(.caption)
                    .foregroundColor(.primary)
                Text("·")
                    .foregroundColor(.secondary)
                Text("\(pct)% similarity")
                    .font(.caption)
                    .foregroundColor(pct >= 90 ? .orange : .secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .circular)
                    .foregroundColor(.black)
            )
            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.clear)
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
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVGrid(columns: viewModel.dynamicColumns, spacing: 8) {
                    ForEach(viewModel.filteredPhotos, id: \.id) { photo in
                        createThumbCell(for: photo)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(scrollViewConfig)
                .focusable()
                .focusEffectDisabled()
                .focused($isFocused)
                .onKeyPress { keyPress in
                    viewModel.handleKeyPress(keyPress,
                                             scrollTo: { photoId in
                                                Task {
                                                    proxy.scrollTo(photoId, anchor: .center)
                                                }
                                            },
                                             openPhotos: { photos in
                                                externalAppManager.openPhotos(photos)
                                            },
                                             onToggleSidebar: { onToggleSidebar?() })
                }
                .onAppear {
                    isFocused = true
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
                .onChange(of: filesModel.selectedFolder) { oldFolder, newFolder in
                    if let firstPhoto = viewModel.filteredPhotos.first {
                        filesModel.selectedPhoto = firstPhoto
                        viewModel.selectedPhotos.removeAll()
                        viewModel.selectedPhotos.insert(firstPhoto.id)
                        viewModel.lastSelectedIndex = 0
                        proxy.scrollTo(firstPhoto.id, anchor: .top)
                    }
                }
            }
        }
    }

    // MARK: - Thumb Cell

    private func createThumbCell(for photo: PhotoItem) -> some View {
        ThumbCell(
            photo: photo,
            isSelected: viewModel.selectedPhotos.contains(photo.id),
            onTap: { modifiers in
                viewModel.handlePhotoTap(photo: photo, modifiers: modifiers)
            },
            onDoubleClick: {
                handleDoubleClick(photo: photo)
            },
            onRatingChanged: { rating in
                viewModel.applyRating(rating, to: [photo])
            },
            onMoveToTrash: { rightClickedPhoto in
                let photosToTrash: [PhotoItem]
                if viewModel.selectedPhotos.contains(rightClickedPhoto.id) {
                    photosToTrash = viewModel.getSelectedPhotosForBulkAction()
                } else {
                    photosToTrash = [rightClickedPhoto]
                }
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
            onMoveAllMarkedToTrash: photo.toDelete ? { [viewModel] in
                let marked = viewModel.getPhotosMarkedForDeletion()
                return (count: marked.count, action: { viewModel.movePhotosToTrash(marked) })
            } : nil,
            size: viewModel.gridType.thumbSize
        )
        #if os(macOS)
        .frame(width: viewModel.gridType.thumbSize, height: viewModel.gridType.cellHeight)
        #endif
        .id(photo.id)
    }

    private var scrollViewConfig: some View {
        GeometryReader { _ in
            Color.clear.onAppear {
                #if os(macOS)
                DispatchQueue.main.async {
                    if let scrollView = NSApp.keyWindow?.contentView?.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView {
                        scrollView.scrollerStyle = .overlay
                        scrollView.hasVerticalScroller = true
                        scrollView.autohidesScrollers = true
                    }
                }
                #endif
            }
        }
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

struct GridWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 450
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct PhotosSheetItem: Identifiable {
    let id = UUID()
    let photos: [PhotoItem]
}
