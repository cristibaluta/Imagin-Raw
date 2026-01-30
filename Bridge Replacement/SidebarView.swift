//
//  SidebarView.swift
//  Imagin Bridge
//
//  Created by Cristian Baluta on 30.01.2026.
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: BrowserModel
    @State private var expandedFolders: Set<URL> = []

    private let expandedFoldersKey = "ExpandedFolders"
    private let selectedFolderKey = "SelectedFolder"

    var body: some View {
        List(selection: $model.selectedFolder) {
            FolderRowView(
                folder: model.rootFolder,
                expandedFolders: $expandedFolders,
                selectedFolder: $model.selectedFolder,
                saveExpandedState: saveExpandedState
            )
        }
        .listStyle(.sidebar)
        .focusable(false)
        .onAppear {
            loadExpandedState()
            loadSelectedFolder()
        }
        .onChange(of: model.selectedFolder) { _, newValue in
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
            // Find the folder in the model that matches the saved URL
            if let folder = findFolder(url: url, in: model.rootFolder) {
                model.selectedFolder = folder
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
}
