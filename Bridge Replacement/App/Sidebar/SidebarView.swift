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
    @State private var showingFolderPicker = false
    @State private var showingAddPopover = false
    let onDoubleClick: (() -> Void)?

    private let expandedFoldersKey = "ExpandedFolders"
    private let selectedFolderKey = "SelectedFolder"

    var body: some View {
        VStack(spacing: 0) {
            // Main folder list or welcome screen
            if model.rootFolders.isEmpty {
                // Welcome screen when no folders are added
                VStack(spacing: 16) {
                    Spacer()

                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    VStack(spacing: 8) {
                        Text("Add Photo Folders")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("This is where you add folders containing photos you want to view and organize.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }

                    Button(action: {
                        showingFolderPicker = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .medium))
                            Text("Add Folder")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Spacer().frame(height: 10)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Normal folder list
                List(selection: $model.selectedFolder) {
                    ForEach(Array(model.rootFolders.enumerated()), id: \.element.id) { index, rootFolder in
                        FolderRowView(
                            folder: rootFolder,
                            expandedFolders: $expandedFolders,
                            selectedFolder: $model.selectedFolder,
                            saveExpandedState: saveExpandedState,
                            onDoubleClick: {
                                onDoubleClick?()
                            },
                            model: model,
                            isRootFolder: true
                        )
                    }
                    .onDelete(perform: deleteFolders)
                }
                .listStyle(.sidebar)
                .focusable(false)
            }

            // Bottom bar with add and remove buttons
            HStack {
                Button(action: {
                    showingAddPopover = true
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .frame(width: 24, height: 32)
                .contentShape(Rectangle())
                .help("Add folder")
                .popover(isPresented: $showingAddPopover) {
                    AddFolderPopover(
                        model: model,
                        onAddVolumes: {
                            showingAddPopover = false
                            addVolumesFolder()
                        },
                        onAddCustomFolder: {
                            showingAddPopover = false
                            showingFolderPicker = true
                        }
                    )
                }

                Button(action: {
                    if let selectedFolder = model.selectedFolder {
                        // Only remove if the selected folder is a root folder
                        if isRootFolder(selectedFolder.url) {
                            model.removeFolder(at: selectedFolder.url)
                        }
                    }
                }) {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isRootFolderSelected() ? .primary : .secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .frame(width: 24, height: 32)
                .contentShape(Rectangle())
                .disabled(!isRootFolderSelected())
                .help("Remove folder")

                Spacer()

                Text("\(model.rootFolders.count) folders")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onAppear {
            loadExpandedState()
            loadSelectedFolder()
        }
        .onChange(of: model.selectedFolder) { _, newValue in
            saveSelectedFolder(newValue)
        }
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    model.addFolder(at: url)
                }
            case .failure(let error):
                print("Failed to select folder: \(error)")
            }
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
            for rootFolder in model.rootFolders {
                if let folder = findFolder(url: url, in: rootFolder) {
                    model.selectedFolder = folder
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
            let folder = model.rootFolders[index]
            model.removeFolder(at: folder.url)
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

    private func isRootFolder(_ url: URL) -> Bool {
        return model.rootFolders.contains { $0.url == url }
    }

    private func isRootFolderSelected() -> Bool {
        guard let selectedFolder = model.selectedFolder else { return false }
        return isRootFolder(selectedFolder.url)
    }

    private func addVolumesFolder() {
        let volumesURL = URL(fileURLWithPath: "/Volumes")
        model.addFolder(at: volumesURL)
    }
}
