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
        isLoadingFullRes = true
        print("🔎 [zoom] starting full-res load: \(URL(fileURLWithPath: path).lastPathComponent)")
        let t0 = Date()

        fullResTask = Task {
            let image = await Self.decodeFullResolution(from: path, t0: t0)
            guard !Task.isCancelled else {
                print("🔎 [zoom] cancelled")
                return
            }
            print("🔎 [zoom] image ready, assigning to view  +\(String(format: "%.3f", -t0.timeIntervalSinceNow))s")
            self.fullResImage = image
            self.isLoadingFullRes = false
            print("🔎 [zoom] done  +\(String(format: "%.3f", -t0.timeIntervalSinceNow))s")
        }
    }

    private static func decodeFullResolution(from path: String, t0: Date) async -> NSImage? {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        print("🔎 [zoom] decodeFullResolution start  +\(String(format: "%.3f", -t0.timeIntervalSinceNow))s")

        if FilesExtensions.raw.contains(ext) {
            let image: NSImage? = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    print("🔎 [zoom] calling RawWrapper  +\(String(format: "%.3f", -t0.timeIntervalSinceNow))s")
                    let img = RawWrapper.shared().extractFullResolution(path)
                    print("🔎 [zoom] RawWrapper returned \(img != nil ? "image" : "nil")  +\(String(format: "%.3f", -t0.timeIntervalSinceNow))s")
                    continuation.resume(returning: img)
                }
            }
            return image
        } else {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImg = CGImageSourceCreateImageAtIndex(src, 0, [
                      kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else {
                print("🔎 [zoom] CGImageSource failed")
                return nil
            }
            print("🔎 [zoom] non-RAW CGImage ready  +\(String(format: "%.3f", -t0.timeIntervalSinceNow))s")
            return NSImage(cgImage: cgImg, size: .zero)
        }
    }

    private func loadPreview() {
        guard let photo = photo else { return }
        let path = photo.path

        // Check memory cache first (instant)
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

        loadingTask = Task(priority: .userInitiated) { [path] in
            // Load EXIF in parallel with the preview
            async let exifTask = Self.loadExifOnly(from: path)

            // Ask PreviewsManager — it checks its own disk cache first,
            // generates a 1024px JPEG if missing, then returns
            let previewImage: NSImage? = await withCheckedContinuation { continuation in
                PreviewsManager.shared.loadPreview(for: path) { image, _ in
                    continuation.resume(returning: image)
                }
            }

            let extractedExif = await exifTask

            guard !Task.isCancelled else { return }

            self.preview = previewImage
            self.exifInfo = extractedExif
            self.isLoading = false

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
