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

    private(set) var photo: PhotoItem?
    private var loadingTask: Task<Void, Never>?
    private var fullResTask: Task<Void, Never>?

    private static let cacheLimit = 10
    private static var imageCache: [String: (IRImage, ExifInfo?)] = [:]
    private static var cacheOrder: [String] = [] // Most recent at end

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
        guard let photo = photo else { return }
        let path = photo.path
        let currentPhoto = photo

        if let (cachedImage, cachedExif) = Self.imageCache[path] {
            self.preview = cachedImage
            self.exifInfo = cachedExif
            self.isLoading = false
            if let idx = Self.cacheOrder.firstIndex(of: path) {
                Self.cacheOrder.remove(at: idx)
                Self.cacheOrder.append(path)
            }
            return
        }

        preview = nil
        isLoading = true
        exifInfo = nil

        loadingTask = Task(priority: .userInitiated) { [path, currentPhoto] in
            let previewImage: IRImage? = await withCheckedContinuation { continuation in
                PreviewsManager.shared.loadPreview(for: currentPhoto) { image, _ in
                    continuation.resume(returning: image)
                }
            }

            guard !Task.isCancelled else { return }

            self.preview = previewImage
            self.isLoading = false

            let extractedExif = await currentPhoto.makeSource().loadExif()

            guard !Task.isCancelled else { return }
            self.exifInfo = extractedExif

            if let img = previewImage {
                Self.imageCache[path] = (img, extractedExif)
                if let idx = Self.cacheOrder.firstIndex(of: path) {
                    Self.cacheOrder.remove(at: idx)
                }
                Self.cacheOrder.append(path)
                while Self.cacheOrder.count > Self.cacheLimit {
                    let oldest = Self.cacheOrder.removeFirst()
                    Self.imageCache.removeValue(forKey: oldest)
                }
            }
        }
    }
}
