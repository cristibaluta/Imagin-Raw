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

    private var isExpanded: Bool {
        expandedFolders.contains(folder.url)
    }

    private var hasChildren: Bool {
        // A folder is expandable if it has a children array (even if empty)
        // nil means no children, [] means expandable but unloaded, [...] means loaded
        return folder.children != nil
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
                        model: model
                    )
                }
            } label: {
                Label(folder.url.lastPathComponent, systemImage: "folder.fill")
                    .tint(Color.blue)
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
                .tint(Color(red: 139/255, green: 206/255, blue: 248/255))
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
