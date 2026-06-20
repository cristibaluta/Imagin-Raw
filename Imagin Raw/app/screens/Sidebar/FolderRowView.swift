//
//  FolderRowView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 30.01.2026.
//

import SwiftUI

struct FolderRowView: View {
    @EnvironmentObject var filesModel: FilesModel
    @EnvironmentObject var appState: AppState
    let folder: FolderItem
    @Binding var expandedFolders: Set<URL>
    @Binding var selectedFolder: FolderItem?
    let saveExpandedState: () -> Void
    let onDoubleClick: () -> Void
    let isRootFolder: Bool
    /// Depth of this folder: 0 = root, 1 = first level inside root, 2+ = deeper
    let depth: Int

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
            return Color("PurpleThemeColor")
        } else if hasChildren {
            // Regular blue for subfolders with children
            return Color.blue
        } else {
            // Light blue for leaf subfolders
            return Color(red: 139/255, green: 206/255, blue: 248/255)
        }
    }

    // Determine the appropriate icon for this folder
    private var folderIcon: String {
        // Check if this is a root folder in /Volumes (external drive)
        if isRootFolder && isVolume {
            return "externaldrive.fill"
        }

        // Check if this is a first-level folder inside /Volumes (the actual external drive)
        let path = folder.url.path
        let components = path.components(separatedBy: "/").filter { !$0.isEmpty }

        // If path is like /Volumes/DriveName, it's the drive itself
        if components.count == 2 && components[0] == "Volumes" {
            return "externaldrive.fill"
        }

        // Otherwise use regular folder icon
        return "folder.fill"
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

    private func sortedChildren(_ children: [FolderItem]) -> [FolderItem] {
        // depth == 0 means this is a root folder, so its children are level 1.
        // depth == 1 means children are level 2, etc.
        let childDepth = depth + 1
        let sortByDate: Bool
        switch filesModel.sidebarSortOption {
        case .name:
            sortByDate = false        // all levels by name
        case .dateCreated:
            sortByDate = true         // all levels by date
        case .nameThenDate:
            sortByDate = childDepth >= 2  // level 1 by name, level 2+ by date
        }

        if sortByDate {
            return children.sorted { a, b in
                let dateA = (try? a.url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let dateB = (try? b.url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return dateA < dateB
            }
        } else {
            return children.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    #if os(macOS)
    private func ejectVolume() {
        guard let volumePath else {
            return
        }

        let volumeURL = URL(fileURLWithPath: volumePath)

        // Try to unmount the volume
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volumeURL)
        } catch {
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
    #endif

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
                                #if os(macOS)
                                filesModel.loadChildrenOnDemand(for: folder)
                                #endif
                            }
                        } else {
                            expandedFolders.remove(folder.url)
                        }
                        saveExpandedState()
                    }
                )
            ) {
                ForEach(sortedChildren(folder.children ?? [])) { childFolder in
                    FolderRowView(folder: childFolder,
                                  expandedFolders: $expandedFolders,
                                  selectedFolder: $selectedFolder,
                                  saveExpandedState: saveExpandedState,
                                  onDoubleClick: onDoubleClick,
                                  isRootFolder: false,
                                  depth: depth + 1
                    )
                }
            } label: {
                Label {
                    Text(folder.title)
                } icon: {
                    Image(systemName: folder.url.isPhotoLibraryRoot ? "photo.on.rectangle.angled" : folderIcon)
                        .foregroundStyle(folderColor)
                }
                .tag(folder)
                .onTapGesture {
                    #if os(iOS)
                    RCLog("👆 [Sidebar] tap folder: \(folder.title) already=\(selectedFolder?.url == folder.url)")
                    if selectedFolder?.url == folder.url {
                        selectedFolder = nil
                        DispatchQueue.main.async { selectedFolder = folder }
                    } else {
                        selectedFolder = folder
                    }
                    #else
                    selectedFolder = folder
                    #endif
                }
                .onDoubleClick {
                    onDoubleClick()
                }
                #if os(macOS)
                .contextMenu {
                    Button(action: {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.url.path)
                    }) {
                        Label("Show in Finder", systemImage: "folder")
                    }

                    Divider()

                    Button(action: {
                        Task {
//                            guard let cacheURL = appState.thumbsManager?.cacheDir(for: folder.url) else {
//                                return
//                            }
//                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cacheURL.path)
                        }
                    }) {
                        Label("Reveal Cache in Finder", systemImage: "folder.badge.questionmark")
                    }

                    Button(role: .destructive, action: {
                        Task.detached(priority: .background) {
                            await appState.thumbnailsCacheManager.purgeCache(folderURL: folder.url)
                            await appState.previewsCacheManager.purgeCache(folderURL: folder.url)
                            await appState.fullResCacheManager.purgeCache(folderURL: folder.url)
                        }
                    }) {
                        Label("Purge Cache", systemImage: "trash")
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
                #endif
            }
        } else {
            Label {
                Text(folder.title)
            } icon: {
                Image(systemName: folder.url.isPhotoKitAlbum ? "photo.stack" : "folder.fill")
                    .foregroundStyle(folderColor)
            }
            .tag(folder)
            .onTapGesture {
                #if os(iOS)
                RCLog("👆 [Sidebar] tap leaf: \(folder.title) already=\(selectedFolder?.url == folder.url)")
                if selectedFolder?.url == folder.url {
                    selectedFolder = nil
                    DispatchQueue.main.async { selectedFolder = folder }
                } else {
                    selectedFolder = folder
                }
                #else
                selectedFolder = folder
                #endif
            }
            .onDoubleClick {
                onDoubleClick()
            }
            #if os(macOS)
            .contextMenu {
                Button(action: {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.url.path)
                }) {
                    Label("Reveal in Finder", systemImage: "folder")
                }

                Divider()

                Button(action: {
                    Task {
//                        guard let cacheURL = filesModel.currentThumbsManager?.cacheDir(for: folder.url) else {
//                            return
//                        }
//                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cacheURL.path)
                    }
                }) {
                    Label("Reveal Cache in Finder", systemImage: "folder.badge.questionmark")
                }

                Button(role: .destructive, action: {
                    Task.detached(priority: .background) {
                        await appState.thumbnailsCacheManager.purgeCache(folderURL: folder.url)
                        await appState.previewsCacheManager.purgeCache(folderURL: folder.url)
                        await appState.fullResCacheManager.purgeCache(folderURL: folder.url)
                    }
                }) {
                    Label("Purge Cache", systemImage: "trash")
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
            #endif
        }
    }
}
