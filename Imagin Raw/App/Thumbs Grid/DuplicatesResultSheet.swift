//
//  DuplicatesResultSheet.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 09.03.2026.
//

import SwiftUI

struct DuplicatesResultSheet: View {
    @ObservedObject var viewModel: ThumbGridViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Find Duplicates")
                        .font(.headline)
                    if let result = viewModel.duplicateScanResult {
                        Text("\(result.groups.count) group(s) found in \(result.totalScanned) photos — \(String(format: "%.2f", result.duration))s")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Body
            if viewModel.isFindingDuplicates {
                scanningView
            } else if let result = viewModel.duplicateScanResult {
                if result.groups.isEmpty {
                    noDuplicatesView(scanned: result.totalScanned, duration: result.duration)
                } else {
                    groupsListView(result: result)
                }
            } else {
                // Sheet opened before scan finished (shouldn't normally happen)
                scanningView
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    // MARK: - Subviews

    private var scanningView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView(value: Double(viewModel.duplicateScanProgress.done),
                         total: Double(max(1, viewModel.duplicateScanProgress.total)))
                .progressViewStyle(.linear)
                .frame(width: 300)
            Text("Analysing \(viewModel.duplicateScanProgress.done) / \(viewModel.duplicateScanProgress.total) photos...")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
    }

    private func noDuplicatesView(scanned: Int, duration: TimeInterval) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.green)
            Text("No duplicates found")
                .font(.headline)
            Text("Scanned \(scanned) photos in \(String(format: "%.2f", duration))s")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private func groupsListView(result: DuplicateScanResult) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(result.groups) { group in
                    DuplicateGroupRow(group: group)
                }
            }
            .padding()
        }
    }
}

// MARK: - Group Row

private struct DuplicateGroupRow: View {
    let group: DuplicateGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(group.photos.count) similar photos")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("(max distance: \(String(format: "%.3f", group.distance)))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(group.photos) { photo in
                        DuplicatePhotoTile(photo: photo)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Photo Tile

private struct DuplicatePhotoTile: View {
    let photo: PhotoItem
    @State private var thumbnail: NSImage? = nil

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let img = thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .overlay(ProgressView().scaleEffect(0.6))
                }
            }
            .frame(width: 120, height: 90)
            .clipped()
            .cornerRadius(4)

            Text(URL(fileURLWithPath: photo.path).lastPathComponent)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 120)

            if let size = photo.fileSizeBytes {
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        let path = photo.path
        Task.detached(priority: .utility) {
            if let cached = await ThumbsManager.shared.getCachedThumbnail(for: path) {
                await MainActor.run { thumbnail = cached }
                return
            }
            // Fall back to reading the file directly at a small size
            if let img = NSImage(contentsOfFile: path) {
                await MainActor.run { thumbnail = img }
            }
        }
    }
}
