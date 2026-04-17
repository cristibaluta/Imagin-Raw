//
//  ThumbCell.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 30.01.2026.
//
import Foundation
import SwiftUI

struct ThumbCell: View {
    let photo: PhotoItem
    let isSelected: Bool
    let onTap: (NSEvent.ModifierFlags) -> Void
    let onDoubleClick: () -> Void
    let onRatingChanged: (Int) -> Void
    let onMoveToTrash: (PhotoItem) -> Void
    let onCopyTo: (PhotoItem) -> Void
    let onRenameTo: (PhotoItem) -> Void
    let onMoveAllMarkedToTrash: (() -> (count: Int, action: () -> Void))?
    let size: CGFloat  // Now accepts size as a parameter
    @State private var thumbnailImage: IRImage?
    @State private var isLoading = false
    @State private var clickCount = 0
    @State private var clickTimer: Timer?
    @State private var isHovering = false

    private var filename: String {
        URL(fileURLWithPath: photo.path).lastPathComponent
    }

    private var currentRating: Int {
        // Use XMP rating if available, otherwise fallback to in-camera rating
        if let xmpRating = photo.xmp?.rating, xmpRating > 0 {
            return xmpRating
        }
        return photo.inCameraRating ?? 0
    }

    var body: some View {
//        let _ = Self._printChanges()
        VStack(spacing: 4) {
            ZStack {
                Rectangle()
                    .fill(Color(red: 41/255, green: 41/255, blue: 41/255))

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
                Group {
                    if isSelected {
                        Rectangle().stroke(.blue, lineWidth: 2)
                    }
                    if photo.toDelete {
                        Image(systemName: "xmark")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.red)
                            .shadow(color: .black, radius: 2, x: 1, y: 1)
                    }

                    // ACR and JPG indicators in top-right corner
                    if photo.hasACR || (photo.isRawFile && photo.hasJPG) {
                        VStack {
                            HStack(spacing: 2) {
                                Spacer()

                                // ACR indicator
                                if photo.hasACR {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white)
                                        .background(
                                            RoundedRectangle(cornerRadius: 3, style: .circular)
                                                .foregroundColor(Color.gray.opacity(0.8))
                                                .frame(width: 20, height: 20)
                                        )
                                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                                }

                                // JPG indicator
                                if photo.isRawFile && photo.hasJPG {
                                    Text("+JPG")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 3, style: .circular)
                                                .foregroundColor(Color.blue.opacity(0.8))
                                        )
                                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                                }
                            }
                            .padding(.trailing, 4)
                            .padding(.top, 4)

                            Spacer()
                        }
                    }
                }
            )
            .onTapGesture {
                #if os(macOS)
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
                #elseif os(iOS)
                let modifiers = NSEvent.ModifierFlags.none
                onTap(modifiers)
                #endif
            }
            .onAppear {
                loadThumbnail()
            }

            Text(filename)
                .font(.system(size: 11))
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 2) // Tighter padding when stars show
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(getLabelBackgroundColor())
                        .opacity(hasLabel() ? 1 : 0)
                )
                .foregroundColor(getLabelTextColor())

            if photo.isRawFile && (isHovering || currentRating > 0) {
                StarRatingView(
                    rating: currentRating,
                    maxRating: 5,
                    starSize: 10,
                    onRatingChanged: onRatingChanged
                )
                .allowsHitTesting(true)
                .frame(height: 10)
            }

            Spacer()
        }
        .contentShape(Rectangle()) // Make entire cell area hoverable
        .onHover { hovering in
            // We don't allow rating for JPG
            isHovering = photo.isRawFile && hovering
        }
        .contextMenu {
            #if os(macOS)
            Button(action: {
                NSWorkspace.shared.selectFile(photo.path, inFileViewerRootedAtPath: "")
            }) {
                Label("Show in Finder", systemImage: "folder")
            }
            #endif

            Button(action: {
                onCopyTo(photo)
            }) {
                Label("Copy to...", systemImage: "doc.on.doc")
            }

            Button(action: {
                onRenameTo(photo)
            }) {
                Label("Rename...", systemImage: "pencil")
            }

            Divider()

            Button(action: {
                onMoveToTrash(photo)
            }) {
                Label("Move to Trash", systemImage: "trash")
            }

            if photo.toDelete, let onMoveAllMarkedToTrash {
                let info = onMoveAllMarkedToTrash()
                Button(action: {
                    info.action()
                }) {
                    Label("Move to Trash all Rejected Photos (\(info.count))", systemImage: "trash.fill")
                }
            }
        }
    }

    private func loadThumbnail() {
        if let cachedImage = ThumbsManager.current?.getCachedThumbnail(for: photo.path) {
            self.thumbnailImage = cachedImage
            return
        }
        isLoading = true
        let photoId = photo.id
        let currentPhoto = photo
        ThumbsManager.current?.loadThumbnail(for: currentPhoto, priority: .medium) { image in
            DispatchQueue.main.async {
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
            return .red
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
