//
//  ThumbCell.swift
//  Imagin Bridge
//
//  Created by Cristian Baluta on 30.01.2026.
//
import SwiftUI

struct ThumbCell: View {
    let path: String
    let isSelected: Bool
    let size: CGFloat = 100
    @State private var image: NSImage? = nil
    @State private var isLoading = false
    @State private var hasAttemptedLoad = false
    
    // Cache filename to avoid repeated string operations
    private var filename: String {
        path.split(separator: "/").last.map(String.init) ?? ""
    }

    var body: some View {
        VStack(spacing: 6) {
            // Thumbnail square
            ZStack {
                Rectangle()
                    .fill(Color(.black))

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    // Show placeholder when not loading
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

            // Filename - cached to avoid repeated string operations
            Text(filename)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: size)

            Spacer()
        }
    }

    private func loadThumbnail() {
        // Check if already cached in memory
        if let cachedImage = ThumbsManager.shared.getCachedThumbnail(for: path) {
            self.image = cachedImage
            return
        }

        // Load asynchronously (from disk cache or generate new)
        isLoading = true
        ThumbsManager.shared.loadThumbnail(for: path) { [path] image in
            // Ensure we're updating the right cell (path might have changed)
            guard self.path == path else { return }

            self.image = image
            self.isLoading = false
        }
    }
}
