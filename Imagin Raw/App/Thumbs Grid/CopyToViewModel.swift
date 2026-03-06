//
//  CopyToViewModel.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 06.03.2026.
//

import Foundation
import AppKit
import SwiftUI

@MainActor
class CopyToViewModel: ObservableObject {

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

    // MARK: - Progress state
    @Published var copyProgress: Double = 0.0
    @Published var currentFile: String = ""
    @Published var copiedCount: Int = 0
    @Published var totalCount: Int = 0
    @Published var copyError: String?
    @Published var isCopying: Bool = false
    @Published var isCancelled: Bool = false

    // MARK: - Init

    init() {
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

    /// Scans `folder` for files already matching `prefix + 0000.ext` and returns the highest number found.
    static func computeSequentialStartOffset(in folder: URL?, prefix: String) -> Int {
        guard let folder else { return 0 }
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

    /// Builds the destination filename for a single photo.
    /// `sequentialIndex` is the 1-based number to use when `useSequentialNumbers` is true.
    static func buildFilename(for photo: PhotoItem,
                              sequentialIndex: Int?,
                              useSequentialNumbers: Bool,
                              renameByExifDate: Bool,
                              customPrefix: String) -> String {
        let url = URL(fileURLWithPath: photo.path)
        let ext = url.pathExtension

        var baseName: String
        if useSequentialNumbers, let idx = sequentialIndex {
            baseName = String(format: "%04d", idx)
        } else {
            baseName = url.deletingPathExtension().lastPathComponent
        }

        if renameByExifDate {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd_HHmmss"
            baseName = fmt.string(from: photo.dateCreated) + "_" + baseName
        }

        if !customPrefix.isEmpty {
            baseName = customPrefix + baseName
        }

        return ext.isEmpty ? baseName : baseName + "." + ext
    }

    /// Builds a preview path string for the first photo in `photos`.
    func previewPath(for photos: [PhotoItem]) -> String? {
        guard let firstPhoto = photos.first,
              let baseURL = destinationURL else { return nil }

        var components: [String] = [baseURL.path]

        if organizeByYear || organizeByMonth || organizeByDay {
            let cal = Calendar.current
            if organizeByYear  { components.append(String(cal.component(.year, from: firstPhoto.dateCreated))) }
            if organizeByMonth { components.append(String(format: "%02d", cal.component(.month, from: firstPhoto.dateCreated))) }
            if organizeByDay   { components.append(String(format: "%02d", cal.component(.day, from: firstPhoto.dateCreated))) }
        }

        if !eventName.isEmpty {
            components.append(eventName)
        }

        if organizeByCameraModel, let model = firstPhoto.cameraModel {
            components.append(model.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let isJpg = firstPhoto.path.lowercased().hasSuffix(".jpg") || firstPhoto.path.lowercased().hasSuffix(".jpeg")
        if organizeJpgsInSubfolder && isJpg { components.append("_jpg") }

        let startOffset = useSequentialNumbers
            ? Self.computeSequentialStartOffset(in: destinationURL, prefix: customPrefix)
            : 0
        let filename = Self.buildFilename(
            for: firstPhoto,
            sequentialIndex: useSequentialNumbers ? (startOffset + 1) : nil,
            useSequentialNumbers: useSequentialNumbers,
            renameByExifDate: renameByExifDate,
            customPrefix: customPrefix
        )
        components.append(filename)

        return components.joined(separator: " > ")
    }

    // MARK: - Copy

    func startCopy(photos: [PhotoItem]) {
        guard let destination = destinationURL else { return }
        isCopying = true
        isCancelled = false
        copyProgress = 0
        copiedCount = 0
        copyError = nil

        // Build file list (RAW + associated JPGs)
        var filesToCopy: [(source: URL, photo: PhotoItem, isJpg: Bool)] = []
        for photo in photos {
            let photoURL = URL(fileURLWithPath: photo.path)
            let baseName = photoURL.deletingPathExtension().lastPathComponent
            let directory = photoURL.deletingLastPathComponent()
            filesToCopy.append((source: photoURL, photo: photo, isJpg: false))
            for jpgExt in ["jpg", "jpeg", "JPG", "JPEG"] {
                let jpgURL = directory.appendingPathComponent("\(baseName).\(jpgExt)")
                if FileManager.default.fileExists(atPath: jpgURL.path) {
                    filesToCopy.append((source: jpgURL, photo: photo, isJpg: true))
                    break
                }
            }
        }

        totalCount = filesToCopy.count
        currentFile = "Preparing..."

        // Compute sequential start offset once — scan destination
        let sequentialStartOffset = useSequentialNumbers
            ? Self.computeSequentialStartOffset(in: destination, prefix: customPrefix)
            : 0

        // Snapshot settings for the background thread
        let _renameByExifDate        = renameByExifDate
        let _useSequentialNumbers    = useSequentialNumbers
        let _customPrefix            = customPrefix
        let _organizeByYear          = organizeByYear
        let _organizeByMonth         = organizeByMonth
        let _organizeByDay           = organizeByDay
        let _eventName               = eventName
        let _organizeByCameraModel   = organizeByCameraModel
        let _organizeJpgsInSubfolder = organizeJpgsInSubfolder
        let backupURL                = backupDestinationURL

        var photoSequentialIndex: [String: Int] = [:]
        var nextSequentialIndex = sequentialStartOffset + 1

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            for (index, file) in filesToCopy.enumerated() {
                if self.isCancelled { break }

                DispatchQueue.main.async { self.currentFile = file.source.lastPathComponent }

                // Resolve sequential index (RAW + JPG pair share the same number)
                var sequentialIndex: Int? = nil
                if _useSequentialNumbers {
                    if let existing = photoSequentialIndex[file.photo.path] {
                        sequentialIndex = existing
                    } else {
                        sequentialIndex = nextSequentialIndex
                        photoSequentialIndex[file.photo.path] = nextSequentialIndex
                        nextSequentialIndex += 1
                    }
                }

                // Build filename
                let base = Self.buildFilename(
                    for: file.photo,
                    sequentialIndex: sequentialIndex,
                    useSequentialNumbers: _useSequentialNumbers,
                    renameByExifDate: _renameByExifDate,
                    customPrefix: _customPrefix
                )
                // Preserve actual extension for JPG companions
                let sourceExt = file.source.pathExtension
                let builtExt  = URL(fileURLWithPath: base).pathExtension
                let newFilename: String
                if sourceExt.lowercased() != builtExt.lowercased() && !sourceExt.isEmpty {
                    newFilename = URL(fileURLWithPath: base).deletingPathExtension().lastPathComponent + "." + sourceExt
                } else {
                    newFilename = base
                }

                func copyToDestination(_ baseURL: URL) throws {
                    var dest = baseURL

                    if _organizeByYear || _organizeByMonth || _organizeByDay {
                        let cal = Calendar.current
                        let date = file.photo.dateCreated
                        if _organizeByYear  { dest = dest.appendingPathComponent(String(cal.component(.year, from: date))) }
                        if _organizeByMonth { dest = dest.appendingPathComponent(String(format: "%02d", cal.component(.month, from: date))) }
                        if _organizeByDay   { dest = dest.appendingPathComponent(String(format: "%02d", cal.component(.day, from: date))) }
                    }
                    if !_eventName.isEmpty {
                        dest = dest.appendingPathComponent(_eventName)
                    }
                    if _organizeByCameraModel, let model = file.photo.cameraModel {
                        dest = dest.appendingPathComponent(model.replacingOccurrences(of: "/", with: "-"))
                    }
                    if file.isJpg && _organizeJpgsInSubfolder {
                        dest = dest.appendingPathComponent("_jpg")
                    }

                    // Single createDirectory call now that the full path is built
                    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

                    let destFile = dest.appendingPathComponent(newFilename)
                    if FileManager.default.fileExists(atPath: destFile.path) { return }
                    try FileManager.default.copyItem(at: file.source, to: destFile)
                }

                do {
                    try copyToDestination(destination)
                    if let backup = backupURL { try copyToDestination(backup) }

                    DispatchQueue.main.async {
                        self.copiedCount = index + 1
                        self.copyProgress = Double(self.copiedCount) / Double(self.totalCount)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.copyError = "Failed to copy \(file.source.lastPathComponent): \(error.localizedDescription)"
                    }
                    break
                }
            }

            DispatchQueue.main.async {
                self.isCopying = false
            }
        }
    }

    func cancel() {
        isCancelled = true
    }

    // MARK: - Bookmark helpers

    static func urlFromBookmark(_ data: Data) -> URL? {
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &isStale),
              !isStale else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    static func bookmarkFromURL(_ url: URL) -> Data? {
        try? url.bookmarkData(options: .withSecurityScope,
                              includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}
