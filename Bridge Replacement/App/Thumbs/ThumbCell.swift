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
    let isMultiSelected: Bool
    let onTap: (NSEvent.ModifierFlags) -> Void
    let onDoubleClick: () -> Void
    let size: CGFloat = 100
    @State private var thumbnailImage: NSImage?
    @State private var isLoading = false
    @State private var clickCount = 0
    @State private var clickTimer: Timer?

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
                } else {
                    Image(systemName: "photo")
                        .foregroundColor(.gray)
                }
            }
            .frame(width: size, height: size)
            .overlay(
                Rectangle()
                    .stroke(
                        (isSelected || isMultiSelected) ? Color.blue : .clear,
                        lineWidth: 2
                    )
            )
            .overlay(
                // Trash icon overlay for photos marked for deletion
                Group {
                    if photo.toDelete {
                        Image(systemName: "trash")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.orange)
                            .shadow(color: .black, radius: 2, x: 1, y: 1)
                    }
                }
            )
            .onTapGesture {
                clickCount += 1

                // Get current modifier keys from NSApp
                let modifiers = NSApp.currentEvent?.modifierFlags ?? []

                if clickCount == 1 {
                    // Immediate single-click action with modifiers
                    onTap(modifiers)

                    // Start timer to detect if second click comes
                    clickTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                        // Timer expired - it was just a single click
                        clickCount = 0
                    }
                } else if clickCount == 2 {
                    // Double-click detected
                    clickTimer?.invalidate()
                    clickCount = 0
                    onDoubleClick()
                }
            }
            .onAppear {
                loadThumbnail()
            }

            // Filename with colored pill background based on label
            Text(filename)
                .font(.system(size: 11))
                .lineLimit(1)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(getLabelBackgroundColor())
                        .opacity(hasLabel() ? 1 : 0)
                )
                .foregroundColor(getLabelTextColor())
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

        // Load asynchronously with medium priority (let the queue system handle prioritization)
        isLoading = true
        let photoId = photo.id // Capture the ID to avoid memory issues
        let photoPath = photo.path // Capture the path

        ThumbsManager.shared.loadThumbnail(for: photoPath, priority: .medium) { image in
            // Use DispatchQueue.main.async to ensure UI updates happen on main thread
            // and check that this is still the correct cell by comparing photo ID
            DispatchQueue.main.async {
                // Only update if this cell is still showing the same photo
                if self.photo.id == photoId {
                    self.thumbnailImage = image
                    self.isLoading = false
                }
            }
        }
    }

    private func hasLabel() -> Bool {
        return photo.toDelete || (photo.xmp?.label != nil && !photo.xmp!.label!.isEmpty)
    }

    private func getLabelBackgroundColor() -> Color {
        // Check if photo is marked for deletion first
        if photo.toDelete {
            return .orange
        }

        guard let label = photo.xmp?.label else { return .clear }

        switch label {
        case "Select":
            return .red
        case "Second":
            return .yellow
        case "Approved":
            return Color(red: 133/255, green: 199/255, blue: 102/255) // Keep existing green
        case "Review":
            return .blue
        case "To Do":
            return .purple
        default:
            return .clear
        }
    }

    private func getLabelTextColor() -> Color {
        // Check if photo is marked for deletion first
        if photo.toDelete {
            return .black
        }

        guard let label = photo.xmp?.label else { return .primary }

        switch label {
        case "Select":
            return .white
        case "Second":
            return .black
        case "Approved":
            return .black
        case "Review":
            return .white
        case "To Do":
            return .white
        default:
            return .primary
        }
    }
}
