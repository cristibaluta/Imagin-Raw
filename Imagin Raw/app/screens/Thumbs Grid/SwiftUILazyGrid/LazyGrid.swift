//
//  LazyGrid.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 19.03.2026.
//

import Foundation
import SwiftUI

struct PhotoGridView: View {
    @ObservedObject var viewModel: ThumbGridViewModel
    @EnvironmentObject var externalAppManager: ExternalAppManager
    @EnvironmentObject var filesModel: FilesModel
    @FocusState private var isFocused: Bool

    var body: some View {
        if viewModel.isDuplicateMode {
            duplicateGridView
        } else {
            gridView
        }
    }

    private var gridView: some View {
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
                                             onToggleSidebar: {
//                        onToggleSidebar?()
                    })
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
    // MARK: - Thumb Cell

    private func createThumbCell(for photo: PhotoItem) -> some View {
        ThumbCell(
            photo: photo,
            isSelected: viewModel.selectedPhotos.contains(photo.id),
            onTap: { modifiers in
                viewModel.handlePhotoTap(photo: photo, modifiers: modifiers)
            },
            onDoubleClick: {
                //                handleDoubleClick(photo: photo)
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
//                copyToViewModel = CopyToViewModel(photos: photos)
            },
            onRenameTo: { rightClickedPhoto in
                let photos = viewModel.selectedPhotos.contains(rightClickedPhoto.id)
                ? viewModel.getSelectedPhotosForBulkAction()
                : [rightClickedPhoto]
//                renameSheetPhotos = PhotosSheetItem(photos: photos)
            },
            onMoveAllMarkedToTrash: photo.toDelete ? { [viewModel] in
                let marked = viewModel.getPhotosMarkedForDeletion()
                return (count: marked.count, action: { viewModel.movePhotosToTrash(marked) })
            } : nil,
            size: viewModel.gridType.thumbSize,
            thumbsManager: viewModel.thumbsManager
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
    
}
