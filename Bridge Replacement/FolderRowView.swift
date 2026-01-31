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
    
    private var isExpanded: Bool {
        expandedFolders.contains(folder.url)
    }
    
    private var hasChildren: Bool {
        folder.children?.isEmpty == false
    }
    
    var body: some View {
        if hasChildren {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { isExpanded },
                    set: { newValue in
                        if newValue {
                            expandedFolders.insert(folder.url)
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
                        saveExpandedState: saveExpandedState
                    )
                }
            } label: {
                Label(folder.url.lastPathComponent, systemImage: "folder.fill")
                    .tint(Color.blue)
                    .tag(folder)
                    .onTapGesture {
                        selectedFolder = folder
                    }
            }
        } else {
            Label(folder.url.lastPathComponent, systemImage: "folder.fill")
                .tint(Color(red: 139/255, green: 206/255, blue: 248/255))
                .tag(folder)
                .onTapGesture {
                    selectedFolder = folder
                }
        }
    }
}
