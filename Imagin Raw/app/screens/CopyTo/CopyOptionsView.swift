//
//  CopyOptionsView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 06.08.2026.
//

import SwiftUI

struct CopyOptionsView: View {
    @ObservedObject var viewModel: PhotoCopySheetModel
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Copy \(viewModel.photos.count) photo\(viewModel.photos.count == 1 ? "" : "s")")
                .font(.headline)

            Divider()

            // Destination
            VStack(alignment: .leading, spacing: 8) {
                Text("Destination:").font(.body)
                HStack {
                    Text(viewModel.destinationURL?.path ?? "No folder selected")
                        .font(.caption).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Browse...") { showFolderPicker(forBackup: false) }
                }
            }

            // Backup destination
            VStack(alignment: .leading, spacing: 8) {
                Text("Backup Destination (Optional):").font(.body)
                HStack {
                    Text(viewModel.backupDestinationURL?.path ?? "Select a folder to make a second copy!")
                        .font(.caption).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Browse...") {
                        showFolderPicker(forBackup: true)
                    }
                    if viewModel.backupDestinationURL != nil {
                        Button { viewModel.backupDestinationURL = nil } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            // Folder organisation options
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Text("Organize by date").font(.body)
                    Spacer()
                    Toggle("Year", isOn: $viewModel.organizeByYear).toggleStyle(.automatic)
                    Toggle("Month", isOn: $viewModel.organizeByMonth).toggleStyle(.automatic)
                        .disabled(!viewModel.organizeByYear)
                    Toggle("Day", isOn: $viewModel.organizeByDay).toggleStyle(.automatic)
                        .disabled(!viewModel.organizeByMonth)
                }

                HStack(spacing: 12) {
                    Text("Client / event / location").font(.body).lineLimit(1)
                    TextField("e.g., Paris, Wedding, Nike", text: $viewModel.eventName)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle(isOn: $viewModel.organizeByCameraModel) {
                    Text("Organize into subfolders by camera model").font(.body)
                }
            }

            Divider()

            // Filename options
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 16) {
                    Text("Filename prefix").font(.body)
                    TextField("e.g., Paris_", text: $viewModel.customPrefix)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle(isOn: $viewModel.useSequentialNumbers) {
                    Text("Replace filename with sequential numbers (0001, 0002...)").font(.body)
                }

                Toggle(isOn: $viewModel.renameByExifDate) {
                    Text("Include creation date (YYYY-MM-DD_HHMMSS)").font(.body)
                }

                Toggle(isOn: $viewModel.organizeJpgsInSubfolder) {
                    Text("Copy jpeg counterparts to '_jpg' subfolder (when raw exists)").font(.body)
                }
            }

            // Preview
            if let previewPath = viewModel.previewPath() {
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preview:")
                        Text(previewPath)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    Spacer()
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Start Copying", action: onStart)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.destinationURL == nil)
            }
        }
        .padding(20)
    }

    #if os(macOS)
    private func showFolderPicker(forBackup: Bool) {
        let panel = NSOpenPanel()
        panel.title = forBackup ? "Choose Backup Destination Folder" : "Choose Destination Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if forBackup { viewModel.backupDestinationURL = url }
            else         { viewModel.destinationURL = url }
        }
    }
    #elseif os(iOS)
    private func showFolderPicker(forBackup: Bool) {
        RCLog("Show folder picker")
    }
    #endif
}
