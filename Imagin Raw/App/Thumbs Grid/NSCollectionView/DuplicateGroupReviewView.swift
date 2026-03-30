//
//  DuplicateGroupReviewView.swift
//  Imagin Raw
//
//  Full-screen review view for a single duplicate group.
//  Shows all photos side-by-side with name, rating, approve and delete actions.
//

import SwiftUI

// MARK: - Review Card

private struct ReviewPhotoCard: View {
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
            VStack(spacing: 6) {
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

                // Action buttons
                HStack(spacing: 8) {
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
                        Label(photo.toDelete ? "Restore" : "Delete", systemImage: photo.toDelete ? "arrow.uturn.backward" : "trash")
                            .font(.caption)
                            .foregroundColor(photo.toDelete ? .secondary : .red)
                    }
                    .buttonStyle(.plain)
                }
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
                withAnimation(.easeIn(duration: 0.15)) {
                    self.previewImage = image
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Review View

struct DuplicateGroupReviewView: View {
    let group: DuplicateGroup
    let groupIndex: Int
    let onRatingChanged: (PhotoItem, Int) -> Void
    let onApprove: (PhotoItem) -> Void
    let onMarkForDeletion: (PhotoItem) -> Void
    let onDismiss: () -> Void

    // Live photo state — updated when actions are taken
    @State private var photos: [PhotoItem]

    init(group: DuplicateGroup,
         groupIndex: Int,
         onRatingChanged: @escaping (PhotoItem, Int) -> Void,
         onApprove: @escaping (PhotoItem) -> Void,
         onMarkForDeletion: @escaping (PhotoItem) -> Void,
         onDismiss: @escaping () -> Void) {
        self.group = group
        self.groupIndex = groupIndex
        self.onRatingChanged = onRatingChanged
        self.onApprove = onApprove
        self.onMarkForDeletion = onMarkForDeletion
        self.onDismiss = onDismiss
        _photos = State(initialValue: group.photos)
    }

    private var similarity: Int {
        max(0, min(100, Int(((1.0 - Double(group.distance)) * 100).rounded())))
    }

    private var isPortrait: Bool {
        guard let first = photos.first,
              let w = first.width, let h = first.height else { return true }
        return h > w
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Title bar
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Group \(groupIndex + 1) — \(photos.count) photos")
                            .font(.headline)
                        Text("\(similarity)% similarity")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                if isPortrait {
                    // Portrait: horizontal scroll, cards fill screen height
                    let cardH = geo.size.height - 14 - 1 - 80 // subtract titlebar + divider + controls
                    let cardW = cardH * 2 / 3 // approximate 2:3 portrait ratio
                    ScrollView(.horizontal, showsIndicators: true) {
                        LazyHStack(alignment: .top, spacing: 16) {
                            ForEach(photos) { photo in
                                ReviewPhotoCard(
                                    photo: photo,
                                    onRatingChanged: { rating in onRatingChanged(photo, rating); bump() },
                                    onApprove: { onApprove(photo); bump() },
                                    onMarkForDeletion: { onMarkForDeletion(photo); bump() }
                                )
                                .frame(width: cardW)
                            }
                        }
                        .padding(20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.underPageBackgroundColor))
                } else {
                    // Landscape: 2-column vertical scroll
                    let hPad: CGFloat = 20
                    let spacing: CGFloat = 16
                    let cardW = (geo.size.width - hPad * 2 - spacing) / 2
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVGrid(columns: [
                            GridItem(.fixed(cardW), spacing: spacing),
                            GridItem(.fixed(cardW), spacing: spacing)
                        ], spacing: 16) {
                            ForEach(photos) { photo in
                                ReviewPhotoCard(
                                    photo: photo,
                                    onRatingChanged: { rating in onRatingChanged(photo, rating); bump() },
                                    onApprove: { onApprove(photo); bump() },
                                    onMarkForDeletion: { onMarkForDeletion(photo); bump() }
                                )
                            }
                        }
                        .padding(hPad)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.underPageBackgroundColor))
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    private func bump() {
        let copy = photos; photos = copy
    }
}
