import SwiftUI
import Photos
import ImageIO
import RCPreferences

@MainActor
class PreviewViewModel: ObservableObject {
    @Published private(set) var photo: PhotoItem?
    @Published private(set) var image: IRImage?
    @Published private(set) var fullResImage: IRImage?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingFullRes = false
    @Published private(set) var exifInfo: ExifInfo?
    @Published private(set) var alignToTopLeft: Bool = appPrefs.bool(.alignToTopLeft)

    private let previewsCacheManager: PhotoCacheManager
    private let fullResCacheManager: PhotoCacheManager

    private var loadingTask: Task<Void, Never>?
    private var fullResTask: Task<Void, Never>?

    init(previewsCacheManager: PhotoCacheManager, fullResCacheManager: PhotoCacheManager) {
        self.previewsCacheManager = previewsCacheManager
        self.fullResCacheManager = fullResCacheManager
    }

    func loadPhoto(_ photo: PhotoItem) {
        if self.photo?.path != photo.path {
            loadingTask?.cancel()
            loadingTask = nil
            fullResTask?.cancel()
            fullResTask = nil
            fullResImage = nil
            isLoadingFullRes = false
        }
        self.photo = photo

        isLoading = true
        image = nil
        exifInfo = nil

        loadingTask = Task(priority: .userInitiated) { [photo] in
            guard !Task.isCancelled else {
                return
            }

            image = await previewsCacheManager.getThumbnail(for: photo)
            isLoading = false

            let extractedExif = await photo.makeSource().loadExif()

            guard !Task.isCancelled else {
                return
            }
            exifInfo = extractedExif
        }
    }

    func toggleAlignment() {
        alignToTopLeft.toggle()
        appPrefs.set(alignToTopLeft, forKey: .alignToTopLeft)
    }

    func exitZoom() {
        fullResTask?.cancel()
        fullResTask = nil
        fullResImage = nil
        isLoadingFullRes = false
    }

    func loadFullResolution() {
        guard let photo else {
            return
        }
        guard fullResImage == nil && !isLoadingFullRes else {
            return
        }

        isLoadingFullRes = true

        fullResTask = Task {
            let image: IRImage? = await fullResCacheManager.getThumbnail(for: photo)
            guard !Task.isCancelled else {
                return
            }
            self.fullResImage = image
            self.isLoadingFullRes = false
        }
    }
}
