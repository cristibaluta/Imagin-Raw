//
//  PhotoSinglePreviewView 2.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 31.07.2026.
//

import SwiftUI

struct PhotosPreviewView: View {

    @ObservedObject var viewModel: PreviewViewModel

    @State private var showPDFExportPanel = false
    @State private var showVideoExportPanel = false

    @State private var showExportPanel = false
    @State private var gridType = GridType(rawValue: appPrefs.string(.gridType)) ?? .small

    var body: some View {
        previewBody
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay(alignment: .topLeading) {
                HStack(spacing: 0) {
                    reviewButton
                    pagePill
                    Spacer()
                }
            }
            .sheet(item: $viewModel.exportJob) { job in
                ExportJPEGProgressView(job: job)
                    .interactiveDismissDisabled(true)
            }
    }

    @ViewBuilder
    private var previewBody: some View {
        VStack(spacing: 0) {
            MacFitGridView(photos: viewModel.photos ?? [],
                           cacheManager: viewModel.previewsCacheManager,
                           isZoomed: viewModel.isMultiZoomed,
                           fullResImages: viewModel.multiFullRes)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onReceive(NotificationCenter.default.publisher(for: .toggleZoom)) { _ in
                    viewModel.toggleMultiZoom()
                }

            // Exif bar
            bottomBar
        }
    }

    @ViewBuilder
    private var reviewButton: some View {
        Button(action: {
            viewModel.startReview()
        }) {
            Image(systemName: "eye")
                .font(.title2)
                .foregroundColor(.blue)
                .padding()
        }
        .buttonStyle(PlainButtonStyle())
        .help("Review selected photos")
    }

    @ViewBuilder
    private var pagePill: some View {
        if let info = viewModel.pageInfo {
            HStack(spacing: 8) {
                Button {
                    viewModel.onPageChange?(-1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(info.index == 0)

                Text("Page \(info.index + 1) of \(info.count)")
                    .font(.callout.monospacedDigit())

                Button {
                    viewModel.onPageChange?(1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(info.index >= info.count - 1)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.secondary.opacity(0.25)))
            .help("Previous / next page of photos")
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        // EXIF bottom bar
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(height: 1)
        PreviewBottomBar(viewModel: viewModel,
                         showExportPanel: $showExportPanel,
                         gridType: $gridType)
    }
}
