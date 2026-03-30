//
//  ThumbGridViewModel.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 06.02.2026.
//

import Foundation
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
    @Published var isLoadingMetadata: Bool = false
    @Published var isFindingDuplicates: Bool = false
    @Published var isDuplicateMode: Bool = false
    @Published var duplicateScanProgress: (done: Int, total: Int) = (0, 0)
    @Published var duplicateScanResult: DuplicateScanResult? = nil
    @Published var similarityMode: DuplicateFinderService.SimilarityMode = .loose

    private var duplicateScanData: DuplicateScanData? = nil

    // Cached filtered photos to avoid recalculating on every access
    @Published private(set) var filteredPhotos: [PhotoItem] = []

    @Published var photosToCopy: [PhotoItem] = []
    @Published var copyDestinationURL: URL?

    // MARK: - Dependencies
    private let filesModel: FilesModel
    private var photosModel: PhotosModel?
    private var searchResultsPhotos: [PhotoItem]? = nil
    private var cancellables = Set<AnyCancellable>()

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
        loadSimilarityMode()

        // Observe ThumbsManager's pendingQueueCount
        ThumbsManager.shared.$pendingQueueCount
            .receive(on: DispatchQueue.main)
            .assign(to: &$cachingQueueCount)

        // Set up observers to recalculate filteredPhotos when any dependency changes
        setupFilteredPhotosObservers()
    }

    private func setupFilteredPhotosObservers() {
        // Recalculate filteredPhotos whenever relevant properties change
        Publishers.CombineLatest4(
            $selectedLabels,
            $selectedRatings,
            $sortOption,
            $isLoadingMetadata
        )
        .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.updateFilteredPhotos()
        }
        .store(in: &cancellables)
    }
    var photoSortComparator: (PhotoItem, PhotoItem) -> Bool {
        switch sortOption {
        case .name:
            return { photo1, photo2 in
                let name1 = URL(fileURLWithPath: photo1.path).lastPathComponent
                let name2 = URL(fileURLWithPath: photo2.path).lastPathComponent
                return name1.localizedStandardCompare(name2) == .orderedAscending
            }
        case .dateCreated:
            return { $0.dateCreated < $1.dateCreated }
        }
    }

    // TODO this is called too often, when i just label a photo
    private func updateFilteredPhotos() {
        var result = photos

        // Get the currently selected photo ID from filesModel instead of looking it up in the old filteredPhotos
        // This prevents issues when filteredPhotos hasn't been updated yet (e.g., right after deletion)
        let lastSelectedPhotoId = filesModel.selectedPhoto?.id

        // If metadata is still loading, show all photos (don't apply filters yet)
        // This prevents showing an empty view while waiting for metadata
        if !isLoadingMetadata {
            // Apply label filtering only after metadata is loaded
            if !selectedLabels.isEmpty {
                result = result.filter { photo in
                    if selectedLabels.contains("Rejected") && photo.toDelete {
                        return true
                    }

                    let photoLabel = photo.xmp?.label ?? ""

                    if selectedLabels.contains("No Label") && photoLabel.isEmpty && !photo.toDelete {
                        return true
                    }

                    return selectedLabels.contains(photoLabel) && !photo.toDelete
                }
            }

            // Apply rating filtering only after metadata is loaded
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
        }

        if !photos.isEmpty && result.isEmpty {
            selectedLabels.removeAll()
            selectedRatings.removeAll()
            result = photos
        }

        // Apply sorting
        result = result.sorted(by: photoSortComparator)

        filteredPhotos = result

        // Update lastSelectedIndex to match the selected photo's position in the new filtered list
        if let selectedPhotoId = lastSelectedPhotoId {
            self.lastSelectedIndex = filteredPhotos.firstIndex(where: { $0.id == selectedPhotoId })
            // If the photo wasn't found but we have a valid selection, preserve the current index
            // This prevents losing the index during reloads when photos are temporarily not in the array
        }
        // Only set to nil if there's no selected photo at all
        else if filesModel.selectedPhoto == nil {
            self.lastSelectedIndex = nil
        }
        // Otherwise keep the existing lastSelectedIndex value
    }

    // MARK: - Photo Loading
    func loadPhotosForFolder(_ folder: FolderItem) {
        print("📂 Loading photos for folder: \(folder.url.lastPathComponent)")

        // Cancel any existing subscriptions
        cancellables.removeAll()

        // Re-setup filtered photos observers after clearing cancellables
        setupFilteredPhotosObservers()

        // Create a new PhotosModel for this folder
        let newPhotosModel = PhotosModel(folder: folder)
        self.photosModel = newPhotosModel

        print("   Old PhotosModel will be deallocated")

        // Set up subscriptions to observe the new PhotosModel's changes
        newPhotosModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Observe PhotosModel's isLoadingMetadata and update our published property
        newPhotosModel.$isLoadingMetadata
            .sink { [weak self] isLoading in
                print("📡 PhotosModel.isLoadingMetadata changed to: \(isLoading)")
                self?.isLoadingMetadata = isLoading
                print("📡 ThumbGridViewModel.isLoadingMetadata set to: \(isLoading)")
            }
            .store(in: &cancellables)

        // Observe PhotosModel's photos array and trigger filteredPhotos recalculation
        newPhotosModel.$photos
            .sink { [weak self] _ in
                self?.updateFilteredPhotos()
            }
            .store(in: &cancellables)

        // Load photos
        newPhotosModel.loadPhotos()

        // Clear selection when loading new folder
        selectedPhotos.removeAll()
        lastSelectedIndex = nil
    }

    func reloadPhotos() {
        print("🔄 Reloading photos")
        photosModel?.reloadPhotos()
    }

    /// Show an explicit list of PhotoItems (Spotlight photo search results).
    func loadSearchResults(_ items: [PhotoItem]) {
        searchResultsPhotos = items
        selectedPhotos.removeAll()
        lastSelectedIndex = nil
        updateFilteredPhotos()
    }

    /// Clear search results, reverting to folder-based photos.
    func clearSearchResults() {
        searchResultsPhotos = nil
        updateFilteredPhotos()
    }

    // MARK: - Computed Properties
    var photos: [PhotoItem] {
        return searchResultsPhotos ?? photosModel?.photos ?? []
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
            result.append("Rejected")
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
                if index >= filteredPhotos.count {
                    break
                }
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

    // MARK: - Undo support
    // Each entry maps trashed file URL back to its original URL
    private var undoStack: [[(trashedURL: URL, originalURL: URL)]] = []

    func movePhotosToTrash(_ photos: [PhotoItem]) {

        var undoEntry: [(trashedURL: URL, originalURL: URL)] = []

        for photo in photos {
            let url = URL(fileURLWithPath: photo.path)
            let fileExtension = url.pathExtension.lowercased()
            let baseName = url.deletingPathExtension().lastPathComponent
            let directory = url.deletingLastPathComponent()

            do {
                // Move main file to trash, capturing the resulting trash URL for undo
                var trashedURL: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
                if let trashedURL = trashedURL as? URL {
                    undoEntry.append((trashedURL: trashedURL, originalURL: url))
                }

                // Delete the cached thumbnail
                ThumbsManager.shared.deleteCachedThumbnail(for: photo.path)
//                PreviewsManager.shared.deleteCachedPreview(for: photo.path)

                // If this is a RAW file, also delete associated files
                if FilesExtensions.raw.contains(fileExtension) {
                    for jpgExt in ["jpg", "jpeg", "JPG", "JPEG"] {
                        let jpgURL = directory.appendingPathComponent("\(baseName).\(jpgExt)")
                        if FileManager.default.fileExists(atPath: jpgURL.path) {
                            var trashedJpgURL: NSURL?
                            try? FileManager.default.trashItem(at: jpgURL, resultingItemURL: &trashedJpgURL)
                            if let trashedJpgURL = trashedJpgURL as? URL {
                                undoEntry.append((trashedURL: trashedJpgURL, originalURL: jpgURL))
                            }
                        }
                    }

                    let xmpURL = directory.appendingPathComponent("\(baseName).xmp")
                    if FileManager.default.fileExists(atPath: xmpURL.path) {
                        var trashedXmpURL: NSURL?
                        try? FileManager.default.trashItem(at: xmpURL, resultingItemURL: &trashedXmpURL)
                        if let trashedXmpURL = trashedXmpURL as? URL {
                            undoEntry.append((trashedURL: trashedXmpURL, originalURL: xmpURL))
                        }
                    }

                    let acrURL = directory.appendingPathComponent("\(baseName).acr")
                    if FileManager.default.fileExists(atPath: acrURL.path) {
                        var trashedAcrURL: NSURL?
                        try? FileManager.default.trashItem(at: acrURL, resultingItemURL: &trashedAcrURL)
                        if let trashedAcrURL = trashedAcrURL as? URL {
                            undoEntry.append((trashedURL: trashedAcrURL, originalURL: acrURL))
                        }
                    }
                }

                // Remove from photos array
                if let index = photosModel?.photos.firstIndex(where: { $0.id == photo.id }) {
                    photosModel?.photos.remove(at: index)
                    filesModel.lastDeletedFiles.append(url)
                }
            } catch {
                // Silently handle errors
            }
        }

        if !undoEntry.isEmpty {
            undoStack.append(undoEntry)
        }

        // Clear selection after moving
        selectedPhotos.removeAll()

        // Save the last selected index before updateFilteredPhotos resets it
        let savedLastSelectedIndex = lastSelectedIndex

        // Force immediate update of filtered photos to reflect the deletion
        updateFilteredPhotos()

        // Select a photo near the last selected index if available
        if !filteredPhotos.isEmpty {
            // Try to select the photo at the same index, or the closest one if that index is now out of bounds
            let targetIndex: Int
            if let lastIndex = savedLastSelectedIndex {
                // If the last index is still valid, use it
                // Otherwise, select the last photo (which is now at lastIndex - 1 if we deleted the last one)
                targetIndex = min(lastIndex, filteredPhotos.count - 1)
            } else {
                // No previous selection, default to first photo
                targetIndex = 0
            }

            let photoToSelect = filteredPhotos[targetIndex]
            filesModel.selectedPhoto = photoToSelect
            selectedPhotos.insert(photoToSelect.id)
            lastSelectedIndex = targetIndex
        } else {
            filesModel.selectedPhoto = nil
            lastSelectedIndex = nil
        }
    }

    func undoLastTrash() {
        guard let lastEntry = undoStack.popLast() else { return }
        for item in lastEntry {
            do {
                try FileManager.default.moveItem(at: item.trashedURL, to: item.originalURL)
                // Invalidate the cached thumbnail so it gets regenerated on reload
                ThumbsManager.shared.deleteCachedThumbnail(for: item.originalURL.path)
            } catch {
                // Silently handle errors
            }
        }
        // Explicitly reload since the file system watcher may not fire fast enough
        reloadPhotos()
    }

    func getPhotosMarkedForDeletion() -> [PhotoItem] {
        return photos.filter { $0.toDelete }
    }

    func getSelectedPhotosForBulkAction() -> [PhotoItem] {
        // Always get photos from the source of truth (photosModel.photos), not from cached filteredPhotos
        // This ensures we get the most current version of photos, even if filteredPhotos hasn't updated yet
        guard let photos = photosModel?.photos else { return [] }

        if selectedPhotos.count > 1 {
            // Get current versions of all selected photos from photosModel
            return photos.filter { selectedPhotos.contains($0.id) }
        } else if let selectedPhoto = filesModel.selectedPhoto {
            // Get the current version of the single selected photo from photosModel
            if let currentPhoto = photos.first(where: { $0.id == selectedPhoto.id }) {
                return [currentPhoto]
            }
            return [selectedPhoto]
        } else {
            return []
        }
    }

    // MARK: - Key Handling

    func handleKeyEvent(_ event: NSEvent,
                        scrollTo: (UUID) -> Void,
                        openPhotos: ([PhotoItem]) -> Void,
                        onToggleSidebar: (() -> Void)?) -> Bool {
        let chars = event.charactersIgnoringModifiers ?? ""
        let key: KeyEquivalent
        switch event.keyCode {
        case 123: key = .leftArrow
        case 124: key = .rightArrow
        case 125: key = .downArrow
        case 126: key = .upArrow
        case 36, 76: key = .return
        default:
            guard let first = chars.first else { return false }
            key = KeyEquivalent(first)
        }

        // Z — toggle zoom
        if key == KeyEquivalent("z") {
            NotificationCenter.default.post(name: .toggleZoom, object: nil)
            return true
        }

        guard !filteredPhotos.isEmpty else { return false }

        let currentIndex = filteredPhotos.firstIndex { $0.id == filesModel.selectedPhoto?.id } ?? 0
        var newIndex = currentIndex

        switch key {
        case .leftArrow:  newIndex = max(0, currentIndex - 1)
        case .rightArrow: newIndex = min(filteredPhotos.count - 1, currentIndex + 1)
        case .upArrow:    newIndex = max(0, currentIndex - gridType.columnCount)
        case .downArrow:  newIndex = min(filteredPhotos.count - 1, currentIndex + gridType.columnCount)
        case .return:
            handleReturnKey(openPhotos: openPhotos)
            return true
        default:
            let mods = event.modifierFlags
            if mods.contains(.command) && chars == "a" { selectAll(); return true }
            if mods.contains(.command) && chars == "z" { undoLastTrash(); return true }
            if chars == "c" || chars == "C" { onToggleSidebar?(); return true }
            if chars == "g" || chars == "G" { toggleGridType(); return true }
            let photos = getSelectedPhotosForBulkAction()
            guard !photos.isEmpty else { return false }
            // Ratings 1-5 (not 0, which is reserved for "To Do" label via labelMap)
            if let rating = Int(chars), rating >= 1 && rating <= 5 { applyRating(rating, to: photos); return true }
            // Toggle delete
            if chars == "x" || chars == "X" { toggleDeleteState(for: photos); return true }
            // Labels via number keys 6-0
            let labelMap: [String: String] = ["6": "Select", "7": "Second", "8": "Approved", "9": "Review", "0": "To Do"]
            if let label = labelMap[chars] { applyLabel(label, to: photos); return true }
            // Remove label
            if chars == "-" { removeLabels(from: photos); return true }
            return false
        }

        if newIndex != currentIndex {
            navigateToPhoto(at: newIndex)
            scrollTo(filteredPhotos[newIndex].id)
            return true
        }
        return false
    }

    func handleKeyPress(_ keyPress: KeyPress,
                        scrollTo: (UUID) -> Void,
                        openPhotos: ([PhotoItem]) -> Void,
                        onToggleSidebar: (() -> Void)?) -> KeyPress.Result {

        // Z — toggle zoom in LargePreviewView
        if keyPress.key == KeyEquivalent("z") {
            NotificationCenter.default.post(name: .toggleZoom, object: nil)
            return .handled
        }

        guard !filteredPhotos.isEmpty else {
            return .ignored
        }

        let currentIndex = filteredPhotos.firstIndex {
            $0.id == filesModel.selectedPhoto?.id
        } ?? 0
        var newIndex = currentIndex

        switch keyPress.key {
        case .leftArrow:
            newIndex = max(0, currentIndex - 1)
        case .rightArrow:
            newIndex = min(filteredPhotos.count - 1, currentIndex + 1)
        case .upArrow:
            newIndex = max(0, currentIndex - gridType.columnCount)
        case .downArrow:
            newIndex = min(filteredPhotos.count - 1, currentIndex + gridType.columnCount)
        case .return:
            handleReturnKey(openPhotos: openPhotos)
            return .handled
        default:
            return handleOtherKeys(keyPress, onToggleSidebar: onToggleSidebar)
        }

        if newIndex != currentIndex {
            navigateToPhoto(at: newIndex)
            scrollTo(filteredPhotos[newIndex].id)
            return .handled
        }

        return .ignored
    }

    private func handleReturnKey(openPhotos: ([PhotoItem]) -> Void) {
        let photosToOpen: [PhotoItem]
        if selectedPhotos.count > 1 {
            photosToOpen = filteredPhotos.filter { selectedPhotos.contains($0.id) }
        } else if let selectedPhoto = filesModel.selectedPhoto {
            photosToOpen = [selectedPhoto]
        } else {
            return
        }
        openPhotos(photosToOpen)
    }

    private func handleOtherKeys(_ keyPress: KeyPress, onToggleSidebar: (() -> Void)?) -> KeyPress.Result {
        let key = keyPress.characters

        // Toggle sidebar (works regardless of selection)
        if key == "c" || key == "C" {
            onToggleSidebar?()
            return .handled
        }

        // Toggle grid type (works regardless of selection)
        if key == "g" || key == "G" {
            toggleGridType()
            return .handled
        }

        let photos = getSelectedPhotosForBulkAction()
        guard !photos.isEmpty else { return .ignored }

        // Command+A for Select All
        if keyPress.modifiers.contains(.command) && keyPress.characters == "a" {
            selectAll()
            return .handled
        }

        // Command+Z for Undo last trash
        if keyPress.modifiers.contains(.command) && keyPress.characters == "z" {
            undoLastTrash()
            return .handled
        }

        // Cmd+Delete — immediately trash selected photos
        if keyPress.modifiers.contains(.command) &&
            (keyPress.key == .delete || keyPress.characters == "\u{7F}") {
            movePhotosToTrash(photos)
            return .handled
        }

        // Toggle reject state (X key, works for all files)
        let rawPhotos = photos.filter { $0.isRawFile }
        guard !rawPhotos.isEmpty else { return .ignored }

        // Rating keys (1-5)
        if let rating = Int(key), rating >= 1 && rating <= 5 {
            applyRating(rating, to: rawPhotos)
            return .handled
        }

        // Label keys (6-0)
        let labelMap: [String: String] = [
            "6": "Select",
            "7": "Second",
            "8": "Approved",
            "9": "Review",
            "0": "To Do"
        ]

        if let label = labelMap[key] {
            applyLabel(label, to: rawPhotos)
            return .handled
        }

        // Remove label
        if key == "-" {
            removeLabels(from: rawPhotos)
            return .handled
        }

        // Toggle reject state (X key)
        if key == "x" || key == "X" {
            toggleDeleteState(for: photos)
            return .handled
        }

        if key == "a" || key == "A" {
            applyLabel(labelMap["8"]!, to: rawPhotos)
            return .handled
        }

        return .ignored
    }

    // MARK: - Persistence
    func saveSortOption() {
        appPrefs.set(sortOption.rawValue, forKey: .sortOption)
    }

    func loadSortOption() {
        let saved = appPrefs.string(.sortOption)
        if let option = SortOption(rawValue: saved) {
            sortOption = option
        }
    }

    func saveGridType() {
        appPrefs.set(gridType.rawValue, forKey: .gridType)
    }

    func loadGridType() {
        let saved = appPrefs.string(.gridType)
        if let type = GridType(rawValue: saved) {
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
        print("🔍 clearInvalidFilters called - photos: \(photos.count), labels: \(selectedLabels), ratings: \(selectedRatings)")

        // Clear invalid label filters
        if !selectedLabels.isEmpty {
            var labelsToRemove: Set<String> = []

            for label in selectedLabels {
                // Check if any photo matches this label
                let hasMatchingPhoto = photos.contains { photo in
                    if label == "Rejected" && photo.toDelete {
                        return true
                    }

                    let photoLabel = photo.xmp?.label ?? ""

                    if label == "No Label" && photoLabel.isEmpty && !photo.toDelete {
                        return true
                    }

                    return photoLabel == label && !photo.toDelete
                }

                if !hasMatchingPhoto {
                    print("   ❌ Label '\(label)' has no matching photos - will remove")
                    labelsToRemove.insert(label)
                }
            }

            // Remove invalid labels
            if !labelsToRemove.isEmpty {
                print("   🗑️ Removing labels: \(labelsToRemove)")
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
            print("   🔎 Checking if remaining filters match any photos...")
            print("   Remaining labels: \(selectedLabels), ratings: \(selectedRatings)")

            // Manually check if any photo matches the remaining filters
            let hasMatchingPhoto = photos.contains { photo in
                var matchesLabel = selectedLabels.isEmpty
                var matchesRating = selectedRatings.isEmpty

                // Check label filter
                if !selectedLabels.isEmpty {
                    if selectedLabels.contains("Rejected") && photo.toDelete {
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
                print("   ❌ No photos match remaining filters - clearing ALL filters")
                selectedLabels.removeAll()
                selectedRatings.removeAll()
            } else {
                print("   ✅ Some photos match remaining filters - keeping them")
            }
        } else {
            print("   ℹ️ No active filters remaining after cleanup")
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
        case "Rejected": return .orange
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

        // Manually trigger filteredPhotos update to ensure UI reflects changes immediately
        updateFilteredPhotos()
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

        // Manually trigger filteredPhotos update to ensure UI reflects changes immediately
        updateFilteredPhotos()
    }

    // MARK: - Duplicate Finding

    func findDuplicates() {
        guard !isFindingDuplicates else { return }
        let photosToScan = filteredPhotos
        guard !photosToScan.isEmpty else { return }

        isFindingDuplicates = true
        duplicateScanProgress = (0, photosToScan.count)
        duplicateScanResult = nil
        duplicateScanData = nil

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // Wait for thumb generation to finish before scanning
            // (DuplicateFinderService reads from thumb cache)
            while await self.cachingQueueCount > 0 {
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            }
            let data = await DuplicateFinderService.scan(
                photos: photosToScan,
                progress: { done, total in
                    DispatchQueue.main.async { self.duplicateScanProgress = (done, total) }
                }
            )
            await MainActor.run {
                self.duplicateScanData = data
                if let data {
                    let result = data.recluster(threshold: self.similarityMode.distanceThreshold, sortBy: self.photoSortComparator)
                    self.duplicateScanResult = result
                    print("🔍 Scan complete: \(result.groups.count) group(s) in \(String(format: "%.2f", data.scanDuration))s")
                }
                self.isFindingDuplicates = false
                self.isDuplicateMode = true
            }
        }
    }

    func setSimilarityMode(_ mode: DuplicateFinderService.SimilarityMode) {
        similarityMode = mode
        saveSimilarityMode()
        // Re-cluster instantly from cached distances — no Vision re-run
        if let data = duplicateScanData {
            duplicateScanResult = data.recluster(threshold: mode.distanceThreshold, sortBy: photoSortComparator)
        }
    }

    func exitDuplicateMode() {
        isDuplicateMode = false
        duplicateScanResult = nil
        duplicateScanData = nil
    }

    func loadSimilarityMode() {
        let saved = appPrefs.int(.similarityMode)
        similarityMode = DuplicateFinderService.SimilarityMode(rawValue: saved) ?? .loose
    }

    func saveSimilarityMode() {
        appPrefs.set(similarityMode.rawValue, forKey: .similarityMode)
    }

}
