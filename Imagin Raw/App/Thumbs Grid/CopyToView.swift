//
//  CopyToView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 10.02.2026.
//

import SwiftUI

// MARK: - Container

struct CopyToView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: CopyToViewModel
    @State private var showProgress = false

    var body: some View {
        Group {
            if showProgress {
                CopyProgressView(viewModel: viewModel) {
                    dismiss()
                }
                .frame(minWidth: 500, minHeight: 180)
            } else {
                CopyOptionsView(viewModel: viewModel) {
                    viewModel.saveSettings()
                    showProgress = true
                    Task {
                        await viewModel.startCopy()
                        if viewModel.copyError == nil && !viewModel.isCancelled {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            dismiss()
                        }
                    }
                } onCancel: {
                    dismiss()
                }
                .frame(minWidth: 500, minHeight: 420)
            }
        }
        .onDisappear {
            viewModel.stopAccessingSecurityScopedResources()
        }
    }
}

// MARK: - Options

struct CopyOptionsView: View {
    @ObservedObject var viewModel: CopyToViewModel
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
                    Text(viewModel.backupDestinationURL?.path ?? "No backup folder selected")
                        .font(.caption).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Browse...") { showFolderPicker(forBackup: true) }
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
                    Text("Copy JPGs to '_jpg' subfolder").font(.body)
                }
            }

            // Preview
            if let preview = viewModel.previewPath() {
                Divider()
                HStack(spacing: 12) {
                    Text("Preview")
                    Text(preview)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1).truncationMode(.head)
                        .padding(8)
                        .background(Color(IRColor.textBackgroundColor))
                        .cornerRadius(4)
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
        print("Show folder picker")
    }
    #endif
}

// MARK: - Progress

struct CopyProgressView: View {
    @ObservedObject var viewModel: CopyToViewModel
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Copying Files...").font(.headline)

            if viewModel.backupDestinationURL != nil {
                Text("Copying to primary and backup destinations")
                    .font(.caption).foregroundColor(.secondary)
            }

            ProgressView(value: viewModel.copyProgress, total: 1.0)
                .progressViewStyle(.linear).frame(height: 8)

            VStack(spacing: 4) {
                HStack {
                    Text("Copying: \(viewModel.currentFile)")
                        .font(.caption).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                }
                HStack {
                    Text("\(viewModel.copiedCount) of \(viewModel.totalCount)")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                }
            }

            if let error = viewModel.copyError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(error).font(.caption).foregroundColor(.secondary).lineLimit(2)
                    Spacer()
                }
            }

            HStack {
                Spacer()
                Button(viewModel.copyError != nil ? "Close" : "Cancel") {
                    if viewModel.copyError == nil { viewModel.cancel() }
                    onDone()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 500, minHeight: 180)
    }
}
