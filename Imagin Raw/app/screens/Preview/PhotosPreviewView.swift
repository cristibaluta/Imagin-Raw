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
                            Image(nsImage: nsImage2)
                                .resizable()
                                .scaledToFit()
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
