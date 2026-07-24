//
//  FoldersList.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 11.02.2026.
//

import SwiftUI

struct FoldersListView: View {
    @EnvironmentObject var fileSystemModel: FileSystemModel
    @EnvironmentObject var appState: AppState
    @State private var expandedFolders: Set<URL> = []
    let onDoubleClick: (() -> Void)?

    var body: some View {
        List(selection: $fileSystemModel.selectedFolder) {
            if sourcesFolders.count > 0 {
                Section(header: Text("Sources").font(.caption)) {
                    ForEach(Array(sourcesFolders.enumerated()), id: \.element.id) { index, rootFolder in
                        FolderRowView(folder: rootFolder,
                                      expandedFolders: $expandedFolders,
                                      selectedFolder: $fileSystemModel.selectedFolder,
                                      saveExpandedState: saveExpandedState,
                                      onDoubleClick: {
                                          onDoubleClick?()
                                      },
                                      isRootFolder: true,
                                      isVolumeFolder: false,
                                      depth: 0)
                    }
                    .onDelete(perform: deleteFolders)
                }
            }
            if volumesFolders.count > 0 {
                Section(header: Text("Volumes").font(.caption)) {
                    ForEach(Array(volumesFolders.enumerated()), id: \.element.id) { index, rootFolder in
                        FolderRowView(folder: rootFolder,
                                      expandedFolders: $expandedFolders,
                                      selectedFolder: $fileSystemModel.selectedFolder,
                                      saveExpandedState: saveExpandedState,
                                      onDoubleClick: {
                                          onDoubleClick?()
                                      },
                                      isRootFolder: true,
                                      isVolumeFolder: true,
                                      depth: 0)
                    }
                    .onDelete(perform: deleteFolders)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)// removes sidebar header bg color
        .focusable(false)
        .onAppear {
            loadExpandedState()
            loadSelectedFolder()
        }
        .onChange(of: fileSystemModel.selectedFolder) { _, newValue in
            saveSelectedFolder(newValue)
        }
    }

    private var sourcesFolders: [FolderItem] {
        fileSystemModel.rootFolders.filter { !$0.url.path.hasPrefix("/Volumes") }
    }

    private var volumesFolders: [FolderItem] {
        fileSystemModel.rootFolders.filter { $0.url.path.hasPrefix("/Volumes") }
    }

    private func loadExpandedState() {
        if let data = UserDefaults.standard.data(forKey: AppPreference.expandedFolders.rawValue),
           let urls = try? JSONDecoder().decode([URL].self, from: data) {
            expandedFolders = Set(urls)
        }
    }

    private func saveExpandedState() {
        let urls = Array(expandedFolders)
        if let data = try? JSONEncoder().encode(urls) {
            UserDefaults.standard.set(data, forKey: AppPreference.expandedFolders.rawValue)
        }
    }

    private func loadSelectedFolder() {
        #if os(macOS)
        if let data = UserDefaults.standard.data(forKey: AppPreference.selectedFolder.rawValue),
           let url = try? JSONDecoder().decode(URL.self, from: data) {
            for rootFolder in fileSystemModel.rootFolders {
                if let folder = findFolder(url: url, in: rootFolder) {
                    fileSystemModel.selectedFolder = folder
                    return
                }
            }
        }
        #endif
    }

    private func saveSelectedFolder(_ folder: FolderItem?) {
        if let folder = folder,
           let data = try? JSONEncoder().encode(folder.url) {
            UserDefaults.standard.set(data, forKey: AppPreference.selectedFolder.rawValue)
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

    #if os(macOS)
    private func deleteFolders(offsets: IndexSet) {
        for index in offsets {
            let folder = fileSystemModel.rootFolders[index]
            fileSystemModel.removeFolder(at: folder.url)
        }
    }
    #elseif os(iOS)
    private func deleteFolders(offsets: IndexSet) {

    }
    #endif

}
