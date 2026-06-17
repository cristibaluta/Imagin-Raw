//
//  CopyToViewModel 2.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 12.06.2026.
//

import Foundation

@MainActor
class RenameProgressViewModel: ObservableObject, Identifiable {
    let id = UUID()

    @Published var progress: Double = 0
    @Published var currentFile: String = "Preparing..."
    @Published var renamedCount: Int = 0
    @Published var renameError: String?

    let photosToRename: [PhotoItem]
    private var renameTask: Task<Void, Never>?

    let newFilename: (PhotoItem, Int) -> String
    let onComplete: () -> Void
    let onCancel: () -> Void

    init(photosToRename: [PhotoItem],
         newFilename: @escaping (PhotoItem, Int) -> String,
         onComplete: @escaping () -> Void,
         onCancel: @escaping () -> Void)
    {
        self.photosToRename = photosToRename
        self.newFilename = newFilename
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    func performRename() {
        renameTask = Task {
            for (index, photo) in photosToRename.enumerated() {
                guard !Task.isCancelled else { break }

                let sourceURL = URL(fileURLWithPath: photo.path)
                let newName = newFilename(photo, index)
                let destURL = sourceURL.deletingLastPathComponent().appendingPathComponent(newName)

                currentFile = sourceURL.lastPathComponent

                // Skip if name is unchanged
                guard sourceURL.lastPathComponent != newName else {
                    renamedCount = index + 1
                    progress = Double(renamedCount) / Double(photosToRename.count)
                    continue
                }

                do {
                    // Heavy file I/O runs off the main actor
                    try await Task.detached(priority: .userInitiated) {
                        try await Self.moveFiles(photo: photo, from: sourceURL, to: destURL)
                    }.value

                    renamedCount = index + 1
                    progress = Double(renamedCount) / Double(photosToRename.count)
                } catch {
                    renameError = "Failed to rename \(sourceURL.lastPathComponent): \(error.localizedDescription)"
                    break
                }
            }

            if renameError == nil && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                onComplete()
            }
        }
    }

    func cancelRename() {
        renameTask?.cancel()
        onCancel()
    }

    private static func moveFiles(photo: PhotoItem, from sourceURL: URL, to destURL: URL) throws {
        let fm = FileManager.default
        // Rename main file
        try fm.moveItem(at: sourceURL, to: destURL)

        // Rename associated XMP sidecar if present
        let xmpSource = sourceURL.deletingPathExtension().appendingPathExtension("xmp")
        let xmpDest = destURL.deletingPathExtension().appendingPathExtension("xmp")
        if fm.fileExists(atPath: xmpSource.path) {
            try? fm.moveItem(at: xmpSource, to: xmpDest)
        }

        // Rename associated ACR sidecar if present
        let acrSource = sourceURL.deletingPathExtension().appendingPathExtension("acr")
        let acrDest = destURL.deletingPathExtension().appendingPathExtension("acr")
        if fm.fileExists(atPath: acrSource.path) {
            try? fm.moveItem(at: acrSource, to: acrDest)
        }

        // Rename associated JPG if present
        if photo.hasJPG {
            for ext in ["jpg", "jpeg", "JPG", "JPEG"] {
                let jpgSource = sourceURL.deletingPathExtension().appendingPathExtension(ext)
                if fm.fileExists(atPath: jpgSource.path) {
                    let jpgDest = destURL.deletingPathExtension().appendingPathExtension(ext)
                    try? fm.moveItem(at: jpgSource, to: jpgDest)
                    break
                }
            }
        }
    }
}
