import SwiftUI
import ImageIO
import RCPreferences

@MainActor
class LargePreviewViewModel: ObservableObject {
    @Published var preview: NSImage?
    @Published var isLoading = false
    @Published var exifInfo: ExifInfo?
    @Published var alignToTopLeft: Bool = appPrefs.bool(.alignToTopLeft)

    private(set) var photo: PhotoItem?
    private var loadingTask: Task<Void, Never>?

    private static let cacheLimit = 10
    private static var imageCache: [String: (NSImage, ExifInfo?)] = [:]
    private static var cacheOrder: [String] = [] // Most recent at end

    func setPhoto(_ photo: PhotoItem) {
        // Cancel any in-flight load for the previous photo
        if self.photo?.path != photo.path {
            loadingTask?.cancel()
            loadingTask = nil
        }
        self.photo = photo
        loadPreview()
    }

    func toggleAlignment() {
        alignToTopLeft.toggle()
        appPrefs.set(alignToTopLeft, forKey: .alignToTopLeft)
    }

    private func loadPreview() {
        guard let photo = photo else { return }
        let path = photo.path
        // Check cache first
        if let (cachedImage, cachedExif) = Self.imageCache[path] {
            self.preview = cachedImage
            self.exifInfo = cachedExif
            self.isLoading = false
            // Move to most recent
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
            let (loadedImage, extractedExif) = await Self.loadImageWithExif(from: path)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.preview = loadedImage
                self.exifInfo = extractedExif
                self.isLoading = false
                if let img = loadedImage {
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

    private static func loadImageWithExif(from path: String) async -> (NSImage?, ExifInfo?) {
        let url = URL(fileURLWithPath: path)
        let fileExtension = url.pathExtension.lowercased()
        let rawExtensions = ["arw", "orf", "rw2", "cr2", "cr3", "crw", "nef", "nrw",
                             "srf", "sr2", "raw", "raf", "pef", "ptx", "dng", "3fr",
                             "fff", "iiq", "mef", "mos", "x3f", "srw", "dcr", "kdc",
                             "k25", "kc2", "mrw", "erf", "bay", "ndd", "sti", "rwl", "r3d"]
        if rawExtensions.contains(fileExtension) {
            guard let rawPhoto = RawWrapper.shared().extractRawPhoto(path) else {
                return (nil, nil)
            }
            let exifInfo: ExifInfo? = if let rawExif = rawPhoto.exifData as? [String: Any] {
                ExifInfo.from(rawExif: rawExif)
            } else {
                nil
            }
            guard let imageData = rawPhoto.imageData else {
                return (nil, exifInfo)
            }
            return (NSImage(data: imageData), exifInfo)
        } else {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                return (NSImage(contentsOfFile: path), nil)
            }
            let nsImage = NSImage(contentsOfFile: path)
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                return (nsImage, ExifInfo.from(imageProperties: properties))
            }
            return (nsImage, nil)
        }
    }
}
