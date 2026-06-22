//
//  CopyToViewModel.swift
//  Imagin Raw
//

import Foundation

class CopyToViewModel: ObservableObject, Identifiable, @unchecked Sendable {
    let id = UUID()

    // MARK: - Photos
    let photos: [PhotoItem]

    // MARK: - Destination
    @Published var destinationURL: URL?
    @Published var backupDestinationURL: URL?

    // MARK: - Filename options
    @Published var renameByExifDate: Bool
    @Published var useSequentialNumbers: Bool
    @Published var customPrefix: String

    // MARK: - Folder organisation options
    @Published var organizeByYear: Bool
    @Published var organizeByMonth: Bool
    @Published var organizeByDay: Bool
    @Published var eventName: String
    @Published var organizeByCameraModel: Bool
    @Published var organizeJpgsInSubfolder: Bool

    // MARK: - Progress state (observed by CopyProgressView)
    @Published var copyProgress: Double = 0.0
    @Published var currentFile: String = ""
    @Published var copiedCount: Int = 0
    @Published var totalCount: Int = 0
    @Published var copyError: String?

    private(set) var isCancelled: Bool = false
//    private var copyTask: Task<Void, Never>?

    init(photos: [PhotoItem]) {
        self.photos = photos
        renameByExifDate        = appPrefs.bool(.copyToRenameByExifDate)
        useSequentialNumbers    = appPrefs.bool(.copyToUseSequentialNumbers)
        customPrefix            = appPrefs.string(.copyToCustomPrefix)
        organizeByYear          = appPrefs.bool(.copyToOrganizeByYear)
        organizeByMonth         = appPrefs.bool(.copyToOrganizeByMonth)
        organizeByDay           = appPrefs.bool(.copyToOrganizeByDay)
        eventName               = appPrefs.string(.copyToEventName)
        organizeByCameraModel   = appPrefs.bool(.copyToOrganizeByCameraModel)
        organizeJpgsInSubfolder = appPrefs.bool(.copyToOrganizeJpgsInSubfolder)

        if let data = UserDefaults.standard.data(forKey: AppPreference.copyToDestinationBookmark.rawValue),
           let url = Self.urlFromBookmark(data) {
            destinationURL = url
        }
        if let data = UserDefaults.standard.data(forKey: AppPreference.copyToBackupBookmark.rawValue),
           let url = Self.urlFromBookmark(data) {
            backupDestinationURL = url
        }
    }

    // MARK: - Persistence

    func saveSettings() {
        appPrefs.set(renameByExifDate,        forKey: .copyToRenameByExifDate)
        appPrefs.set(useSequentialNumbers,    forKey: .copyToUseSequentialNumbers)
        appPrefs.set(customPrefix,            forKey: .copyToCustomPrefix)
        appPrefs.set(organizeByYear,          forKey: .copyToOrganizeByYear)
        appPrefs.set(organizeByMonth,         forKey: .copyToOrganizeByMonth)
        appPrefs.set(organizeByDay,           forKey: .copyToOrganizeByDay)
        appPrefs.set(eventName,               forKey: .copyToEventName)
        appPrefs.set(organizeByCameraModel,   forKey: .copyToOrganizeByCameraModel)
        appPrefs.set(organizeJpgsInSubfolder, forKey: .copyToOrganizeJpgsInSubfolder)

        if let url = destinationURL {
            if let data = Self.bookmarkFromURL(url) {
                UserDefaults.standard.set(data, forKey: AppPreference.copyToDestinationBookmark.rawValue)
            }
            appPrefs.set(url.absoluteString, forKey: .copyToLastDestinationURL)
        }
        if let url = backupDestinationURL {
            if let data = Self.bookmarkFromURL(url) {
                UserDefaults.standard.set(data, forKey: AppPreference.copyToBackupBookmark.rawValue)
            }
            appPrefs.set(url.absoluteString, forKey: .copyToLastBackupDestinationURL)
        } else {
            UserDefaults.standard.removeObject(forKey: AppPreference.copyToLastBackupDestinationURL.rawValue)
            UserDefaults.standard.removeObject(forKey: AppPreference.copyToBackupBookmark.rawValue)
        }
    }

    func stopAccessingSecurityScopedResources() {
        destinationURL?.stopAccessingSecurityScopedResource()
        backupDestinationURL?.stopAccessingSecurityScopedResource()
    }

    // MARK: - Filename helpers

    private func computeSequentialStartOffset(in folder: URL?, prefix: String) -> Int {
        guard let folder else {
            return 0
        }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )) ?? []
        let prefixPattern = prefix.isEmpty ? "" : NSRegularExpression.escapedPattern(for: prefix)
        let pattern = try? NSRegularExpression(pattern: "^\(prefixPattern)(\\d{4})\\.")
        var highest = 0
        for file in files {
            let name = file.lastPathComponent
            let range = NSRange(name.startIndex..., in: name)
            if let match = pattern?.firstMatch(in: name, range: range),
               let numRange = Range(match.range(at: 1), in: name),
               let number = Int(name[numRange]) {
                highest = max(highest, number)
            }
        }
        return highest
    }

    private func buildDestinationFilename(for photo: PhotoItem,
                                          sequentialIndex: Int?,
                                          useSequentialNumbers: Bool,
                                          renameByExifDate: Bool,
                                          customPrefix: String) -> String {
        var baseName: String
        if useSequentialNumbers, let idx = sequentialIndex {
            baseName = String(format: "%04d", idx)
        } else {
            baseName = photo.url.deletingPathExtension().lastPathComponent
        }
        if renameByExifDate {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd_HHmmss"
            baseName = fmt.string(from: photo.dateCreated) + "_" + baseName
        }
        if !customPrefix.isEmpty {
            baseName = customPrefix + baseName
        }
        return baseName
    }

    private func buildDestinationFolder(base: URL,
                                        date: Date,
                                        cameraModel: String?,
                                        isJpegCompanion: Bool,
                                        settings: CopySettings) -> URL {
        var dest = base
        let cal = Calendar.current
        if settings.organizeByYear {
            dest = dest.appendingPathComponent(String(cal.component(.year, from: date)))
        }
        if settings.organizeByMonth {
            dest = dest.appendingPathComponent(String(format: "%02d", cal.component(.month, from: date)))
        }
        if settings.organizeByDay {
            dest = dest.appendingPathComponent(String(format: "%02d", cal.component(.day, from: date)))
        }
        if !settings.eventName.isEmpty {
            dest = dest.appendingPathComponent(settings.eventName)
        }
        if settings.organizeByCameraModel, let model = cameraModel {
            dest = dest.appendingPathComponent(model.replacingOccurrences(of: "/", with: "-")
                        .trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if isJpegCompanion && settings.organizeJpgsInSubfolder {
            dest = dest.appendingPathComponent("_jpg")
        }
        return dest
    }

    /// Builds a preview path string for the first photo in `photos`.
    func previewPath() -> AttributedString? {
        guard let firstPhoto = photos.first, let baseURL = destinationURL else {
            return nil
        }

        let settings = CopySettings(self)
        let isJpg = firstPhoto.path.lowercased().hasSuffix(".jpg") ||
                    firstPhoto.path.lowercased().hasSuffix(".jpeg") ||
                    firstPhoto.path.lowercased().hasSuffix(".heic")
        let ext = firstPhoto.url.pathExtension
        let destFolder = buildDestinationFolder(base: baseURL,
                                                date: firstPhoto.dateCreated,
                                                cameraModel: firstPhoto.cameraModel,
                                                isJpegCompanion: isJpg,
                                                settings: settings)

        let startOffset = useSequentialNumbers ? computeSequentialStartOffset(in: destinationURL, prefix: customPrefix) : 0
        let destFilename = buildDestinationFilename(for: firstPhoto,
                                                    sequentialIndex: useSequentialNumbers ? (startOffset + 1) : nil,
                                                    useSequentialNumbers: useSequentialNumbers,
                                                    renameByExifDate: renameByExifDate,
                                                    customPrefix: customPrefix)
        let destFilenameWithExt = destFilename + "." + ext

        let str = (destFolder.pathComponents + [destFilenameWithExt]).joined(separator: " > ")
            .replacingOccurrences(of: "/ > /", with: " > ")
            .replacingOccurrences(of: "//", with: "/")

        var baseString = AttributedString(str)

        // Find the range of the target word
        if let range = baseString.range(of: destFilenameWithExt) {
            // Apply standard system selection colors
            baseString[range].backgroundColor = .accentColor // Native accent background
            baseString[range].foregroundColor = .white       // High-contrast text color
        }

        return baseString
    }

    // MARK: - Copy

    func startCopy() async {
        guard let destinationURL else {
            return
        }
        await MainActor.run {
            copyProgress = 0
            copiedCount = 0
            copyError = nil
        }

        let count = photos.count

        await MainActor.run {
            totalCount = count
            currentFile = "Preparing..."
        }

        let startOffset = useSequentialNumbers
            ? computeSequentialStartOffset(in: destinationURL, prefix: customPrefix)
            : 0

        // Capture settings for use inside the task
        let settings = CopySettings(self)
        let backupURL = backupDestinationURL
        var photoSequentialIndex: [String: Int] = [:]
        var nextIndex = startOffset + 1

        for (index, photo) in photos.enumerated() {
            if self.isCancelled {
                break
            }

            await MainActor.run {
                self.currentFile = photo.url.lastPathComponent
            }

            // Resolve sequential index — RAW + JPG companions share the same number
            var sequentialIndex: Int?
            if settings.useSequentialNumbers {
                if let existing = photoSequentialIndex[photo.path] {
                    sequentialIndex = existing
                } else {
                    sequentialIndex = nextIndex
                    photoSequentialIndex[photo.path] = nextIndex
                    nextIndex += 1
                }
            }

            // Build filename, preserving actual extension for JPG companions
            let destFilename = buildDestinationFilename(for: photo,
                                                        sequentialIndex: sequentialIndex,
                                                        useSequentialNumbers: settings.useSequentialNumbers,
                                                        renameByExifDate: settings.renameByExifDate,
                                                        customPrefix: settings.customPrefix)
            do {
                try copyPhoto(photo, to: destinationURL, destinationFilename: destFilename, settings: settings)
                if let backupURL {
                    try copyPhoto(photo, to: backupURL, destinationFilename: destFilename, settings: settings)
                }
                await MainActor.run {
                    self.copiedCount = index + 1
                    self.copyProgress = Double(self.copiedCount) / Double(self.totalCount)
                }
            } catch {
                await MainActor.run {
                    self.copyError = "Failed to copy \(photo.url.lastPathComponent): \(error.localizedDescription)"
                }
                break
            }
        }
    }

    private func copyPhoto(_ photo: PhotoItem,
                          to destBaseFolderURL: URL,
                          destinationFilename: String,
                          settings: CopySettings) throws {

        let destFolderURL = buildDestinationFolder(base: destBaseFolderURL,
                                                   date: photo.dateCreated,
                                                   cameraModel: photo.cameraModel,
                                                   isJpegCompanion: false,
                                                   settings: settings)
        try FileManager.default.createDirectory(at: destFolderURL, withIntermediateDirectories: true)

        // 1. Copy the original file
        let sourceExt = photo.url.pathExtension
        let destFileURL = destFolderURL.appendingPathComponent(destinationFilename).appendingPathExtension(sourceExt)
        guard !FileManager.default.fileExists(atPath: destFileURL.path) else {
            return
        }
        try FileManager.default.copyItem(at: photo.url, to: destFileURL)

        // 2. If original file is RAW, search for all companion files and copy them
        guard photo.isRawFile else {
            return
        }
        let baseName  = photo.url.deletingPathExtension().lastPathComponent
        let sourceDir = photo.url.deletingLastPathComponent()
        // Copy XMP and ACR
        for ext in ["xmp", "acr", "XMP", "ACR"] {
            let sidecarURL = sourceDir.appendingPathComponent(baseName).appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: sidecarURL.path) {
                let sidecarDestURL = destFolderURL.appendingPathComponent(destinationFilename).appendingPathExtension(ext)
                if !FileManager.default.fileExists(atPath: sidecarDestURL.path) {
                    try FileManager.default.copyItem(at: sidecarURL, to: sidecarDestURL)
                }
            }
        }
        // If the raw has a jpeg counterpart, search for it and add it to the list as well
        if photo.hasJPG {
            let jpegDestFolderURL = buildDestinationFolder(base: destBaseFolderURL,
                                                           date: photo.dateCreated,
                                                           cameraModel: photo.cameraModel,
                                                           isJpegCompanion: true,
                                                           settings: settings)
            try FileManager.default.createDirectory(at: jpegDestFolderURL, withIntermediateDirectories: true)

            for ext in ["jpg", "jpeg", "heic", "JPG", "JPEG", "HEIC"] {
                let jpegURL = sourceDir.appendingPathComponent(baseName).appendingPathExtension(ext)
                if FileManager.default.fileExists(atPath: jpegURL.path) {
                    let jpegDestURL = jpegDestFolderURL.appendingPathComponent(destinationFilename).appendingPathExtension(ext)
                    try FileManager.default.copyItem(at: jpegURL, to: jpegDestURL)
                    break
                }
            }
        }
    }

    func cancel() {
        isCancelled = true
    }

    // MARK: - Bookmark helpers

    static func urlFromBookmark(_ data: Data) -> URL? {
        #if os(macOS)
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: .withSecurityScope,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &isStale),
                !isStale else {
            return nil
        }
        _ = url.startAccessingSecurityScopedResource()
        return url
        #else
        return nil
        #endif
    }

    static func bookmarkFromURL(_ url: URL) -> Data? {
        #if os(macOS)
        try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        return nil
        #endif
    }
}

// MARK: - Settings snapshot (value type for safe cross-actor capture)

struct CopySettings {
    let renameByExifDate: Bool
    let useSequentialNumbers: Bool
    let customPrefix: String
    let organizeByYear: Bool
    let organizeByMonth: Bool
    let organizeByDay: Bool
    let eventName: String
    let organizeByCameraModel: Bool
    let organizeJpgsInSubfolder: Bool

    init(_ vm: CopyToViewModel) {
        renameByExifDate        = vm.renameByExifDate
        useSequentialNumbers    = vm.useSequentialNumbers
        customPrefix            = vm.customPrefix
        organizeByYear          = vm.organizeByYear
        organizeByMonth         = vm.organizeByMonth
        organizeByDay           = vm.organizeByDay
        eventName               = vm.eventName
        organizeByCameraModel   = vm.organizeByCameraModel
        organizeJpgsInSubfolder = vm.organizeJpgsInSubfolder
    }
}
