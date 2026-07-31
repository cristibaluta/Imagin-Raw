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

    let previewsCacheManager: PhotoCacheManager
    private let fullResCacheManager: PhotoCacheManager

    private var loadingTask: Task<Void, Never>?
    private var fullResTask: Task<Void, Never>?

    init(previewsCacheManager: PhotoCacheManager, fullResCacheManager: PhotoCacheManager) {
        self.previewsCacheManager = previewsCacheManager
        self.fullResCacheManager = fullResCacheManager
    }

    func loadPhotos(_ photos: [PhotoItem]) {
        self.photos = photos
        isLoading = true

        loadingTask?.cancel()
        loadingTask = Task(priority: .userInitiated) { [photos] in
            guard !Task.isCancelled else {
                return
            }
            // Load max 2 photos
            let images: [IRImage]?
            if photos.count > 1 {
                if let image1 = await previewsCacheManager.getImage(for: photos.first!),
                   let image2 = await previewsCacheManager.getImage(for: photos.last!) {
                    images = [image1, image2]
                } else {
                    images = nil
                }
            }
            else if let photo = photos.first {
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
        images = nil
        fullResImage = nil
        isLoading = false
        isLoadingFullRes = false
    }
}
