//
//  FolderRowView.swift
//  Imagin Raw
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
    @EnvironmentObject var filesModel: FilesModel
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

    // Check if this folder is in /Volumes (external drive, network share, etc.)
    private var isVolume: Bool {
        return folder.url.path.hasPrefix("/Volumes/")
    }

    // Get the volume path (first component after /Volumes/)
    private var volumePath: String? {
        let path = folder.url.path
        guard path.hasPrefix("/Volumes/") else { return nil }

        // Extract volume name: /Volumes/MyDrive/... -> /Volumes/MyDrive
        let components = path.components(separatedBy: "/")
        if components.count >= 3 {
            return "/Volumes/\(components[2])"
        }
        return nil
    }

    private func ejectVolume() {
        guard let volumePath = volumePath else {
            print("❌ Could not determine volume path for: \(folder.url.path)")
            return
        }

        let volumeURL = URL(fileURLWithPath: volumePath)

        // Try to unmount the volume
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volumeURL)
            print("✅ Successfully ejected volume: \(volumePath)")
        } catch {
            print("❌ Failed to eject volume: \(error.localizedDescription)")
            // Show alert to user
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Failed to Eject"
                alert.informativeText = "Could not eject '\(volumeURL.lastPathComponent)': \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
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
                                filesModel.loadChildrenOnDemand(for: folder)
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
                        isRootFolder: false // Child folders are never root folders
                    )
                }
            } label: {
                Label {
                    Text(folder.url.lastPathComponent)
                } icon: {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(folderColor)
                }
                .tag(folder)
                .onTapGesture {
                    selectedFolder = folder
                }
                .onDoubleClick {
                    onDoubleClick()
                }
                .contextMenu {
                    Button(action: {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.url.path)
                    }) {
                        Label("Reveal in Finder", systemImage: "magnifyingglass")
                    }

                    // Only show eject option for root folders in /Volumes
                    if isVolume {
                        Divider()
                        Button(action: {
                            ejectVolume()
                        }) {
                            Label("Eject", systemImage: "eject")
                        }
                    }
                }
            }
        } else {
            Label {
                Text(folder.url.lastPathComponent)
            } icon: {
                Image(systemName: "folder.fill")
                    .foregroundStyle(folderColor)
            }
            .tag(folder)
            .onTapGesture {
                selectedFolder = folder
            }
            .onDoubleClick {
                onDoubleClick()
            }
            .contextMenu {
                Button(action: {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.url.path)
                }) {
                    Label("Reveal in Finder", systemImage: "magnifyingglass")
                }

                // Only show eject option for root folders in /Volumes
                if isRootFolder && isVolume {
                    Divider()
                    Button(action: {
                        ejectVolume()
                    }) {
                        Label("Eject", systemImage: "eject")
                    }
                }
            }
        }
    }
}
