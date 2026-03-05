//
//  LargePreviewView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 30.01.2026.
//

import SwiftUI

struct LargePreviewView: View {
    let photo: PhotoItem
    @StateObject private var model = LargePreviewViewModel()

    var body: some View {
        ZStack {
            // Background layer - ensures full view coverage
            Rectangle()
                .fill(Color.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Main image view
            if let nsImage = model.preview {
                if model.alignToTopLeft {
                    HStack {
                        VStack {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                                .padding(2)
                            Spacer()
                        }
                        Spacer()
                    }
                } else {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .padding(2)
                }
            } else if model.isLoading {
                ProgressView("Loading...")
                    .progressViewStyle(CircularProgressViewStyle())
            } else {
                Text("Failed to load image")
                    .foregroundColor(.secondary)
            }

            // Overlay positioned using stacks and spacers
            VStack {
                // Top overlay with alignment button
                HStack {
                    Button(action: {
                        model.toggleAlignment()
                    }) {
                        Image(systemName: model.alignToTopLeft ? "arrow.down.right.square" : "arrow.up.left.square")
                            .font(.title2)
                            .foregroundColor(model.alignToTopLeft ? .white.opacity(0.4) : .white)
                            .padding()
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(model.alignToTopLeft ? "Center image" : "Align to top-left")

                    Spacer() // Push button to left
                }

                Spacer() // Push content to bottom

                HStack {
                    if model.alignToTopLeft {
                        Spacer()
                        if let nsImage = model.preview, let exifInfo = model.exifInfo {
                            CompactExifOverlayView(nsImage: nsImage, exifInfo: exifInfo)
                        }
                    } else {
                        if let nsImage = model.preview, let exifInfo = model.exifInfo {
                            CompactExifOverlayView(nsImage: nsImage, exifInfo: exifInfo)
                        }
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear {
            model.setPhoto(photo)
        }
        .onChange(of: photo) { _, newPhoto in
            model.setPhoto(newPhoto)
        }
    }
}
