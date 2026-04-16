//
//  SearchResultsFoldersListView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 05.03.2026.
//

import SwiftUI

/// A flat list of folder search results only.
/// Photo results are shown in the content column (ThumbGridView).
struct SearchResultsFoldersListView: View {

    let folderResults: [FolderItem]
    let isSearching: Bool

    @EnvironmentObject var filesModel: FilesModel

    var body: some View {
        Group {
            if isSearching && folderResults.isEmpty {
                VStack {
                    Spacer()
                    ProgressView("Searching...")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.top, 44)
            } else if folderResults.isEmpty {
                VStack {
                    Spacer()
                    Text("No folders found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.top, 44)
            } else {
                List(folderResults, id: \.url, selection: $filesModel.selectedFolder) { folder in
                    SearchFolderRowView(folder: folder)
                        .tag(folder)
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
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

private struct SearchFolderRowView: View {
    let folder: FolderItem
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(folder.url.lastPathComponent)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(folder.url.deletingLastPathComponent().path)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } icon: {
            Image(systemName: "folder.fill")
                .foregroundColor(.blue)
                .font(.system(size: 13))
        }
        .padding(.vertical, 2)
    }
}
