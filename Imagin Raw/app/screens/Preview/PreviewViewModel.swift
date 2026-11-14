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
    /// Zoom level of the single photo zoom, 1 = 100%. Kept while moving between photos.
    @Published var zoomScale: CGFloat = 1
    /// Center of the largest face in the zoomed photo (normalized, origin top-left), nil when none.
    @Published private(set) var faceCenter: CGPoint?
    /// While `fullResImage` is a stand-in (the small preview shown zoomed until the full
    /// resolution loads), the full resolution pixel size it should be drawn at. nil otherwise.
    @Published private(set) var zoomPixelSize: CGSize?
    /// Long side in pixels of the last full resolution image, to size the next stand-in the same way.
    private var lastFullResLongSide: CGFloat?
    /// True while zoomed in (or loading the zoom) on a single photo.
    var isSingleZoomActive: Bool { fullResImage != nil || isLoadingFullRes }
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
    /// Removes a photo from the preview (deselects it) keeping the page size. Set by AppState.
    var onRemove: ((PhotoItem) -> Void)?

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
    private var loadedSinglePhotoID: UUID?
    private var fullResTask: Task<Void, Never>?
    private var multiFullResTask: Task<Void, Never>?

    init(previewsCacheManager: PhotoCacheManager, fullResCacheManager: PhotoCacheManager) {
        self.previewsCacheManager = previewsCacheManager
        self.fullResCacheManager = fullResCacheManager
    }

    func loadPhotos(_ photos: [PhotoItem]) {
        // Nothing selected (e.g. the last photo was moved to trash): show the empty state
        guard !photos.isEmpty else {
            reset()
            return
        }
        self.photos = photos
        loadingTask?.cancel()

        // Multiple photos are loaded by the grid cells themselves
        guard photos.count <= 1 else {
            images = nil
            isLoading = false
            exitZoom()
            loadedSinglePhotoID = nil
            if isMultiZoomed {
                loadMultiFullRes()
            }
            return
        }
        exitMultiZoom()

        // Stay zoomed when moving to another photo; the new photo's full resolution is loaded below
        let isSamePhoto = photos.first?.id == loadedSinglePhotoID
        let stayZoomed = isSingleZoomActive
        loadedSinglePhotoID = photos.first?.id
        if !isSamePhoto {
            if stayZoomed, let photo = photos.first {
                // Keep the current zoomed image on screen until the new one is ready (no flash)
                startZoomLoad(for: photo)
            } else {
                fullResTask?.cancel()
                fullResTask = nil
                fullResImage = nil
                zoomPixelSize = nil
                faceCenter = nil
                isLoadingFullRes = false
            }
        }
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
        zoomPixelSize = nil
        faceCenter = nil
        isLoadingFullRes = false
        zoomScale = 1
    }

    /// Zooms the single photo in, or out when already zoomed (or loading the zoom).
    func toggleZoom() {
        if isSingleZoomActive {
            exitZoom()
        } else {
            loadFullResolution()
        }
    }

    func loadFullResolution() {
        guard let photo = photos?.first else {
            return
        }
        guard fullResImage == nil && !isLoadingFullRes else {
            return
        }
        startZoomLoad(for: photo)
    }

    /// Zooms into `photo`: first shows its small preview drawn at full size (instant),
    /// then swaps in the full resolution when it has loaded.
    private func startZoomLoad(for photo: PhotoItem) {
        fullResTask?.cancel()
        isLoadingFullRes = true

        let findFace = appPrefs.bool(.zoomToFace)
        fullResTask = Task {
            // 1. Preview: find the face on it and show it as a stand-in
            var face: CGPoint?
            if let preview = await previewsCacheManager.getImage(for: photo) {
                guard !Task.isCancelled else {
                    return
                }
                let cg = preview.cgImage(forProposedRect: nil, context: nil, hints: nil)
                if findFace, let cg {
                    nonisolated(unsafe) let image = cg
                    face = await Task.detached(priority: .userInitiated) {
                        FaceFinder.largestFaceCenter(in: image)
                    }.value
                    guard !Task.isCancelled else {
                        return
                    }
                }
                if let cg, let size = standInPixelSize(for: photo, previewWidth: CGFloat(cg.width),
                                                       previewHeight: CGFloat(cg.height)) {
                    self.faceCenter = face
                    self.zoomPixelSize = size
                    self.fullResImage = preview
                }
            }

            // 2. Full resolution
            let image = await fullResCacheManager.getImage(for: photo)
            guard !Task.isCancelled else {
                return
            }
            if let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                self.lastFullResLongSide = CGFloat(max(cg.width, cg.height))
            }
            self.faceCenter = face
            self.zoomPixelSize = nil
            self.fullResImage = image
            self.isLoadingFullRes = false
        }
    }

    /// Size to draw the preview at so it lines up with the full resolution image that will replace it.
    private func standInPixelSize(for photo: PhotoItem, previewWidth: CGFloat, previewHeight: CGFloat) -> CGSize? {
        guard previewWidth > 0, previewHeight > 0 else {
            return nil
        }
        let exifLongSide = photo.exif.flatMap { exif -> CGFloat? in
            guard let w = exif.width, let h = exif.height, w > 0, h > 0 else {
                return nil
            }
            return CGFloat(max(w, h))
        }
        guard let longSide = lastFullResLongSide ?? exifLongSide else {
            return nil
        }
        let scale = longSide / max(previewWidth, previewHeight)
        return CGSize(width: previewWidth * scale, height: previewHeight * scale)
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
        zoomPixelSize = nil
        faceCenter = nil
        loadedSinglePhotoID = nil
        isLoading = false
        isLoadingFullRes = false
    }
}
