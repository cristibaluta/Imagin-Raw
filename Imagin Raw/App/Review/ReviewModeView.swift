//
//  ReviewModeView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 02.02.2026.
//

import SwiftUI

struct ReviewModeView: View {
    let photos: [PhotoItem]
    @Binding var selectedPhoto: PhotoItem?
    @EnvironmentObject var filesModel: FilesModel
    @State private var currentIndex: Int
    @State private var isExiting = false
    @FocusState private var isFocused: Bool

    let onExit: () -> Void
    let onUpdatePhoto: (PhotoItem, XmpMetadata) -> Void
    let onToggleDelete: (PhotoItem) -> Void

    init(photos: [PhotoItem], selectedPhoto: Binding<PhotoItem?>, onExit: @escaping () -> Void, onUpdatePhoto: @escaping (PhotoItem, XmpMetadata) -> Void, onToggleDelete: @escaping (PhotoItem) -> Void) {
        self.photos = photos
        self._selectedPhoto = selectedPhoto
        self.onExit = onExit
        self.onUpdatePhoto = onUpdatePhoto
        self.onToggleDelete = onToggleDelete

        // Find the current index
        if let selected = selectedPhoto.wrappedValue,
           let index = photos.firstIndex(where: { $0.id == selected.id }) {
            self._currentIndex = State(initialValue: index)
        } else {
            self._currentIndex = State(initialValue: 0)
        }
    }

    private var currentPhoto: PhotoItem? {
        guard currentIndex >= 0 && currentIndex < photos.count else { return nil }
        return photos[currentIndex]
    }

    private var previousPhoto: PhotoItem? {
        let prevIndex = currentIndex - 1
        guard prevIndex >= 0 else { return nil }
        return photos[prevIndex]
    }

    private var nextPhoto: PhotoItem? {
        let nextIndex = currentIndex + 1
        guard nextIndex < photos.count else { return nil }
        return photos[nextIndex]
    }

    var body: some View {
        ZStack {
            // Black background
            Color.black
                .ignoresSafeArea(.all)

            // Main carousel content
            HStack(spacing: 0) {
                // Previous photo thumbnail - positioned at left edge
                HStack {
                    if let prevPhoto = previousPhoto {
                        CarouselThumbnail(photo: prevPhoto, isSelected: false, size: 150)
                            .opacity(0.7)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    navigateToPrevious()
                                }
                            }
                    } else {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 150, height: 150)
                    }
                    Spacer()
                }
                .frame(width: 170)
                .padding(.leading, 20)

                // Current photo - large display taking most of screen
                if let photo = currentPhoto {
                    CarouselMainPhoto(photo: photo)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 20)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 20)
                }

                // Next photo thumbnail - positioned at right edge
                HStack {
                    Spacer()
                    if let nextPhoto = nextPhoto {
                        CarouselThumbnail(photo: nextPhoto, isSelected: false, size: 150)
                            .opacity(0.7)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    navigateToNext()
                                }
                            }
                    } else {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 150, height: 150)
                    }
                }
                .frame(width: 170)
                .padding(.trailing, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Top overlay with photo info and exit button
            VStack {
                HStack {
                    // Photo info with filename and colored label background
                    if let photo = currentPhoto {
                        VStack(alignment: .leading, spacing: 8) {
                            // Filename with colored label background (like ThumbCell)
                            Text(URL(fileURLWithPath: photo.path).lastPathComponent)
                                .font(.headline)
                                .foregroundColor(getLabelTextColor(for: photo))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(getLabelBackgroundColor(for: photo))
                                        .opacity(hasLabel(photo: photo) ? 1 : 0)
                                )

                            // Photo position indicator
                            Text("\(currentIndex + 1) of \(photos.count)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }

                    Spacer()

                    // Exit button
                    Button(action: {
                        onExit()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Exit review mode (Space)")
                }
                .padding(.horizontal, 30)
                .padding(.top, 20)

                Spacer()
            }
        }
        .focusable()
        .focused($isFocused)
        .onKeyPress { keyPress in
            handleKeyPress(keyPress)
        }
        .onAppear {
            // Update selected photo when view appears
            if let photo = currentPhoto {
                selectedPhoto = photo
            }
            // Automatically focus the view for immediate keyboard navigation
            isFocused = true
        }
        .onChange(of: currentIndex) { _, newIndex in
            // Update selected photo when index changes
            if let photo = currentPhoto {
                selectedPhoto = photo
            }
        }
    }

    private func navigateToPrevious() {
        if currentIndex > 0 {
            currentIndex -= 1
        }
    }

    private func navigateToNext() {
        if currentIndex < photos.count - 1 {
            currentIndex += 1
        }
    }

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        guard let photo = currentPhoto else { return .ignored }

        switch keyPress.key {
        case .space:
            onExit()
            return .handled
        case .escape:
            onExit()
            return .handled
        case .leftArrow:
            withAnimation(.easeInOut(duration: 0.2)) {
                navigateToPrevious()
            }
            return .handled
        case .rightArrow:
            withAnimation(.easeInOut(duration: 0.2)) {
                navigateToNext()
            }
            return .handled
        case .delete:
            onToggleDelete(photo)
            return .handled
        default:
            // Handle labeling keys with character input
            let characters = keyPress.characters

            switch characters {
            case "1":
                handleRatingKey(1, for: photo)
                return .handled
            case "2":
                handleRatingKey(2, for: photo)
                return .handled
            case "3":
                handleRatingKey(3, for: photo)
                return .handled
            case "4":
                handleRatingKey(4, for: photo)
                return .handled
            case "5":
                handleRatingKey(5, for: photo)
                return .handled
            case "6":
                handleLabelKey(.red, for: photo)
                return .handled
            case "7":
                handleLabelKey(.yellow, for: photo)
                return .handled
            case "8":
                handleLabelKey(.green, for: photo)
                return .handled
            case "9":
                handleLabelKey(.blue, for: photo)
                return .handled
            case "0":
                handleLabelKey(.purple, for: photo)
                return .handled
            case "-":
                removeLabelFromPhoto(photo)
                return .handled
            case "d", "D":
                onToggleDelete(photo)
                return .handled
            default:
                return .ignored
            }
        }
    }

    private func handleLabelKey(_ labelKey: LabelKey, for photo: PhotoItem) {
        // Create updated XMP metadata
        let updatedXmp = XmpMetadata(
            label: labelKey.rawValue,
            rating: photo.xmp?.rating, // Preserve existing rating
            creator: photo.xmp?.creator,
            rights: photo.xmp?.rights,
            createDate: photo.xmp?.createDate,
            modifyDate: photo.xmp?.modifyDate,
            cameraModel: photo.xmp?.cameraModel,
            lens: photo.xmp?.lens,
            focalLength: photo.xmp?.focalLength,
            aperture: photo.xmp?.aperture,
            shutterSpeed: photo.xmp?.shutterSpeed,
            iso: photo.xmp?.iso,
            exposureBias: photo.xmp?.exposureBias
        )

        // Call the update callback
        onUpdatePhoto(photo, updatedXmp)
    }

    private func removeLabelFromPhoto(_ photo: PhotoItem) {
        let updatedXmp = XmpMetadata(
            label: nil,
            rating: photo.xmp?.rating, // Preserve existing rating
            creator: photo.xmp?.creator,
            rights: photo.xmp?.rights,
            createDate: photo.xmp?.createDate,
            modifyDate: photo.xmp?.modifyDate,
            cameraModel: photo.xmp?.cameraModel,
            lens: photo.xmp?.lens,
            focalLength: photo.xmp?.focalLength,
            aperture: photo.xmp?.aperture,
            shutterSpeed: photo.xmp?.shutterSpeed,
            iso: photo.xmp?.iso,
            exposureBias: photo.xmp?.exposureBias
        )

        onUpdatePhoto(photo, updatedXmp)
    }

    private func handleRatingKey(_ rating: Int, for photo: PhotoItem) {
        // Create updated XMP metadata with new rating
        let updatedXmp = XmpMetadata(
            label: photo.xmp?.label, // Preserve existing label
            rating: rating,
            creator: photo.xmp?.creator,
            rights: photo.xmp?.rights,
            createDate: photo.xmp?.createDate,
            modifyDate: photo.xmp?.modifyDate,
            cameraModel: photo.xmp?.cameraModel,
            lens: photo.xmp?.lens,
            focalLength: photo.xmp?.focalLength,
            aperture: photo.xmp?.aperture,
            shutterSpeed: photo.xmp?.shutterSpeed,
            iso: photo.xmp?.iso,
            exposureBias: photo.xmp?.exposureBias
        )

        // Call the update callback
        onUpdatePhoto(photo, updatedXmp)
    }

    // MARK: - Label Color Helper Methods

    private func hasLabel(photo: PhotoItem) -> Bool {
        return photo.toDelete || (photo.xmp?.label != nil && !photo.xmp!.label!.isEmpty)
    }

    private func getLabelBackgroundColor(for photo: PhotoItem) -> Color {
        if photo.toDelete {
            return .orange
        }

        guard let label = photo.xmp?.label, !label.isEmpty else {
            return .clear
        }

        switch label {
        case "Red": return .red
        case "Yellow": return .yellow
        case "Green": return .green
        case "Blue": return .blue
        case "Purple": return .purple
        default: return .gray
        }
    }

    private func getLabelTextColor(for photo: PhotoItem) -> Color {
        if hasLabel(photo: photo) {
            // Use white text on colored backgrounds for better readability
            return .white
        } else {
            // Use white text when no background
            return .white
        }
    }
}
// MARK: - Supporting Views

struct CarouselThumbnail: View {
    let photo: PhotoItem
    let isSelected: Bool
    let size: CGFloat

    var body: some View {
        AsyncImage(url: URL(fileURLWithPath: photo.path)) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        } placeholder: {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
        }
        .frame(width: size, height: size)
        .clipped()
        .overlay(
            Rectangle()
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
        )
    }
}

struct CarouselMainPhoto: View {
    let photo: PhotoItem

    var body: some View {
        AsyncImage(url: URL(fileURLWithPath: photo.path)) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        } placeholder: {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    ProgressView()
                        .tint(.white)
                )
        }
        .overlay(
            // Trash icon overlay for photos marked for deletion
            Group {
                if photo.toDelete {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "trash")
                                .font(.system(size: 60, weight: .bold))
                                .foregroundColor(.orange)
                                .shadow(color: .black, radius: 4, x: 2, y: 2)
                                .padding(30)
                        }
                        Spacer()
                    }
                }
            }
        )
    }
}

struct ReviewModeLabels: View {
    let photo: PhotoItem

    var body: some View {
        HStack(spacing: 20) {
            ForEach(LabelKey.allCases, id: \.self) { label in
                VStack(spacing: 4) {
                    Circle()
                        .fill(label.color)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: photo.xmp?.label == label.rawValue ? 3 : 0)
                        )

                    Text(label.displayName)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))

                    Text("(\(label.keyboardShortcut))")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 15)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.6))
        )
    }
}

// MARK: - Label Key Enum

enum LabelKey: String, CaseIterable {
    case red = "Red"
    case yellow = "Yellow"
    case green = "Green"
    case blue = "Blue"
    case purple = "Purple"

    var color: Color {
        switch self {
        case .red: return .red
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        }
    }

    var displayName: String {
        return rawValue
    }

    var keyboardShortcut: String {
        switch self {
        case .red: return "6"
        case .yellow: return "7"
        case .green: return "8"
        case .blue: return "9"
        case .purple: return "5"
        }
    }

    init?(from key: KeyEquivalent) {
        switch key {
        case KeyEquivalent("6"): self = .red
        case KeyEquivalent("7"): self = .yellow
        case KeyEquivalent("8"): self = .green
        case KeyEquivalent("9"): self = .blue
        case KeyEquivalent("5"): self = .purple
        default: return nil
        }
    }
}
