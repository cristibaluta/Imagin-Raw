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

    let previewsCacheManager: PhotoCacheManager
    private let fullResCacheManager: PhotoCacheManager

    private var loadingTask: Task<Void, Never>?
    private var fullResTask: Task<Void, Never>?

    init(previewsCacheManager: PhotoCacheManager, fullResCacheManager: PhotoCacheManager) {
        self.previewsCacheManager = previewsCacheManager
        self.fullResCacheManager = fullResCacheManager
    }

    func loadPhoto(_ photo: PhotoItem) {
        guard photo.path != self.photo?.path else {
            RCLog("Photo already loaded \(photo.path)")
            return
        }
        reset()
        self.photo = photo
        isLoading = true

        loadingTask = Task(priority: .userInitiated) { [photo] in

            let image = await previewsCacheManager.getImage(for: photo)
            guard !Task.isCancelled else {
                return
            }
            self.image = image
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
            let image = await fullResCacheManager.getImage(for: photo)
            guard !Task.isCancelled else {
                return
            }
            self.fullResImage = image
            self.isLoadingFullRes = false
        }
    }

    func reset() {
        photo = nil
        loadingTask?.cancel()
        loadingTask = nil
        fullResTask?.cancel()
        fullResTask = nil
        image = nil
        fullResImage = nil
        isLoading = false
        isLoadingFullRes = false
        exifInfo = nil
    }
}
