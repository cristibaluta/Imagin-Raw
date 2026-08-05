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

    @Published private(set) var filteredAndSortedPhotos: [PhotoItem] = []
    @Published private(set) var groupedPhotos: [(title: String, photos: [PhotoItem])] = []
    @Published var selectedPhotos: [PhotoItem] = []
    @Published var lastSelectedIndexPath: IndexPath?
    // Filtering options
    @Published var selectedLabels: Set<PhotoLabel> = []
    @Published var selectedRatings: Set<Int> = []
    @Published var selectedNames: Set<String> = []
    // Sorting
    @Published var sortOption: SortOption = .name
    // UI
    @Published var gridType: GridType = .small
    @Published var windowWidth: CGFloat = 1200
    @Published var isSidebarCollapsed: Bool = false
    @Published var isLoadingMetadata: Bool = false
    @Published var copyJob: PhotoCopySheetModel? = nil
    @Published var renameJob: PhotosSheetItem? = nil

    var onReviewSelected: ((ReviewGroupItem?) -> Void)?

    /// Set before loading a folder to auto-select a specific photo once it appears in the grid.
    var pendingSelectURL: URL? = nil {
        didSet {
            RCLog("🎯 [ThumbGridViewModel] pendingSelectURL set to: \(pendingSelectURL?.lastPathComponent ?? "nil")")
        }
    }

    var showMinimap: Bool {
        groupedPhotos.count > 1
    }

    private let fileSystemModel: FileSystemModel
    let thumbsManager: PhotoCacheManager
    private let duplicatesFinderModel: DuplicatesFinderViewModel
    private let externalAppManager: ExternalAppManager
    private let cachingManager: IRCachingImageManager
    private(set) var photosModel: PhotosModel?
    private var searchResultsPhotos: [PhotoItem]? = nil
    private var cancellables = Set<AnyCancellable>()

    private let metadataService = PhotoMetadataService()
    private let trashService: PhotoTrashService

    init(fileSystemModel: FileSystemModel,
         thumbsManager: PhotoCacheManager,
         trashService: PhotoTrashService,
         duplicatesFinderModel: DuplicatesFinderViewModel,
         externalAppManager: ExternalAppManager) {

        self.fileSystemModel = fileSystemModel
        self.thumbsManager = thumbsManager
        self.trashService = trashService
        self.cachingManager = IRCachingImageManager(cacheManager: thumbsManager)
        self.duplicatesFinderModel = duplicatesFinderModel
        self.externalAppManager = externalAppManager

        loadSortOption()
        loadGridType()
        setupFilteredPhotosObservers()

        metadataService.fileSystemModel = fileSystemModel
        metadataService.onPhotoUpdated = { [weak self] in
            self?.filterAndSortPhotos()
        }
    }

    private func setupFilteredPhotosObservers() {
        Publishers.CombineLatest4($selectedLabels,
                                  $selectedRatings,
                                  $selectedNames,
                                  $sortOption)
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.filterAndSortPhotos()
            }
            .store(in: &cancellables)

        $isLoadingMetadata
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                if self?.isLoadingMetadata == false {
                    self?.filterAndSortPhotos()
                    self?.initializeSelection()
                }
            }
            .store(in: &cancellables)

        duplicatesFinderModel.$duplicateScanResult
            .dropFirst()
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                // TODO: Without the delay, filterAndSortPhotos doesn't actually find the duplicateScanResult
                // and it's not showing the correct thumbnails
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

    var availableLabels: [PhotoLabel] {
        PhotoFilterService.availableLabels(from: photos)
    }

    var availableRatings: [Int] {
        PhotoFilterService.availableRatings(from: photos)
    }

    var photoSortComparator: (PhotoItem, PhotoItem) -> Bool {
        PhotoFilterService.comparator(for: sortOption)
    }

    private static let previewMinWidth: CGFloat = 280
    private static let gap: CGFloat = 3

    var effectiveColumnCount: Int {
        if gridType == .small {
            return gridType.columnCount
        }
        let available = windowWidth - (isSidebarCollapsed ? 0 : MainView.sidebarColumnWidth) - Self.previewMinWidth
        return max(2, Int(floor((available + Self.gap) / (gridType.thumbSize + Self.gap))))
    }

    var dynamicColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: gridType.thumbSize), spacing: 8), count: effectiveColumnCount)
    }

    var gridWidth: CGFloat {
        let cols = CGFloat(effectiveColumnCount)
        let thumbsWidth = cols * gridType.thumbSize + (cols + 1) * Self.gap
        let minimap: CGFloat = groupedPhotos.count > 1 ? MinimapView.width : 0
        return thumbsWidth + minimap + 1
    }

    var showCachingProgress: Bool {
        duplicatesFinderModel.cachingQueueCount > 0
    }

    // MARK: - Filtering

    func filterAndSortPhotos() {
        RCLog(">>>>>>>> filterAndSortPhotos")
        let lastSelectedPhotoId = selectedPhotos.first?.id
        var result = photos

        // Filter photos
        if !isLoadingMetadata {
            result = PhotoFilterService.apply(labels: selectedLabels,
                                              ratings: selectedRatings,
                                              names: selectedNames,
                                              to: result)
        }

        if !photos.isEmpty && result.isEmpty {
            result = photos
        }

        // Sort photos
        result = result.sorted(by: photoSortComparator)
        filteredAndSortedPhotos = result

        // Group photos
        if let results = duplicatesFinderModel.duplicateScanResult {
            var index = 0
            let count = results.groups.count
            groupedPhotos = results.groups.map {
                index += 1
                return (title: "Group \(index) / \(count)", photos: $0.photos)
            }
        } else {
            groupedPhotos = PhotoFilterService.groupPhotos(from: result, sortOption: sortOption)
        }

        if let id = lastSelectedPhotoId {
            for (i, group) in groupedPhotos.enumerated() {
                let item = group.photos.firstIndex { $0.id == id }
                if let item {
                    lastSelectedIndexPath = IndexPath(item: item, section: i)
                    break
                }
            }
        } else if !selectedPhotos.isEmpty {
            lastSelectedIndexPath = nil
        }

        // Auto-select a specific photo requested via drag-and-drop / open-with
        if let url = pendingSelectURL {
            if let photo = filteredAndSortedPhotos.first(where: { $0.url == url }) {
                RCLog("found pending photo, selecting: \(photo.url.lastPathComponent)")
                pendingSelectURL = nil
                selectedPhotos = [photo]

                for (i, group) in groupedPhotos.enumerated() {
                    let item = group.photos.firstIndex { $0.id == photo.id }
                    if let item {
                        lastSelectedIndexPath = IndexPath(item: item, section: i)
                        break
                    }
                }
            } else {
                RCLog("pending photo not in grid yet, waiting...")
            }
        }
    }

    func clearInvalidFilters() {
        selectedLabels = selectedLabels.filter { label in
            photos.contains { photo in
                if label == .rejected {
                    return photo.state == .rejected
                }
                let xmpLabel = photo.xmp?.label ?? ""
                if label == .noLabel {
                    return xmpLabel.isEmpty && photo.state != .rejected
                }
                return xmpLabel == label.rawValue && photo.state != .rejected
            }
        }
        selectedRatings = selectedRatings.filter { rating in
            photos.contains {
                $0.effectiveRating == rating
            }
        }
    }

    func toggleLabelFilter(_ label: PhotoLabel) {
        if selectedLabels.contains(label) {
            selectedLabels.remove(label)
        } else {
            selectedLabels.insert(label)
        }
    }

    // MARK: - Photo Loading

    func loadPhotosForFolder(_ folder: FolderItem, includeSubfolders: Bool) {
        RCLog("Loading photos for folder: \(folder.url.lastPathComponent) | pendingSelectURL before reset: \(pendingSelectURL?.lastPathComponent ?? "nil")")
        let savedPendingURL = pendingSelectURL
        resetPreviousSession()
        pendingSelectURL = savedPendingURL
        setupFilteredPhotosObservers()

        let newPhotosModel = PhotosModel(folder: folder, includeSubfolders: includeSubfolders)
        photosModel = newPhotosModel
        metadataService.photosModel = newPhotosModel
        trashService.photosModel = newPhotosModel
        lastSelectedIndexPath = nil

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

//        newPhotosModel.$photos
//            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
//            .sink { [weak self] _ in
//                self?.filterAndSortPhotos()
//            }
//            .store(in: &cancellables)

        newPhotosModel.loadPhotos()
    }

    private func resetPreviousSession() {
        cancellables.removeAll()
        duplicatesFinderModel.exitDuplicateMode()
        searchResultsPhotos = nil
        selectedPhotos.removeAll()
        filteredAndSortedPhotos.removeAll()
    }

    func reloadPhotos() {
        photosModel?.reloadPhotos()
    }

    func applyFileSystemChanges(at urls: [URL]) {
        RCLog("Applying file system changes for \(urls.count) file(s)")
        for url in urls where !FileManager.default.fileExists(atPath: url.path) {
            if let photo = photosModel?.photos.first(where: { $0.url == url }) {
                selectedPhotos.removeAll(where: { $0.id == photo.id })
            }
        }
        photosModel?.applyFileSystemChanges(at: urls)
        filterAndSortPhotos()
    }

    func reloadMetadata(forSidecar url: URL) {
        photosModel?.reloadMetadata(forSidecar: url) { [weak self] in
            DispatchQueue.main.async {
                self?.filterAndSortPhotos()
            }
        }
    }

    func loadSearchResults(_ items: [PhotoItem]) {
        searchResultsPhotos = items
        selectedPhotos.removeAll()
        lastSelectedIndexPath = nil
        filterAndSortPhotos()
    }

    func clearSearchResults() {
        searchResultsPhotos = nil
        filterAndSortPhotos()
    }

    func requestImage(for photo: PhotoItem, completion: @escaping @Sendable (IRImage?) -> Void) {
        cachingManager.requestImage(for: photo, completion: completion)
    }

    // MARK: - Selection

    func handlePhotoTap(photo: PhotoItem, modifiers: NSEvent.ModifierFlags) {
        guard let photoIndexPath = indexPath(for: photo) else {
            return
        }
        if modifiers.contains(.command) {
            // Toggle selected state
            if selectedPhotos.contains(photo) {
                selectedPhotos.removeAll(where: { $0.id == photo.id })
            } else {
                selectedPhotos.append(photo)
                lastSelectedIndexPath = photoIndexPath
            }
        } else if modifiers.contains(.shift) {
            selectedPhotos += photos(from: lastSelectedIndexPath ?? IndexPath(item: 0, section: 0), to: photoIndexPath)
            lastSelectedIndexPath = photoIndexPath
        } else {
            selectedPhotos = [photo]
            lastSelectedIndexPath = photoIndexPath
        }
    }

    func selectAll() {
        selectedPhotos = filteredAndSortedPhotos
        lastSelectedIndexPath = IndexPath(item: 0, section: 0)
    }

    func initializeSelection() {
        if selectedPhotos.isEmpty, let first = filteredAndSortedPhotos.first {
            selectedPhotos = [first]
        }
    }

    func getPhotosMarkedForDeletion() -> [PhotoItem] {
        photos.filter { $0.state == .rejected }
    }

    // MARK: - Rating & Label (delegate to service)

    func applyRating(_ rating: Int, to photos: [PhotoItem]) {
        metadataService.applyRating(rating, to: photos)
    }

    func applyLabel(_ label: PhotoLabel, to photos: [PhotoItem]) {
        metadataService.applyLabel(label.rawValue, to: photos)
    }

    func removeLabels(from photos: [PhotoItem]) {
        metadataService.removeLabels(from: photos)
    }

    func removeLabelsAndRatings(from photos: [PhotoItem]) {
        metadataService.removeLabels(from: photos)
        metadataService.applyRating(0, to: photos)
    }

    func toggleCopyState(for photos: [PhotoItem]) {
        metadataService.toggleCopyState(for: photos)
    }

    func toggleRejectedState(for photos: [PhotoItem]) {
        metadataService.toggleRejectedState(for: photos)
    }

    func movePhotosToTrash(_ photos: [PhotoItem]) {
        guard let first = photos.first else {
            return
        }
        // 1. Get the index of the first photo to delete
        let index = filteredAndSortedPhotos.firstIndex { $0.id == first.id }

        // 2. Move selected photos to trash
        let photosToDelete = selectedPhotos.contains(first)
            ? selectedPhotos
            : photos
        trashService.movePhotosToTrash(photosToDelete)

        // 3. Remove from models
        selectedPhotos.removeAll()
        let remainingPhotos = (photosModel?.photos ?? []).filter { !photosToDelete.contains($0) }
        // TODO: photosmodel will also trigger a filterAndSortPhotos
        photosModel?.photos = remainingPhotos
        // 4. Rebuild the model
        // TODO: Is this needed? Is this causing the UI reload when deleting a photo?
        filterAndSortPhotos()

        // 5. Find the next closest index after the photos were deleted
        if let index, index < filteredAndSortedPhotos.count {
//            let nextIndex = min(index, filteredAndSortedPhotos.count - 1)
//            let nextPhoto = filteredAndSortedPhotos[nextIndex]
//            selectedPhotos = [nextPhoto]
//            lastSelectedIndexPath = nextIndex
        } else {
            selectedPhotos.removeAll()
            lastSelectedIndexPath = nil
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
                openPhotos(selectedPhotos.count > 1
                           ? filteredAndSortedPhotos.filter { selectedPhotos.contains($0) }
                           : selectedPhotos)
                return true
            case .space:
                if !selectedPhotos.isEmpty {
                    onReviewSelected?(selectedPhotos)
                }
                return true
            case .delete:
                if !selectedPhotos.isEmpty {
                    event.modifierFlags.contains(.command)
                        ? movePhotosToTrash(selectedPhotos)
                        : toggleRejectedState(for: selectedPhotos)
                }
                return true
            default:
                let mods = event.modifierFlags
                if mods.contains(.command) && chars == "a" {
                    selectAll()
                    return true
                }
                if mods.contains(.option) && chars == "c" {
                    quickCopy(photos: selectedPhotos)
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
                if chars == "s" || chars == "S" {
                    onToggleSidebar?()
                    return true
                }
                if chars == "g" || chars == "G" {
                    toggleGridType()
                    return true
                }

                // This actions are applied only to selectedPhotos
                if selectedPhotos.isEmpty {
                    return false
                }

                if chars == "a" || chars == "A" {
                    applyLabel(.approved, to: selectedPhotos)
                    return true
                }
                if chars == "c" || chars == "C" {
                    toggleCopyState(for: selectedPhotos)
                    return true
                }
                if chars == "x" || chars == "X" {
                    if mods.contains(.option) {
                        selectedLabels = selectedLabels.contains(.rejected) ? [] : [.rejected]
                    } else {
                        toggleRejectedState(for: selectedPhotos)
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
                        applyRating(r, to: selectedPhotos)
                    }
                    return true
                }
                let labelMap = ["6": PhotoLabel.select,
                                "7": PhotoLabel.second,
                                "8": PhotoLabel.approved,
                                "9": PhotoLabel.review,
                                "0": PhotoLabel.todo]
                if let label = labelMap[chars] {
                    if mods.contains(.option) {
                        if selectedLabels.contains(label) {
                            selectedLabels.remove(label)
                        } else {
                            selectedLabels.insert(label)
                        }
                    } else {
                        applyLabel(label, to: selectedPhotos)
                    }
                    return true
                }
                if chars == "-" {
                    removeLabelsAndRatings(from: selectedPhotos)
                    return true
                }
                return false
        }
        #else
        return false
        #endif
    }

    private func navigateTo(_ key: KeyEquivalent) -> PhotoItem? {
        guard groupedPhotos.count > 0 else {
            return nil
        }
        var nextIndex: IndexPath? = nil
        var item: Int? = 0
        let section: Int? = groupedPhotos.firstIndex {
            let r = $0.photos.firstIndex { $0.id == selectedPhotos.first?.id }
            item = r
            return r != nil
        }
        if let section, let item {
            switch key {
                case .leftArrow:
                    // Find the prev  item in the current section
                    if item > 0 {
                        nextIndex = IndexPath(item: item - 1, section: section)
                    } else {
                        // Go to prev item in the prev section
                        if section > 0 {
                            nextIndex = IndexPath(item: groupedPhotos[section-1].photos.count - 1, section: section - 1)
                        } else {
                            return nil
                        }
                    }
                case .rightArrow:
                    // Find the next  item in the current section
                    let photosInSection = groupedPhotos[section].photos
                    if photosInSection.count > item + 1 {
                        nextIndex = IndexPath(item: item + 1, section: section)
                    } else {
                        // Go to first item in the next section
                        if section + 1 < groupedPhotos.count {
                            nextIndex = IndexPath(item: 0, section: section + 1)
                        } else {
                            nextIndex = IndexPath(item: 0, section: 0)
                        }
                    }
                case .upArrow:
                    let columns = 3
                    let currentRow = item / columns
                    let currentCol = item % columns
                    if currentRow - 1 >= 0 {
                        nextIndex = indexInSection(section: section, row: currentRow - 1, col: currentCol)
                    } else {
                        // move to previous section, same column, LAST row
                        nextIndex = lastAvailable(fromSection: section - 1, col: currentCol, searchBackward: true)
                    }
                case .downArrow:
                    let columns = 3
                    let currentRow = item / columns
                    let currentCol = item % columns
                    let rowsInSection = (groupedPhotos[section].photos.count + columns - 1) / columns
                    if currentRow + 1 < rowsInSection {
                        // move down within section, clamp to last item in that row
                        nextIndex = indexInSection(section: section, row: currentRow + 1, col: currentCol)
                    } else {
                        // move to next section, same column, first row that has it
                        nextIndex = firstAvailable(fromSection: section + 1, col: currentCol, searchForward: true)
                    }
                default:
                    return nil
            }
        }
        if let nextIndex {
            let nextPhoto = groupedPhotos[nextIndex.section].photos[nextIndex.item]
            selectedPhotos = [nextPhoto]
            lastSelectedIndexPath = nextIndex
            return nextPhoto
        }
        return nil
    }

    private func indexPath(for photo: PhotoItem) -> IndexPath? {
        for (i, group) in groupedPhotos.enumerated() {
            let item = group.photos.firstIndex { $0.id == photo.id }
            if let item {
                return IndexPath(item: item, section: i)
            }
        }
        return nil
    }

    private func photos(from a: IndexPath, to b: IndexPath) -> [PhotoItem] {
        let start = min(a, b)
        let end = max(a, b)

        guard start.section >= 0, end.section < groupedPhotos.count else {
            return []
        }

        var result: [PhotoItem] = []

        for section in start.section...end.section {
            let photos = groupedPhotos[section].photos
            let firstItem = section == start.section ? start.item : 0
            let lastItem = section == end.section ? end.item : photos.count - 1

            guard firstItem >= 0, lastItem < photos.count, firstItem <= lastItem else {
                continue
            }

            for item in photos[firstItem...lastItem] where !selectedPhotos.contains(item) {
                result.append(item)
            }
        }

        return result
    }

    // Get IndexPath for a row/col in a section, clamping to last item if column doesn't exist in that row
    func indexInSection(section: Int, row: Int, col: Int) -> IndexPath? {
        let columns = 3
        let count = groupedPhotos[section].photos.count
        let candidate = row * columns + col
        let item = min(candidate, count - 1)  // clamp if row is short
        guard item >= 0 else {
            return nil
        }
        return IndexPath(item: item, section: section)
    }

    // Search forward through sections for the first row containing `col`
    func firstAvailable(fromSection: Int, col: Int, searchForward: Bool) -> IndexPath? {
        guard fromSection < groupedPhotos.count, fromSection >= 0 else {
            return nil
        }
        let count = groupedPhotos[fromSection].photos.count
        guard count > 0 else {
            return firstAvailable(fromSection: fromSection + 1, col: col, searchForward: true)
        }
        let item = min(col, count - 1)  // first row, same column (or last item if row is shorter)
        return IndexPath(item: item, section: fromSection)
    }

    // Search backward through sections for the LAST row containing `col`
    func lastAvailable(fromSection: Int, col: Int, searchBackward: Bool) -> IndexPath? {
        guard fromSection >= 0, fromSection < groupedPhotos.count else {
            return nil
        }
        let columns = 3
        let count = groupedPhotos[fromSection].photos.count
        guard count > 0 else {
            return lastAvailable(fromSection: fromSection - 1, col: col, searchBackward: true)
        }
        let lastRow = (count - 1) / columns
        let candidate = lastRow * columns + col
        let item = min(candidate, count - 1)  // clamp to last item if last row is short
        return IndexPath(item: item, section: fromSection)
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

    func quickCopy(photos: [PhotoItem]) {
        copyJob = PhotoCopySheetModel(photos: photos, isCopying: true)
        Task(priority: .userInitiated) {
            guard let copyJob else {
                return
            }
            await copyJob.startCopy()
            if copyJob.copyError == nil && !copyJob.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                self.copyJob = nil
            }
        }
    }

    func buildReviewGroupItem(groupIndex: Int) {
        guard let groups = duplicatesFinderModel.duplicateScanResult?.groups, groupIndex < groups.count else {
            fatalError()
        }
        let group = groups[groupIndex]
        let reviewGroupItem = ReviewGroupItem(
            group: group,
            index: groupIndex,
            totalGroups: groups.count,
            onRatingChanged: { [weak self] photo, rating in
                self?.applyRating(rating, to: [photo])
            },
            onApprove: { [weak self] photo in
                self?.applyLabel(.approved, to: [photo])
            },
            onMarkForDeletion: { [weak self] photo in
                self?.toggleRejectedState(for: [photo])
            },
            onNavigate: { [weak self] newIndex in
                guard newIndex >= 0, newIndex < groups.count else {
                    return
                }
                self?.buildReviewGroupItem(groupIndex: newIndex)
            }
        )
        onReviewSelected?(reviewGroupItem)
    }

    func buildReviewGroupItemFromPhotos(_ photos: [PhotoItem]) {
        let group = DuplicateGroup(photos: photos, distance: 0)
        let reviewGroupItem = ReviewGroupItem(
            group: group,
            index: 0,
            totalGroups: 1,
            onRatingChanged: { [weak self] photo, rating in
                self?.applyRating(rating, to: [photo])
            },
            onApprove: { [weak self] photo in
                self?.applyLabel(.approved, to: [photo])
            },
            onMarkForDeletion: { [weak self] photo in
                self?.toggleRejectedState(for: [photo])
            },
            onNavigate: { _ in }
        )
        onReviewSelected?(reviewGroupItem)
    }
}

extension ThumbGridViewModel: ThumbCellDelegate {

    func image(for photo: PhotoItem, completion: @escaping @Sendable (IRImage?) -> Void) -> Void {
        requestImage(for: photo, completion: completion)
    }

    func startCachingImages(for photos: [PhotoItem]) {
        cachingManager.startCachingImages(for: photos)
    }

    func stopCachingImages(for photos: [PhotoItem]) {
        cachingManager.stopCachingImages(for: photos)
    }

    func onTap(photo: PhotoItem, modifiers: NSEvent.ModifierFlags) {
        handlePhotoTap(photo: photo, modifiers: modifiers)
    }

    func onDoubleClick(photo: PhotoItem) {
        if selectedPhotos.contains(where: { $0.id == photo.id }) {
            // If we double click one of the selected photos, open all of them
            externalAppManager.openPhotos(selectedPhotos)
        } else {
            externalAppManager.openPhotos([photo])
        }
    }

    func onRatingChanged(photo: PhotoItem, rating: Int) {
        applyRating(rating, to: [photo])
    }

    func onLabelChanged(photo: PhotoItem, label: PhotoLabel?) {
        if let label {
            applyLabel(label, to: [photo])
        } else {
            removeLabels(from: [photo])
        }
    }

    func onMoveToTrash(photo: PhotoItem) {
        movePhotosToTrash([photo])
    }

    func onCopyTo(photo: PhotoItem) {
        let photos = selectedPhotos.contains(photo)
            ? selectedPhotos
            : [photo]
        copyJob = PhotoCopySheetModel(photos: photos)
    }

    func onQuickCopy(photo: PhotoItem) {
        let photos = selectedPhotos.contains(photo)
            ? selectedPhotos
            : [photo]
        quickCopy(photos: photos)
    }

    func onRenameTo(photo: PhotoItem) {
        let photos = selectedPhotos.contains(photo)
            ? selectedPhotos
            : [photo]
        renameJob = PhotosSheetItem(photos: photos)
    }

    func onMoveAllMarkedToTrash(photo: PhotoItem) {
        let marked = getPhotosMarkedForDeletion()
        movePhotosToTrash(marked)
    }

    func onApprove(photo: PhotoItem) {
        applyLabel(.approved, to: [photo])
    }

    func onReject(photo: PhotoItem) {
        toggleRejectedState(for: [photo])
    }

    func onReviewSelected(photo: PhotoItem) {
        let photos = selectedPhotos.contains(photo)
            ? selectedPhotos
            : [photo]
        buildReviewGroupItemFromPhotos(photos)
    }

    func onOpenWith(photo: PhotoItem, app: PhotoApp) {
        let photos = selectedPhotos.contains(photo)
            ? selectedPhotos
            : [photo]
        externalAppManager.openPhotos(photos, with: app)
    }

    func onCreateVideo(photos: [PhotoItem]) {
        // If the tapped photo is part of the current selection, use all selected
        let triggerPhoto = photos.first
        let isInSelection = triggerPhoto.map { selectedPhotos.contains($0) } ?? false
        guard isInSelection else {
            return
        }
//        appState.previewViewModel.showVideoEditor = true
    }

    func onCreatePDF(photos: [PhotoItem]) {
        let triggerPhoto = photos.first
        let isInSelection = triggerPhoto.map { selectedPhotos.contains($0) } ?? false
        guard isInSelection else {
            return
        }
//        appState.previewViewModel.showPDFEditor = true
    }

    func selectedPhotosCount() -> Int {
        selectedPhotos.count
    }

    func markedForDeletionCount() -> Int {
        getPhotosMarkedForDeletion().count
    }

    func discoveredPhotoApps() -> [PhotoApp] {
        externalAppManager.discoveredPhotoApps
    }
}
