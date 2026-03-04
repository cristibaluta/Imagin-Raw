import SwiftUI
import ImageIO

class LargePreviewViewModel: ObservableObject {
    @Published var preview: NSImage?
    @Published var isLoading = false
    @Published var exifData: [String: Any]?
    @Published var alignToTopLeft: Bool = UserDefaults.standard.bool(forKey: "ImageAlignmentTopLeft")
    
    private(set) var photo: PhotoItem?

    func setPhoto(_ photo: PhotoItem) {
        self.photo = photo
        loadPreview()
    }

    func toggleAlignment() {
        alignToTopLeft.toggle()
        UserDefaults.standard.set(alignToTopLeft, forKey: "ImageAlignmentTopLeft")
    }

    private func loadPreview() {
        guard let photo = photo, preview == nil else { return }
        isLoading = true
        exifData = nil
        Task.detached(priority: .userInitiated) { [weak self] in
            let (loadedImage, extractedExifData) = await Self.loadImageWithExif(from: photo.path)
            await MainActor.run {
                self?.preview = loadedImage
                self?.exifData = extractedExifData
                self?.isLoading = false
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
