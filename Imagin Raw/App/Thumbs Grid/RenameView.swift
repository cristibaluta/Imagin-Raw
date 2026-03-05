//
//  RenameView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 05.03.2026.
//

import SwiftUI

struct RenameView: View {
    @Environment(\.dismiss) private var dismiss
    let photosToRename: [PhotoItem]

    @State private var renameByExifDate = false
    @State private var customPrefix = ""
    @State private var showProgressView = false
    @State private var renameError: String?
    @State private var renamedCount = 0

    init(photosToRename: [PhotoItem]) {
        self.photosToRename = photosToRename
        _renameByExifDate = State(initialValue: appPrefs.bool(.copyToRenameByExifDate))
        _customPrefix = State(initialValue: appPrefs.string(.copyToCustomPrefix))
    }

    // Preview of what the first photo would be renamed to
    private var previewName: String? {
        guard let photo = photosToRename.first else { return nil }
        return newFilename(for: photo)
    }

    private func newFilename(for photo: PhotoItem) -> String {
        let url = URL(fileURLWithPath: photo.path)
        let originalFilename = url.lastPathComponent
        var result = originalFilename

        if renameByExifDate {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
            let dateString = dateFormatter.string(from: photo.dateCreated)
            if !customPrefix.isEmpty {
                result = customPrefix + dateString + "_" + originalFilename
            } else {
                result = dateString + "_" + originalFilename
            }
        } else if !customPrefix.isEmpty {
            result = customPrefix + originalFilename
        }

        return result
    }

    var body: some View {
        Group {
            if showProgressView {
                RenameProgressView(
                    photosToRename: photosToRename,
                    newFilename: { newFilename(for: $0) },
                    onComplete: { dismiss() },
                    onCancel: { dismiss() }
                )
                .frame(minWidth: 500, minHeight: 160)
            } else {
                VStack(spacing: 20) {
                    Text("Rename \(photosToRename.count) photo\(photosToRename.count == 1 ? "" : "s")")
                        .font(.headline)

                    Divider()

                    VStack(alignment: .leading, spacing: 16) {
                        // Custom prefix
                        HStack(alignment: .center, spacing: 16) {
                            Text("Filename prefix")
                                .font(.body)
                            TextField("e.g., Paris_", text: $customPrefix)
                                .textFieldStyle(.roundedBorder)
                        }

                        // Rename by EXIF date
                        Toggle(isOn: $renameByExifDate) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Include creation date (YYYY-MM-DD_HHMMSS)")
                                    .font(.body)
                            }
                        }
                    }

                    // Preview
                    if let preview = previewName {
                        Divider()
                        HStack(spacing: 12) {
                            Text("Preview")
                            Text(preview)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.head)
                                .padding(8)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(4)
                        }
                    }

                    Spacer()

                    Divider()

                    HStack(spacing: 12) {
                        Button("Cancel") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                        Spacer()
                        Button("Rename") {
                            appPrefs.set(renameByExifDate, forKey: .copyToRenameByExifDate)
                            appPrefs.set(customPrefix, forKey: .copyToCustomPrefix)
                            showProgressView = true
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(customPrefix.isEmpty && !renameByExifDate)
                    }
                }
                .padding(20)
                .frame(minWidth: 500, minHeight: 260)
            }
        }
    }
}

private struct RenameProgressView: View {
    let photosToRename: [PhotoItem]
    let newFilename: (PhotoItem) -> String
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var progress: Double = 0
    @State private var currentFile: String = "Preparing..."
    @State private var renamedCount: Int = 0
    @State private var renameError: String?
    @State private var isCancelled = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Renaming Files...")
                .font(.headline)

            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)

            VStack(spacing: 4) {
                HStack {
                    Text("Renaming: \(currentFile)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                HStack {
                    Text("\(renamedCount) of \(photosToRename.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            if let error = renameError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            HStack {
                Spacer()
                Button(renameError != nil ? "Close" : "Cancel") {
                    isCancelled = true
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .onAppear { performRename() }
    }

    private func performRename() {
        let fm = FileManager.default

        DispatchQueue.global(qos: .userInitiated).async {
            for (index, photo) in photosToRename.enumerated() {
                guard !isCancelled else { break }

                let sourceURL = URL(fileURLWithPath: photo.path)
                let newName = newFilename(photo)
                let destURL = sourceURL.deletingLastPathComponent().appendingPathComponent(newName)

                DispatchQueue.main.async { currentFile = sourceURL.lastPathComponent }

                // Skip if name is unchanged
                guard sourceURL.lastPathComponent != newName else {
                    DispatchQueue.main.async {
                        renamedCount = index + 1
                        progress = Double(renamedCount) / Double(photosToRename.count)
                    }
                    continue
                }

                do {
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

                    DispatchQueue.main.async {
                        renamedCount = index + 1
                        progress = Double(renamedCount) / Double(photosToRename.count)
                    }
                } catch {
                    DispatchQueue.main.async {
                        renameError = "Failed to rename \(sourceURL.lastPathComponent): \(error.localizedDescription)"
                    }
                    break
                }
            }

            DispatchQueue.main.async {
                if renameError == nil && !isCancelled {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { onComplete() }
                }
            }
        }
    }
}
