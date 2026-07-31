import SwiftUI
import Photos
import ImageIO
import RCPreferences

@MainActor
class PreviewViewModel: ObservableObject {

    @Published private(set) var photos: [PhotoItem]?
    @Published private(set) var image: IRImage?
    @Published private(set) var fullResImage: IRImage?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingFullRes = false
    @Published private(set) var alignToTopLeft: Bool = appPrefs.bool(.alignToTopLeft)
    @Published private(set) var exifIsExpanded: Bool = appPrefs.bool(.exifExpanded)

    let previewsCacheManager: PhotoCacheManager
    private let fullResCacheManager: PhotoCacheManager

    private var loadingTask: Task<Void, Never>?
    private var fullResTask: Task<Void, Never>?

    init(previewsCacheManager: PhotoCacheManager, fullResCacheManager: PhotoCacheManager) {
        self.previewsCacheManager = previewsCacheManager
        self.fullResCacheManager = fullResCacheManager
    }

    func loadPhotos(_ photos: [PhotoItem]) {
        guard photos.first?.path != self.photos?.first?.path else {
            return
        }
        self.photos = photos
        isLoading = true

        loadingTask?.cancel()
        loadingTask = Task(priority: .userInitiated) { [photos] in
            guard !Task.isCancelled else {
                return
            }
            let image = await previewsCacheManager.getImage(for: photos.first!)
            guard !Task.isCancelled else {
                return
            }
            self.image = image
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

    func reset() {
        photos = nil
        loadingTask?.cancel()
        loadingTask = nil
        fullResTask?.cancel()
        fullResTask = nil
        image = nil
        fullResImage = nil
        isLoading = false
        isLoadingFullRes = false
    }
}
