import SwiftUI
import Photos
import ImageIO
import RCPreferences

@MainActor
class PreviewViewModel: ObservableObject {

    @Published private(set) var photos: [PhotoItem]?
    @Published private(set) var images: [IRImage]?
    @Published private(set) var fullResImage: IRImage?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingFullRes = false
    @Published private(set) var alignToTopLeft: Bool = appPrefs.bool(.alignToTopLeft)
    @Published private(set) var exifIsExpanded: Bool = appPrefs.bool(.exifExpanded)
    @Published var showVideoEditor: Bool = false
    @Published var showPDFEditor: Bool = false
    @Published var exportJob: ExportJPEGJob? = nil
    @Published private(set) var isMultiZoomed = false
    @Published private(set) var isLoadingMultiFullRes = false
    /// Full resolution images of the displayed photos while zoomed, keyed by photo path
    @Published private(set) var multiFullRes: [String: IRImage] = [:]

    /// Called to enter review mode with the given photos. Set by AppState.
    var onReview: (([PhotoItem]) -> Void)?
    /// Called to move to the next (+1) / previous (-1) page of photos. Set by AppState.
    var onPageChange: ((Int) -> Void)?
    /// Photo currently under the mouse in the grid, nil when none. Key shortcuts target it.
    var hoveredPhoto: PhotoItem?
    /// Per-photo actions triggered from the hover overlay. Set by AppState.
    var onRatingChanged: ((PhotoItem, Int) -> Void)?
    var onApprove: ((PhotoItem) -> Void)?
    var onReject: ((PhotoItem) -> Void)?

    /// Picks up rating/label/state changes of the displayed photos from the latest `allPhotos`.
    func refreshMetadata(from allPhotos: [PhotoItem]) {
        guard let photos, !photos.isEmpty else {
            return
        }
        let ids = Set(photos.map(\.id))
        var latest: [UUID: PhotoItem] = [:]
        for p in allPhotos where ids.contains(p.id) {
            latest[p.id] = p
        }
        let updated = photos.map { latest[$0.id] ?? $0 }
        if updated != photos {
            self.photos = updated
        }
    }
    /// Page of the displayed photos, nil when unknown.
    @Published var pageInfo: PageInfo?

    func startReview() {
        guard let photos, photos.count > 1 else {
            return
        }
        onReview?(photos)
    }

    let previewsCacheManager: PhotoCacheManager
    private let fullResCacheManager: PhotoCacheManager

    private var loadingTask: Task<Void, Never>?
    private var fullResTask: Task<Void, Never>?
    private var multiFullResTask: Task<Void, Never>?

    init(previewsCacheManager: PhotoCacheManager, fullResCacheManager: PhotoCacheManager) {
        self.previewsCacheManager = previewsCacheManager
        self.fullResCacheManager = fullResCacheManager
    }

    func loadPhotos(_ photos: [PhotoItem]) {
        self.photos = photos
        loadingTask?.cancel()

        // Multiple photos are loaded by the grid cells themselves
        guard photos.count <= 1 else {
            images = nil
            isLoading = false
            if isMultiZoomed {
                loadMultiFullRes()
            }
            return
        }
        exitMultiZoom()
        isLoading = true

        loadingTask = Task(priority: .userInitiated) { [photos] in
            guard !Task.isCancelled else {
                return
            }
            let images: [IRImage]?
            if let photo = photos.first {
                if let image1 = await previewsCacheManager.getImage(for: photo) {
                    images = [image1]
                } else {
                    images = nil
                }
            }
            else {
                images = nil
            }

            guard !Task.isCancelled else {
                return
            }
            self.images = images
            isLoading = false
        }
    }

    func toggleAlignment() {
        alignToTopLeft.toggle()
        appPrefs.set(alignToTopLeft, forKey: .alignToTopLeft)
    }

    func toggleExifExpanded() {
        exifIsExpanded.toggle()
        appPrefs.set(exifIsExpanded, forKey: .exifExpanded)
    }

    // MARK: - Zoom for multiple photos (synced pan, see MacFitGridView)

    func toggleMultiZoom() {
        guard (photos?.count ?? 0) > 1 else {
            return
        }
        if isMultiZoomed {
            exitMultiZoom()
        } else {
            isMultiZoomed = true
            loadMultiFullRes()
        }
    }

    func exitMultiZoom() {
        multiFullResTask?.cancel()
        multiFullResTask = nil
        isMultiZoomed = false
        isLoadingMultiFullRes = false
        multiFullRes = [:]
    }

    /// Loads the full resolution of the displayed photos one by one, dropping the ones no longer displayed.
    private func loadMultiFullRes() {
        multiFullResTask?.cancel()
        let photos = self.photos ?? []
        let wanted = Set(photos.map(\.path))
        multiFullRes = multiFullRes.filter { wanted.contains($0.key) }
        let missing = photos.filter { multiFullRes[$0.path] == nil }
        guard !missing.isEmpty else {
            isLoadingMultiFullRes = false
            return
        }
        isLoadingMultiFullRes = true
        multiFullResTask = Task {
            for photo in missing {
                let image = await fullResCacheManager.getImage(for: photo)
                guard !Task.isCancelled else {
                    return
                }
                if let image {
                    multiFullRes[photo.path] = image
                }
            }
            isLoadingMultiFullRes = false
        }
    }

    func exitZoom() {
        fullResTask?.cancel()
        fullResTask = nil
        fullResImage = nil
        isLoadingFullRes = false
    }

    func loadFullResolution() {
        guard let photo = photos?.first else {
            return
        }
        guard fullResImage == nil && !isLoadingFullRes else {
            return
        }

        isLoadingFullRes = true

        fullResTask = Task {
            let image = await fullResCacheManager.getImage(for: photo)
            guard !Task.isCancelled else {
                return
            }
            self.fullResImage = image
            self.isLoadingFullRes = false
        }
    }

    /// Shows the PDF editor, closing the video editor if it is open.
    func openPDFEditor() {
        showVideoEditor = false
        showPDFEditor = true
    }

    /// Shows the video editor, closing the PDF editor if it is open.
    func openVideoEditor() {
        showPDFEditor = false
        showVideoEditor = true
    }

    var hasRawPhotos: Bool {
        photos?.contains(where: { $0.isRaw }) ?? false
    }

    func exportEmbeddedJPEGs() {
        #if os(macOS)
        guard exportJob == nil else {
            return
        }
        let paths = (photos ?? []).filter { $0.isRaw }.map { $0.url.path(percentEncoded: false) }
        guard let job = ExportJPEGJob.promptAndCreate(paths: paths, onFinished: { [weak self] in
            self?.exportJob = nil
        }) else {
            return
        }
        exportJob = job
        job.start()
        #endif
    }

    func reset() {
        hoveredPhoto = nil
        exitMultiZoom()
        photos = nil
        loadingTask?.cancel()
        loadingTask = nil
        fullResTask?.cancel()
        fullResTask = nil
        images = nil
        fullResImage = nil
        isLoading = false
        isLoadingFullRes = false
    }
}
