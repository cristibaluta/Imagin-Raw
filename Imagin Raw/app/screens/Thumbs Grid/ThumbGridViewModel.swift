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

    @Published var selectedPhotos: Set<UUID> = []
    @Published var selectedPhoto: PhotoItem?
    @Published var selectedLabels: Set<String> = []
    @Published var selectedRatings: Set<Int> = []
    @Published var sortOption: SortOption = .name
    @Published var gridType: GridType = .small
    @Published var windowWidth: CGFloat = 1200
    @Published var isSidebarCollapsed: Bool = false
    @Published var lastSelectedIndex: Int?
    @Published var cachingQueueCount: Int = 0
    @Published var isLoadingMetadata: Bool = false
    @Published var isFindingDuplicates: Bool = false
    @Published var isDuplicateMode: Bool = false
    @Published var duplicateScanProgress: (done: Int, total: Int) = (0, 0)
    @Published var duplicateScanResult: DuplicateScanResult? = nil
    @Published var similarityMode: DuplicateFinderService.SimilarityMode = .loose
    @Published private(set) var filteredAndSortedPhotos: [PhotoItem] = []
    @Published private(set) var dateGroups: [(title: String, photos: [PhotoItem])] = []
    @Published var photosToCopy: [PhotoItem] = []
    @Published var copyDestinationURL: URL?

    private var duplicateScanData: DuplicateScanData? = nil

    private let filesModel: FilesModel
    let thumbsManager: PhotoCacheManager
    private(set) var photosModel: PhotosModel?
    private var searchResultsPhotos: [PhotoItem]? = nil
    private var cancellables = Set<AnyCancellable>()

    private let metadataService = PhotoMetadataService()
    private let trashService    = PhotoTrashService()

    enum SortOption: String, CaseIterable {
        case name         = "Name"
        case dateCaptured = "Date Captured"
        case dateModified = "Date Modified"
        case fileType     = "File Type"
        case rating       = "Rating"
    }

    enum GridType: String, CaseIterable, Identifiable {
        case small = "SmallGrid"
        case large = "LargeGrid"

        var id: String { rawValue }

        var columnCount: Int  { self == .small ? 3 : 5 }
        var thumbSize: CGFloat { self == .small ? 110 : 210 }
        var cellHeight: CGFloat { self == .small ? 150 : 250 }
        var displayName: String { self == .small ? "Small" : "Large" }
        var iconName: String { self == .small ? "square.grid.3x3" : "square.grid.4x4.fill" }
    }
    let id = UUID()
    init(filesModel: FilesModel, thumbsManager: PhotoCacheManager) {
        self.filesModel = filesModel
        self.thumbsManager = thumbsManager
        loadSortOption()
        loadGridType()
        loadSimilarityMode()
        setupFilteredPhotosObservers()
        setupServices()
        print(">>>>>>> init ThumbGridViewModel \(id)")
    }

    private func setupServices() {
        metadataService.filesModel = filesModel
        metadataService.onPhotoUpdated = { [weak self] in
            self?.filterAndSortPhotos()
        }
        trashService.filesModel = filesModel
        trashService.thumbsManager = thumbsManager
    }

    private func setupFilteredPhotosObservers() {
        Publishers.CombineLatest4($selectedLabels, $selectedRatings, $sortOption, $isLoadingMetadata)
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.filterAndSortPhotos()
            }
            .store(in: &cancellables)
    }

    var photos: [PhotoItem] {
        searchResultsPhotos ?? photosModel?.photos ?? []
    }

    var photosSize: Int64 {
        photos.reduce(into: 0) { result, photo in
            result += photo.fileSizeBytes ?? 0
        }
    }

    var availableLabels: [String] {
        PhotoFilterService.availableLabels(from: photos)
    }

    var availableRatings: [Int] {
        PhotoFilterService.availableRatings(from: photos)
    }

    var photoSortComparator: (PhotoItem, PhotoItem) -> Bool {
        PhotoFilterService.comparator(for: sortOption)
    }

    private static let sidebarWidth: CGFloat = 200
    private static let previewMinWidth: CGFloat = 280
    private static let gap: CGFloat = 3

    var effectiveColumnCount: Int {
        if gridType == .small {
            return gridType.columnCount
        }
        let available = windowWidth - (isSidebarCollapsed ? 0 : Self.sidebarWidth) - Self.previewMinWidth
        return max(2, Int(floor((available + Self.gap) / (gridType.thumbSize + Self.gap))))
    }

    var dynamicColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: gridType.thumbSize), spacing: 8), count: effectiveColumnCount)
    }

    var gridWidth: CGFloat {
        let cols = CGFloat(effectiveColumnCount)
        let thumbsWidth = cols * gridType.thumbSize + (cols + 1) * Self.gap
        let minimap: CGFloat = (!dateGroups.isEmpty && !isDuplicateMode) ? MinimapView.width : 0
        return thumbsWidth + minimap + 1
    }

    var showCachingProgress: Bool {
        cachingQueueCount > 0
    }

    // MARK: - Filtering

    func filterAndSortPhotos() {
        let lastSelectedPhotoId = selectedPhoto?.id
        var result = photos

        // Filter photos
        if !isLoadingMetadata {
            result = PhotoFilterService.apply(labels: selectedLabels, ratings: selectedRatings, to: result)
        }

        if !photos.isEmpty && result.isEmpty {
            result = photos
        }

        // Sort photos
        result = result.sorted(by: photoSortComparator)
        Task {
            filteredAndSortedPhotos = result
            
            // Group photos
            dateGroups = PhotoFilterService.buildDateGroups(from: result, sortOption: sortOption)
            
            if let id = lastSelectedPhotoId {
                lastSelectedIndex = filteredAndSortedPhotos.firstIndex { $0.id == id }
            } else if selectedPhoto == nil {
                lastSelectedIndex = nil
            }
        }
    }

    func clearInvalidFilters() {
        let before = (selectedLabels, selectedRatings)
        selectedLabels = selectedLabels.filter { label in
            photos.contains { photo in
                if label == "Rejected" {
                    return photo.toDelete
                }
                let pl = photo.xmp?.label ?? ""
                if label == "No Label" {
                    return pl.isEmpty && !photo.toDelete
                }
                return pl == label && !photo.toDelete
            }
        }
        selectedRatings = selectedRatings.filter { rating in
            photos.contains { $0.effectiveRating == rating }
        }
        RCLog("🔍 clearInvalidFilters: labels \(before.0)→\(selectedLabels) ratings \(before.1)→\(selectedRatings)")
    }

    func toggleLabelFilter(_ label: String) {
        if selectedLabels.contains(label) {
            selectedLabels.remove(label)
        } else {
            selectedLabels.insert(label)
        }
    }

    // MARK: - Photo Loading

    func loadPhotosForFolder(_ folder: FolderItem) {
        RCLog("📂 Loading photos for folder: \(folder.url.lastPathComponent)")
        reset()
        setupFilteredPhotosObservers()

        let newPhotosModel = PhotosModel(folder: folder)
        photosModel = newPhotosModel
        metadataService.photosModel = newPhotosModel
        trashService.photosModel = newPhotosModel
        selectedPhotos.removeAll()
        lastSelectedIndex = nil
        selectedPhoto = nil

        newPhotosModel.objectWillChange
            .sink { [weak self] _ in
                Task {
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        newPhotosModel.$isLoadingMetadata
            .sink { [weak self] isLoading in
                self?.isLoadingMetadata = isLoading
            }
            .store(in: &cancellables)

        newPhotosModel.$photos
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.filterAndSortPhotos()
            }
            .store(in: &cancellables)

        newPhotosModel.loadPhotos()
    }

    func reset() {
        cancellables.removeAll()
        clearSearchResults()
        exitDuplicateMode()
        selectedPhoto = nil
        selectedPhotos.removeAll()
    }

    func reloadPhotos() {
        RCLog("🔄 Reloading photos")
        photosModel?.reloadPhotos()
    }

    func reloadMetadata(forSidecar url: URL) {
        photosModel?.reloadMetadata(forSidecar: url) { [weak self] in
            self?.filterAndSortPhotos()
        }
    }

    func loadSearchResults(_ items: [PhotoItem]) {
        searchResultsPhotos = items
        selectedPhotos.removeAll()
        lastSelectedIndex = nil
        filterAndSortPhotos()
    }

    func clearSearchResults() {
        searchResultsPhotos = nil
        filterAndSortPhotos()
    }

    // MARK: - Selection

    func handlePhotoTap(photo: PhotoItem, modifiers: NSEvent.ModifierFlags) {
        let photoIndex = filteredAndSortedPhotos.firstIndex(where: { $0.id == photo.id }) ?? 0
        if modifiers.contains(.command) {
            // Toggle selected state
            if selectedPhotos.contains(photo.id) {
                selectedPhotos.remove(photo.id)
            } else {
                selectedPhotos.insert(photo.id)
                selectedPhoto = photo
                lastSelectedIndex = photoIndex
            }
        } else if modifiers.contains(.shift) {
            let start = min(lastSelectedIndex ?? 0, photoIndex)
            let end = max(lastSelectedIndex ?? 0, photoIndex)
            for i in start...end where i < filteredAndSortedPhotos.count {
                selectedPhotos.insert(filteredAndSortedPhotos[i].id)
            }
            selectedPhoto = photo
        } else {
            selectedPhoto = photo
            selectedPhotos = [photo.id]
            lastSelectedIndex = photoIndex
        }
    }

    func selectAll() {
        selectedPhotos = Set(filteredAndSortedPhotos.map { $0.id })
        if let first = filteredAndSortedPhotos.first {
            selectedPhoto = first
            lastSelectedIndex = 0
        }
    }

    // TODO: is this needed? doesn't take into the account the groups
//    func navigateToPhoto(at newIndex: Int) {
//        guard newIndex >= 0 && newIndex < filteredAndSortedPhotos.count else {
//            return
//        }
//        selectedPhotos = [filteredAndSortedPhotos[newIndex].id]
//        selectedPhoto = filteredAndSortedPhotos[newIndex]
//        lastSelectedIndex = newIndex
//    }

    func initializeSelection() {
        if selectedPhoto == nil, let first = filteredAndSortedPhotos.first {
            selectedPhoto = first
            selectedPhotos = [first.id]
        }
    }

    func getPhotosMarkedForDeletion() -> [PhotoItem] {
        photos.filter { $0.toDelete }
    }

    func getSelectedPhotosForBulkAction() -> [PhotoItem] {
        guard let allPhotos = photosModel?.photos else {
            return []
        }
        if selectedPhotos.count > 1 {
            return allPhotos.filter { selectedPhotos.contains($0.id) }
        }
        if let sel = selectedPhoto {
            return [allPhotos.first(where: { $0.id == sel.id }) ?? sel]
        }
        return []
    }

    // MARK: - Rating & Label (delegate to service)

    func applyRating(_ rating: Int, to photos: [PhotoItem]) {
        metadataService.applyRating(rating, to: photos)
    }

    func applyLabel(_ label: String, to photos: [PhotoItem]) {
        metadataService.applyLabel(label, to: photos)
    }

    func removeLabels(from photos: [PhotoItem]) {
        metadataService.removeLabels(from: photos)
    }

    func toggleDeleteState(for photos: [PhotoItem]) {
        metadataService.toggleDeleteState(for: photos)
    }

    func movePhotosToTrash(_ photos: [PhotoItem]) {
        guard let first = photos.first else {
            return
        }
        // 1. Get the index of the photo to delete
        let index = filteredAndSortedPhotos.firstIndex { $0.id == first.id }

        // 2. Move selected photos to trash
        let photosToDelete = selectedPhotos.contains(first.id)
            ? getSelectedPhotosForBulkAction()
            : photos
        trashService.movePhotosToTrash(photosToDelete)
        selectedPhotos.removeAll()
        filterAndSortPhotos()

        // 3. Find the next closest index after the photos were deleted
        if let index,  index < filteredAndSortedPhotos.count {
            let nextIndex = min(index, filteredAndSortedPhotos.count - 1)
            let nextPhoto = filteredAndSortedPhotos[nextIndex]
            selectedPhoto = nextPhoto
            selectedPhotos = [nextPhoto.id]
            lastSelectedIndex = nextIndex
        } else {
            selectedPhoto = nil
            lastSelectedIndex = nil
        }
    }

    func undoLastTrash() {
        trashService.undoLastTrash()
        reloadPhotos()
    }

    // MARK: - Key Handling

    func handleKeyEvent(_ event: NSEvent,
                        scrollTo: (UUID) -> Void,
                        openPhotos: ([PhotoItem]) -> Void,
                        onToggleSidebar: (() -> Void)?,
                        onReviewSelected: (([PhotoItem]) -> Void)? = nil) -> Bool {
        #if os(macOS)
        let chars = event.charactersIgnoringModifiers ?? ""
        let key: KeyEquivalent
        switch event.keyCode {
            case 123: key = .leftArrow
            case 124: key = .rightArrow
            case 125: key = .downArrow
            case 126: key = .upArrow
            case 36, 76: key = .return
            case 49: key = .space
            case 51: key = .delete
            default:
                guard let first = chars.first else {
                    return false
                }
                key = KeyEquivalent(first)
        }

        if filteredAndSortedPhotos.isEmpty {
            return false
        }

        switch key {
            case .leftArrow, .rightArrow, .upArrow, .downArrow:
                if let nextPhoto = navigateTo(key) {
                    scrollTo(nextPhoto.id)
                    return true
                }
                return false
            case .return:
                let photos = getSelectedPhotosForBulkAction()
                openPhotos(selectedPhotos.count > 1 ? filteredAndSortedPhotos.filter { selectedPhotos.contains($0.id) } : photos)
                return true
            case .space:
                let photos = getSelectedPhotosForBulkAction()
                if !photos.isEmpty {
                    onReviewSelected?(photos)
                }
                return true
            case .delete:
                let photos = getSelectedPhotosForBulkAction()
                if !photos.isEmpty {
                    event.modifierFlags.contains(.command) ? movePhotosToTrash(photos) : toggleDeleteState(for: photos)
                }
                return true
            default:
                let mods = event.modifierFlags
                if mods.contains(.command) && chars == "a" {
                    selectAll()
                    return true
                }
                if chars == "z" {
                    if mods.contains(.command) {
                        undoLastTrash()
                    } else {
                        NotificationCenter.default.post(name: .toggleZoom, object: nil)
                    }
                    return true
                }
                if chars == "c" || chars == "C" {
                    onToggleSidebar?()
                    return true
                }
                if chars == "g" || chars == "G" {
                    toggleGridType()
                    return true
                }

                let photos = getSelectedPhotosForBulkAction()
                if photos.isEmpty {
                    return false
                }

                if chars == "a" || chars == "A" {
                    applyLabel("Approved", to: photos)
                    return true
                }
                if chars == "x" || chars == "X" {
                    if mods.contains(.option) {
                        if selectedLabels.contains("Rejected") {
                            selectedLabels = []
                        } else {
                            selectedLabels = ["Rejected"]
                        }
                    } else {
                        toggleDeleteState(for: photos)
                    }
                    return true
                }
                if let r = Int(chars), r >= 1 && r <= 5 {
                    if mods.contains(.option) {
                        if selectedRatings.contains(r) {
                            selectedRatings.remove(r)
                        } else {
                            selectedRatings.insert(r)
                        }
                    } else {
                        applyRating(r, to: photos)
                    }
                    return true
                }
                let labelMap = ["6": "Select", "7": "Second", "8": "Approved", "9": "Review", "0": "To Do"]
                if let label = labelMap[chars] {
                    if mods.contains(.option) {
                        if selectedLabels.contains(label) {
                            selectedLabels.remove(label)
                        } else {
                            selectedLabels.insert(label)
                        }
                    } else {
                        applyLabel(label, to: photos)
                    }
                    return true
                }
                if chars == "-" {
                    removeLabels(from: photos)
                    return true
                }
                return false
        }
        #endif
        return false
    }

    private func navigateTo(_ key: KeyEquivalent) -> PhotoItem? {
        if dateGroups.count > 0 {
            var nextIndex: IndexPath? = nil
            var item: Int? = 0
            let section: Int? = dateGroups.firstIndex {
                let r = $0.photos.firstIndex { $0.id == selectedPhoto?.id }
                item = r
                return r != nil
            }
            if let section, let item {
                switch key {
                    case .leftArrow:
                        // Find the prev  item in the current section
                        if item - 1 >= 0 {
                            nextIndex = IndexPath(item: item - 1, section: section)
                        } else {
                            // Go to prev item in the next section
                            if section - 1 >= 0 {
                                nextIndex = IndexPath(item: dateGroups[section-1].photos.count - 1, section: section - 1)
                            } else {
                                nextIndex = IndexPath(item: dateGroups[section-1].photos.count - 1, section: dateGroups.count - 1)
                            }
                        }
                    case .rightArrow:
                        // Find the next  item in the current section
                        let photosInSection = dateGroups[section].photos
                        if photosInSection.count > item + 1 {
                            nextIndex = IndexPath(item: item + 1, section: section)
                        } else {
                            // Go to first item in the next section
                            if section + 1 < dateGroups.count {
                                nextIndex = IndexPath(item: 0, section: section + 1)
                            } else {
                                nextIndex = IndexPath(item: 0, section: 0)
                            }
                        }
                    case .upArrow:
                        let columns = 3
                        let direction = -columns
                        let flatIndex = flatIndexFor(section: section, item: item) + direction
                        nextIndex = indexPathFor(flatIndex: flatIndex)
                    case .downArrow:
                        let columns = 3
                        let direction = columns
                        let flatIndex = flatIndexFor(section: section, item: item) + direction
                        nextIndex = indexPathFor(flatIndex: flatIndex)
                    default:
                        return nil
                }
            }
            if let nextIndex {
                let nextPhoto = dateGroups[nextIndex.section].photos[nextIndex.item]
                selectedPhotos = [nextPhoto.id]
                selectedPhoto = nextPhoto
                lastSelectedIndex = nil
                return nextPhoto
            }
        } else {
            // Navigate through the filteredAndSortedPhotos
            let cur = filteredAndSortedPhotos.firstIndex { $0.id == selectedPhoto?.id } ?? 0
            var nextIndex = cur

            switch key {
                case .leftArrow:  nextIndex = max(0, cur - 1)
                case .rightArrow: nextIndex = min(filteredAndSortedPhotos.count - 1, cur + 1)
                case .upArrow:    nextIndex = max(0, cur - gridType.columnCount)
                case .downArrow:  nextIndex = min(filteredAndSortedPhotos.count - 1, cur + gridType.columnCount)
                default:
                    return nil
            }
            let nextPhoto = filteredAndSortedPhotos[nextIndex]
            selectedPhotos = [nextPhoto.id]
            selectedPhoto = nextPhoto
            lastSelectedIndex = nil
            return nextPhoto
        }
        return nil
    }

    // Convert section+item → flat index across all sections
    private func flatIndexFor(section: Int, item: Int) -> Int {
        let itemsBefore = (0..<section).reduce(0) { $0 + dateGroups[$1].photos.count }
        return itemsBefore + item
    }

    // Convert flat index → section+item
    private func indexPathFor(flatIndex: Int) -> IndexPath? {
        guard flatIndex >= 0 else { return nil }
        var remaining = flatIndex
        for (s, group) in dateGroups.enumerated() {
            if remaining < group.photos.count {
                return IndexPath(item: remaining, section: s)
            }
            remaining -= group.photos.count
        }
        return nil  // past the end
    }

    // MARK: - Persistence

    func saveSortOption() {
        appPrefs.set(sortOption.rawValue, forKey: .sortOption)
    }
    func loadSortOption() {
        let saved = appPrefs.string(.sortOption)
        let migrated = saved == "Date Created" ? "Date Captured" : saved
        if let opt = SortOption(rawValue: migrated) {
            sortOption = opt
        }
    }
    func saveGridType() {
        appPrefs.set(gridType.rawValue, forKey: .gridType)
    }
    func loadGridType() {
        if let t = GridType(rawValue: appPrefs.string(.gridType)) {
            gridType = t
        }
    }
    func toggleGridType() {
        gridType = gridType == .small ? .large : .small
        saveGridType()
    }

    // MARK: - Duplicate Finding

    func findDuplicates() {
        guard !isFindingDuplicates else {
            return
        }
        let photosToScan = filteredAndSortedPhotos
        guard !photosToScan.isEmpty else {
            return
        }
        isFindingDuplicates = true
        duplicateScanProgress = (0, photosToScan.count)
        duplicateScanResult = nil
        duplicateScanData = nil

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else {
                return
            }
            while await self.cachingQueueCount > 0 {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
//            let data = await DuplicateFinderService.scan(
//                photos: photosToScan, thumbsManager: thumbsManager,
//                progress: { done, total in
//                    DispatchQueue.main.async {
//                        self.duplicateScanProgress = (done, total)
//                    }
//                })
//            await MainActor.run {
//                self.duplicateScanData = data
//                if let data {
//                    let result = data.recluster(threshold: self.similarityMode.distanceThreshold,
//                                                sortBy: self.photoSortComparator)
//                    self.duplicateScanResult = result
//                    RCLog("🔍 Scan complete: \(result.groups.count) group(s) in \(String(format: "%.2f", data.scanDuration))s")
//                }
//                self.isFindingDuplicates = false
//                self.isDuplicateMode = true
//            }
        }
    }

    func setSimilarityMode(_ mode: DuplicateFinderService.SimilarityMode) {
        similarityMode = mode
        appPrefs.set(mode.rawValue, forKey: .similarityMode)
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
        similarityMode = DuplicateFinderService.SimilarityMode(rawValue: appPrefs.int(.similarityMode)) ?? .loose
    }
}
