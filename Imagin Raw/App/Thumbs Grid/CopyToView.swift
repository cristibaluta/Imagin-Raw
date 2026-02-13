//
//  CopyToView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 10.02.2026.
//

import SwiftUI
import AppKit

struct CopyToView: View {
    @Environment(\.dismiss) private var dismiss
    let photosToCoрy: [PhotoItem]

    @State private var destinationURL: URL?
    @State private var showProgressView = false
    @State private var renameByExifDate = false
    @State private var customPrefix = ""
    @State private var organizeByDate = false

    var body: some View {
        if showProgressView, let destination = destinationURL {
            CopyProgressView(
                photosToCoрy: photosToCoрy,
                destinationURL: destination,
                renameByExifDate: renameByExifDate,
                customPrefix: customPrefix,
                organizeByDate: organizeByDate,
                onComplete: {
                    dismiss()
                },
                onCancel: {
                    dismiss()
                }
            )
            .frame(minWidth: 500, minHeight: 180)
        } else {
            CopyOptionsView(
                photosCount: photosToCoрy.count,
                destinationURL: $destinationURL,
                renameByExifDate: $renameByExifDate,
                customPrefix: $customPrefix,
                organizeByDate: $organizeByDate,
                onStart: {
                    showProgressView = true
                },
                onCancel: {
                    dismiss()
                }
            )
            .frame(minWidth: 500, minHeight: 320)
        }
    }
}

struct CopyOptionsView: View {
    let photosCount: Int
    @Binding var destinationURL: URL?
    @Binding var renameByExifDate: Bool
    @Binding var customPrefix: String
    @Binding var organizeByDate: Bool
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("Copy Options")
                    .font(.headline)

                Text("Copying \(photosCount) photo\(photosCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Destination folder selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Destination:")
                    .font(.body)

                HStack {
                    if let url = destinationURL {
                        Text(url.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("No folder selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button("Browse...") {
                        showFolderPicker()
                    }
                }
            }

            Divider()

            // Options
            VStack(alignment: .leading, spacing: 16) {
                // Rename by EXIF date
                Toggle(isOn: $renameByExifDate) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rename files by EXIF date")
                            .font(.body)
                        Text("Format: YYYY-MM-DD_HHMMSS")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Custom prefix
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom prefix (optional)")
                        .font(.body)
                    TextField("e.g., Vacation_", text: $customPrefix)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                }

                // Organize by date
                Toggle(isOn: $organizeByDate) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Organize into subfolders by date")
                            .font(.body)
                        Text("Creates folders like: 02-13 (Month-Day)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Start Copying") {
                    onStart()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(destinationURL == nil)
            }
        }
        .padding(20)
    }

    private func showFolderPicker() {
        let panel = NSOpenPanel()
        panel.title = "Choose Destination Folder"
        panel.message = "Select a folder to copy \(photosCount) photo\(photosCount == 1 ? "" : "s") to"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                destinationURL = url
            }
        }
    }
}

struct CopyProgressView: View {
    let photosToCoрy: [PhotoItem]
    let destinationURL: URL
    let renameByExifDate: Bool
    let customPrefix: String
    let organizeByDate: Bool
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var copyProgress: Double = 0.0
    @State private var currentFile: String = ""
    @State private var copiedCount: Int = 0
    @State private var totalCount: Int = 0
    @State private var copyError: String?
    @State private var isCancelled = false

    var body: some View {
        VStack(spacing: 16) {
            // Header
            Text("Copying Files...")
                .font(.headline)

            // Progress bar
            ProgressView(value: copyProgress, total: 1.0)
                .progressViewStyle(.linear)
                .frame(height: 8)

            // Current file and count
            VStack(spacing: 4) {
                HStack {
                    Text("Copying: \(currentFile)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }

                HStack {
                    Text("\(copiedCount) of \(totalCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            // Error message
            if let error = copyError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    Spacer()
                }
            }

            // Cancel button
            HStack {
                Spacer()
                Button(copyError != nil ? "Close" : "Cancel") {
                    if copyError == nil {
                        isCancelled = true
                    }
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 500, minHeight: 180)
        .onAppear {
            performCopy()
        }
    }

    private func performCopy() {
        // Count total files to copy (RAW + potential JPGs)
        var filesToCopy: [(source: URL, photo: PhotoItem?, filename: String)] = []

        for photo in photosToCoрy {
            let photoURL = URL(fileURLWithPath: photo.path)
            let baseName = photoURL.deletingPathExtension().lastPathComponent
            let directory = photoURL.deletingLastPathComponent()

            // Add the RAW file
            filesToCopy.append((source: photoURL, photo: photo, filename: photoURL.lastPathComponent))

            // Check for associated JPG
            for jpgExt in ["jpg", "jpeg", "JPG", "JPEG"] {
                let jpgURL = directory.appendingPathComponent("\(baseName).\(jpgExt)")
                if FileManager.default.fileExists(atPath: jpgURL.path) {
                    filesToCopy.append((source: jpgURL, photo: nil, filename: jpgURL.lastPathComponent))
                    break // Only add the first JPG found
                }
            }
        }

        totalCount = filesToCopy.count
        currentFile = "Preparing..."

        // Perform copy on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            for (index, file) in filesToCopy.enumerated() {
                // Check if cancelled
                if isCancelled {
                    break
                }

                DispatchQueue.main.async {
                    currentFile = file.filename
                }

                // Determine destination filename and path
                let originalFilename = file.filename
                let fileExtension = file.source.pathExtension
                var newFilename = originalFilename

                // Apply custom prefix
                if !customPrefix.isEmpty {
                    newFilename = customPrefix + originalFilename
                }

                // Rename by EXIF date if option is enabled and we have photo metadata
                if renameByExifDate, let photo = file.photo {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
                    let dateString = dateFormatter.string(from: photo.dateCreated)

                    if !customPrefix.isEmpty {
                        newFilename = customPrefix + dateString + "." + fileExtension
                    } else {
                        newFilename = dateString + "." + fileExtension
                    }
                }

                // Determine destination folder
                var destinationFolder = destinationURL

                // Organize by date if option is enabled and we have photo metadata
                if organizeByDate, let photo = file.photo {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "MM-dd"
                    let folderName = dateFormatter.string(from: photo.dateCreated)
                    destinationFolder = destinationURL.appendingPathComponent(folderName)

                    // Create subfolder if it doesn't exist
                    do {
                        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
                    } catch {
                        DispatchQueue.main.async {
                            copyError = "Failed to create folder \(folderName): \(error.localizedDescription)"
                        }
                        break
                    }
                }

                let destinationFileURL = destinationFolder.appendingPathComponent(newFilename)

                do {
                    // Check if file already exists
                    if FileManager.default.fileExists(atPath: destinationFileURL.path) {
                        // Skip files that already exist
                        DispatchQueue.main.async {
                            copiedCount = index + 1
                            copyProgress = Double(copiedCount) / Double(totalCount)
                        }
                        continue
                    }

                    // Copy the file
                    try FileManager.default.copyItem(at: file.source, to: destinationFileURL)

                    DispatchQueue.main.async {
                        copiedCount = index + 1
                        copyProgress = Double(copiedCount) / Double(totalCount)
                    }
                } catch {
                    DispatchQueue.main.async {
                        copyError = "Failed to copy \(file.filename): \(error.localizedDescription)"
                    }
                    break
                }
            }

            // Complete
            DispatchQueue.main.async {
                if copyError == nil && !isCancelled {
                    // Success - close the dialog after a brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        onComplete()
                    }
                }
            }
        }
    }
}
