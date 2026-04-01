//
//  ReviewPhotoCard.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 31.03.2026.
//
import SwiftUI

struct ReviewPhotoCard: View {
    let photo: PhotoItem
    var isZoomed: Bool = false
    var fullResImage: IRImage? = nil
    var isFullResLoading: Bool = false
    @Binding var syncedMousePosition: CGPoint
    let onRatingChanged: (Int) -> Void
    let onApprove: () -> Void
    let onMarkForDeletion: () -> Void

    @State private var previewImage: IRImage? = nil
    @State private var isLoading = true
    @State private var previewAspectRatio: CGFloat? = nil

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
            // Preview / zoom image
            ZStack {
                Color(red: 41/255, green: 41/255, blue: 41/255)

                if isZoomed {
                    // Zoomed 100% view
                    if let fullRes = fullResImage {
                        SyncedZoomView(image: fullRes, mousePosition: $syncedMousePosition)
                            .transition(.opacity)
                    } else if isFullResLoading {
                        ZStack {
                            if let img = previewImage {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .transition(.opacity)
                            }
                            ProgressView("Loading full res…")
                                .progressViewStyle(.circular)
                                .scaleEffect(0.7)
                        }
                    } else if let img = previewImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .transition(.opacity)
                    }
                } else {
                    // Normal preview
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
            .aspectRatio(previewAspectRatio, contentMode: .fit)
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
                if let image, image.size.height > 0 {
                    self.previewAspectRatio = image.size.width / image.size.height
                }
            }
        }
    }
}

// MARK: - SyncedZoomView

/// Displays a full-res image at 100% pixel resolution.
/// Uses a shared `mousePosition` binding so multiple instances pan in sync.
#if os(macOS)
struct SyncedZoomView: View {
    let image: IRImage
    @Binding var mousePosition: CGPoint

    private var pixelSize: CGSize {
        if let rep = image.representations.first as? NSBitmapImageRep {
            return CGSize(width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh))
        }
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return CGSize(width: CGFloat(cg.width), height: CGFloat(cg.height))
        }
        return image.size
    }

    var body: some View {
        GeometryReader { geo in
            let imgW = pixelSize.width
            let imgH = pixelSize.height
            let viewW = geo.size.width
            let viewH = geo.size.height
            let overflowX = max(0, imgW - viewW)
            let overflowY = max(0, imgH - viewH)
            let offsetX = -overflowX * mousePosition.x
            let offsetY = -overflowY * mousePosition.y

            Image(nsImage: image)
                .resizable()
                .frame(width: imgW, height: imgH)
                .offset(x: offsetX, y: offsetY)
                .frame(width: viewW, height: viewH, alignment: .topLeading)
                .clipped()
                .background(
                    MouseTrackingView(onMouseMoved: { point, viewSize in
                        let nx = viewSize.width  > 0 ? max(0, min(1, point.x / viewSize.width))  : 0.5
                        let ny = viewSize.height > 0 ? max(0, min(1, 1 - point.y / viewSize.height)) : 0.5
                        mousePosition = CGPoint(x: nx, y: ny)
                    })
                )
        }
    }
}
#endif
