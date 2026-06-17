//
//  RenameView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 05.03.2026.
//

import SwiftUI

@MainActor
struct RenameView: View {
    @Environment(\.dismiss) private var dismiss
    let photosToRename: [PhotoItem]

    @State private var renameByExifDate = false
    @State private var useSequentialNumbers = false
    @State private var customPrefix = ""
    @State private var showProgressView = false

    init(photosToRename: [PhotoItem]) {
        self.photosToRename = photosToRename
        _renameByExifDate = State(initialValue: appPrefs.bool(.copyToRenameByExifDate))
        _customPrefix = State(initialValue: appPrefs.string(.copyToCustomPrefix))
    }

    /// Scans the folder for files already named with 4-digit numbers (optionally
    /// filtered by the current prefix) and returns the highest number found,
    /// so the new batch starts after it.
    private var sequentialStartIndex: Int {
        guard useSequentialNumbers, let firstPhoto = photosToRename.first else {
            return 0
        }
        let folder = URL(fileURLWithPath: firstPhoto.path).deletingLastPathComponent()
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )) ?? []

        // Build pattern: if a prefix is set, require it before the 4-digit number
        let prefixPattern = customPrefix.isEmpty ? "" : NSRegularExpression.escapedPattern(for: customPrefix)
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

    private var previewName: String? {
        guard let photo = photosToRename.first else {
            return nil
        }
        return newFilename(for: photo, index: 0, startOffset: sequentialStartIndex)
    }

    private func newFilename(for photo: PhotoItem, index: Int, startOffset: Int = 0) -> String {
        let url = URL(fileURLWithPath: photo.path)
        let ext = url.pathExtension

        var baseName: String

        if useSequentialNumbers {
            baseName = String(format: "%04d", startOffset + index + 1)
        } else {
            baseName = url.deletingPathExtension().lastPathComponent
        }

        if renameByExifDate {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
            baseName = dateFormatter.string(from: photo.dateCreated) + "_" + baseName
        }

        if !customPrefix.isEmpty {
            baseName = customPrefix + baseName
        }

        return ext.isEmpty ? baseName : baseName + "." + ext
    }

    var body: some View {
        Group {
            if showProgressView {
                let startOffset = sequentialStartIndex
                RenameProgressView(viewModel: RenameProgressViewModel(photosToRename: photosToRename,
                                                                      newFilename: { newFilename(for: $0, index: $1, startOffset: startOffset) },
                                                                      onComplete: { dismiss() },
                                                                      onCancel: { dismiss() })
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
                            Text("Include creation date (YYYY-MM-DD_HHMMSS)")
                                .font(.body)
                        }

                        // Sequential numbering
                        Toggle(isOn: $useSequentialNumbers) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Replace filename with sequential number (0001, 0002...)")
                                    .font(.body)
                                Text("Continues from the highest number already in the folder")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
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
                                .background(Color(IRColor.textBackgroundColor))
                                .cornerRadius(4)
                            Spacer()
                        }
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .keyboardShortcut(.cancelAction)
                        Spacer()
                        Button("Rename") {
                            appPrefs.set(renameByExifDate, forKey: .copyToRenameByExifDate)
                            appPrefs.set(customPrefix, forKey: .copyToCustomPrefix)
                            showProgressView = true
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(customPrefix.isEmpty && !renameByExifDate && !useSequentialNumbers)
                    }
                }
                .padding(20)
                .frame(minWidth: 500, minHeight: 300)
            }
        }
    }
}
