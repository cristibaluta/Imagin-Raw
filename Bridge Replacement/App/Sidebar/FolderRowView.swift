//
//  FolderRowView.swift
//  Imagin Bridge
//
//  Created by Cristian Baluta on 30.01.2026.
//

import SwiftUI

struct FolderRowView: View {
    let folder: FolderItem
    @Binding var expandedFolders: Set<URL>
    @Binding var selectedFolder: FolderItem?
    let saveExpandedState: () -> Void
    let onDoubleClick: () -> Void
    @ObservedObject var model: BrowserModel
    let isRootFolder: Bool

    private var isExpanded: Bool {
        expandedFolders.contains(folder.url)
    }

    private var hasChildren: Bool {
        // A folder is expandable if it has a children array (even if empty)
        // nil means no children, [] means expandable but unloaded, [...] means loaded
        return folder.children != nil
    }

    private var folderColor: Color {
        if isRootFolder {
            // Dark purple for root folders (user-added folders)
            return Color(red: 0.4, green: 0.2, blue: 0.7)
        } else if hasChildren {
            // Regular blue for subfolders with children
            return Color.blue
        } else {
            // Light blue for leaf subfolders
            return Color(red: 139/255, green: 206/255, blue: 248/255)
        }
    }

    private var needsToLoadChildren: Bool {
        // Check if this folder has an empty children array (placeholder for expandable but unloaded)
        return folder.children?.isEmpty == true
    }

    var body: some View {
        if hasChildren {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { isExpanded },
                    set: { newValue in
                        if newValue {
                            expandedFolders.insert(folder.url)
                            // Trigger on-demand loading if this folder needs its children loaded
                            if needsToLoadChildren {
                                print("Loading children on demand for: \(folder.url.path)")
                                model.loadChildrenOnDemand(for: folder)
                            }
                        } else {
                            expandedFolders.remove(folder.url)
                        }
                        saveExpandedState()
                    }
                )
            ) {
                ForEach(folder.children ?? []) { childFolder in
                    FolderRowView(
                        folder: childFolder,
                        expandedFolders: $expandedFolders,
                        selectedFolder: $selectedFolder,
                        saveExpandedState: saveExpandedState,
                        onDoubleClick: onDoubleClick,
                        model: model,
                        isRootFolder: false // Child folders are never root folders
                    )
                }
            } label: {
                Label(folder.url.lastPathComponent, systemImage: "folder.fill")
                    .tint(folderColor)
                    .tag(folder)
                    .onTapGesture {
                        selectedFolder = folder
                    }
                    .onDoubleClick {
                        onDoubleClick()
                    }
            }
        } else {
            Label(folder.url.lastPathComponent, systemImage: "folder.fill")
                .tint(folderColor)
                .tag(folder)
                .onTapGesture {
                    selectedFolder = folder
                }
                .onDoubleClick {
                    onDoubleClick()
                }
        }
    }
}
