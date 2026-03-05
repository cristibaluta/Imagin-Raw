//
//  SearchResultsFoldersListView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 05.03.2026.
//

import SwiftUI

/// A flat list of folder search results. No hierarchy, no expand/collapse.
/// Tapping a row selects the folder and loads its photos directly.
struct SearchResultsFoldersListView: View {

    let results: [FolderItem]
    let isSearching: Bool

    @EnvironmentObject var filesModel: FilesModel

    var body: some View {
        Group {
            if isSearching {
                VStack {
                    Spacer()
                    ProgressView("Searching...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.top, 44)
            } else if results.isEmpty {
                VStack {
                    Spacer()
                    Text("No folders found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.top, 44)
            } else {
                List(results, id: \.url, selection: $filesModel.selectedFolder) {
                    folder in
                    SearchResultRowView(
                        folder: folder,
                        isSelected: filesModel.selectedFolder?.url == folder.url
                    )
                    .onTapGesture {
                        filesModel.selectedFolder = folder
                    }
                }
                .listStyle(.sidebar)
                .focusable(false)
                .safeAreaInset(edge: .top) {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }
}

private struct SearchResultRowView: View {

    let folder: FolderItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .foregroundColor(.blue)
                .font(.system(size: 13))

            VStack(alignment: .leading, spacing: 1) {
                // Folder name
                Text(folder.url.lastPathComponent)
                    .font(.system(size: 13))
                    .lineLimit(1)
                // Parent path as subtitle
                Text(folder.url.deletingLastPathComponent().path)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .padding(.vertical, 2)
    }
}
