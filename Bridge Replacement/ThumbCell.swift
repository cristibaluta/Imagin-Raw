//
//  ThumbCell.swift
//  Imagin Bridge
//
//  Created by Cristian Baluta on 30.01.2026.
//
import SwiftUI

struct ThumbCell: View {
    let photo: PhotoItem
    let isSelected: Bool
    let size: CGFloat = 100
    @State private var thumbnailImage: NSImage?
    @State private var isLoading = false

    private var filename: String {
        URL(fileURLWithPath: photo.path).lastPathComponent
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Rectangle()
                    .fill(Color(.black))

                if let image = thumbnailImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                } else {
                    Image(systemName: "photo")
                        .foregroundColor(.gray)
                }
            }
            .frame(width: size, height: size)
            .overlay(
                Rectangle()
                    .stroke(isSelected ? Color.blue : .clear, lineWidth: 2)
            )
            .onAppear {
                loadThumbnail()
            }

            // Filename with green pill background for approved photos
            Text(filename)
                .font(.callout)
                .lineLimit(1)
                .padding(5)
                .background(
                    Capsule()
                        .fill(photo.isApproved ? Color.green : Color.clear)
                        .opacity(photo.isApproved ? 0.8 : 0)
                )
                .foregroundColor(photo.isApproved ? .white : .primary)
                .frame(height: 30)

            Spacer()
        }
    }

    private func loadThumbnail() {
        // Check if already cached in memory
        if let cachedImage = ThumbsManager.shared.getCachedThumbnail(for: photo.path) {
            self.thumbnailImage = cachedImage
            return
        }

        // Load asynchronously (from disk cache or generate new)
        isLoading = true
        ThumbsManager.shared.loadThumbnail(for: photo.path) { [photo] image in
            // Ensure we're updating the right cell
            guard self.photo.path == photo.path else { return }

            self.thumbnailImage = image
            self.isLoading = false
        }
    }
}
