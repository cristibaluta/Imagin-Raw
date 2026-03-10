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
        VStack(spacing: 0) {
            // Image area
            ZStack(alignment: model.alignToTopLeft ? .topLeading : .center) {
                Rectangle()
                    .fill(Color.clear)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let nsImage = model.preview {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .padding(2)
                } else if model.isLoading {
                    ProgressView("Loading...")
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    Text("Failed to load image")
                        .foregroundColor(.secondary)
                }

                // Alignment button — top-left only
                VStack {
                    HStack {
                        Button(action: { model.toggleAlignment() }) {
                            Image(systemName: model.alignToTopLeft ? "arrow.down.right.square" : "arrow.up.left.square")
                                .font(.title2)
                                .foregroundColor(model.alignToTopLeft ? .white.opacity(0.4) : .gray)
                                .padding()
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help(model.alignToTopLeft ? "Center image" : "Align to top-left")
                        Spacer()
                    }
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // EXIF bottom bar
            if let exifInfo = model.exifInfo {
                ExifBarView(exifInfo: exifInfo, fileSize: photo.fileSizeBytes)
            }
        }
        .onAppear {
            model.setPhoto(photo)
        }
        .onChange(of: photo) { _, newPhoto in
            model.setPhoto(newPhoto)
        }
    }
}
