import SwiftUI
import Photos
import ImageIO
import RCPreferences

@MainActor
class PreviewViewModel: ObservableObject {
    @Published var preview: IRImage?
    @Published var isLoading = false
    @Published var exifInfo: ExifInfo?
    @Published var alignToTopLeft: Bool = appPrefs.bool(.alignToTopLeft)
    @Published var fullResImage: IRImage? = nil
    @Published var isLoadingFullRes = false

    private let previewsCacheManager: PhotoCacheManager
    private(set) var photo: PhotoItem?
    private var loadingTask: Task<Void, Never>?
    private var fullResTask: Task<Void, Never>?

    init(previewsCacheManager: PhotoCacheManager) {
        self.previewsCacheManager = previewsCacheManager
    }

    func setPhoto(_ photo: PhotoItem) {
        if self.photo?.path != photo.path {
            loadingTask?.cancel()
            loadingTask = nil
            fullResTask?.cancel()
            fullResTask = nil
            fullResImage = nil
            isLoadingFullRes = false
        }
        self.photo = photo
        loadPreview()
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
        guard let photo = photo else { return }
        guard !isLoadingFullRes && fullResImage == nil else { return }
        let currentPhoto = photo

        if let cached = FullResManager.shared.cachedImage(for: currentPhoto) {
            self.fullResImage = cached
            return
        }

        isLoadingFullRes = true

        fullResTask = Task {
            let image: IRImage? = await withCheckedContinuation { continuation in
                FullResManager.shared.loadFullRes(for: currentPhoto) { img in
                    continuation.resume(returning: img)
                }
            }
            guard !Task.isCancelled else { return }
            self.fullResImage = image
            self.isLoadingFullRes = false
        }
    }

    private func loadPreview() {
        guard let photo else {
            return
        }

        isLoading = true
        preview = nil
        exifInfo = nil

        loadingTask = Task(priority: .userInitiated) { [photo] in

            let previewImage: IRImage? = await previewsCacheManager.getThumbnail(for: photo)

            guard !Task.isCancelled else {
                return
            }
            self.preview = previewImage
            self.isLoading = false

            let extractedExif = await photo.makeSource().loadExif()

            guard !Task.isCancelled else {
                return
            }
            self.exifInfo = extractedExif
        }
    }
}
