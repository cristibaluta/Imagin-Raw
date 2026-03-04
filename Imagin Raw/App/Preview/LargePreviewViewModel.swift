import SwiftUI
import ImageIO
import RCPreferences

class LargePreviewViewModel: ObservableObject {
    @Published var preview: NSImage?
    @Published var isLoading = false
    @Published var exifData: [String: Any]?
    @Published var alignToTopLeft: Bool = appPrefs.bool(.alignToTopLeft)

    private(set) var photo: PhotoItem?

    private static let cacheLimit = 10
    private static var imageCache: [String: (NSImage, [String: Any]?)] = [:]
    private static var cacheOrder: [String] = [] // Most recent at end

    func setPhoto(_ photo: PhotoItem) {
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
            self.exifData = cachedExif
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
        exifData = nil
        Task(priority: .userInitiated) { [weak self, path] in
            let (loadedImage, extractedExifData) = await Self.loadImageWithExif(from: path)
            await MainActor.run {
                self?.preview = loadedImage
                self?.exifData = extractedExifData
                self?.isLoading = false
                // Store in cache if loaded
                if let img = loadedImage {
                    Self.imageCache[path] = (img, extractedExifData)
                    if let idx = Self.cacheOrder.firstIndex(of: path) {
                        Self.cacheOrder.remove(at: idx)
                    }
                    Self.cacheOrder.append(path)
                    // Enforce cache limit
                    while Self.cacheOrder.count > Self.cacheLimit {
                        let oldest = Self.cacheOrder.removeFirst()
                        Self.imageCache.removeValue(forKey: oldest)
                    }
                }
            }
        }
    }

    private static func loadImageWithExif(from path: String) async -> (NSImage?, [String: Any]?) {
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
            let metadata = RawWrapper.shared().extractMetadata(path)
            let _ = metadata?["rating"] as? NSNumber
            var exifInfo: [String: Any]? = nil
            if let exifData = rawPhoto.exifData {
                exifInfo = exifData as? [String: Any]
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
                var exifDict: [String: Any] = [:]
                if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                    if let aperture = exif[kCGImagePropertyExifFNumber] as? NSNumber {
                        exifDict["Aperture"] = aperture
                    }
                    if let shutter = exif[kCGImagePropertyExifExposureTime] as? NSNumber {
                        exifDict["ShutterSpeed"] = shutter
                    }
                    if let iso = exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber], let isoVal = iso.first {
                        exifDict["ISO"] = isoVal
                    }
                    if let focal = exif[kCGImagePropertyExifFocalLength] as? NSNumber {
                        exifDict["FocalLength"] = focal
                    }
                }
                if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                    if let make = tiff[kCGImagePropertyTIFFMake] as? String {
                        exifDict["Make"] = make
                    }
                    if let model = tiff[kCGImagePropertyTIFFModel] as? String {
                        exifDict["Model"] = model
                    }
                }
                return (nsImage, exifDict)
            }
            return (nsImage, nil)
        }
    }
}

