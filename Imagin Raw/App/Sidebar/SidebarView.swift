//
//  SidebarView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 30.01.2026.
//

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var filesModel: FilesModel
    @State private var showingFolderPicker = false
    @State private var showingAddPopover = false
    @State private var searchText = ""
    @StateObject private var searcher = SpotlightSearcher()
    let onDoubleClick: (() -> Void)?

    // Default initializer for backwards compatibility
    init(onDoubleClick: (() -> Void)? = nil) {
        self.onDoubleClick = onDoubleClick
    }

    private let expandedFoldersKey = "ExpandedFolders"
    private let selectedFolderKey = "SelectedFolder"

    private var isSearching: Bool {
        searchText.count >= 3
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField("Search folders...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onChange(of: searchText) { _, newValue in
                        if newValue.count >= 3 {
                            searcher.search(query: newValue, in: filesModel.rootFolders)
                        } else {
                            searcher.stopSearch()
                        }
                    }
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        searcher.stopSearch()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if isSearching {
                SearchResultsFoldersListView(
                    results: searcher.results,
                    isSearching: searcher.isSearching
                )
            } else {
                FoldersListView {
                    self.onDoubleClick?()
                }
            }

            HStack {
                Button(action: {
                    if showingAddPopover {
                        // Close with animation
                        withAnimation {
                            showingAddPopover = false
                        }
                    } else {
                        // Open without animation
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            showingAddPopover = true
                        }
                    }
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
                    if let selectedFolder = filesModel.selectedFolder {
                        // Only remove if the selected folder is a root folder
                        if isRootFolder(selectedFolder.url) {
                            filesModel.removeFolder(at: selectedFolder.url)
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

                Text("\(filesModel.rootFolders.count) folders")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    filesModel.addFolder(at: url)
                }
            case .failure(_):
                break
            }
        }
    }

    private func isRootFolder(_ url: URL) -> Bool {
        return filesModel.rootFolders.contains { $0.url == url }
    }

    private func isRootFolderSelected() -> Bool {
        guard let selectedFolder = filesModel.selectedFolder else { return false }
        return isRootFolder(selectedFolder.url)
    }

    private func addVolumesFolder() {
        // Instead of adding /Volumes directly (which won't work in sandboxed apps),
        // open a file picker at /Volumes to let user select which volume to add
        let openPanel = NSOpenPanel()
        openPanel.message = "Please allow access to this folder in order to see all your external hard drives"
        openPanel.prompt = "Allow Access"
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.directoryURL = URL(fileURLWithPath: "/Volumes")

        openPanel.begin { response in
            if response == .OK, let selectedURL = openPanel.url {
                // User selected a folder in /Volumes - add it
                self.filesModel.addFolder(at: selectedURL)
            }
        }
    }
}
