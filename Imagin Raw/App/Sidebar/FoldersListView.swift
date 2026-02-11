//
//  FoldersList.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 11.02.2026.
//

import SwiftUI

struct FoldersListView: View {
    @EnvironmentObject var filesModel: FilesModel
    @State private var expandedFolders: Set<URL> = []
    let onDoubleClick: (() -> Void)?

    // Default initializer for backwards compatibility
    init(onDoubleClick: (() -> Void)? = nil) {
        self.onDoubleClick = onDoubleClick
    }

    private let expandedFoldersKey = "ExpandedFolders"
    private let selectedFolderKey = "SelectedFolder"

    var body: some View {
        List(selection: $filesModel.selectedFolder) {
            ForEach(Array(filesModel.rootFolders.enumerated()), id: \.element.id) { index, rootFolder in
                FolderRowView(
                    folder: rootFolder,
                    expandedFolders: $expandedFolders,
                    selectedFolder: $filesModel.selectedFolder,
                    saveExpandedState: saveExpandedState,
                    onDoubleClick: {
                        onDoubleClick?()
                    },
                    isRootFolder: true
                )
            }
            .onDelete(perform: deleteFolders)
        }
        .listStyle(.sidebar)
        .focusable(false)
        .onAppear {
            loadExpandedState()
            loadSelectedFolder()
        }
        .onChange(of: filesModel.selectedFolder) { _, newValue in
            saveSelectedFolder(newValue)
        }
    }

    private func loadExpandedState() {
        if let data = UserDefaults.standard.data(forKey: expandedFoldersKey),
           let urls = try? JSONDecoder().decode([URL].self, from: data) {
            expandedFolders = Set(urls)
        }
    }

    private func saveExpandedState() {
        let urls = Array(expandedFolders)
        if let data = try? JSONEncoder().encode(urls) {
            UserDefaults.standard.set(data, forKey: expandedFoldersKey)
        }
    }

    private func loadSelectedFolder() {
        if let data = UserDefaults.standard.data(forKey: selectedFolderKey),
           let url = try? JSONDecoder().decode(URL.self, from: data) {
            // Find the folder in any of the root folders that matches the saved URL
            for rootFolder in filesModel.rootFolders {
                if let folder = findFolder(url: url, in: rootFolder) {
                    filesModel.selectedFolder = folder
                    return
                }
            }
        }
    }

    private func saveSelectedFolder(_ folder: FolderItem?) {
        if let folder = folder,
           let data = try? JSONEncoder().encode(folder.url) {
            UserDefaults.standard.set(data, forKey: selectedFolderKey)
        }
    }

    private func findFolder(url: URL, in folderItem: FolderItem) -> FolderItem? {
        if folderItem.url == url {
            return folderItem
        }

        if let children = folderItem.children {
            for child in children {
                if let found = findFolder(url: url, in: child) {
                    return found
                }
            }
        }

        return nil
    }

    private func deleteFolders(offsets: IndexSet) {
        for index in offsets {
            let folder = filesModel.rootFolders[index]
            filesModel.removeFolder(at: folder.url)
        }
    }

    private func isDescendant(_ childURL: URL, of parentFolder: FolderItem) -> Bool {
        if let children = parentFolder.children {
            for child in children {
                if child.url == childURL || isDescendant(childURL, of: child) {
                    return true
                }
            }
        }
        return false
    }
}
