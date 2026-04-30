//
//  ThumbsBottomBar.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 17.03.2026.
//

import SwiftUI

struct ThumbsBottomBar: View {
    @StateObject var viewModel: ThumbGridViewModel
    @Binding var showDuplicatesSheet: Bool
    @State private var showFilterPopover = false
    @State private var showSortPopover = false

    var body: some View {
        HStack(spacing: 12) {
            buttonGrid
                .padding(.leading, 8)

            if viewModel.isDuplicateMode {
                Spacer()
                if !viewModel.isFindingDuplicates {
                    HStack(spacing: 0) {
                        ForEach(DuplicateFinderService.SimilarityMode.allCases, id: \.self) { mode in
                            Button(action: { viewModel.setSimilarityMode(mode) }) {
                                Text(mode.label)
                                    .font(.system(size: 10, weight: viewModel.similarityMode == mode ? .semibold : .regular))
                                    .foregroundColor(viewModel.similarityMode == mode ? .primary : .secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(viewModel.similarityMode == mode ? Color.accentColor.opacity(0.15) : Color.clear)
                            }
                            .buttonStyle(PlainButtonStyle())
                            if mode != DuplicateFinderService.SimilarityMode.allCases.last {
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.3))
                                    .frame(width: 1, height: 14)
                            }
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                    )

                    buttonExitDuplicates

//                    if let result = viewModel.duplicateScanResult {
//                        let totalDupePhotos = result.groups.reduce(0) { $0 + $1.photos.count }
//                        Text("\(result.groups.count) group(s), \(totalDupePhotos) duplicates")
//                            .font(.caption)
//                            .foregroundColor(.blue)
//                            .lineLimit(1)
//                            .padding(.trailing, 8)
//                    }
                }
            } else {
                buttonSort
                buttonsFilters
                buttonFindDuplicates
                Spacer()
                photoCountText
            }

            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 1, height: 14)
        }
        .frame(height: 40)
    }

    private var buttonGrid: some View {
        Button(action: {
            viewModel.toggleGridType()
        }) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var buttonSort: some View {
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
    }

    private var buttonsFilters: some View {
        HStack(spacing: 2) {
            Button(action: { showFilterPopover.toggle() }) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
            }
            .padding(4)
            .buttonStyle(PlainButtonStyle())
            .popover(isPresented: $showFilterPopover) {
                FilterPopoverView(selectedLabels: $viewModel.selectedLabels,
                                  selectedRatings: $viewModel.selectedRatings,
                                  photos: viewModel.photos)
            }

            ForEach(viewModel.availableLabels, id: \.self) { label in
                Button(action: { viewModel.toggleLabelFilter(label) }) {
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

            Spacer().frame(width: 4)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.gray.opacity(0.5), lineWidth: 1)
        )
        .layoutPriority(1)
    }

    private var buttonFindDuplicates: some View {
        Button(action: {
            viewModel.findDuplicates()
            showDuplicatesSheet = true
        }) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
        }
        .buttonStyle(PlainButtonStyle())
        .help("Find duplicate or similar photos")
    }

    private var buttonExitDuplicates: some View {
        Button(action: {
            viewModel.exitDuplicateMode()
        }) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.blue)
        }
        .buttonStyle(PlainButtonStyle())
        .help("Exit duplicates view")
    }

    private var photoCountText: some View {
        Group {
            if viewModel.isLoadingMetadata {
                Text("Collecting metadata...")
                    .foregroundColor(.orange)
            } else if viewModel.showCachingProgress {
                Text("Generating \(viewModel.cachingQueueCount) thumbnails...")
                    .foregroundColor(.orange)
            } else if viewModel.selectedPhotos.count > 1 {
                Text("\(viewModel.selectedPhotos.count) of \(viewModel.photos.count) selected")
                    .foregroundColor(.blue)
            } else if viewModel.selectedLabels.count > 0 || viewModel.selectedRatings.count > 0 {
                Text("\(viewModel.filteredPhotos.count) of \(viewModel.photos.count) photos")
                    .foregroundColor(.secondary)
            } else {
                Text("\(viewModel.photos.count) photos")
                    .foregroundColor(.secondary)
            }
        }
        .font(.caption)
        .lineLimit(1)
    }
}
