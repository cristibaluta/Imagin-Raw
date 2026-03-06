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

    let selectedApp: PhotoApp?
    let searchPhotoResults: [PhotoItem]?
    let onOpenSelectedPhotos: (([PhotoItem]) -> Void)?
    let onEnterReviewMode: (() -> Void)?
    @FocusState private var isFocused: Bool
    @Binding var openSelectedPhotosCallback: (() -> Void)?

    @State private var showFilterPopover = false
    @State private var showSortPopover = false
    @State private var showGridTypePopover = false
    @State private var copyToSheetPhotos: PhotosSheetItem? = nil
    @State private var renameSheetPhotos: PhotosSheetItem? = nil

    init(filesModel: FilesModel, selectedApp: PhotoApp?, searchPhotoResults: [PhotoItem]? = nil, onOpenSelectedPhotos: (([PhotoItem]) -> Void)?, onEnterReviewMode: (() -> Void)?, openSelectedPhotosCallback: Binding<(() -> Void)?>) {
        self._viewModel = StateObject(wrappedValue: ThumbGridViewModel(filesModel: filesModel))
        self.selectedApp = selectedApp
        self.searchPhotoResults = searchPhotoResults
        self.onOpenSelectedPhotos = onOpenSelectedPhotos
        self.onEnterReviewMode = onEnterReviewMode
        self._openSelectedPhotosCallback = openSelectedPhotosCallback
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main thumbnail grid
            ScrollViewReader { proxy in
                GeometryReader { geometry in
                    if viewModel.filteredPhotos.isEmpty {
                        emptyStateView
                    } else {
                        photoGridView(proxy: proxy, geometry: geometry)
                    }
                }
            }

            // Filter and Sort bar
            if !viewModel.photos.isEmpty {
                filterSortBar
            }
        }
        .preference(key: GridWidthPreferenceKey.self, value: viewModel.gridWidth+16)
        .sheet(item: $copyToSheetPhotos) { item in
            CopyToView(photosToCoрy: item.photos)
                .environmentObject(filesModel)
                .interactiveDismissDisabled(false)
        }
        .sheet(item: $renameSheetPhotos) { item in
            RenameView(photosToRename: item.photos)
                .interactiveDismissDisabled(false)
        }
        .onAppear {
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
                // Search is active: show search photo results
                viewModel.loadSearchResults(results)
            } else {
                // Search was cleared: revert to the currently selected folder
                viewModel.clearSearchResults()
                if let folder = filesModel.selectedFolder {
                    viewModel.loadPhotosForFolder(folder)
                }
            }
        }
        .onChange(of: filesModel.selectedFolder) { oldFolder, newFolder in
            guard let folder = newFolder, oldFolder?.url != newFolder?.url else { return }
            // A folder was selected (either normally or from search results).
            // Always load its photos — this overrides search results in the content column.
            // The search sidebar stays untouched.
            viewModel.clearSearchResults()
            viewModel.loadPhotosForFolder(folder)
            filesModel.selectedPhoto = nil
            viewModel.selectedPhotos.removeAll()
        }
        .onChange(of: filesModel.folderContentDidChange) { oldValue, newValue in
            if newValue != nil {
                viewModel.reloadPhotos()
            }
        }
    }

    // MARK: - View Components

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text(viewModel.photos.isEmpty ? "No Supported Photos Found" : "No Photos Match Current Filter")
                    .font(.headline)
                    .foregroundColor(.primary)

                if viewModel.photos.isEmpty {
                    Text("This folder doesn't contain any supported image formats.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Text("Supported formats: RAW files (CR2, NEF, ARW, etc.), JPEG, PNG, TIFF")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Try adjusting your filter settings to see more photos.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func photoGridView(proxy: ScrollViewProxy, geometry: GeometryProxy) -> some View {
        let content = ScrollView(.vertical) {
            LazyVGrid(columns: viewModel.dynamicColumns, spacing: 8) {
                ForEach(viewModel.filteredPhotos, id: \.id) { photo in
                    createThumbCell(for: photo)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }

        return content
            .background(scrollViewConfig)
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .onKeyPress { keyPress in
                handleKeyPress(keyPress, proxy: proxy, viewportHeight: geometry.size.height)
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
                print("🔔 isLoadingMetadata changed: \(oldValue) -> \(newValue)")
                // When metadata loading completes, clear invalid filters
                if oldValue == true && newValue == false {
                    print("🎯 Calling clearInvalidFilters()")
                    viewModel.clearInvalidFilters()
                }
            }
            .onChange(of: filesModel.selectedFolder) { oldFolder, newFolder in
                // Scroll to top and select first photo when folder changes
                if let firstPhoto = viewModel.filteredPhotos.first {
                    filesModel.selectedPhoto = firstPhoto
                    viewModel.selectedPhotos.removeAll()
                    viewModel.selectedPhotos.insert(firstPhoto.id)
                    viewModel.lastSelectedIndex = 0
                    proxy.scrollTo(firstPhoto.id, anchor: .top)
                }
            }
    }

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
                copyToSheetPhotos = PhotosSheetItem(photos: photos)
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
        .frame(width: viewModel.gridType.thumbSize, height: viewModel.gridType.cellHeight)
        .id(photo.id)
    }

    private var scrollViewConfig: some View {
        GeometryReader { _ in
            Color.clear.onAppear {
                configureScrollView()
            }
        }
    }

    private var filterSortBar: some View {
        HStack(spacing: 12) {
            // Grid Type button
            Button(action: {
                viewModel.toggleGridType()
            }) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.leading, 8)

            // Sort button
            Button(action: {
                showSortPopover.toggle()
            }) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
            }
            .buttonStyle(PlainButtonStyle())
            .popover(isPresented: $showSortPopover) {
                SortPopoverView(sortOption: $viewModel.sortOption)
            }
            .onChange(of: viewModel.sortOption) { _, _ in
                viewModel.saveSortOption()
            }

            // Filter section
            HStack(spacing: 2) {
                Button(action: {
                    showFilterPopover.toggle()
                }) {
                    Text("Filter")
                        .font(.caption)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                }
                .buttonStyle(PlainButtonStyle())
                .popover(isPresented: $showFilterPopover) {
                    FilterPopoverView(selectedLabels: $viewModel.selectedLabels,
                                      selectedRatings: $viewModel.selectedRatings,
                                      photos: viewModel.photos)
                }

                ForEach(viewModel.availableLabels, id: \.self) { label in
                    Button(action: {
                        viewModel.toggleLabelFilter(label)
                    }) {
                        let iconName = if label == "Rejected" {
                            viewModel.selectedLabels.contains(label) ? "x.square.fill" : "x.square"
                        } else {
                            viewModel.selectedLabels.contains(label) ? "checkmark.square.fill" : "square.fill"
                        }
                        Image(systemName: iconName)
                            .foregroundColor(viewModel.getColorForLabel(label))
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(label)
                }

                // TODO show this only if there are starred photos
                if true {
                    Button(action: {
                        if viewModel.selectedRatings.isEmpty {
                            viewModel.selectedRatings = [1, 2, 3, 4, 5]
                        } else {
                            viewModel.selectedRatings = []
                        }
                    }) {
                        Image(systemName: viewModel.selectedRatings.isEmpty ? "star" : "star.fill")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Filter by all ratings")
                }
            }
            .padding(.horizontal, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
            )
            .layoutPriority(1)

            Spacer()

            // Photo count
            photoCountText
        }
        .frame(height: 40)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var photoCountText: some View {
        Group {
            // Priority 1: Show metadata loading when collecting XMP and rating data
            if viewModel.isLoadingMetadata {
                Text("Collecting metadata...")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            // Priority 2: Show caching progress when generating thumbnails
            else if viewModel.showCachingProgress {
                Text("Generating \(viewModel.cachingQueueCount) thumbnails...")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            // Priority 3: Show selected count when multiple photos selected
            else if viewModel.selectedPhotos.count > 1 {
                Text("\(viewModel.selectedPhotos.count) of \(viewModel.photos.count) selected")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            // Priority 4: Show filtered count when filters are active
            else if viewModel.selectedLabels.count > 0 || viewModel.selectedRatings.count > 0 {
                Text("\(viewModel.filteredPhotos.count) of \(viewModel.photos.count) photos")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            // Priority 5: Show total count
            else {
                Text("\(viewModel.photos.count) photos")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .lineLimit(1)
        .padding(.trailing, 8)
    }

    // MARK: - Event Handlers

    private func handleDoubleClick(photo: PhotoItem) {
        filesModel.selectedPhoto = photo
        if viewModel.selectedPhotos.count > 1 {
            let selectedPhotoItems = viewModel.filteredPhotos.filter { viewModel.selectedPhotos.contains($0.id) }
            externalAppManager.openPhotos(selectedPhotoItems, with: selectedApp)
        } else {
            externalAppManager.openPhoto(photo, with: selectedApp)
        }
    }

    private func handleKeyPress(_ keyPress: KeyPress, proxy: ScrollViewProxy, viewportHeight: CGFloat) -> KeyPress.Result {
        guard !viewModel.filteredPhotos.isEmpty else { return .ignored }

        let currentIndex = viewModel.filteredPhotos.firstIndex { $0.id == filesModel.selectedPhoto?.id } ?? 0
        var newIndex = currentIndex

        switch keyPress.key {
        case .leftArrow:
            newIndex = max(0, currentIndex - 1)
        case .rightArrow:
            newIndex = min(viewModel.filteredPhotos.count - 1, currentIndex + 1)
        case .upArrow:
            newIndex = max(0, currentIndex - viewModel.gridType.columnCount)
        case .downArrow:
            newIndex = min(viewModel.filteredPhotos.count - 1, currentIndex + viewModel.gridType.columnCount)
        case .return:
            handleReturnKey()
            return .handled
        case .space:
            if filesModel.selectedPhoto != nil {
                onEnterReviewMode?()
            }
            return .handled
        case .delete:
            return handleOtherKeys(keyPress)
        default:
            return handleOtherKeys(keyPress)
        }

        if newIndex != currentIndex {
            viewModel.navigateToPhoto(at: newIndex)
            proxy.scrollTo(viewModel.filteredPhotos[newIndex].id, anchor: .center)
            return .handled
        }

        return .ignored
    }

    private func handleReturnKey() {
        if viewModel.selectedPhotos.count > 1 {
            let selectedPhotoItems = viewModel.filteredPhotos.filter { viewModel.selectedPhotos.contains($0.id) }
            externalAppManager.openPhotos(selectedPhotoItems, with: selectedApp)
        } else if let selectedPhoto = filesModel.selectedPhoto {
            externalAppManager.openPhoto(selectedPhoto, with: selectedApp)
        }
    }

    private func handleOtherKeys(_ keyPress: KeyPress) -> KeyPress.Result {
        let photos = viewModel.getSelectedPhotosForBulkAction()
        guard !photos.isEmpty else { return .ignored }

        // Command+A for Select All
        if keyPress.modifiers.contains(.command) && keyPress.characters == "a" {
            viewModel.selectAll()
            return .handled
        }

        // Command+Z for Undo last trash
        if keyPress.modifiers.contains(.command) && keyPress.characters == "z" {
            viewModel.undoLastTrash()
            return .handled
        }

        // Cmd+Delete — immediately trash selected photos
        // The Delete (backspace) key sends \u{7F}, also check keyPress.key == .delete
        if keyPress.modifiers.contains(.command) &&
            (keyPress.key == .delete || keyPress.characters == "\u{7F}") {
            viewModel.movePhotosToTrash(photos)
            return .handled
        }

        let key = keyPress.characters

        // Filter to only RAW files for rating and labeling operations
        let rawPhotos = photos.filter { $0.isRawFile }
        guard !rawPhotos.isEmpty else { return .ignored }

        // Rating keys (1-5)
        if let rating = Int(key), rating >= 1 && rating <= 5 {
            viewModel.applyRating(rating, to: rawPhotos)
            return .handled
        }

        // Label keys (6-0)
        let labelMap: [String: String] = [
            "6": "Select",
            "7": "Second",
            "8": "Approved",
            "9": "Review",
            "0": "To Do"
        ]

        if let label = labelMap[key] {
            viewModel.applyLabel(label, to: rawPhotos)
            return .handled
        }

        // Remove label
        if key == "-" {
            viewModel.removeLabels(from: rawPhotos)
            return .handled
        }

        // Toggle reject state (X key, works for all files)
        if key == "x" || key == "X" {
            viewModel.toggleDeleteState(for: photos)
            return .handled
        }
        if key == "a" || key == "A" {
            viewModel.applyLabel(labelMap["8"]!, to: rawPhotos)
            return .handled
        }

        return .ignored
    }

    private func configureScrollView() {
        DispatchQueue.main.async {
            if let scrollView = NSApp.keyWindow?.contentView?.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView {
                scrollView.scrollerStyle = .legacy
                scrollView.hasVerticalScroller = true
                scrollView.autohidesScrollers = false
            }
        }
    }
}

struct ViewOffsetKey: PreferenceKey {
    typealias Value = CGFloat
    static var defaultValue = CGFloat.zero
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value += nextValue()
    }
}

struct GridWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 450
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Identifiable wrapper so .sheet(item:) gets the photos at the moment of presentation,
/// avoiding the stale-state bug that occurs with .sheet(isPresented:) + a separate array.
struct PhotosSheetItem: Identifiable {
    let id = UUID()
    let photos: [PhotoItem]
}
