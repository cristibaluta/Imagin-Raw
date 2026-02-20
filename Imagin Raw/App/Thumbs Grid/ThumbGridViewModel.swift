//
//  ThumbGridViewModel.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 06.02.2026.
//

import SwiftUI
import Combine

@MainActor
class ThumbGridViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var selectedPhotos: Set<UUID> = []
    @Published var selectedLabels: Set<String> = []
    @Published var selectedRatings: Set<Int> = [] // Rating filters (1-5)
    @Published var sortOption: SortOption = .name
    @Published var gridType: GridType = .threeColumns
    @Published var lastSelectedIndex: Int?
    @Published var cachingQueueCount: Int = 0

    @Published var photosToCopy: [PhotoItem] = []
    @Published var copyDestinationURL: URL?

    // MARK: - Dependencies
    private let filesModel: FilesModel
    private var photosModel: PhotosModel?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Constants
    private let sortOptionKey = "SelectedSortOption"
    private let gridTypeKey = "SelectedGridType"

    // MARK: - Enums
    enum SortOption: String, CaseIterable {
        case name = "Name"
        case dateCreated = "Date Created"
    }

    enum GridType: String, CaseIterable, Identifiable {
        case twoColumns = "TwoColumns"
        case threeColumns = "ThreeColumns"
        case fourColumns = "FourColumns"

        var id: String { self.rawValue }

        var columnCount: Int {
            switch self {
            case .twoColumns: return 2
            case .threeColumns: return 3
            case .fourColumns: return 4
            }
        }

        var thumbSize: CGFloat {
            switch self {
            case .twoColumns: return 100
            case .threeColumns: return 100
            case .fourColumns: return 200
            }
        }

        var cellHeight: CGFloat {
            switch self {
            case .twoColumns: return 150
            case .threeColumns: return 150
            case .fourColumns: return 250
            }
        }

        var displayName: String {
            switch self {
            case .twoColumns: return "2 Columns (100px)"
            case .threeColumns: return "3 Columns (100px)"
            case .fourColumns: return "4 Columns (200px)"
            }
        }

        var iconName: String {
            switch self {
            case .twoColumns: return "square.grid.2x2"
            case .threeColumns: return "square.grid.3x3"
            case .fourColumns: return "square.grid.4x4.fill"
            }
        }
    }

    // MARK: - Initialization
    init(filesModel: FilesModel) {
        self.filesModel = filesModel
        loadSortOption()
        loadGridType()

        // Observe ThumbsManager's pendingQueueCount
        ThumbsManager.shared.$pendingQueueCount
            .receive(on: DispatchQueue.main)
            .assign(to: &$cachingQueueCount)
    }

    // MARK: - Photo Loading
    func loadPhotosForFolder(_ folder: FolderItem) {
        // Create a new PhotosModel for this folder
        let newPhotosModel = PhotosModel(folder: folder)
        self.photosModel = newPhotosModel

        // Load photos
        newPhotosModel.loadPhotos()

        // Clear selection when loading new folder
        selectedPhotos.removeAll()
        lastSelectedIndex = nil
    }

    func reloadPhotos() {
        photosModel?.reloadPhotos()
    }

    // MARK: - Computed Properties
    var photos: [PhotoItem] {
        return photosModel?.photos ?? []
    }

    var isLoadingMetadata: Bool {
        return photosModel?.isLoadingMetadata ?? false
    }

    var filteredPhotos: [PhotoItem] {
        var result = photos

        // Apply label filtering
        if !selectedLabels.isEmpty {
            result = result.filter { photo in
                if selectedLabels.contains("To Delete") && photo.toDelete {
                    return true
                }

                let photoLabel = photo.xmp?.label ?? ""

                if selectedLabels.contains("No Label") && photoLabel.isEmpty && !photo.toDelete {
                    return true
                }

                return selectedLabels.contains(photoLabel) && !photo.toDelete
            }
        }

        // Apply rating filtering
        if !selectedRatings.isEmpty {
            result = result.filter { photo in
                // Get the effective rating (XMP or in-camera fallback)
                let rating: Int
                if let xmpRating = photo.xmp?.rating, xmpRating > 0 {
                    rating = xmpRating
                } else {
                    rating = photo.inCameraRating ?? 0
                }
                return selectedRatings.contains(rating)
            }
        }

        // Apply sorting
        switch sortOption {
        case .name:
            result = result.sorted { photo1, photo2 in
                let name1 = URL(fileURLWithPath: photo1.path).lastPathComponent
                let name2 = URL(fileURLWithPath: photo2.path).lastPathComponent
                return name1.localizedStandardCompare(name2) == .orderedAscending
            }
        case .dateCreated:
            result = result.sorted { photo1, photo2 in
                return photo1.dateCreated < photo2.dateCreated
            }
        }

        return result
    }

    var availableLabels: [String] {
        var labelSet = Set<String>()
        var hasToDelete = false

        for photo in photos {
            if photo.toDelete {
                hasToDelete = true
            }
            if let label = photo.xmp?.label, !label.isEmpty {
                labelSet.insert(label)
            }
        }

        var result: [String] = []
        if labelSet.count > 0 {
            // We add No Label only if there are any of the other labels
            result.append("No Label")
        }

        let standardOrder = ["Select", "Second", "Approved", "Review", "To Do"]
        for label in standardOrder {
            if labelSet.contains(label) {
                result.append(label)
            }
        }

        if hasToDelete {
            result.append("To Delete")
        }

        return result
    }

    var dynamicColumns: [GridItem] {
        let columnCount = gridType.columnCount
        let spacing: CGFloat = 8
        return Array(repeating: GridItem(.flexible(minimum: gridType.thumbSize), spacing: spacing), count: columnCount)
    }

    var gridWidth: CGFloat {
        let columnCount = gridType.columnCount
        let thumbSize = gridType.thumbSize
        let spacing: CGFloat = 8
        let horizontalPadding: CGFloat = 24 // 12 on each side
        let totalSpacing = CGFloat(columnCount - 1) * spacing
        return (CGFloat(columnCount) * thumbSize) + totalSpacing + horizontalPadding
    }

    // MARK: - Caching Progress
    var showCachingProgress: Bool {
        return cachingQueueCount > 0
    }

    // MARK: - Selection Management
    func handlePhotoTap(photo: PhotoItem, modifiers: NSEvent.ModifierFlags) {
        let photoIndex = filteredPhotos.firstIndex(where: { $0.id == photo.id }) ?? 0

        if modifiers.contains(.command) {
            if selectedPhotos.contains(photo.id) {
                selectedPhotos.remove(photo.id)
            } else {
                selectedPhotos.insert(photo.id)
                filesModel.selectedPhoto = photo
                lastSelectedIndex = photoIndex
            }
        } else if modifiers.contains(.shift) {
            let lastSelectedIndex = self.lastSelectedIndex ?? 0
            let startIndex = min(lastSelectedIndex, photoIndex)
            let endIndex = max(lastSelectedIndex, photoIndex)

            for index in startIndex...endIndex {
                selectedPhotos.insert(filteredPhotos[index].id)
            }
            filesModel.selectedPhoto = photo
        } else {
            selectedPhotos.removeAll()
            selectedPhotos.insert(photo.id)
            filesModel.selectedPhoto = photo
            lastSelectedIndex = photoIndex
        }
    }

    func selectAll() {
        selectedPhotos.removeAll()
        for photo in filteredPhotos {
            selectedPhotos.insert(photo.id)
        }
        if let firstPhoto = filteredPhotos.first {
            filesModel.selectedPhoto = firstPhoto
            lastSelectedIndex = 0
        }
    }

    func navigateToPhoto(at newIndex: Int) {
        guard newIndex >= 0 && newIndex < filteredPhotos.count else { return }

        selectedPhotos.removeAll()
        selectedPhotos.insert(filteredPhotos[newIndex].id)
        filesModel.selectedPhoto = filteredPhotos[newIndex]
        lastSelectedIndex = newIndex
    }

    func initializeSelection() {
        if filesModel.selectedPhoto == nil && !filteredPhotos.isEmpty {
            filesModel.selectedPhoto = filteredPhotos.first
            selectedPhotos.removeAll()
            if let firstPhoto = filteredPhotos.first {
                selectedPhotos.insert(firstPhoto.id)
            }
        }
    }

    // MARK: - Rating & Label Management
    func applyRating(_ rating: Int, to photos: [PhotoItem]) {
        // Only apply rating to RAW files
        let rawPhotos = photos.filter { $0.isRawFile }
        for photo in rawPhotos {
            setPhotoRating(photo: photo, rating: rating)
        }
    }

    func applyLabel(_ label: String, to photos: [PhotoItem]) {
        // Only apply labels to RAW files
        let rawPhotos = photos.filter { $0.isRawFile }
        for photo in rawPhotos {
            createAndSaveXmpFile(for: photo, targetLabel: label)
        }
    }

    func removeLabels(from photos: [PhotoItem]) {
        // Only remove labels from RAW files
        let rawPhotos = photos.filter { $0.isRawFile }
        for photo in rawPhotos {
            removeAnyLabel(for: photo)
        }
    }

    func toggleDeleteState(for photos: [PhotoItem]) {
        for photo in photos {
            toggleToDeleteState(for: photo)
        }
    }

    func movePhotosToTrash(_ photos: [PhotoItem]) {
        let rawExtensions = ["arw", "orf", "rw2", "cr2", "cr3", "crw", "nef", "nrw",
                           "srf", "sr2", "raw", "raf", "pef", "ptx", "dng", "3fr",
                           "fff", "iiq", "mef", "mos", "x3f", "srw", "dcr", "kdc",
                           "k25", "kc2", "mrw", "erf", "bay", "ndd", "sti", "rwl", "r3d"]

        for photo in photos {
            let url = URL(fileURLWithPath: photo.path)
            let fileExtension = url.pathExtension.lowercased()
            let baseName = url.deletingPathExtension().lastPathComponent
            let directory = url.deletingLastPathComponent()

            do {
                // Move main file to trash
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)

                // Delete the cached thumbnail
                ThumbsManager.shared.deleteCachedThumbnail(for: photo.path)

                // If this is a RAW file, also delete associated files
                if rawExtensions.contains(fileExtension) {
                    // Delete associated JPG files
                    for jpgExt in ["jpg", "jpeg", "JPG", "JPEG"] {
                        let jpgURL = directory.appendingPathComponent("\(baseName).\(jpgExt)")
                        if FileManager.default.fileExists(atPath: jpgURL.path) {
                            try? FileManager.default.trashItem(at: jpgURL, resultingItemURL: nil)
                        }
                    }

                    // Delete associated XMP file
                    let xmpURL = directory.appendingPathComponent("\(baseName).xmp")
                    if FileManager.default.fileExists(atPath: xmpURL.path) {
                        try? FileManager.default.trashItem(at: xmpURL, resultingItemURL: nil)
                    }

                    // Delete associated ACR file
                    let acrURL = directory.appendingPathComponent("\(baseName).acr")
                    if FileManager.default.fileExists(atPath: acrURL.path) {
                        try? FileManager.default.trashItem(at: acrURL, resultingItemURL: nil)
                    }
                }

                // Remove from photos array
                if let index = photosModel?.photos.firstIndex(where: { $0.id == photo.id }) {
                    photosModel?.photos.remove(at: index)
                }
            } catch {
                // Silently handle errors
            }
        }

        // Clear selection after moving
        selectedPhotos.removeAll()

        // Select first remaining photo if available
        if !filteredPhotos.isEmpty {
            let firstPhoto = filteredPhotos[0]
            filesModel.selectedPhoto = firstPhoto
            selectedPhotos.insert(firstPhoto.id)
            lastSelectedIndex = 0
        } else {
            filesModel.selectedPhoto = nil
        }
    }

    func getSelectedPhotosForBulkAction() -> [PhotoItem] {
        if selectedPhotos.count > 1 {
            return filteredPhotos.filter { selectedPhotos.contains($0.id) }
        } else if let selectedPhoto = filesModel.selectedPhoto {
            return [selectedPhoto]
        } else {
            return []
        }
    }

    // MARK: - Persistence
    func saveSortOption() {
        UserDefaults.standard.set(sortOption.rawValue, forKey: sortOptionKey)
    }

    func loadSortOption() {
        if let savedOption = UserDefaults.standard.string(forKey: sortOptionKey),
           let option = SortOption(rawValue: savedOption) {
            sortOption = option
        }
    }

    func saveGridType() {
        UserDefaults.standard.set(gridType.rawValue, forKey: gridTypeKey)
    }

    func loadGridType() {
        if let savedType = UserDefaults.standard.string(forKey: gridTypeKey),
           let type = GridType(rawValue: savedType) {
            gridType = type
        }
    }

    func toggleGridType() {
        gridType = (gridType == .threeColumns) ? .fourColumns : .threeColumns
        saveGridType()
    }

    func toggleLabelFilter(_ label: String) {
        if selectedLabels.contains(label) {
            selectedLabels.remove(label)
        } else {
            selectedLabels.insert(label)
        }
    }

    func clearInvalidFilters() {
        // Clear invalid label filters
        if !selectedLabels.isEmpty {
            var labelsToRemove: Set<String> = []

            for label in selectedLabels {
                // Check if any photo matches this label
                let hasMatchingPhoto = photos.contains { photo in
                    if label == "To Delete" && photo.toDelete {
                        return true
                    }

                    let photoLabel = photo.xmp?.label ?? ""

                    if label == "No Label" && photoLabel.isEmpty && !photo.toDelete {
                        return true
                    }

                    return photoLabel == label && !photo.toDelete
                }

                if !hasMatchingPhoto {
                    labelsToRemove.insert(label)
                }
            }

            // Remove invalid labels
            if !labelsToRemove.isEmpty {
                selectedLabels.subtract(labelsToRemove)
            }
        }

        // Clear invalid rating filters
        if !selectedRatings.isEmpty {
            var ratingsToRemove: Set<Int> = []

            for rating in selectedRatings {
                // Check if any photo has this rating
                let hasMatchingPhoto = photos.contains { photo in
                    // Get the effective rating (XMP or in-camera fallback)
                    let effectiveRating: Int
                    if let xmpRating = photo.xmp?.rating, xmpRating > 0 {
                        effectiveRating = xmpRating
                    } else {
                        effectiveRating = photo.inCameraRating ?? 0
                    }
                    return effectiveRating == rating
                }

                if !hasMatchingPhoto {
                    ratingsToRemove.insert(rating)
                }
            }

            // Remove invalid ratings
            if !ratingsToRemove.isEmpty {
                selectedRatings.subtract(ratingsToRemove)
            }
        }

        // After clearing invalid filters, check if any photos would match the remaining filters
        // If we still have active filters but no photos match, clear all filters
        if !photos.isEmpty && (!selectedLabels.isEmpty || !selectedRatings.isEmpty) {
            // Manually check if any photo matches the remaining filters
            let hasMatchingPhoto = photos.contains { photo in
                var matchesLabel = selectedLabels.isEmpty
                var matchesRating = selectedRatings.isEmpty

                // Check label filter
                if !selectedLabels.isEmpty {
                    if selectedLabels.contains("To Delete") && photo.toDelete {
                        matchesLabel = true
                    } else {
                        let photoLabel = photo.xmp?.label ?? ""
                        if selectedLabels.contains("No Label") && photoLabel.isEmpty && !photo.toDelete {
                            matchesLabel = true
                        } else if selectedLabels.contains(photoLabel) && !photo.toDelete {
                            matchesLabel = true
                        }
                    }
                }

                // Check rating filter
                if !selectedRatings.isEmpty {
                    let effectiveRating: Int
                    if let xmpRating = photo.xmp?.rating, xmpRating > 0 {
                        effectiveRating = xmpRating
                    } else {
                        effectiveRating = photo.inCameraRating ?? 0
                    }
                    matchesRating = selectedRatings.contains(effectiveRating)
                }

                return matchesLabel && matchesRating
            }

            // If no photos match the remaining filters, clear all filters
            if !hasMatchingPhoto {
                selectedLabels.removeAll()
                selectedRatings.removeAll()
            }
        }
    }

    func getColorForLabel(_ label: String) -> Color {
        switch label {
        case "No Label": return .secondary
        case "Select": return .red
        case "Second": return .yellow
        case "Approved": return .green
        case "Review": return .blue
        case "To Do": return .purple
        case "To Delete": return .orange
        default: return .secondary
        }
    }

    // MARK: - Private XMP Operations
    private func setPhotoRating(photo: PhotoItem, rating: Int) {
        let photoURL = URL(fileURLWithPath: photo.path)
        let photoDirectory = photoURL.deletingLastPathComponent()
        let photoName = photoURL.deletingPathExtension().lastPathComponent
        let xmpFileName = "\(photoName).xmp"
        let xmpFileURL = photoDirectory.appendingPathComponent(xmpFileName)

        var xmpContent: String

        if FileManager.default.fileExists(atPath: xmpFileURL.path) {
            do {
                xmpContent = try String(contentsOf: xmpFileURL, encoding: .utf8)
                xmpContent = XmpParser.updateRating(in: xmpContent, rating: rating)
            } catch {
                return
            }
        } else {
            xmpContent = XmpParser.createXmpContent(rating: rating, label: photo.xmp?.label)
        }

        do {
            try xmpContent.write(to: xmpFileURL, atomically: true, encoding: .utf8)
            if let parsedMetadata = XmpParser.parseMetadata(from: xmpContent) {
                updatePhotoWithXmpMetadata(photo: photo, xmpMetadata: parsedMetadata)
            }
        } catch {
            // Silently handle error
        }
    }

    private func createAndSaveXmpFile(for photo: PhotoItem, targetLabel: String) {
        let photoURL = URL(fileURLWithPath: photo.path)
        let photoDirectory = photoURL.deletingLastPathComponent()
        let photoName = photoURL.deletingPathExtension().lastPathComponent
        let xmpFileName = "\(photoName).xmp"
        let xmpFileURL = photoDirectory.appendingPathComponent(xmpFileName)

        var xmpContent: String
        var currentLabel: String? = nil

        if FileManager.default.fileExists(atPath: xmpFileURL.path) {
            do {
                xmpContent = try String(contentsOf: xmpFileURL, encoding: .utf8)

                if let existingMetadata = XmpParser.parseMetadata(from: xmpContent) {
                    currentLabel = existingMetadata.label
                }

                let newLabel: String? = (currentLabel == targetLabel) ? nil : targetLabel
                xmpContent = updateXmpLabel(in: xmpContent, newLabel: newLabel)
            } catch {
                return
            }
        } else {
            xmpContent = XmpParser.createXmpContent(rating: photo.xmp?.rating ?? 0, label: targetLabel)
        }

        do {
            try xmpContent.write(to: xmpFileURL, atomically: true, encoding: .utf8)
            if let parsedMetadata = XmpParser.parseMetadata(from: xmpContent) {
                updatePhotoWithXmpMetadata(photo: photo, xmpMetadata: parsedMetadata)
            }
        } catch {
            // Silently handle error
        }
    }

    private func removeAnyLabel(for photo: PhotoItem) {
        let photoURL = URL(fileURLWithPath: photo.path)
        let photoDirectory = photoURL.deletingLastPathComponent()
        let photoName = photoURL.deletingPathExtension().lastPathComponent
        let xmpFileName = "\(photoName).xmp"
        let xmpFileURL = photoDirectory.appendingPathComponent(xmpFileName)

        guard FileManager.default.fileExists(atPath: xmpFileURL.path) else {
            return
        }

        do {
            var xmpContent = try String(contentsOf: xmpFileURL, encoding: .utf8)
            xmpContent = updateXmpLabel(in: xmpContent, newLabel: nil)
            try xmpContent.write(to: xmpFileURL, atomically: true, encoding: .utf8)

            if let parsedMetadata = XmpParser.parseMetadata(from: xmpContent) {
                updatePhotoWithXmpMetadata(photo: photo, xmpMetadata: parsedMetadata)
            }
        } catch {
            // Silently handle error
        }
    }

    private func updateXmpLabel(in xmpContent: String, newLabel: String?) -> String {
        var updatedContent = xmpContent
        let labelPattern = #"xmp:Label="[^"]*""#

        if let range = updatedContent.range(of: labelPattern, options: .regularExpression) {
            if let newLabel = newLabel {
                updatedContent.replaceSubrange(range, with: "xmp:Label=\"\(newLabel)\"")
            } else {
                updatedContent.replaceSubrange(range, with: "xmp:Label=\"\"")
            }
        } else if let newLabel = newLabel {
            let descriptionPattern = #"(<rdf:Description[^>]*)"#
            if let match = updatedContent.range(of: descriptionPattern, options: .regularExpression) {
                let insertPosition = updatedContent.index(match.upperBound, offsetBy: 0)
                let labelAttribute = "\n   xmp:Label=\"\(newLabel)\""
                updatedContent.insert(contentsOf: labelAttribute, at: insertPosition)
            }
        }

        // Update MetadataDate
        let currentDate = Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withTimeZone, .withColonSeparatorInTimeZone]
        dateFormatter.timeZone = TimeZone.current
        let currentDateString = dateFormatter.string(from: currentDate)

        let metadataDatePattern = #"xmp:MetadataDate="[^"]*""#
        if let range = updatedContent.range(of: metadataDatePattern, options: .regularExpression) {
            updatedContent.replaceSubrange(range, with: "xmp:MetadataDate=\"\(currentDateString)\"")
        } else {
            let descriptionPattern = #"(<rdf:Description[^>]*)"#
            if let match = updatedContent.range(of: descriptionPattern, options: .regularExpression) {
                let insertPosition = updatedContent.index(match.upperBound, offsetBy: 0)
                let metadataAttribute = "\n   xmp:MetadataDate=\"\(currentDateString)\""
                updatedContent.insert(contentsOf: metadataAttribute, at: insertPosition)
            }
        }

        return updatedContent
    }

    private func toggleToDeleteState(for photo: PhotoItem) {
        guard let photosModel = photosModel,
              let photoIndex = photosModel.photos.firstIndex(where: { $0.path == photo.path }) else {
            return
        }

        let currentPhoto = photosModel.photos[photoIndex]

        let updatedPhoto = PhotoItem(
            id: currentPhoto.id,
            path: currentPhoto.path,
            xmp: currentPhoto.xmp,
            dateCreated: currentPhoto.dateCreated,
            toDelete: !currentPhoto.toDelete,
            hasACR: currentPhoto.hasACR,
            hasJPG: currentPhoto.hasJPG,
            inCameraRating: currentPhoto.inCameraRating,
            isRawFile: currentPhoto.isRawFile,
            fileSizeBytes: currentPhoto.fileSizeBytes,
            width: currentPhoto.width,
            height: currentPhoto.height,
            cameraMake: currentPhoto.cameraMake,
            cameraModel: currentPhoto.cameraModel
        )

        photosModel.photos[photoIndex] = updatedPhoto
        filesModel.selectedPhoto = updatedPhoto
    }

    private func updatePhotoWithXmpMetadata(photo: PhotoItem, xmpMetadata: XmpMetadata) {
        guard let photosModel = photosModel,
              let photoIndex = photosModel.photos.firstIndex(where: { $0.path == photo.path }) else {
            return
        }

        let currentPhoto = photosModel.photos[photoIndex]

        let updatedPhoto = PhotoItem(
            id: photo.id,
            path: photo.path,
            xmp: xmpMetadata,
            dateCreated: photo.dateCreated,
            toDelete: currentPhoto.toDelete,
            hasACR: currentPhoto.hasACR,
            hasJPG: currentPhoto.hasJPG,
            inCameraRating: currentPhoto.inCameraRating,
            isRawFile: currentPhoto.isRawFile,
            fileSizeBytes: currentPhoto.fileSizeBytes,
            width: currentPhoto.width,
            height: currentPhoto.height,
            cameraMake: currentPhoto.cameraMake,
            cameraModel: currentPhoto.cameraModel
        )

        photosModel.photos[photoIndex] = updatedPhoto
        filesModel.selectedPhoto = updatedPhoto
    }
}
