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
                reviewButton
            }
            .sheet(item: $viewModel.exportJob) { job in
                ExportJPEGProgressView(job: job)
                    .interactiveDismissDisabled(true)
            }
    }

    @ViewBuilder
    private var previewBody: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack {
                Spacer()
                // Photo
                if let nsImage1 = viewModel.images?.first, let nsImage2 = viewModel.images?.last {
                        HStack {
                            Image(nsImage: nsImage1)
                                .resizable()
                                .scaledToFit()
                                .allowedDynamicRange(.high)
                            Image(nsImage: nsImage2)
                                .resizable()
                                .scaledToFit()
                                .allowedDynamicRange(.high)
                        }
                        .padding(8)
                } else if viewModel.isLoading {
                    ProgressView("Loading...")
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    Text("Failed to load image")
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            Spacer()

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
