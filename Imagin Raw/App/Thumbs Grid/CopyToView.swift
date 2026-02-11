//
//  CopyToView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 10.02.2026.
//

import SwiftUI

struct CopyToView: View {
    @EnvironmentObject var filesModel: FilesModel
    @Environment(\.dismiss) private var dismiss
    let photosToCoрy: [PhotoItem]

    @State private var isCopying = false
    @State private var copyProgress: Double = 0.0
    @State private var currentFile: String = ""
    @State private var copiedCount: Int = 0
    @State private var totalCount: Int = 0
    @State private var copyError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Copy \(photosToCoрy.count) photo\(photosToCoрy.count == 1 ? "" : "s") to...")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            // Folder selection view - Reuse the existing SidebarView
            FoldersListView()
                .disabled(isCopying)

            Divider()

            // Progress section (only visible when copying)
            if isCopying {
                VStack(spacing: 8) {
                    ProgressView(value: copyProgress, total: 1.0)
                        .progressViewStyle(.linear)

                    HStack {
                        Text("Copying: \(currentFile)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(copiedCount) of \(totalCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()

                Divider()
            }

            // Error message
            if let error = copyError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()

                Divider()
            }

            // Bottom buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Copy") {
                    performCopy()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(filesModel.selectedFolder == nil || isCopying)
            }
            .padding()
        }
        .frame(width: 400, height: 600)
        .onAppear {
            // Enable copy mode to prevent photo loading
            filesModel.isInCopyMode = true
        }
        .onDisappear {
            // Disable copy mode when popover closes
            filesModel.isInCopyMode = false
        }
    }

    private func performCopy() {
        guard let destinationURL = filesModel.selectedFolder?.url else { return }

        isCopying = true
        copyProgress = 0.0
        copyError = nil
        copiedCount = 0

        // Count total files to copy (RAW + potential JPGs)
        var filesToCopy: [(source: URL, filename: String)] = []

        for photo in photosToCoрy {
            let photoURL = URL(fileURLWithPath: photo.path)
            let baseName = photoURL.deletingPathExtension().lastPathComponent
            let directory = photoURL.deletingLastPathComponent()

            // Add the RAW file
            filesToCopy.append((source: photoURL, filename: photoURL.lastPathComponent))

            // Check for associated JPG
            for jpgExt in ["jpg", "jpeg", "JPG", "JPEG"] {
                let jpgURL = directory.appendingPathComponent("\(baseName).\(jpgExt)")
                if FileManager.default.fileExists(atPath: jpgURL.path) {
                    filesToCopy.append((source: jpgURL, filename: jpgURL.lastPathComponent))
                    break // Only add the first JPG found
                }
            }
        }

        totalCount = filesToCopy.count

        // Perform copy on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            for (_, file) in filesToCopy.enumerated() {
                DispatchQueue.main.async {
                    currentFile = file.filename
                }

                let destinationFileURL = destinationURL.appendingPathComponent(file.filename)

                do {
                    // Check if file already exists
                    if FileManager.default.fileExists(atPath: destinationFileURL.path) {
                        // Skip or handle conflict - for now, skip
                        DispatchQueue.main.async {
                            copiedCount += 1
                            copyProgress = Double(copiedCount) / Double(totalCount)
                        }
                        continue
                    }

                    // Copy the file
                    try FileManager.default.copyItem(at: file.source, to: destinationFileURL)

                    DispatchQueue.main.async {
                        copiedCount += 1
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
                if copyError == nil {
                    // Success - close the dialog after a brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        dismiss()
                    }
                } else {
                    isCopying = false
                }
            }
        }
    }
}
