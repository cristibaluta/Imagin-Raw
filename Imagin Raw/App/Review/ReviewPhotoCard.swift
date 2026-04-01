//
//  ReviewPhotoCard.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 31.03.2026.
//
import SwiftUI

struct ReviewPhotoCard: View {
    let photo: PhotoItem
    let onRatingChanged: (Int) -> Void
    let onApprove: () -> Void
    let onMarkForDeletion: () -> Void

    @State private var previewImage: IRImage? = nil
    @State private var isLoading = true

    private var filename: String {
        URL(fileURLWithPath: photo.path).lastPathComponent
    }

    private var currentRating: Int {
        if let r = photo.xmp?.rating, r > 0 { return r }
        return photo.inCameraRating ?? 0
    }

    private var isApproved: Bool {
        photo.xmp?.label == "Approved"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Preview image
            ZStack {
                Color(red: 41/255, green: 41/255, blue: 41/255)

                if let img = previewImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .transition(.opacity)
                } else if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.7)
                }

                // Trash overlay
                if photo.toDelete {
                    ZStack {
                        Color.black.opacity(0.45)
                        Image(systemName: "xmark")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.red)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Controls
            HStack(spacing: 6) {
                // Filename
                Text(filename)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)

                // Star rating
                StarRatingView(
                    rating: currentRating,
                    maxRating: 5,
                    starSize: 12,
                    onRatingChanged: onRatingChanged
                )

                Spacer().frame(width: .infinity)

                // Approve
                Button(action: onApprove) {
                    Label(isApproved ? "Approved" : "Approve", systemImage: "checkmark.circle\(isApproved ? ".fill" : "")")
                        .font(.caption)
                        .foregroundColor(isApproved ? .green : .secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                // Mark for deletion
                Button(action: onMarkForDeletion) {
                    Label(photo.toDelete ? "Rejected" : "Reject", systemImage: photo.toDelete ? "arrow.uturn.backward" : "xmark")
                        .font(.caption)
                        .foregroundColor(photo.toDelete ? .secondary : .red)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(photo.toDelete ? Color.red.opacity(0.6) :
                        isApproved ? Color.green.opacity(0.6) : Color.clear,
                        lineWidth: 2)
        )
        .onAppear { loadPreview() }
        .onChange(of: photo.path) { _, _ in loadPreview() }
    }

    private func loadPreview() {
        isLoading = true
        PreviewsManager.shared.loadPreview(for: photo.path) { image, _ in
            DispatchQueue.main.async {
                self.previewImage = image
                self.isLoading = false
            }
        }
    }
}
