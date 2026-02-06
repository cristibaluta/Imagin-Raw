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
    let onOpenSelectedPhotos: (([PhotoItem]) -> Void)?
    let onEnterReviewMode: (() -> Void)?

    @FocusState private var isFocused: Bool
    @State private var showFilterPopover = false
    @State private var showSortPopover = false
    @State private var showGridTypePopover = false

    init(filesModel: FilesModel, selectedApp: PhotoApp?, onOpenSelectedPhotos: (([PhotoItem]) -> Void)?, onEnterReviewMode: (() -> Void)?) {
        self._viewModel = StateObject(wrappedValue: ThumbGridViewModel(filesModel: filesModel))
        self.selectedApp = selectedApp
        self.onOpenSelectedPhotos = onOpenSelectedPhotos
        self.onEnterReviewMode = onEnterReviewMode
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
        .frame(width: viewModel.gridWidth)
        .fixedSize(horizontal: true, vertical: false)
        .preference(key: GridWidthPreferenceKey.self, value: viewModel.gridWidth)
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
        let content = ScrollView(.vertical, showsIndicators: true) {
            LazyVGrid(columns: viewModel.dynamicColumns, spacing: 8) {
                ForEach(viewModel.filteredPhotos, id: \.id) { photo in
                    createThumbCell(for: photo)
                }
            }
            .padding(.horizontal, 4)
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
            .onChange(of: viewModel.photos) { _, newPhotos in
                if filesModel.selectedPhoto == nil && !newPhotos.isEmpty {
                    filesModel.selectedPhoto = newPhotos.first
                }
            }
            .onChange(of: filesModel.selectedFolder) { _, newFolder in
                // Scroll to top and select first photo when folder changes
                if let firstPhoto = viewModel.filteredPhotos.first {
                    // Select the first photo
                    filesModel.selectedPhoto = firstPhoto
                    viewModel.selectedPhotos.removeAll()
                    viewModel.selectedPhotos.insert(firstPhoto.id)
                    viewModel.lastSelectedIndex = 0

                    // Scroll to top without animation
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
                    FilterPopoverView(selectedLabels: $viewModel.selectedLabels, photos: viewModel.photos)
                }

                ForEach(viewModel.availableLabels, id: \.self) { label in
                    Button(action: {
                        viewModel.toggleLabelFilter(label)
                    }) {
                        Image(systemName: viewModel.selectedLabels.contains(label) ? "checkmark.square.fill" : "square")
                            .foregroundColor(viewModel.getColorForLabel(label))
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(label)
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
            if viewModel.selectedPhotos.count > 1 {
                Text("\(viewModel.selectedPhotos.count) of \(viewModel.photos.count) selected")
                    .font(.caption)
                    .foregroundColor(.blue)
            } else if viewModel.selectedLabels.count > 0 {
                Text("\(viewModel.filteredPhotos.count) of \(viewModel.photos.count) photos")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
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

        let key = keyPress.characters

        // Rating keys (1-5)
        if let rating = Int(key), rating >= 1 && rating <= 5 {
            viewModel.applyRating(rating, to: photos)
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
            viewModel.applyLabel(label, to: photos)
            return .handled
        }

        // Remove label
        if key == "-" {
            viewModel.removeLabels(from: photos)
            return .handled
        }

        // Toggle delete state
        if key == "\u{7F}" || key == "d" || key == "D" {
            viewModel.toggleDeleteState(for: photos)
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
