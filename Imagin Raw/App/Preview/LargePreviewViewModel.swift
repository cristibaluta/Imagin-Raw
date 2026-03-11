import SwiftUI
import ImageIO
import RCPreferences

@MainActor
class LargePreviewViewModel: ObservableObject {
    @Published var preview: NSImage?
    @Published var isLoading = false
    @Published var exifInfo: ExifInfo?
    @Published var alignToTopLeft: Bool = appPrefs.bool(.alignToTopLeft)
    @Published var fullResImage: NSImage? = nil
    @Published var isLoadingFullRes = false

    private(set) var photo: PhotoItem?
    private var loadingTask: Task<Void, Never>?
    private var fullResTask: Task<Void, Never>?

    private static let cacheLimit = 10
    private static var imageCache: [String: (NSImage, ExifInfo?)] = [:]
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
        let path = photo.path

        // Check memory cache first — instant if recently viewed
        if let cached = FullResManager.shared.cachedImage(for: path) {
            print("🔎 [zoom] cache hit \(URL(fileURLWithPath: path).lastPathComponent)")
            self.fullResImage = cached
            return
        }

        isLoadingFullRes = true
        print("🔎 [zoom] starting full-res load: \(URL(fileURLWithPath: path).lastPathComponent)")
        let t0 = Date()

        fullResTask = Task {
            let image: NSImage? = await withCheckedContinuation { continuation in
                FullResManager.shared.loadFullRes(for: path) { img in
                    continuation.resume(returning: img)
                }
            }
            guard !Task.isCancelled else {
                print("🔎 [zoom] cancelled")
                return
            }
            print("🔎 [zoom] done  +\(String(format: "%.3f", -t0.timeIntervalSinceNow))s")
            self.fullResImage = image
            self.isLoadingFullRes = false
        }
    }

    private func loadPreview() {
        guard let photo = photo else { return }
        let path = photo.path
        let t0 = Date()
        let filename = URL(fileURLWithPath: path).lastPathComponent
        print("🖼 [preview] start \(filename)")

        if let (cachedImage, cachedExif) = Self.imageCache[path] {
            print("🖼 [preview] memory cache hit \(filename)")
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

        loadingTask = Task(priority: .userInitiated) { [path] in
            print("🖼 [preview] task start  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s")

            // Step 1: get preview image from PreviewsManager
            let previewImage: NSImage? = await withCheckedContinuation { continuation in
                PreviewsManager.shared.loadPreview(for: path) { image, _ in
                    print("🖼 [preview] PreviewsManager callback  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s  image=\(image != nil)")
                    continuation.resume(returning: image)
                }
            }
            print("🖼 [preview] image ready  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s")

            guard !Task.isCancelled else { return }

            // Show image immediately — don't wait for EXIF
            self.preview = previewImage
            self.isLoading = false
            print("🖼 [preview] assigned to view  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s")

            // Step 2: load EXIF separately after image is visible
            let extractedExif = await Self.loadExifOnly(from: path)
            print("🖼 [preview] exif ready  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s")

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
            print("🖼 [preview] done  +\(String(format:"%.3f",-t0.timeIntervalSinceNow))s")
        }
    }

    /// Load EXIF metadata only — no image decoding
    private static func loadExifOnly(from path: String) async -> ExifInfo? {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        if FilesExtensions.raw.contains(ext) {
            guard let rawPhoto = RawWrapper.shared().extractRawPhoto(path),
                  let rawExif = rawPhoto.exifData as? [String: Any] else { return nil }
            return ExifInfo.from(rawExif: rawExif)
        } else {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return nil }
            return ExifInfo.from(imageProperties: props)
        }
    }
}
