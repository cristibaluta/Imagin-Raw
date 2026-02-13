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
    @State private var backupDestinationURL: URL?
    @State private var showProgressView = false
    @State private var renameByExifDate = false
    @State private var customPrefix = ""
    @State private var organizeByDate = false
    @State private var organizeByCameraModel = false
    @State private var organizeJpgsInSubfolder = false

    var body: some View {
        if showProgressView, let destination = destinationURL {
            CopyProgressView(
                photosToCoрy: photosToCoрy,
                destinationURL: destination,
                backupDestinationURL: backupDestinationURL,
                renameByExifDate: renameByExifDate,
                customPrefix: customPrefix,
                organizeByDate: organizeByDate,
                organizeByCameraModel: organizeByCameraModel,
                organizeJpgsInSubfolder: organizeJpgsInSubfolder,
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
                photosToCoрy: photosToCoрy,
                photosCount: photosToCoрy.count,
                destinationURL: $destinationURL,
                backupDestinationURL: $backupDestinationURL,
                renameByExifDate: $renameByExifDate,
                customPrefix: $customPrefix,
                organizeByDate: $organizeByDate,
                organizeByCameraModel: $organizeByCameraModel,
                organizeJpgsInSubfolder: $organizeJpgsInSubfolder,
                onStart: {
                    showProgressView = true
                },
                onCancel: {
                    dismiss()
                }
            )
            .frame(minWidth: 500, minHeight: 420)
        }
    }
}

struct CopyOptionsView: View {
    let photosToCoрy: [PhotoItem]
    let photosCount: Int
    @Binding var destinationURL: URL?
    @Binding var backupDestinationURL: URL?
    @Binding var renameByExifDate: Bool
    @Binding var customPrefix: String
    @Binding var organizeByDate: Bool
    @Binding var organizeByCameraModel: Bool
    @Binding var organizeJpgsInSubfolder: Bool
    let onStart: () -> Void
    let onCancel: () -> Void

    // Computed property to generate preview path
    private var previewPath: String? {
        guard let firstPhoto = photosToCoрy.first,
              let baseURL = destinationURL else {
            return nil
        }

        var components: [String] = [baseURL.path]

        // Add date folder if enabled
        if organizeByDate {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MM-dd"
            let folderName = dateFormatter.string(from: firstPhoto.dateCreated)
            components.append(folderName)
        }

        // Add camera model folder if enabled
        if organizeByCameraModel, let cameraModel = firstPhoto.cameraModel {
            // Clean up camera model for folder name
            let cleanModel = cameraModel
                .replacingOccurrences(of: "/", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            components.append(cleanModel)
        }

        // Add _jpg folder if this would be a JPG and the option is enabled
        let isJpg = firstPhoto.path.lowercased().hasSuffix(".jpg") ||
                    firstPhoto.path.lowercased().hasSuffix(".jpeg")
        if organizeJpgsInSubfolder && isJpg {
            components.append("_jpg")
        }

        // Generate filename
        var filename = URL(fileURLWithPath: firstPhoto.path).lastPathComponent
        let fileExtension = URL(fileURLWithPath: firstPhoto.path).pathExtension

        if renameByExifDate {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
            let dateString = dateFormatter.string(from: firstPhoto.dateCreated)

            if !customPrefix.isEmpty {
                filename = customPrefix + dateString + "." + fileExtension
            } else {
                filename = dateString + "." + fileExtension
            }
        } else if !customPrefix.isEmpty {
            filename = customPrefix + filename
        }

        components.append(filename)

        return components.joined(separator: "/")
    }

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
                Text("Primary Destination:")
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
                        showFolderPicker(forBackup: false)
                    }
                }
            }

            // Backup destination folder selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Backup Destination (Optional):")
                    .font(.body)

                HStack {
                    if let url = backupDestinationURL {
                        Text(url.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("No backup folder selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button("Browse...") {
                        showFolderPicker(forBackup: true)
                    }

                    if backupDestinationURL != nil {
                        Button(action: {
                            backupDestinationURL = nil
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            // Options
            HStack {
                VStack(alignment: .leading, spacing: 16) {
                    // Rename by EXIF date
                    Toggle(isOn: $renameByExifDate) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rename files by creation date")
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

                    // Organize by camera model
                    Toggle(isOn: $organizeByCameraModel) {
                        Text("Organize into subfolders by camera model")
                            .font(.body)
                    }

                    // Organize JPGs in subfolder
                    Toggle(isOn: $organizeJpgsInSubfolder) {
                        Text("Copy JPGs to _jpg subfolder")
                            .font(.body)
                    }
                }
                Spacer()
            }

            // Preview section
            if let preview = previewPath {
                Divider()

                HStack {
                    Text(preview)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(4)
                    Spacer()
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

    private func showFolderPicker(forBackup: Bool) {
        let panel = NSOpenPanel()
        panel.title = forBackup ? "Choose Backup Destination Folder" : "Choose Destination Folder"
        panel.message = "Select a folder to copy \(photosCount) photo\(photosCount == 1 ? "" : "s") to"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                if forBackup {
                    backupDestinationURL = url
                } else {
                    destinationURL = url
                }
            }
        }
    }
}

struct CopyProgressView: View {
    let photosToCoрy: [PhotoItem]
    let destinationURL: URL
    let backupDestinationURL: URL?
    let renameByExifDate: Bool
    let customPrefix: String
    let organizeByDate: Bool
    let organizeByCameraModel: Bool
    let organizeJpgsInSubfolder: Bool
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

            if backupDestinationURL != nil {
                Text("Copying to primary and backup destinations")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

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
        var filesToCopy: [(source: URL, photo: PhotoItem?, filename: String, isJpg: Bool)] = []

        for photo in photosToCoрy {
            let photoURL = URL(fileURLWithPath: photo.path)
            let baseName = photoURL.deletingPathExtension().lastPathComponent
            let directory = photoURL.deletingLastPathComponent()

            // Add the RAW file
            filesToCopy.append((source: photoURL, photo: photo, filename: photoURL.lastPathComponent, isJpg: false))

            // Check for associated JPG
            for jpgExt in ["jpg", "jpeg", "JPG", "JPEG"] {
                let jpgURL = directory.appendingPathComponent("\(baseName).\(jpgExt)")
                if FileManager.default.fileExists(atPath: jpgURL.path) {
                    filesToCopy.append((source: jpgURL, photo: nil, filename: jpgURL.lastPathComponent, isJpg: true))
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

                // Helper function to copy to a destination
                func copyToDestination(_ baseURL: URL) throws {
                    var destinationFolder = baseURL

                    // Organize by date if option is enabled and we have photo metadata
                    if organizeByDate, let photo = file.photo {
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "MM-dd"
                        let folderName = dateFormatter.string(from: photo.dateCreated)
                        destinationFolder = baseURL.appendingPathComponent(folderName)

                        // Create subfolder if it doesn't exist
                        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
                    }

                    // Organize by camera model if option is enabled and we have photo metadata
                    if organizeByCameraModel, let photo = file.photo, let cameraModel = photo.cameraModel {
                        // Clean up camera model for folder name (replace / with -)
                        let cleanModel = cameraModel.replacingOccurrences(of: "/", with: "-")
                        destinationFolder = destinationFolder.appendingPathComponent(cleanModel)

                        // Create subfolder if it doesn't exist
                        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
                    }

                    // If this is a JPG and the option is enabled, put it in _jpg subfolder
                    if file.isJpg && organizeJpgsInSubfolder {
                        destinationFolder = destinationFolder.appendingPathComponent("_jpg")

                        // Create _jpg subfolder if it doesn't exist
                        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
                    }

                    let destinationFileURL = destinationFolder.appendingPathComponent(newFilename)

                    // Skip if file already exists
                    if FileManager.default.fileExists(atPath: destinationFileURL.path) {
                        return
                    }

                    // Copy the file
                    try FileManager.default.copyItem(at: file.source, to: destinationFileURL)
                }

                do {
                    // Copy to primary destination
                    try copyToDestination(destinationURL)

                    // Copy to backup destination if provided
                    if let backupURL = backupDestinationURL {
                        try copyToDestination(backupURL)
                    }

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
